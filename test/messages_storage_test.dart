import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:unsync/models/message.dart';
import 'package:unsync/services/chat_image_store.dart';
import 'package:unsync/services/messages_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('old stored json without image fields loads unchanged', () {
    final m = StoredMessage.fromJson({'text': 'hi', 'isSent': true, 'time': 't'});
    expect(m.text, 'hi');
    expect(m.imagePath, isNull);
    expect(m.caption, isNull);
  });

  test('text message json stays in the old format (no image keys)', () {
    final json = StoredMessage(text: 'hi', isSent: false, time: 't').toJson();
    expect(json.keys.toSet(), {'text', 'isSent', 'time'});
  });

  test('image message round trips through json', () {
    final m = StoredMessage(
      text: '',
      isSent: true,
      time: 't',
      imagePath: r'C:\x\a.jpg',
      caption: 'cap',
    );
    final back = StoredMessage.fromJson(m.toJson());
    expect(back.imagePath, r'C:\x\a.jpg');
    expect(back.caption, 'cap');
  });

  test('Message carries optional image fields', () {
    const m = Message(
      text: '',
      isSent: true,
      time: '10:00',
      imagePath: 'p.jpg',
      caption: 'c',
    );
    expect(m.imagePath, 'p.jpg');
    expect(m.caption, 'c');
    expect(const Message(text: 'x', isSent: true, time: 't').imagePath, isNull);
  });

  test('MessagesService persists an image message and reloads it', () async {
    SharedPreferences.setMockInitialValues({});
    await MessagesService().addMessage('42', '', true, imagePath: 'p.jpg', caption: 'c');
    final fresh = await MessagesService().getMessages('42');
    expect(fresh.single.imagePath, 'p.jpg');
    expect(fresh.single.caption, 'c');
  });

  test('ChatImageStore.save writes the bytes under the peer folder', () async {
    final root = await Directory.systemTemp.createTemp('chat_img_test');
    addTearDown(() => root.delete(recursive: true));
    final path = await ChatImageStore.save('1795497595096', Uint8List.fromList([1, 2, 3]), root: root);
    expect(path.contains('chat_images'), isTrue);
    expect(path.contains('1795497595096'), isTrue);
    expect(await File(path).readAsBytes(), [1, 2, 3]);
  });

  test('ChatImageStore.save cannot escape its root via the peer id', () async {
    final root = await Directory.systemTemp.createTemp('chat_img_test');
    addTearDown(() => root.delete(recursive: true));
    final path = await ChatImageStore.save('../../evil', Uint8List.fromList([9]), root: root);
    expect(File(path).absolute.path.startsWith(root.absolute.path), isTrue);
  });
}
