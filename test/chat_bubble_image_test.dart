import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:unsync/models/message.dart';
import 'package:unsync/screens/chat_screen.dart';

Widget host(Message m) => MaterialApp(home: Scaffold(body: MessageBubble(message: m)));

void main() {
  testWidgets('text message still shows its text', (tester) async {
    await tester.pumpWidget(host(const Message(text: 'hello', isSent: false, time: '10:00')));
    expect(find.text('hello'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  // Real file IO never completes inside testWidgets' fake-async zone, so all
  // of it happens inside runAsync.
  testWidgets('picture message shows the image and its caption', (tester) async {
    late Directory dir;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('bubble_test');
      final file = File('${dir.path}/p.png');
      await file.writeAsBytes(Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 8))));
      await tester.pumpWidget(host(Message(
        text: '', isSent: false, time: '10:00', imagePath: file.path, caption: 'sunset')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('sunset'), findsOneWidget);
    await tester.runAsync(() => dir.delete(recursive: true));
  });

  testWidgets('a missing picture file shows a notice instead of crashing', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(host(const Message(
        text: '', isSent: false, time: '10:00', imagePath: r'C:\nope\missing.jpg')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Picture could not be displayed'), findsOneWidget);
  });
}
