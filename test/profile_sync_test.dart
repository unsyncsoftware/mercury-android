import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:unsync/services/profile_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List jpeg(int w, int h, {bool noise = false}) {
  final image = img.Image(width: w, height: h);
  final rnd = Random(3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      noise
          ? image.setPixelRgb(x, y, rnd.nextInt(256), rnd.nextInt(256), rnd.nextInt(256))
          : image.setPixelRgb(x, y, 40, 160, 90);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 82));
}

String envelope({Object? type = 'profile', Object? photo}) =>
    jsonEncode({'mercury': 1, 'type': type, 'photo': photo});

void main() {
  group('envelope', () {
    test('build then parse round trips the photo bytes', () {
      final photo = jpeg(160, 160);
      final json = buildProfileEnvelope(photo);
      expect(json, isNotNull);
      expect(parseProfileEnvelope(json!), photo);
      expect(looksLikeProfileEnvelope(json), isTrue);
    });

    test('build rejects a photo that is too large, not an image, or too big in pixels', () {
      expect(buildProfileEnvelope(jpeg(300, 300, noise: true)), isNull); // > 40 KB
      expect(buildProfileEnvelope(Uint8List.fromList([1, 2, 3])), isNull);
      expect(buildProfileEnvelope(jpeg(600, 100)), isNull); // > 512 px
    });

    test('parse rejects bad base64, empty, oversized and non-image data', () {
      expect(parseProfileEnvelope(envelope(photo: '!!!')), isNull);
      expect(parseProfileEnvelope(envelope(photo: '')), isNull);
      expect(parseProfileEnvelope(envelope(photo: base64Encode(List<int>.filled(50000, 1)))), isNull);
      expect(parseProfileEnvelope(envelope(photo: base64Encode(List<int>.filled(100, 1)))), isNull);
      expect(parseProfileEnvelope(envelope(photo: base64Encode(jpeg(600, 100)))), isNull);
    });

    test('an invalid profile still looks like one; text and pictures do not', () {
      expect(looksLikeProfileEnvelope(envelope(photo: '!!!')), isTrue);
      expect(looksLikeProfileEnvelope('hello'), isFalse);
      expect(looksLikeProfileEnvelope(envelope(type: 'image', photo: 'x')), isFalse);
      expect(parseProfileEnvelope(envelope(type: 'image', photo: base64Encode(jpeg(40, 40)))), isNull);
    });
  });

  group('ProfileSync', () {
    late Directory dir;
    late File photo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dir = await Directory.systemTemp.createTemp('profile_sync');
      photo = File('${dir.path}${Platform.pathSeparator}profile_photo.jpg');
      await photo.writeAsBytes(jpeg(160, 160));
    });
    tearDown(() => dir.delete(recursive: true));

    test('sends once per contact, then not again', () async {
      expect(await ProfileSync.pendingProfileEnvelope('1', photo.path), isNotNull);
      await ProfileSync.markSent('1', photo.path);
      expect(await ProfileSync.pendingProfileEnvelope('1', photo.path), isNull);
    });

    test('each contact is tracked separately', () async {
      await ProfileSync.markSent('1', photo.path);
      expect(await ProfileSync.pendingProfileEnvelope('2', photo.path), isNotNull);
    });

    test('a changed photo is sent again', () async {
      await ProfileSync.markSent('1', photo.path);
      await photo.writeAsBytes(jpeg(128, 128));
      expect(await ProfileSync.pendingProfileEnvelope('1', photo.path), isNotNull);
    });

    test('nothing to send without a photo file', () async {
      expect(await ProfileSync.pendingProfileEnvelope('1', null), isNull);
      expect(await ProfileSync.pendingProfileEnvelope('1', '${dir.path}/missing.jpg'), isNull);
    });
  });
}
