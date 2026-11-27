import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed25519;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'community_blocks.dart';
import 'relay_service.dart';

/// Resolves the signed forum.site record and sends requests over Mercury's relay.
class CommunityService {
  CommunityService(this.relay, this.peerId);

  final RelayService relay;
  final String peerId;

  /// Members blocked on this device; their content is hidden here only.
  final CommunityBlocks blocks = CommunityBlocks();
  String? _forumPeerId;
  DateTime? _expires;
  static const _keyStorage = FlutterSecureStorage();
  static const _keyName = 'mercury_forum_key_v1';
  static final _keyPattern = RegExp(r'^[A-Za-z0-9_-]{32,100}$');
  String? _key;
  Map<String, dynamic>? _session;
  final Map<int, Future<Uint8List>> _images = {};
  final Map<int, Future<Uint8List>> _avatars = {};

  Map<String, dynamic>? get session => _session;

  Future<String?> exportKey() async {
    await _loadKey();
    return _key;
  }

  Future<void> _loadKey() async {
    if (_key != null) return;
    final stored = await _keyStorage.read(key: _keyName);
    if (stored != null && _keyPattern.hasMatch(stored)) _key = stored;
  }

  Future<Map<String, dynamic>> loadSession() async {
    final result = await get('/api/me');
    _session = result;
    return result;
  }

  Future<Map<String, dynamic>> importKey(String value) async {
    final key = value.trim();
    if (!_keyPattern.hasMatch(key))
      throw const FormatException('Invalid forum key');
    final result = await get('/api/me', keyOverride: key);
    if (result['keyStatus'] != 'valid') {
      throw StateError('The forum did not recognize this key');
    }
    await _keyStorage.write(key: _keyName, value: key);
    _key = key;
    _session = result;
    return result;
  }

