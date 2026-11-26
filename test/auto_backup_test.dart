import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:unsync/services/auto_backup.dart';

import 'backup_service_test.dart' show FakeBackupStore;

class FakeLocation implements BackupLocation {
  FakeLocation({this.available = true, this.failWith});
  bool available;
  Object? failWith;
  final Map<String, Uint8List> written = {};
  int writes = 0;

  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<void> write(String fileName, Uint8List bytes) async {
    if (failWith != null) throw failWith!;
    writes++;
    written[fileName] = bytes;
  }
}

FakeBackupStore _account() {
  final s = FakeBackupStore();
  s.prefs['peer_id'] = '1795315617380';
  s.prefs['display_name'] = 'batman';
  s.secure['mesh_identity_bundle'] =
      '{"peerId":"1795315617380","publicKey":"P","privateKey":"K"}';
  s.secure['signal_identity_key_pair'] = 'K';
  s.secure['signal_registration_id'] = '1';
  return s;
}

// Fast stand-in for the real (slow, isolate-based) encryptor.
Future<Uint8List> _fakeEncrypt(Uint8List snapshot, String passphrase) async =>
    Uint8List.fromList([...utf8.encode('ENC:$passphrase:'), ...snapshot]);

void main() {
  late FakeBackupStore store;
  late FakeLocation location;
  late DateTime now;
  late AutoBackup backup;

  setUp(() {
    store = _account();
    location = FakeLocation();
    now = DateTime.utc(2026, 11, 26, 12);
    backup = AutoBackup(
      store: store,
      location: location,
      clock: () => now,
      encryptor: _fakeEncrypt,
    );
  });

  test('does nothing until backup is set up', () async {
    expect(await backup.runIfDue(), BackupRunResult.notConfigured);
    expect(location.writes, 0);
  });

  test('first run after setup writes the backup file', () async {
    await backup.configure(passphrase: 'pw');
    expect(await backup.runIfDue(), BackupRunResult.done);
    expect(location.written.keys, [AutoBackup.fileName]);
    expect(utf8.decode(location.written[AutoBackup.fileName]!.sublist(0, 6)), 'ENC:pw');
    expect((await backup.status()).lastSuccess, now);
    expect((await backup.status()).lastError, isNull);
  });

  test('a second run within the minimum interval is skipped', () async {
    await backup.configure(passphrase: 'pw');
    await backup.runIfDue();
    now = now.add(const Duration(minutes: 10));
    expect(await backup.runIfDue(), BackupRunResult.notDue);
    expect(location.writes, 1);
  });

  test('a run after the interval writes again over the same file', () async {
    await backup.configure(passphrase: 'pw');
    await backup.runIfDue();
    now = now.add(AutoBackup.minInterval + const Duration(minutes: 1));
    expect(await backup.runIfDue(), BackupRunResult.done);
    expect(location.writes, 2);
    expect(location.written, hasLength(1));
  });

  test('force ignores the interval', () async {
    await backup.configure(passphrase: 'pw');
    await backup.runIfDue();
    expect(await backup.runIfDue(force: true), BackupRunResult.done);
    expect(location.writes, 2);
  });

  test('an unreachable folder records an error and does not throw', () async {
    await backup.configure(passphrase: 'pw');
    location.available = false;
    expect(await backup.runIfDue(), BackupRunResult.failed);
    expect(location.writes, 0);
    expect((await backup.status()).lastError, isNotNull);
  });

  test('a write failure records an error and keeps the last good time', () async {
    await backup.configure(passphrase: 'pw');
    await backup.runIfDue();
    final good = now;
    now = now.add(const Duration(hours: 3));
    location.failWith = const FileSystemException('disk full');
    expect(await backup.runIfDue(), BackupRunResult.failed);
    final s = await backup.status();
    expect(s.lastSuccess, good);
    expect(s.lastError, contains('disk full'));
  });

  test('a later success clears the error', () async {
    await backup.configure(passphrase: 'pw');
    location.available = false;
    await backup.runIfDue();
    location.available = true;
    expect(await backup.runIfDue(), BackupRunResult.done);
    expect((await backup.status()).lastError, isNull);
  });

  test('disabling stops runs', () async {
    await backup.configure(passphrase: 'pw');
    await backup.disable();
    expect(await backup.runIfDue(force: true), BackupRunResult.notConfigured);
  });

  test('no account yet is not an error and writes nothing', () async {
    final empty = AutoBackup(
      store: FakeBackupStore(),
      location: location,
      clock: () => now,
      encryptor: _fakeEncrypt,
    );
    await empty.configure(passphrase: 'pw');
    expect(await empty.runIfDue(), BackupRunResult.notConfigured);
    expect(location.writes, 0);
  });

  test('a backup older than the stale limit is flagged', () async {
    await backup.configure(passphrase: 'pw');
    await backup.runIfDue();
    expect((await backup.status()).isStale(now), isFalse);
    expect(
      (await backup.status()).isStale(now.add(AutoBackup.staleAfter + const Duration(days: 1))),
      isTrue,
    );
  });

  test('configured but never backed up counts as stale', () async {
    await backup.configure(passphrase: 'pw');
    expect((await backup.status()).isStale(now), isTrue);
  });

  test('an empty passphrase is refused at setup', () async {
    expect(() => backup.configure(passphrase: ''), throwsArgumentError);
  });

  test('the passphrase is kept in secure storage, never in plain preferences', () async {
    await backup.configure(passphrase: 'pw-secret');
    expect(store.secure.values, contains('pw-secret'));
    expect(store.prefs.values, isNot(contains('pw-secret')));
  });

  group('DirectoryBackupLocation', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('mbk_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('writes the file and leaves no temp file behind', () async {
      final loc = DirectoryBackupLocation(dir.path);
      await loc.write('a.mercurybackup', Uint8List.fromList([1, 2, 3]));
      expect(File('${dir.path}/a.mercurybackup').readAsBytesSync(), [1, 2, 3]);
      expect(dir.listSync().length, 1);
    });

    test('overwrites the previous backup', () async {
      final loc = DirectoryBackupLocation(dir.path);
      await loc.write('a.mercurybackup', Uint8List.fromList([1]));
      await loc.write('a.mercurybackup', Uint8List.fromList([2, 2]));
      expect(File('${dir.path}/a.mercurybackup').readAsBytesSync(), [2, 2]);
      expect(dir.listSync().length, 1);
    });

    test('a missing folder is reported unavailable', () async {
      final loc = DirectoryBackupLocation('${dir.path}/gone');
      expect(await loc.isAvailable(), isFalse);
      expect(await DirectoryBackupLocation(dir.path).isAvailable(), isTrue);
    });
  });

}
