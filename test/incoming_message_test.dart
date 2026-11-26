import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unsync/services/chat_image.dart';
import 'package:unsync/services/incoming_message.dart';
import 'package:unsync/services/messages_service.dart';

String pictureEnvelope({String? caption}) {
  final image = img.Image(width: 40, height: 20);
  img.fill(image, color: img.ColorRgb8(10, 200, 30));
  return buildImageEnvelope(
    Uint8List.fromList(img.encodePng(image)),
    caption: caption,
  )!;
}

void main() {
  late Directory root;
  late MessagesService messages;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('incoming_test');
    messages = MessagesService();
  });
  tearDown(() => root.delete(recursive: true));

  test('plain text is stored as text and previews as itself', () async {
    final preview = await storeIncomingMessage(messages, '7', 'hello', imageRoot: root);
    final stored = (await messages.getMessages('7')).single;
    expect(preview, 'hello');
    expect(stored.text, 'hello');
    expect(stored.imagePath, isNull);
    expect(stored.isSent, isFalse);
  });

  test('a picture is saved to a file and previews as Photo', () async {
    final preview = await storeIncomingMessage(messages, '7', pictureEnvelope(), imageRoot: root);
    final stored = (await messages.getMessages('7')).single;
    expect(preview, 'Photo');
    expect(stored.text, '');
    expect(File(stored.imagePath!).existsSync(), isTrue);
    expect(stored.imagePath!.startsWith(root.path), isTrue);
  });

  test('a picture caption is stored and shown in the preview', () async {
    final preview = await storeIncomingMessage(
      messages, '7', pictureEnvelope(caption: 'sunset'), imageRoot: root);
    final stored = (await messages.getMessages('7')).single;
    expect(preview, 'Photo: sunset');
    expect(stored.caption, 'sunset');
  });

  test('an invalid picture envelope becomes a notice, never raw JSON', () async {
    final bad = jsonEncode({'mercury': 1, 'type': 'image', 'mime': 'x', 'w': 1, 'h': 1, 'data': '!!'});
    final preview = await storeIncomingMessage(messages, '7', bad, imageRoot: root);
    final stored = (await messages.getMessages('7')).single;
    expect(preview, kPictureUnavailableText);
    expect(stored.text, kPictureUnavailableText);
    expect(stored.imagePath, isNull);
  });

  test('json that is not an envelope stays ordinary text', () async {
    await storeIncomingMessage(messages, '7', '{"a":1}', imageRoot: root);
    expect((await messages.getMessages('7')).single.text, '{"a":1}');
  });

  group('profile messages', () {
    String profileEnvelope() {
      final photo = img.Image(width: 64, height: 64);
      img.fill(photo, color: img.ColorRgb8(40, 160, 90));
      return jsonEncode({
        'mercury': 1,
        'type': 'profile',
        'photo': base64Encode(img.encodeJpg(photo)),
      });
    }

    test('a valid profile is handed to onProfile and never stored or notified', () async {
      String? gotPeer;
      Uint8List? gotBytes;
      final preview = await storeIncomingMessage(
        messages,
        '7',
        profileEnvelope(),
        imageRoot: root,
        onProfile: (peerId, bytes) async {
          gotPeer = peerId;
          gotBytes = bytes;
        },
      );
      expect(preview, isNull);
      expect(gotPeer, '7');
      expect(gotBytes, isNotEmpty);
      expect(await messages.getMessages('7'), isEmpty);
    });

    test('an invalid profile is dropped silently, not shown as text', () async {
      var called = false;
      final bad = jsonEncode({'mercury': 1, 'type': 'profile', 'photo': '!!!'});
      final preview = await storeIncomingMessage(
        messages,
        '7',
        bad,
        imageRoot: root,
        onProfile: (peerId, bytes) async => called = true,
      );
      expect(preview, isNull);
      expect(called, isFalse);
      expect(await messages.getMessages('7'), isEmpty);
    });

    test('a profile with no handler is still not shown as text', () async {
      final preview = await storeIncomingMessage(messages, '7', profileEnvelope(), imageRoot: root);
      expect(preview, isNull);
      expect(await messages.getMessages('7'), isEmpty);
    });
  });
}
