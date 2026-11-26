import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'android_backup_channel.dart';
import 'auto_backup.dart';
import 'backup_crypto.dart';
import 'backup_service.dart';

/// [BackupStore] on the real app storage.
class PlatformBackupStore implements BackupStore {
  PlatformBackupStore({FlutterSecureStorage? secure})
      : _secure = secure ?? const FlutterSecureStorage();
  final FlutterSecureStorage _secure;

  @override
  Future<String?> readPref(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> writePref(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);

  @override
  Future<List<String>> prefKeys() async =>
      (await SharedPreferences.getInstance()).getKeys().toList();

  @override
  Future<String?> readSecure(String key) => _secure.read(key: key);

  @override
  Future<void> writeSecure(String key, String value) =>
      _secure.write(key: key, value: value);

  @override
  Future<Uint8List?> readFile(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    return await file.exists() ? file.readAsBytes() : null;
  }

  @override
  Future<String> writeFile(String name, Uint8List bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}

Uint8List _decryptJob(List<Object> args) =>
    BackupCrypto.decrypt(args[0] as Uint8List, args[1] as String);

/// App-level entry points used by the screens.
class BackupController {
  static final PlatformBackupStore store = PlatformBackupStore();

  static Future<AutoBackup> autoBackup() async {
    final folder = await store.readPref('backup_folder') ?? '';
    return AutoBackup(store: store, location: SafBackupLocation(folder));
  }

  /// Safe to call at any time; does nothing unless backup is set up and due.
  static Future<BackupRunResult> runIfDue({bool force = false}) async =>
      (await autoBackup()).runIfDue(force: force);

  /// Restores a backup file on a device that has no account yet.
  static Future<void> restoreFromBytes(Uint8List bytes, String passphrase) async {
    // Decrypt off the UI thread (key derivation is deliberately slow).
    final snapshot = await compute(_decryptJob, [bytes, passphrase]);
    await BackupService.restoreSnapshot(store, snapshot);
  }
}
