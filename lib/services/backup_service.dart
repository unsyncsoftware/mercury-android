import 'dart:convert';
import 'dart:typed_data';

import 'backup_crypto.dart';

/// Where the backup reads from and restores to. The real implementation sits on
/// SharedPreferences, secure storage and the documents folder; tests use a fake.
abstract class BackupStore {
  Future<String?> readPref(String key);
  Future<void> writePref(String key, String value);
  Future<List<String>> prefKeys();
  Future<String?> readSecure(String key);
  Future<void> writeSecure(String key, String value);

  /// Reads a file in the app documents folder by plain name, or null.
  Future<Uint8List?> readFile(String name);

  /// Writes a file in the app documents folder and returns its full path.
  Future<String> writeFile(String name, Uint8List bytes);
}

/// Restore was asked to run on a device that already has an account.
class BackupTargetNotEmptyException implements Exception {
  @override
  String toString() => 'BackupTargetNotEmptyException: this device already has an account';
}

/// Builds and restores the account backup.
///
/// Free-tier scope: identity, keys, contacts, message text and profile photos.
/// Chat attachments (pictures, files) are never included. Signal sessions and
/// pre-keys are not included either; a restored identity creates fresh ones.
class BackupService {
  static const _format = 1;
  static const _keyPeerId = 'peer_id';
  static const _keyDisplayName = 'display_name';
  static const _keyHandle = 'handle';
  static const _keyContacts = 'contacts';
  static const _keyProfilePhotoPath = 'profile_photo_path';
  static const _messagesPrefix = 'messages_';
  static const _contactPhotoPrefix = 'contact_photo_';
  static const _ownPhotoFile = 'profile_photo.jpg';

  static const _keyMeshIdentity = 'mesh_identity_bundle';
  static const _keySignalIdentity = 'signal_identity_key_pair';
  static const _keySignalRegistration = 'signal_registration_id';
  static const _secureKeys = [_keyMeshIdentity, _keySignalIdentity, _keySignalRegistration];

  static final _photoFileName = RegExp(r'^contact_photo_[A-Za-z0-9_-]+\.jpg$');

  /// Shown in place of an attachment that is not in the backup.
  static const attachmentPlaceholder = 'Attachment not included in backup';

  static Future<Uint8List> createBackup(
    BackupStore store,
    String passphrase, {
    int logN = BackupCrypto.defaultLogN,
  }) async {
    final snapshot = await buildSnapshot(store);
    return BackupCrypto.encrypt(snapshot, passphrase, logN: logN);
  }

  static Future<void> restoreBackup(
    BackupStore store,
    Uint8List file,
    String passphrase,
  ) async {
    final snapshot = BackupCrypto.decrypt(file, passphrase);
    await restoreSnapshot(store, snapshot);
  }

