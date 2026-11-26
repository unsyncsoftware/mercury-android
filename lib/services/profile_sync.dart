import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'chat_image.dart';

/// Profile photos travel as a small encrypted message over the normal chat
/// path (relay or direct), not only in the direct-connection handshake.
///
/// Envelope (Signal plaintext): {"mercury":1,"type":"profile","photo":"<base64>"}
const int kMaxProfilePhotoBytes = 40000;
const int kMaxProfilePhotoSide = 512;

bool _photoLooksValid(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > kMaxProfilePhotoBytes) return false;
  final dims = peekImageDimensions(bytes);
  return dims != null &&
      dims[0] >= 1 &&
      dims[1] >= 1 &&
      dims[0] <= kMaxProfilePhotoSide &&
      dims[1] <= kMaxProfilePhotoSide;
}

/// The envelope for [photo], or null if it is too large, too big in pixels,
/// or not a readable image.
String? buildProfileEnvelope(Uint8List photo) {
  if (!_photoLooksValid(photo)) return null;
  return jsonEncode({'mercury': 1, 'type': 'profile', 'photo': base64Encode(photo)});
}

Map<String, dynamic>? _profileMap(String plaintext) {
  if (!plaintext.startsWith('{')) return null;
  try {
    final data = jsonDecode(plaintext);
    if (data is Map<String, dynamic> && data['mercury'] == 1 && data['type'] == 'profile') {
      return data;
    }
  } catch (_) {}
  return null;
}

/// True when the text claims to be a profile envelope, valid or not, so it is
/// never shown as chat text.
bool looksLikeProfileEnvelope(String plaintext) => _profileMap(plaintext) != null;

/// The photo bytes of a valid profile envelope, else null.
Uint8List? parseProfileEnvelope(String plaintext) {
  final photo = _profileMap(plaintext)?['photo'];
  if (photo is! String || photo.isEmpty) return null;
  Uint8List bytes;
  try {
    bytes = base64Decode(photo);
  } catch (_) {
    return null;
  }
  return _photoLooksValid(bytes) ? bytes : null;
}

/// Tracks which of our photo revisions each contact has been sent.
class ProfileSync {
  static String _key(String peerId) => 'profile_sent_$peerId';

  /// "<length>:<modified ms>" of the photo file, or null if there is none.
  static Future<String?> _revisionOf(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final stat = await file.stat();
      return '${stat.size}:${stat.modified.millisecondsSinceEpoch}';
    } catch (_) {
      return null;
    }
  }

  /// The envelope to send to [peerId], or null when there is no valid photo or
  /// this revision was already sent to that contact.
  static Future<String?> pendingProfileEnvelope(String peerId, String? photoPath) async {
    final revision = await _revisionOf(photoPath);
    if (revision == null) return null;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_key(peerId)) == revision) return null;
    try {
      return buildProfileEnvelope(await File(photoPath!).readAsBytes());
    } catch (_) {
      return null;
    }
  }

  /// Records that the current photo revision reached [peerId].
  static Future<void> markSent(String peerId, String? photoPath) async {
    final revision = await _revisionOf(photoPath);
    if (revision == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(peerId), revision);
  }
}
