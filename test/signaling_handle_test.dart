import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:unsync/services/handle_service.dart';
import 'package:unsync/services/identity_service.dart';
import 'package:unsync/services/signaling_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

Future<(SignalingService, _FakeWebSocketChannel, _SocketHarness)> _connected() async {
  final harness = _SocketHarness();
  final service = SignalingService(
    identityService: _FakeIdentityService(),
    channelFactory: harness.connect,
    authChallengeTimeout: const Duration(milliseconds: 200),
    reconnectDelays: const [Duration(milliseconds: 1)],
  );
  await service.connect('1795315617380');
  return (service, harness.single, harness);
}

void main() {
  test('claimHandle sends the claim and resolves on the reply', () async {
    final (service, channel, harness) = await _connected();
    final pending = service.claimHandle('@Batman');
    await pumpEventQueue();
    expect(channel.sink.messages.last, {'type': 'claim_handle', 'handle': '@batman'});
    channel.sendServer({'type': 'handle_claim_result', 'ok': true, 'handle': '@batman'});
    final result = await pending;
    expect(result.ok, isTrue);
    expect(result.handle, '@batman');
    service.disconnect();
    await harness.close();
  });

  test('a taken handle comes back with its reason', () async {
    final (service, channel, harness) = await _connected();
    final pending = service.claimHandle('@batman');
    await pumpEventQueue();
    channel.sendServer({'type': 'handle_claim_result', 'ok': false, 'reason': 'taken'});
    final result = await pending;
    expect(result.ok, isFalse);
    expect(result.reason, 'taken');
    service.disconnect();
    await harness.close();
  });

  test('no reply means timeout', () async {
    final (service, _, harness) = await _connected();
    final result = await service.claimHandle(
      '@batman',
      timeout: const Duration(milliseconds: 30),
    );
    expect(result.ok, isFalse);
    expect(result.reason, 'timeout');
    service.disconnect();
    await harness.close();
  });

  test('fetchHandle reports the server handle, or unsupported on an old server', () async {
    final (service, channel, harness) = await _connected();
    final pending = service.fetchHandle();
    await pumpEventQueue();
    expect(channel.sink.messages.last, {'type': 'get_handle'});
    channel.sendServer({'type': 'handle_status', 'handle': '@batman'});
    final status = await pending;
    expect(status.supported, isTrue);
    expect(status.handle, '@batman');

    final old = await service.fetchHandle(timeout: const Duration(milliseconds: 30));
    expect(old.supported, isFalse);
    expect(old.handle, isNull);
    service.disconnect();
    await harness.close();
  });

  test('a null handle status means supported but no handle yet', () async {
    final (service, channel, harness) = await _connected();
    final pending = service.fetchHandle();
    await pumpEventQueue();
    channel.sendServer({'type': 'handle_status', 'handle': null});
    final status = await pending;
    expect(status.supported, isTrue);
    expect(status.handle, isNull);
    service.disconnect();
    await harness.close();
  });
}

class _FakeIdentityService extends IdentityService {
  String? lastDisplayName;

  @override
  Future<MeshAuthResponse?> signSignalingAuthChallenge({
    required String nonce,
    required Object serverTime,
    String? displayName,
  }) async {
    lastDisplayName = displayName;
    return MeshAuthResponse(
      peerId: '1795315617380',
      publicKey: 'public-key',
      signature: 'signature',
      authVersion: displayName == null ? 'cloaknet-auth-v1' : 'cloaknet-auth-v2',
      displayName: displayName,
    );
  }
}

class _SocketHarness {
  final List<_FakeWebSocketChannel> channels = [];

  _FakeWebSocketChannel get single => channels.single;

  WebSocketChannel connect(Uri uri) {
    final channel = _FakeWebSocketChannel();
    channels.add(channel);
    return channel;
  }

  Future<void> close() async {
    for (final channel in channels) {
      await channel.closeServer();
    }
  }
}

class _FakeWebSocketChannel implements WebSocketChannel {
  final StreamController<String> _server = StreamController<String>();

  @override
  late final Stream<String> stream = _server.stream;

  @override
  final _RecordingWebSocketSink sink = _RecordingWebSocketSink();

  @override
  Future<void> get ready => Future<void>.value();

  void sendServer(Map<String, dynamic> message) {
    if (!_server.isClosed) {
      _server.add(jsonEncode(message));
    }
  }

  Future<void> closeServer() => _server.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingWebSocketSink implements WebSocketSink {
  final List<Map<String, dynamic>> messages = [];
  final Completer<void> _done = Completer<void>();
  bool closed = false;

  @override
  void add(Object? event) {
    messages.add(jsonDecode(event! as String) as Map<String, dynamic>);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closed = true;
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  @override
  Future<void> get done => _done.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
