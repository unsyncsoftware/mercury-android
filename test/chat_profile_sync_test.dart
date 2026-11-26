import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:unsync/models/contact.dart';
import 'package:unsync/screens/chat_screen.dart';
import 'package:unsync/services/profile_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

const contact = Contact(
  id: '1795497595096',
  name: 'coolkid',
  initials: 'CK',
  lastMessage: '',
  time: '',
  online: true,
);

// Real file IO needs real event-loop turns; alternate them with pumps.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump();
  }
}

Future<File> makePhoto(WidgetTester tester, String name, int side) async {
  late File photo;
  await tester.runAsync(() async {
    final dir = await Directory.systemTemp.createTemp(name);
    photo = File('${dir.path}${Platform.pathSeparator}p.jpg');
    final image = img.Image(width: side, height: side);
    img.fill(image, color: img.ColorRgb8(10, 120, 200));
    await photo.writeAsBytes(Uint8List.fromList(img.encodeJpg(image)));
  });
  return photo;
}

void main() {
  testWidgets('opening a chat sends our profile once, silently, and not again', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final photo = await makePhoto(tester, 'chat_profile', 120);

    final sent = <String>[];
    Widget chat() => MaterialApp(
      home: ChatScreen(
        contact: contact,
        connectionNotifier: ValueNotifier(true),
        profilePhotoPath: photo.path,
        onEncrypt: (text) async {
          sent.add(text);
          return 'cipher';
        },
      ),
    );

    await tester.pumpWidget(chat());
    await settle(tester);
    expect(sent.length, 1);
    expect(looksLikeProfileEnvelope(sent.single), isTrue);
    expect(find.byType(SnackBar), findsNothing);

    // Re-open: already sent for this photo, so nothing more is sent.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(chat());
    await settle(tester);
    expect(sent.length, 1);

    await tester.runAsync(() => photo.parent.delete(recursive: true));
  });

  testWidgets('a missing session stays silent and retries next time', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final photo = await makePhoto(tester, 'chat_profile2', 100);

    var attempts = 0;
    await tester.pumpWidget(MaterialApp(
      home: ChatScreen(
        contact: contact,
        connectionNotifier: ValueNotifier(true),
        profilePhotoPath: photo.path,
        onEncrypt: (text) async {
          attempts++;
          throw Exception('no session');
        },
      ),
    ));
    await settle(tester);
    expect(attempts, 1);
    expect(find.byType(SnackBar), findsNothing);
    final pending = await tester.runAsync(
      () => ProfileSync.pendingProfileEnvelope(contact.id, photo.path),
    );
    expect(pending, isNotNull);

    await tester.runAsync(() => photo.parent.delete(recursive: true));
  });
}
