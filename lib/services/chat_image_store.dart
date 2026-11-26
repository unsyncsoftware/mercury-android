import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Picture bytes live in files, never in the preferences JSON.
class ChatImageStore {
  /// Writes [bytes] to `chat_images/<peerId>/<epochMillis>.jpg` under [root]
  /// (default: the app documents directory) and returns the file path. The
  /// peer id is sanitised so it can never point outside the folder.
  static Future<String> save(
    String peerId,
    Uint8List bytes, {
    Directory? root,
  }) async {
    final base = root ?? await getApplicationDocumentsDirectory();
    final safePeer = peerId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}chat_images${Platform.pathSeparator}$safePeer',
    );
    await dir.create(recursive: true);
    var stamp = DateTime.now().millisecondsSinceEpoch;
    var file = File('${dir.path}${Platform.pathSeparator}$stamp.jpg');
    while (await file.exists()) {
      stamp++;
      file = File('${dir.path}${Platform.pathSeparator}$stamp.jpg');
    }
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
