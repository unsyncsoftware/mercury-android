import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:unsync/services/chat_image.dart';

Uint8List png(int w, int h, {bool alpha = false}) {
  final image = img.Image(width: w, height: h, numChannels: alpha ? 4 : 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      image.setPixelRgba(x, y, (x * 255) ~/ w, (y * 255) ~/ h, 128, alpha ? 100 : 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List noisePng(int size) {
  final rnd = Random(7);
  final image = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      image.setPixelRgb(x, y, rnd.nextInt(256), rnd.nextInt(256), rnd.nextInt(256));
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

String envelopeJson({
  Object? mime = 'image/jpeg',
  Object? w = 10,
  Object? h = 10,
  Object? data,
  Object? type = 'image',
}) =>
    jsonEncode({
      'mercury': 1,
      'type': type,
      'mime': mime,
      'w': w,
      'h': h,
      'data': data ?? base64Encode(List<int>.filled(100, 1)),
    });

void main() {
  reviewTests();
  test('plain text is not an envelope', () {
    expect(parseImageEnvelope('hello'), isNull);
    expect(looksLikeImageEnvelope('hello'), isFalse);
    expect(parseImageEnvelope('{"a":1}'), isNull);
    expect(looksLikeImageEnvelope('{"a":1}'), isFalse);
  });

  test('build then parse round trip stays within size and dimension caps', () {
    final json = buildImageEnvelope(png(2000, 1000), caption: 'hi');
    expect(json, isNotNull);
    expect(json!.length <= kMaxEnvelopeChars, isTrue);
    final env = parseImageEnvelope(json)!;
    expect(env.mime, 'image/jpeg');
    expect(env.caption, 'hi');
    expect(max(env.w, env.h) <= 1280, isTrue);
    expect(env.bytes.isNotEmpty, isTrue);
  });

  test('does not upscale a small image', () {
    final env = parseImageEnvelope(buildImageEnvelope(png(100, 50))!)!;
    expect(env.w, 100);
    expect(env.h, 50);
  });

  test('rejects wrong mime but still looks like an envelope', () {
    final s = envelopeJson(mime: 'text/html');
    expect(parseImageEnvelope(s), isNull);
    expect(looksLikeImageEnvelope(s), isTrue);
  });

  test('rejects corrupt base64', () {
    final s = envelopeJson(data: '!!!not base64!!!');
    expect(parseImageEnvelope(s), isNull);
    expect(looksLikeImageEnvelope(s), isTrue);
  });

  test('rejects decoded bytes over 150 KB', () {
    final s = envelopeJson(data: base64Encode(List<int>.filled(kMaxReceivedImageBytes + 1, 1)));
    expect(parseImageEnvelope(s), isNull);
    expect(looksLikeImageEnvelope(s), isTrue);
  });

  test('rejects non-positive or non-integer dimensions', () {
    expect(parseImageEnvelope(envelopeJson(w: 0)), isNull);
    expect(parseImageEnvelope(envelopeJson(h: -5)), isNull);
    expect(parseImageEnvelope(envelopeJson(w: 'ten')), isNull);
    expect(parseImageEnvelope(envelopeJson(w: 100000)), isNull);
  });

  test('image too noisy to fit returns null instead of throwing', () {
    expect(buildImageEnvelope(noisePng(1600)), isNull);
  });

  test('garbage bytes return null', () {
    expect(buildImageEnvelope(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test('png with transparency encodes without throwing', () {
    final json = buildImageEnvelope(png(300, 300, alpha: true));
    expect(json, isNotNull);
    expect(parseImageEnvelope(json!), isNotNull);
  });

  test('very wide panorama is scaled to the long side cap', () {
    final env = parseImageEnvelope(buildImageEnvelope(png(4000, 200))!)!;
    expect(env.w, 1280);
    expect(env.h <= 70, isTrue);
  });

  test('exif rotation is honoured (landscape tagged 6 becomes portrait)', () {
    final src = img.Image(width: 400, height: 200);
    img.fill(src, color: img.ColorRgb8(200, 50, 50));
    src.exif.imageIfd.orientation = 6;
    final jpg = Uint8List.fromList(img.encodeJpg(src));
    final env = parseImageEnvelope(buildImageEnvelope(jpg)!)!;
    expect(env.w < env.h, isTrue);
  });

  test('previewText summarises pictures and leaves text alone', () {
    expect(previewText('hello there'), 'hello there');
    expect(previewText(envelopeJson()), 'Photo');
    final withCaption = jsonEncode({
      'mercury': 1,
      'type': 'image',
      'mime': 'image/jpeg',
      'w': 10,
      'h': 10,
      'data': base64Encode([1, 2, 3]),
      'caption': 'sunset',
    });
    expect(previewText(withCaption), 'Photo: sunset');
  });
}

// Added after review: the envelope's w/h are only a claim. A tiny file whose
// real pixel dimensions are huge must be rejected before anything decodes it.
void reviewTests() {
  test('rejects an image whose real dimensions exceed the cap even if the envelope claims small ones', () {
    final wide = img.Image(width: 4200, height: 100, numChannels: 1);
    final bytes = Uint8List.fromList(img.encodePng(wide));
    expect(bytes.length < kMaxReceivedImageBytes, isTrue);
    final s = jsonEncode({
      'mercury': 1, 'type': 'image', 'mime': 'image/png', 'w': 10, 'h': 10,
      'data': base64Encode(bytes),
    });
    expect(looksLikeImageEnvelope(s), isTrue);
    expect(parseImageEnvelope(s), isNull);
  });

  test('rejects bytes that are not an image at all', () {
    final s = jsonEncode({
      'mercury': 1, 'type': 'image', 'mime': 'image/jpeg', 'w': 10, 'h': 10,
      'data': base64Encode(List<int>.filled(200, 7)),
    });
    expect(parseImageEnvelope(s), isNull);
  });

  test('accepts a real small image', () {
    final ok = img.Image(width: 64, height: 48);
    final s = jsonEncode({
      'mercury': 1, 'type': 'image', 'mime': 'image/png', 'w': 64, 'h': 48,
      'data': base64Encode(img.encodePng(ok)),
    });
    expect(parseImageEnvelope(s), isNotNull);
  });
}
