import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:unsync/services/account_removal.dart';

void main() {
  late Directory root;
  late Directory documents;
  late Directory support;
  late Directory legacy;

  setUp(() {
    root = Directory.systemTemp.createTempSync('mercury_removal');
    documents = Directory('${root.path}/Documents')..createSync();
    support = Directory('${root.path}/Unsync Software/Mercury Messenger')
      ..createSync(recursive: true);
    legacy = Directory('${root.path}/com.example/Mercury')
      ..createSync(recursive: true);
  });
  tearDown(() => root.deleteSync(recursive: true));

  File touch(Directory dir, String name) =>
      File('${dir.path}/$name')..writeAsStringSync('x');

  test('deletes Mercury photos and chat pictures from Documents', () async {
    touch(documents, 'profile_photo.jpg');
    touch(documents, 'contact_photo_1795497595096.jpg');
    Directory('${documents.path}/chat_images/1795497595096')
        .createSync(recursive: true);
    touch(Directory('${documents.path}/chat_images/1795497595096'), '1.jpg');

    await AccountRemoval.wipeFiles(documents: documents);

    expect(File('${documents.path}/profile_photo.jpg').existsSync(), isFalse);
    expect(
      File('${documents.path}/contact_photo_1795497595096.jpg').existsSync(),
      isFalse,
    );
    expect(Directory('${documents.path}/chat_images').existsSync(), isFalse);
  });

  test('never touches anything else in Documents', () async {
    touch(documents, 'my tax return.pdf');
    touch(documents, 'holiday.jpg');
    touch(documents, 'contact_photo_notes.txt');
    Directory('${documents.path}/Work').createSync();

    await AccountRemoval.wipeFiles(documents: documents);

    expect(File('${documents.path}/my tax return.pdf').existsSync(), isTrue);
    expect(File('${documents.path}/holiday.jpg').existsSync(), isTrue);
    expect(File('${documents.path}/contact_photo_notes.txt').existsSync(), isTrue);
    expect(Directory('${documents.path}/Work').existsSync(), isTrue);
  });

  test('deletes the settings, keys and every safety copy', () async {
    for (final name in [
      'shared_preferences.json',
      'shared_preferences.json.last-good',
      'shared_preferences.json.damaged-123',
      'shared_preferences.json.pre-migration',
      'flutter_secure_storage.dat',
      'flutter_secure_storage.dat.last-good',
    ]) {
      touch(support, name);
    }
    touch(support, 'unrelated.log');

    await AccountRemoval.wipeFiles(documents: documents, support: support);

    final left = support.listSync().map((e) => e.uri.pathSegments.last).toList();
    expect(left, ['unrelated.log']);
  });

  test('deletes the old pre-rename folder files so the migration cannot restore them',
      () async {
    touch(legacy, 'shared_preferences.json');
    touch(legacy, 'flutter_secure_storage.dat');

    await AccountRemoval.wipeFiles(documents: documents, legacy: legacy);

    expect(legacy.listSync(), isEmpty);
  });

  test('missing folders are fine', () async {
    final gone = Directory('${root.path}/nope');
    final deleted = await AccountRemoval.wipeFiles(
      documents: gone,
      support: gone,
      legacy: gone,
    );
    expect(deleted, isEmpty);
  });
}
