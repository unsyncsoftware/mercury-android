import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Erases this Mercury account from this device.
///
/// Used by both "Remove from this device" (the account stays on the server and
/// can be restored from a backup) and "Delete my account" (after the server
/// has deleted it). The caller closes the app straight after, so nothing in
/// memory can write the settings back.
class AccountRemoval {
  /// Mercury's own files in the documents folder. On Windows that folder is
  /// the user's Documents, so only these names are ever touched there.
  static const ownPhotoFile = 'profile_photo.jpg';
  static const contactPhotoPrefix = 'contact_photo_';
  static const chatImagesDir = 'chat_images';

  /// Settings and keys, plus Mercury's files on disk.
  static Future<void> wipeThisDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await const FlutterSecureStorage().deleteAll();

    Directory? support;
    Directory? legacy;
    if (Platform.isWindows) {
      support = await getApplicationSupportDirectory();
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        legacy = Directory('$appData\\com.example\\Mercury');
      }
    }
    await wipeFiles(
      documents: await getApplicationDocumentsDirectory(),
      support: support,
      legacy: legacy,
    );
  }

  /// Deletes Mercury's files. [support] is the Windows settings folder: the
  /// settings guard's last-good copies there would otherwise bring the keys
  /// back on the next start. [legacy] is the pre-rename Windows folder, which
  /// the one-time migration would otherwise copy back in. Returns what was
  /// deleted. Never throws: a file that cannot be deleted is skipped.
  static Future<List<String>> wipeFiles({
    required Directory documents,
    Directory? support,
    Directory? legacy,
  }) async {
    final deleted = <String>[];

    Future<void> remove(FileSystemEntity entity) async {
      try {
        if (!await entity.exists()) return;
        await entity.delete(recursive: true);
        deleted.add(entity.path);
      } catch (_) {
        // Locked or already gone: keep going.
      }
    }

    final sep = Platform.pathSeparator;
    await remove(File('${documents.path}$sep$ownPhotoFile'));
    await remove(Directory('${documents.path}$sep$chatImagesDir'));
    if (await documents.exists()) {
      await for (final entity in documents.list(followLinks: false)) {
        final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (entity is File &&
            name.startsWith(contactPhotoPrefix) &&
            name.endsWith('.jpg')) {
          await remove(entity);
        }
      }
    }

    for (final dir in [support, legacy]) {
      if (dir == null || !await dir.exists()) continue;
      await for (final entity in dir.list(followLinks: false)) {
        final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (entity is File && _isSettingsFile(name)) await remove(entity);
      }
    }
    return deleted;
  }

  /// The settings and key files and every copy of them Mercury makes.
  static bool _isSettingsFile(String name) =>
      name.startsWith('shared_preferences.json') ||
      name.startsWith('flutter_secure_storage.dat');
}