  Future<Map<String, dynamic>> join({
    String? handle,
    String? inviteCode,
  }) async {
    final session = _session ?? await loadSession();
    if (session['openJoin'] != true && inviteCode == null) {
      throw StateError('Joining requires a forum invite code');
    }
    final random = Random.secure();
    final key = base64Url
        .encode(List<int>.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    final params = inviteCode != null
        ? {'code': inviteCode.trim(), 't': '${session['token'] ?? ''}'}
        : {'handle': handle?.trim() ?? '', 't': '${session['token'] ?? ''}'};
    final result = await get(
      Uri(
        path: inviteCode != null ? '/api/w/claim' : '/api/w/join',
        queryParameters: params,
      ).toString(),
      keyOverride: key,
    );
    await _keyStorage.write(key: _keyName, value: key);
    _key = key;
    await loadSession();
    return result;
  }

  Future<Map<String, dynamic>> writePost({
    required String title,
    required String content,
    required String category,
    Uint8List? imageBytes,
  }) async {
    final imageId = imageBytes == null ? null : await uploadImage(imageBytes);
    return _write('/api/w/post', {
      'title': title,
      'content': content,
      'category': category,
      if (imageId != null) 'image': '$imageId',
    });
  }

  Future<int> uploadImage(Uint8List bytes) =>
      _uploadBytes(bytes, forAvatar: false);

  Future<int> _uploadBytes(Uint8List bytes, {required bool forAvatar}) async {
    if (bytes.length > 40 * 1024) throw StateError('Picture is too large');
    final session = _session ?? await loadSession();
    if (session['features'] is! Map ||
        session['features'][forAvatar ? 'profileAvatars' : 'postImages'] !=
            true) {
      throw StateError(
        forAvatar
            ? 'The forum host does not support profile photos yet'
            : 'The forum host does not support pictures yet',
      );
    }
    if (session['canWrite'] != true)
      throw StateError('Join the forum to post pictures');
    Future<Map<String, dynamic>> request(
      String path,
      Map<String, String> params,
    ) => get(
      Uri(
        path: path,
        queryParameters: {...params, 't': '${session['token']}'},
      ).toString(),
    );
    final started = await request('/api/w/image/start', {
      'size': '${bytes.length}',
    });
    final id = started['id'];
    final chunkBytes = started['chunkBytes'];
    if (id is! String ||
        chunkBytes is! int ||
        chunkBytes < 1 ||
        chunkBytes > 6144) {
      throw const FormatException('Invalid image upload response');
    }
    var index = 0;
    for (var offset = 0; offset < bytes.length; offset += chunkBytes) {
      final end = (offset + chunkBytes).clamp(0, bytes.length);
      final data = base64Url
          .encode(bytes.sublist(offset, end))
          .replaceAll('=', '');
      await request('/api/w/image/chunk', {
        'id': id,
        'i': '$index',
        'data': data,
      });
      index++;
    }
    final finished = await request('/api/w/image/finish', {
      'id': id,
      'count': '$index',
    });
    final imageId = finished['imageId'];
    if (imageId is! int)
      throw const FormatException('Invalid image upload response');
    return imageId;
  }

  Future<void> syncAvatar(Uint8List bytes, String revision) async {
    final session = _session ?? await loadSession();
    if (session['canWrite'] != true ||
        session['features'] is! Map ||
        session['features']['profileAvatars'] != true)
      return;
    final handle = session['handle'];
    if (handle is! String || handle.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final marker = 'forum_avatar_revision_$handle';
    if (session['avatarId'] is int && prefs.getString(marker) == revision)
      return;
    final imageId = await _uploadBytes(bytes, forAvatar: true);
    await get(
      Uri(
        path: '/api/w/avatar',
        queryParameters: {'image': '$imageId', 't': '${session['token']}'},
      ).toString(),
    );
    session['avatarId'] = imageId;
    await prefs.setString(marker, revision);
  }

  Future<Uint8List> image(int id) async {
    final pending = _images.putIfAbsent(id, () async {
      final forumPeer = await _resolveForum();
      return relay.fetchMeshBytes(forumPeer, peerId, '/api/images/$id');
    });
    try {
      return await pending;
    } catch (_) {
      _images.remove(id);
      rethrow;
    }
  }

  Future<Uint8List> avatar(int id) async {
    final pending = _avatars.putIfAbsent(id, () async {
      final forumPeer = await _resolveForum();
      return relay.fetchMeshBytes(forumPeer, peerId, '/api/avatars/$id');
    });
    try {
      return await pending;
    } catch (_) {
      _avatars.remove(id);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> writeComment({
    required String postId,
    required String body,
  }) => _write('/api/w/comment', {'post': postId, 'body': body});

  /// Author-only. [removeImage] drops the picture; otherwise it is kept.
  Future<Map<String, dynamic>> editPost({
    required String postId,
    required String title,
    required String content,
    required String category,
    bool removeImage = false,
  }) => _write('/api/w/post/edit', {
    'id': postId,
    'title': title,
    'content': content,
    'category': category,
    if (removeImage) 'remove_image': '1',
  });

  Future<Map<String, dynamic>> deletePost(String postId) =>
      _write('/api/w/post/delete', {'id': postId});

  /// [kind] is 'post' or 'comment'.
  Future<Map<String, dynamic>> report({
    required String kind,
    required String id,
    required String reason,
  }) => _write('/api/w/report', {'kind': kind, 'id': id, 'reason': reason});

  /// Members, without anyone blocked on this device.
  Future<List<Map<String, dynamic>>> members() async {
    final result = await get('/api/members');
    await blocks.ensureLoaded();
    return (result['members'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .where((m) => !blocks.isBlocked('${m['handle']}'))
            .toList() ??
        [];
  }

  /// Conversations, without anyone blocked on this device.
  Future<List<Map<String, dynamic>>> dmThreads() async {
    final result = await get('/api/dm/threads');
    await blocks.ensureLoaded();
    return (result['threads'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .where((t) => !blocks.isBlocked('${t['peer']}'))
            .toList() ??
        [];
  }

  Future<List<Map<String, dynamic>>> dmWith(String handle) async {
    final result = await get(
      Uri(path: '/api/dm/with', queryParameters: {'h': handle}).toString(),
    );
    return (result['messages'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];
  }

  Future<Map<String, dynamic>> sendDm({
    required String to,
    required String body,
  }) => _write('/api/w/dm', {'to': to, 'body': body});

  Future<Map<String, dynamic>> _write(
    String path,
    Map<String, String> params,
  ) async {
    var session = _session ?? await loadSession();
    if (session['canWrite'] != true)
      throw StateError('Join the forum to participate');
    final random = Random.secure();
    final nonce = base64Url
        .encode(List<int>.generate(16, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    Future<Map<String, dynamic>> attempt() => get(
      Uri(
        path: path,
        queryParameters: {...params, 't': '${session['token']}', 'n': nonce},
      ).toString(),
    );
    try {
      return await attempt();
    } catch (error) {
      if (!error.toString().contains('403')) rethrow;
      session = await loadSession();
      return attempt();
    }
  }

  static final _peerPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$');
  static final _spkiPrefix = [
    0x30,
    0x2a,
    0x30,
    0x05,
    0x06,
    0x03,
    0x2b,
    0x65,
    0x70,
    0x03,
    0x21,
    0x00,
  ];

  Future<String> _resolveForum() async {
    if (_forumPeerId != null &&
        _expires != null &&
        DateTime.now().isBefore(_expires!)) {
      return _forumPeerId!;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final uri = Uri.https('mesh.unsync.uk', '/mesh/resolve', {
        'handle': 'forum.site',
      });
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 6));
      final response = await request.close().timeout(
        const Duration(seconds: 6),
      );
      if (response.statusCode != 200) {
        throw StateError('Forum registry returned ${response.statusCode}');
      }
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 6));
      final record = jsonDecode(body);
      if (record is! Map<String, dynamic>) {
        throw const FormatException('Invalid forum registry record');
      }
      final name = record['site_name'];
      final id = record['peer_id'];
      final pubkey = record['pubkey'];
      final signature = record['signature'];
      if (name != 'forum.site' ||
          id is! String ||
          !_peerPattern.hasMatch(id) ||
          pubkey is! String ||
          signature is! String) {
        throw const FormatException('Invalid forum registry record');
      }
      final keyBytes = base64Url.decode(base64Url.normalize(pubkey));
      final rawKey = keyBytes.length == 32
          ? keyBytes
          : keyBytes.length == 44 &&
                _spkiPrefix.asMap().entries.every(
                  (e) => keyBytes[e.key] == e.value,
                )
          ? keyBytes.sublist(12)
          : null;
      final sigBytes = base64Url.decode(base64Url.normalize(signature));
      final payload = Uint8List.fromList(utf8.encode('forum.site|$id|$pubkey'));
      if (rawKey == null ||
          sigBytes.length != 64 ||
          !ed25519.verify(
            ed25519.PublicKey(Uint8List.fromList(rawKey)),
            payload,
            Uint8List.fromList(sigBytes),
          )) {
        throw const FormatException('Forum registry signature failed');
      }
      _forumPeerId = id;
      _expires = DateTime.now().add(const Duration(minutes: 5));
      return id;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> get(String path, {String? keyOverride}) async {
    if (peerId.isEmpty) throw StateError('Mercury identity is not ready');
    await _loadKey();
    final forumPeer = await _resolveForum();
    final key = keyOverride ?? _key;
    final uri = Uri.parse(path);
    final requestPath = key == null
        ? path
        : uri
              .replace(queryParameters: {...uri.queryParameters, 'k': key})
              .toString();
    final body = await relay.fetchMeshText(forumPeer, peerId, requestPath);
    final json = jsonDecode(body);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Invalid forum response');
    }
    return json;
  }
}