  static Future<Uint8List> buildSnapshot(BackupStore store) async {
    final peerId = await store.readPref(_keyPeerId);
    if (peerId == null || peerId.isEmpty) {
      throw StateError('There is no account to back up');
    }
    final prefs = <String, String>{_keyPeerId: peerId};
    final displayName = await store.readPref(_keyDisplayName);
    if (displayName != null) prefs[_keyDisplayName] = displayName;
    final handle = await store.readPref(_keyHandle);
    if (handle != null) prefs[_keyHandle] = handle;
    final contacts = await store.readPref(_keyContacts);
    if (contacts != null) prefs[_keyContacts] = contacts;

    for (final key in await store.prefKeys()) {
      if (!key.startsWith(_messagesPrefix)) continue;
      final raw = await store.readPref(key);
      if (raw != null) prefs[key] = _withoutAttachments(raw);
    }

    final secure = <String, String>{};
    for (final key in _secureKeys) {
      final value = await store.readSecure(key);
      if (value != null) secure[key] = value;
    }

    final files = <String, String>{};
    Future<void> addFile(String name) async {
      final bytes = await store.readFile(name);
      if (bytes != null) files[name] = base64Encode(bytes);
    }

    await addFile(_ownPhotoFile);
    if (contacts != null) {
      for (final c in _decodeList(contacts)) {
        final id = c is Map ? c['peerId'] : null;
        if (id is String && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
          await addFile('$_contactPhotoPrefix$id.jpg');
        }
      }
    }

    final snapshot = {
      'format': _format,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'prefs': prefs,
      'secure': secure,
      'files': files,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(snapshot)));
  }

  static Future<void> restoreSnapshot(BackupStore store, Uint8List bytes) async {
    // Validate everything before writing anything, so a bad file changes nothing.
    final Map<String, dynamic> snapshot;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      snapshot = decoded;
    } on FormatException {
      throw BackupFormatException('Backup content is not readable');
    }
    if (snapshot['format'] != _format) {
      throw BackupFormatException('Unsupported backup content version');
    }
    final prefs = _stringMap(snapshot['prefs']);
    final secure = _stringMap(snapshot['secure']);
    final files = _stringMap(snapshot['files']);

    final peerId = prefs[_keyPeerId];
    if (peerId == null || peerId.isEmpty) {
      throw BackupFormatException('Backup has no account id');
    }
    for (final key in _secureKeys) {
      if ((secure[key] ?? '').isEmpty) {
        throw BackupFormatException('Backup is missing $key');
      }
    }
    try {
      final bundle = jsonDecode(secure[_keyMeshIdentity]!);
      if (bundle is! Map || bundle['peerId'] != peerId) {
        throw BackupFormatException('Backup identity does not match the account id');
      }
    } on FormatException {
      throw BackupFormatException('Backup identity is not readable');
    }
    final photos = <String, Uint8List>{};
    for (final entry in files.entries) {
      final name = entry.key;
      if (name != _ownPhotoFile && !_photoFileName.hasMatch(name)) {
        throw BackupFormatException('Backup contains an unexpected file');
      }
      try {
        photos[name] = base64Decode(entry.value);
      } on FormatException {
        throw BackupFormatException('Backup photo is not readable');
      }
    }

    // An account counts as existing once it has a display name. The splash
    // screen makes a peer id earlier than that, and restore replaces it.
    final existingName = await store.readPref(_keyDisplayName);
    if (existingName != null && existingName.isNotEmpty) {
      throw BackupTargetNotEmptyException();
    }

    for (final entry in secure.entries) {
      if (_secureKeys.contains(entry.key)) {
        await store.writeSecure(entry.key, entry.value);
      }
    }
    for (final entry in photos.entries) {
      final path = await store.writeFile(entry.key, entry.value);
      if (entry.key == _ownPhotoFile) {
        await store.writePref(_keyProfilePhotoPath, path);
      } else {
        final id = entry.key.substring(
          _contactPhotoPrefix.length,
          entry.key.length - '.jpg'.length,
        );
        await store.writePref('$_contactPhotoPrefix$id', path);
      }
    }
    for (final entry in prefs.entries) {
      final k = entry.key;
      final allowed = k == _keyPeerId ||
          k == _keyDisplayName ||
          k == _keyHandle ||
          k == _keyContacts ||
          k.startsWith(_messagesPrefix);
      // The account id goes last, so a half-finished restore still looks empty.
      if (allowed && k != _keyPeerId) await store.writePref(k, entry.value);
    }
    await store.writePref(_keyPeerId, peerId);
  }

  static List<dynamic> _decodeList(String raw) {
    try {
      final v = jsonDecode(raw);
      return v is List ? v : const [];
    } on FormatException {
      return const [];
    }
  }

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) return {};
    return {
      for (final e in value.entries)
        if (e.key is String && e.value is String) e.key as String: e.value as String,
    };
  }

  static String _withoutAttachments(String rawMessages) {
    final list = _decodeList(rawMessages);
    final cleaned = list.map((m) {
      if (m is! Map || m['imagePath'] == null) return m;
      final copy = Map<String, dynamic>.from(m);
      copy.remove('imagePath');
      final caption = copy['caption'];
      copy['text'] = caption is String && caption.isNotEmpty
          ? '$attachmentPlaceholder: $caption'
          : attachmentPlaceholder;
      return copy;
    }).toList();
    return jsonEncode(cleaned);
  }
}
