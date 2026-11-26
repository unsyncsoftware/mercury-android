import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:unsync/models/contact.dart';
import 'package:unsync/screens/chat_screen.dart';
import 'package:unsync/services/chat_image.dart';

const contact = Contact(
  id: '1795497595096',
  name: 'coolkid',
  initials: 'CK',
  lastMessage: '',
  time: '',
  online: true,
);

Uint8List smallPng() {
  final image = img.Image(width: 60, height: 40);
  img.fill(image, color: img.ColorRgb8(200, 30, 30));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  testWidgets('a picture too large to send shows a message and sends nothing', (tester) async {
    var encryptCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: ChatScreen(
        contact: contact,
        connectionNotifier: ValueNotifier(true),
        onEncrypt: (text) async {
          encryptCalls++;
          return 'cipher';
        },
        pickPicture: () async => smallPng(),
        buildPictureEnvelope: (bytes, caption) async => null,
      ),
    ));
    await tester.tap(find.byTooltip('Attach picture'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Picture too large to send'), findsOneWidget);
    expect(encryptCalls, 0);
  });

  testWidgets('cancelling the picker sends nothing', (tester) async {
    var encryptCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: ChatScreen(
        contact: contact,
        connectionNotifier: ValueNotifier(true),
        onEncrypt: (text) async {
          encryptCalls++;
          return 'cipher';
        },
        pickPicture: () async => null,
      ),
    ));
    await tester.tap(find.byTooltip('Attach picture'));
    await tester.pump();
    expect(encryptCalls, 0);
    expect(find.text('Picture too large to send'), findsNothing);
  });

  testWidgets('a picture is encrypted as an envelope and saved with its caption', (tester) async {
    String? encrypted;
    String? savedPath;
    String? savedCaption;
    late Directory root;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('send_pic_test');
    });
    await tester.pumpWidget(MaterialApp(
      home: ChatScreen(
        contact: contact,
        connectionNotifier: ValueNotifier(true),
        imageRoot: root,
        onEncrypt: (text) async {
          encrypted = text;
          return 'cipher';
        },
        onMessageSaved: (text, isSent, {imagePath, caption}) {
          savedPath = imagePath;
          savedCaption = caption;
        },
        pickPicture: () async => smallPng(),
        buildPictureEnvelope: (bytes, caption) async => buildImageEnvelope(bytes, caption: caption),
      ),
    ));
    await tester.enterText(find.byType(TextField), 'sunset');
    await tester.tap(find.byTooltip('Attach picture'));
    // The save does several real file operations; each needs a real event-loop
    // turn before the fake-async continuation can run, so alternate.
    for (var i = 0; i < 40 && savedPath == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(encrypted, isNotNull);
    final env = parseImageEnvelope(encrypted!)!;
    expect(env.caption, 'sunset');
    expect(savedCaption, 'sunset');
    expect(File(savedPath!).existsSync(), isTrue);
    await tester.runAsync(() => root.delete(recursive: true));
  });

  testWidgets('if saving the local copy fails after sending, it says so instead of "could not send"', (tester) async {
    var encryptCalls = 0;
    late Directory root;
    late File blocker;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('send_pic_fail');
      // A file where the "chat_images" folder should be makes the save fail.
      blocker = File('${root.path}${Platform.pathSeparator}chat_images');
      await blocker.writeAsString('not a folder');
    });
    await tester.pumpWidget(MaterialApp(
      home: ChatScreen(
        contact: contact,
        connectionNotifier: ValueNotifier(true),
        imageRoot: root,
        onEncrypt: (text) async {
          encryptCalls++;
          return 'cipher';
        },
        pickPicture: () async => smallPng(),
        buildPictureEnvelope: (bytes, caption) async => buildImageEnvelope(bytes, caption: caption),
      ),
    ));
    await tester.tap(find.byTooltip('Attach picture'));
    for (var i = 0; i < 40 && encryptCalls == 0; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(encryptCalls, 1);
    expect(find.text('Sent, but a copy could not be saved on this device'), findsOneWidget);
    expect(find.text('Could not send that picture'), findsNothing);
    await tester.runAsync(() => root.delete(recursive: true));
  });
}
