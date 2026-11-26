// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show visibleForTesting;
import '../config.dart';
import 'identity_service.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class RelayService {
  static const String _relayUrl = UnsyncConfig.relayUrl;
  WebSocketChannel? _channel;
  bool _connected = false;
  bool _registered = false;
  Completer<void>? _ready;
  final Map<String, _MeshPending> _meshPending = {};
  bool _reconnecting = false;
  Timer? _pingTimer;
  Function(String from, String payload)? onQueuedMessage;
  final Map<String, Completer<Map<String, dynamic>?>> _bundleCompleters = {};
  final IdentityService _identityService;
  final void Function(Map<String, dynamic>)? _sendOverride;
  final Duration _registerFallbackDelay;

  // `register` is held back until the relay has accepted our auth response. A
  // relay with sender auth enforced rejects register from an unauthenticated
  // connection (AUTH_REQUIRED_FOR_RELAY), so registering on connect left the
  // device unregistered and unable to receive anything.
  String? _pendingId;
  String? _pendingFcmToken;
  bool _registerSent = false;
  Timer? _registerFallbackTimer;

  RelayService({
    IdentityService? identityService,
    void Function(Map<String, dynamic>)? sendOverride,
    Duration registerFallbackDelay = const Duration(seconds: 5),
  }) : _identityService = identityService ?? IdentityService(),
       _sendOverride = sendOverride,
       _registerFallbackDelay = registerFallbackDelay;

  Future<void> connect(String myId, {String? fcmToken}) async {
    if (_reconnecting) return;
    _reconnecting = true;
    try {
      _channel = IOWebSocketChannel.connect(Uri.parse(_relayUrl));
      _registered = false;
      _ready = Completer<void>();
      _channel!.stream.listen(
        (data) => _handleMessage(data),
        onDone: () {
          _connected = false;
          _failMesh(StateError('Relay disconnected'));
          print('Relay disconnected');
          Future.delayed(
            const Duration(seconds: 10),
            () => connect(myId, fcmToken: fcmToken),
          );
        },
        onError: (e) {
          _connected = false;
          _failMesh(StateError('Relay disconnected'));
          print('Relay error: $e');
          Future.delayed(
            const Duration(seconds: 10),
            () => connect(myId, fcmToken: fcmToken),
          );
        },
        cancelOnError: false,
      );
      _beginRegistration(myId, fcmToken);
      _connected = true;
      _reconnecting = false;
      _startPing();
      print('Relay connected as $myId');
    } catch (e) {
      print('Relay connect failed: $e');
      Future.delayed(
        const Duration(seconds: 10),
        () => connect(myId, fcmToken: fcmToken),
      );
    }
  }

  Future<void> _handleMessage(dynamic data) async {
    try {
      final msg = jsonDecode(data as String);
      final type = msg['type'] as String?;
      switch (type) {
        case 'auth_challenge':
          await _handleAuthChallenge(msg);
          break;
        case 'auth_ok':
          print('Relay auth_ok');
          _sendRegisterOnce();
          break;
        case 'auth_failed':
          print(
            'Relay auth failed: ${msg['error'] ?? msg['reason'] ?? 'unknown'}',
          );
          // Fall back to the legacy register; a relay that enforces auth will
          // reject it and say so below, one that does not still serves us.
          _sendRegisterOnce();
          break;
        case 'relay_error':
          print('Relay error: ${msg['error']}');
          break;
        case 'registered':
          _registered = true;
          if (_ready != null && !_ready!.isCompleted) _ready!.complete();
          print('Relay registered: ${msg['id']}');
          break;
        case 'mesh-response-start':
          final pending = _meshPending[msg['requestId']];
          if (pending != null) {
            pending.status = msg['status'] is int ? msg['status'] as int : 200;
          }
          break;
        case 'mesh-chunk':
          final pending = _meshPending[msg['requestId']];
          if (pending != null) {
            pending.append(base64Decode(msg['data'] as String? ?? ''));
          }
          break;
        case 'mesh-response-end':
          _finishMesh(msg['requestId'] as String?);
          break;
        case 'mesh-response':
          final pending = _meshPending[msg['requestId']];
          if (pending != null) {
            pending.status = msg['status'] is int ? msg['status'] as int : 200;
            pending.append(base64Decode(msg['body'] as String? ?? ''));
          }
          _finishMesh(msg['requestId'] as String?);
          break;
        case 'queued':
          print('Relay: queued from ${msg['from']}');
          onQueuedMessage?.call(
            msg['from'] as String,
            msg['payload'] as String,
          );
          break;
        case 'stored':
          print('Relay: blob stored for ${msg['to']}');
          break;
        case 'bundle_uploaded':
          print('Relay: bundle uploaded for ${msg['id']}');
          break;
        case 'bundle':
          final id = msg['id'] as String;
          final completer = _bundleCompleters.remove(id);
          completer?.complete(msg['bundle'] as Map<String, dynamic>?);
          break;
        case 'bundle_not_found':
          final id = msg['id'] as String;
          final completer = _bundleCompleters.remove(id);
          completer?.complete(null);
          break;
      }
    } catch (e) {
      print('Relay handle error: $e');
    }
  }

  Future<void> _handleAuthChallenge(Map<String, dynamic> msg) async {
    final version = msg['version'];
    final nonce = msg['nonce'];
    final serverTime = msg['server_time'];
    if (version is! String ||
        nonce is! String ||
        (serverTime is! int && serverTime is! String)) {
      print('Relay auth challenge invalid; continuing legacy mode');
      _sendRegisterOnce();
      return;
    }

    final response = await _identityService.signRelayAuthChallenge(
      version: version,
      nonce: nonce,
      serverTime: serverTime,
    );
    if (response == null) {
      print('Relay auth unavailable');
      _sendRegisterOnce();
      return;
    }

    _send({
      'type': 'auth_response',
      'peer_id': response.peerId,
      'pubkey': response.publicKey,
      'signature': response.signature,
    });
    print('Relay auth_response sent');
    // Wait for auth_ok, but never forever: re-arm the fallback from here.
    _armRegisterFallback();
  }

  // Called once per connection. Registers only when the relay says it is ready
  // (auth_ok) or when it clearly will not authenticate us (no challenge, a
  // challenge we cannot answer, auth_failed, or silence past the fallback).
  void _beginRegistration(String id, String? fcmToken) {
    _pendingId = id;
    _pendingFcmToken = fcmToken;
    _registerSent = false;
    _armRegisterFallback();
  }

  void _armRegisterFallback() {
    _registerFallbackTimer?.cancel();
    _registerFallbackTimer = Timer(_registerFallbackDelay, _sendRegisterOnce);
  }

  void _sendRegisterOnce() {
    final id = _pendingId;
    if (_registerSent || id == null) return;
    _registerSent = true;
    _registerFallbackTimer?.cancel();
    _send({'type': 'register', 'id': id, 'fcmToken': _pendingFcmToken});
  }

  @visibleForTesting
  void beginRegistrationForTest(String id, String? fcmToken) =>
      _beginRegistration(id, fcmToken);

  @visibleForTesting
  Future<void> handleMessageForTest(String data) => _handleMessage(data);

  void uploadBundle(String peerId, Map<String, dynamic> bundle) {
    _send({'type': 'upload_bundle', 'id': peerId, 'bundle': bundle});
  }

  Future<Map<String, dynamic>?> fetchBundle(String peerId) async {
    if (!_connected) return null;
    final completer = Completer<Map<String, dynamic>?>();
    _bundleCompleters[peerId] = completer;
    _send({'type': 'get_bundle', 'id': peerId});
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _bundleCompleters.remove(peerId);
        return null;
      },
    );
  }

  Future<Map<String, dynamic>?> getBundle(String peerId) => fetchBundle(peerId);

  Future<void> storeMessage(
    String to,
    String from,
    String encryptedPayload,
  ) async {
    if (!_connected) {
      print('Relay: not connected, cannot store');
      return;
    }
    // Signaling authenticates wake requests against the *sender's* identity,
    // so the relay cannot mint one — it can only forward what we sign. Without
    // this the relay's wake ping is rejected with 400 and the recipient is
    // never pushed; the message just waits until they next open the app.
    final wake = await _identityService
        .signWakeRequest(peerId: to)
        .catchError((Object e) {
          print('Relay: wake signing failed: $e');
          return null;
        });
    _send({
      'type': 'store',
      'to': to,
      'from': from,
      'payload': encryptedPayload,
      if (wake != null) 'wake': wake,
    });
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_connected) _send({'type': 'ping'});
    });
  }

  void _send(Map<String, dynamic> msg) {
    final override = _sendOverride;
    if (override != null) {
      override(msg);
      return;
    }
    _channel?.sink.add(jsonEncode(msg));
  }

  bool get isConnected => _connected;

  Future<String> fetchMeshText(String to, String from, String path) async =>
      utf8.decode(await fetchMeshBytes(to, from, path));

  Future<Uint8List> fetchMeshBytes(String to, String from, String path) async {
    if (!path.startsWith('/api/')) {
      throw ArgumentError('Forum API path required');
    }
    if (!_registered) {
      final ready = _ready;
      if (ready == null) throw StateError('Relay is not connected');
      await ready.future.timeout(const Duration(seconds: 15));
      if (!_registered) throw StateError('Relay is not connected');
    }
    final random = Random.secure();
    final requestId = base64Url
        .encode(List<int>.generate(18, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    final pending = _MeshPending();
    _meshPending[requestId] = pending;
    _send({
      'type': 'mesh-request',
      'to': to,
      'from': from,
      'requestId': requestId,
      'path': path,
    });
    try {
      return await pending.result.future.timeout(const Duration(seconds: 30));
    } finally {
      _meshPending.remove(requestId);
    }
  }

  void _finishMesh(String? id) {
    final pending = _meshPending.remove(id);
    if (pending == null || pending.result.isCompleted) return;
    if (pending.status < 200 || pending.status >= 300) {
      pending.result.completeError(StateError('Forum returned ${pending.status}'));
    } else {
      pending.result.complete(Uint8List.fromList(pending.bytes));
    }
  }

  void _failMesh(Object error) {
    _registered = false;
    if (_ready != null && !_ready!.isCompleted) _ready!.complete();
    for (final pending in _meshPending.values) {
      if (!pending.result.isCompleted) pending.result.completeError(error);
    }
    _meshPending.clear();
  }

  void dispose() {
    _failMesh(StateError('Relay closed'));
    _pingTimer?.cancel();
    _registerFallbackTimer?.cancel();
    _channel?.sink.close();
  }
}

class _MeshPending {
  final result = Completer<Uint8List>();
  final bytes = <int>[];
  int status = 200;

  void append(List<int> chunk) {
    if (result.isCompleted) return;
    if (bytes.length + chunk.length > 4 * 1024 * 1024) {
      result.completeError(StateError('Forum response too large'));
      return;
    }
    bytes.addAll(chunk);
  }
}