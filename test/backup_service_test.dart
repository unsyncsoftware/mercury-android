import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:unsync/services/backup_crypto.dart';
import 'package:unsync/services/backup_service.dart';

class FakeBackupStore implements BackupStore {
  final Map<String, String> prefs = {};
  final Map<String, String> secure = {};
  final Map<String, Uint8List> files = {};

  @override
  Future<String?> readPref(String key) async => prefs[key];
  @override
  Future<void> writePref(String key, String value) async => prefs[key] = value;
  @override
  Future<List<String>> prefKeys() async => prefs.keys.toList();
  @override
  Future<String?> readSecure(String key) async => secure[key];
  @override
  Future<void> writeSecure(String key, String value) async => secure[key] = value;
  @override
  Future<Uint8List?> readFile(String name) async => files[name];
  @override
  Future<String> writeFile(String name, Uint8List bytes) async {
    files[name] = bytes;
    return '/restored/$name';
  }
}

const _bundle =
    '{"peerId":"1795315617380","publicKey":"PUB","privateKey":"PRIV"}';

FakeBackupStore _populated() {
  final s = FakeBackupStore();
  s.prefs['peer_id'] = '1795315617380';
  s.prefs['display_name'] = 'batman';
  s.prefs['handle'] = '@batman';
  s.prefs['contacts'] = jsonEncode([
    {'peerId': '1795497595096', 'displayName': 'coolkid', 'addedAt': '2026-11-01T10:00:00.000'},
  ]);
  s.prefs['messages_1795497595096'] = jsonEncode([
    {'text': 'hello', 'isSent': true, 'time': '2026-11-02T10:00:00.000'},
    {
      'text': '',
      'isSent': false,
      'time': '2026-11-02T10:01:00.000',
      'imagePath': 'C:/Users/x/Documents/chat_images/1795497595096/1.jpg',
      'caption': 'my dog',
    },
    {
      'text': '',
      'isSent': false,
      'time': '2026-11-02T10:02:00.000',
      'imagePath': 'C:/Users/x/Documents/chat_images/1795497595096/2.jpg',
    },
  ]);
  s.prefs['biometric_enabled'] = 'true';
  s.prefs['age_confirmed_18_v1'] = 'true';
  s.secure['mesh_identity_bundle'] = _bundle;
  s.secure['signal_identity_key_pair'] = 'SIGNALKEYPAIR';
  s.secure['signal_registration_id'] = '4242';
  s.secure['signal_sessions'] = 'SESSIONS';
  s.secure['signal_pre_keys'] = 'PREKEYS';
  s.secure['signal_signed_pre_keys'] = 'SIGNEDPREKEYS';
  s.files['profile_photo.jpg'] = Uint8List.fromList([1, 2, 3]);
  s.files['contact_photo_1795497595096.jpg'] = Uint8List.fromList([4, 5, 6]);
  s.files['chat_images/1795497595096/1.jpg'] = Uint8List.fromList([9, 9, 9]);
  return s;
}

