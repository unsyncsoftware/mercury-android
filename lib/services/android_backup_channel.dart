import 'package:flutter/services.dart';

import 'auto_backup.dart';

/// Talks to BackupDocuments.kt: folder and file pickers (Storage Access
/// Framework) and writing the backup into the chosen folder.
class AndroidBackupChannel {
  static const channel = MethodChannel('uk.unsync.messenger/backup');

  /// Lets the user choose a folder. Null when cancelled.
  static Future<({String uri, String name})?> pickFolder() async {
    final result = await channel.invokeMapMethod<String, dynamic>('pickFolder');
    if (result == null) return null;
    return (uri: result['uri'] as String, name: result['name'] as String? ?? 'Folder');
  }

  /// Lets the user choose a backup file. Null when cancelled.
  static Future<({String name, Uint8List bytes})?> pickFile() async {
    final result = await channel.invokeMapMethod<String, dynamic>('pickFile');
    if (result == null) return null;
    return (name: result['name'] as String? ?? 'backup', bytes: result['bytes'] as Uint8List);
  }
}

/// A folder chosen through the Storage Access Framework.
class SafBackupLocation implements BackupLocation {
  SafBackupLocation(this.uri);
  final String uri;

  @override
  Future<bool> isAvailable() async {
    if (uri.isEmpty) return false;
    try {
      return await AndroidBackupChannel.channel.invokeMethod<bool>('isAvailable', {'uri': uri}) ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> write(String fileName, Uint8List bytes) async {
    await AndroidBackupChannel.channel.invokeMethod<bool>(
      'write',
      {'uri': uri, 'name': fileName, 'bytes': bytes},
    );
  }
}
