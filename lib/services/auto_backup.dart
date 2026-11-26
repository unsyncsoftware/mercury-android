import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;

import 'backup_crypto.dart';
import 'backup_service.dart';

/// Where the backup file is kept. The user picks a folder once.
abstract class BackupLocation {
  Future<bool> isAvailable();

  /// Replaces [fileName] with [bytes] without ever leaving a half-written file.
  Future<void> write(String fileName, Uint8List bytes);
}

/// A plain folder on disk (used on Windows).
class DirectoryBackupLocation implements BackupLocation {
  DirectoryBackupLocation(this.path);
  final String path;

  @override
  Future<bool> isAvailable() => Directory(path).exists();

  @override
  Future<void> write(String fileName, Uint8List bytes) async {
    final sep = Platform.pathSeparator;
    final temp = File('$path$sep$fileName.tmp');
    final target = File('$path$sep$fileName');
    await temp.writeAsBytes(bytes, flush: true);
    try {
      await temp.rename(target.path);
    } on FileSystemException {
      // Windows refuses to rename over an existing file in some cases.
      if (await target.exists()) await target.delete();
      await temp.rename(target.path);
    }
  }
}

enum BackupRunResult { notConfigured, notDue, done, failed }

class BackupStatus {
  BackupStatus({
    required this.enabled,
    required this.folder,
    required this.lastSuccess,
    required this.lastError,
  });
  final bool enabled;
  final String? folder;
  final DateTime? lastSuccess;
  final String? lastError;

  bool isStale(DateTime now) =>
      enabled &&
      (lastSuccess == null || now.difference(lastSuccess!) > AutoBackup.staleAfter);
}

typedef BackupEncryptor = Future<Uint8List> Function(Uint8List snapshot, String passphrase);

Uint8List _encryptJob(List<Object> args) =>
    BackupCrypto.encrypt(args[0] as Uint8List, args[1] as String);

Future<Uint8List> _isolateEncrypt(Uint8List snapshot, String passphrase) =>
    compute(_encryptJob, [snapshot, passphrase]);

/// Keeps the backup file up to date after a one-time setup.
class AutoBackup {
  AutoBackup({
    required this.store,
    required this.location,
    DateTime Function()? clock,
    BackupEncryptor? encryptor,
  })  : _clock = clock ?? DateTime.now,
        _encryptor = encryptor ?? _isolateEncrypt;

  static const fileName = 'Mercury.mercurybackup';
  static const minInterval = Duration(hours: 1);
  static const staleAfter = Duration(days: 30);

  static const _kEnabled = 'backup_enabled';
  static const _kFolder = 'backup_folder';
  static const _kLastSuccess = 'backup_last_success';
  static const _kLastError = 'backup_last_error';
  static const _kPassphrase = 'backup_passphrase';

  final BackupStore store;
  final BackupLocation location;
  final DateTime Function() _clock;
  final BackupEncryptor _encryptor;

  /// Turns automatic backup on. The passphrase goes to secure storage only.
  Future<void> configure({required String passphrase, String? folder}) async {
    if (passphrase.isEmpty) throw ArgumentError('A passphrase is required');
    await store.writeSecure(_kPassphrase, passphrase);
    if (folder != null) await store.writePref(_kFolder, folder);
    await store.writePref(_kEnabled, 'true');
    await store.writePref(_kLastError, '');
  }

  Future<void> disable() => store.writePref(_kEnabled, 'false');

  Future<BackupStatus> status() async {
    final last = await store.readPref(_kLastSuccess);
    final err = await store.readPref(_kLastError);
    return BackupStatus(
      enabled: (await store.readPref(_kEnabled)) == 'true',
      folder: await store.readPref(_kFolder),
      lastSuccess: last == null || last.isEmpty ? null : DateTime.tryParse(last),
      lastError: err == null || err.isEmpty ? null : err,
    );
  }

  /// Writes the backup if one is due. Never throws; problems are recorded in
  /// [status] so the app can show a warning.
  Future<BackupRunResult> runIfDue({bool force = false}) async {
    final s = await status();
    final passphrase = await store.readSecure(_kPassphrase);
    final hasAccount = (await store.readPref('display_name') ?? '').isNotEmpty;
    if (!s.enabled || passphrase == null || passphrase.isEmpty || !hasAccount) {
      return BackupRunResult.notConfigured;
    }
    final now = _clock();
    if (!force && s.lastSuccess != null && now.difference(s.lastSuccess!) < minInterval) {
      return BackupRunResult.notDue;
    }
    try {
      if (!await location.isAvailable()) {
        throw const FileSystemException('The backup folder is not reachable');
      }
      final snapshot = await BackupService.buildSnapshot(store);
      final sealed = await _encryptor(snapshot, passphrase);
      await location.write(fileName, sealed);
      await store.writePref(_kLastSuccess, now.toUtc().toIso8601String());
      await store.writePref(_kLastError, '');
      return BackupRunResult.done;
    } catch (e) {
      await store.writePref(_kLastError, e.toString());
      return BackupRunResult.failed;
    }
  }
}