void main() {
  const pass = 'a long passphrase';
  const fast = 10;

  Future<Uint8List> backupOf(FakeBackupStore s) =>
      BackupService.createBackup(s, pass, logN: fast);

  test('restore brings back identity, keys, contacts and message text', () async {
    final file = await backupOf(_populated());
    final target = FakeBackupStore();
    await BackupService.restoreBackup(target, file, pass);

    expect(target.prefs['peer_id'], '1795315617380');
    expect(target.prefs['display_name'], 'batman');
    expect(target.prefs['handle'], '@batman');
    expect(target.secure['mesh_identity_bundle'], _bundle);
    expect(target.secure['signal_identity_key_pair'], 'SIGNALKEYPAIR');
    expect(target.secure['signal_registration_id'], '4242');
    expect(target.prefs['contacts'], contains('coolkid'));
    final msgs = jsonDecode(target.prefs['messages_1795497595096']!) as List;
    expect(msgs.first['text'], 'hello');
    expect(msgs, hasLength(3));
  });

  test('profile and contact photos are restored and their paths set', () async {
    final file = await backupOf(_populated());
    final target = FakeBackupStore();
    await BackupService.restoreBackup(target, file, pass);

    expect(target.files['profile_photo.jpg'], [1, 2, 3]);
    expect(target.files['contact_photo_1795497595096.jpg'], [4, 5, 6]);
    expect(target.prefs['profile_photo_path'], '/restored/profile_photo.jpg');
    expect(
      target.prefs['contact_photo_1795497595096'],
      '/restored/contact_photo_1795497595096.jpg',
    );
  });

  test('chat attachments are not backed up and leave a placeholder', () async {
    final file = await backupOf(_populated());
    final target = FakeBackupStore();
    await BackupService.restoreBackup(target, file, pass);

    expect(target.files.keys.any((k) => k.startsWith('chat_images')), isFalse);
    final msgs = jsonDecode(target.prefs['messages_1795497595096']!) as List;
    expect(msgs[1].containsKey('imagePath'), isFalse);
    expect(msgs[1]['text'], contains('not included in backup'));
    expect(msgs[1]['text'], contains('my dog'));
    expect(msgs[2]['text'], contains('not included in backup'));
  });

  test('the plain snapshot never contains attachment paths or bytes', () async {
    final snapshot = utf8.decode(await BackupService.buildSnapshot(_populated()));
    expect(snapshot, isNot(contains('chat_images')));
    expect(snapshot, isNot(contains('imagePath')));
  });

  test('sessions, pre-keys and device settings are left out', () async {
    final file = await backupOf(_populated());
    final target = FakeBackupStore();
    await BackupService.restoreBackup(target, file, pass);

    expect(target.secure.containsKey('signal_sessions'), isFalse);
    expect(target.secure.containsKey('signal_pre_keys'), isFalse);
    expect(target.secure.containsKey('signal_signed_pre_keys'), isFalse);
    expect(target.prefs.containsKey('biometric_enabled'), isFalse);
    expect(target.prefs.containsKey('age_confirmed_18_v1'), isFalse);
  });

  test('restore refuses to overwrite an account that already exists', () async {
    final file = await backupOf(_populated());
    final target = FakeBackupStore()
      ..prefs['peer_id'] = '999'
      ..prefs['display_name'] = 'someone';
    await expectLater(
      BackupService.restoreBackup(target, file, pass),
      throwsA(isA<BackupTargetNotEmptyException>()),
    );
    expect(target.prefs['peer_id'], '999');
  });

  test('a fresh install that only has an auto-made peer id can still restore', () async {
    // The splash screen creates a peer id before the user finishes setup.
    final file = await backupOf(_populated());
    final target = FakeBackupStore()..prefs['peer_id'] = '1799999999999';
    await BackupService.restoreBackup(target, file, pass);
    expect(target.prefs['peer_id'], '1795315617380');
    expect(target.prefs['display_name'], 'batman');
  });

  test('wrong passphrase changes nothing', () async {
    final file = await backupOf(_populated());
    final target = FakeBackupStore();
    await expectLater(
      BackupService.restoreBackup(target, file, 'nope'),
      throwsA(isA<BackupDecryptException>()),
    );
    expect(target.prefs, isEmpty);
    expect(target.secure, isEmpty);
  });

  test('a backup without the identity key is refused and writes nothing', () async {
    final s = _populated()..secure.remove('mesh_identity_bundle');
    final file = await backupOf(s);
    final target = FakeBackupStore();
    await expectLater(
      BackupService.restoreBackup(target, file, pass),
      throwsA(isA<BackupFormatException>()),
    );
    expect(target.prefs, isEmpty);
    expect(target.secure, isEmpty);
  });

  test('a backup whose identity key belongs to another peer id is refused', () async {
    final s = _populated()
      ..secure['mesh_identity_bundle'] =
          '{"peerId":"1111111111111","publicKey":"PUB","privateKey":"PRIV"}';
    final file = await backupOf(s);
    final target = FakeBackupStore();
    await expectLater(
      BackupService.restoreBackup(target, file, pass),
      throwsA(isA<BackupFormatException>()),
    );
    expect(target.prefs, isEmpty);
  });

  test('a file name that could escape the folder is refused', () async {
    final snapshot = {
      'format': 1,
      'prefs': {'peer_id': '1795315617380', 'display_name': 'batman'},
      'secure': {
        'mesh_identity_bundle': _bundle,
        'signal_identity_key_pair': 'K',
        'signal_registration_id': '1',
      },
      'files': {'../../evil.jpg': base64Encode([1])},
    };
    final file = BackupCrypto.encrypt(
      Uint8List.fromList(utf8.encode(jsonEncode(snapshot))),
      pass,
      logN: fast,
    );
    final target = FakeBackupStore();
    await expectLater(
      BackupService.restoreBackup(target, file, pass),
      throwsA(isA<BackupFormatException>()),
    );
    expect(target.files, isEmpty);
    expect(target.prefs, isEmpty);
  });

  test('backing up an empty app is refused (nothing to back up)', () async {
    await expectLater(
      BackupService.createBackup(FakeBackupStore(), pass, logN: fast),
      throwsA(isA<StateError>()),
    );
  });
}
