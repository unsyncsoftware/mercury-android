import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Picture messages travel as a JSON envelope inside the normal encrypted
/// plaintext, so transport and encryption are unchanged. Anything that is not
/// a valid envelope is plain text.
///
/// The Signal ciphertext is base64-encoded again on the wire, so an envelope of
/// [kMaxEnvelopeChars] becomes about a third larger, still under the roughly
/// 256 KB data-channel limit.
const int kMaxEnvelopeChars = 150000;
const int kMaxReceivedImageBytes = 150 * 1024;
const int _kMaxLongSide = 1280;
const int _kMaxDimension = 8192;
const int _kMaxCaptionChars = 500;

/// Real pixel size limit on received pictures. Senders cap at 1280, so this is
/// generous; it exists because the envelope's w/h are only a claim and a tiny
/// file can declare enormous dimensions.
const int _kMaxRealDimension = 4096;

class ImageEnvelope {
  final String mime;
  final int w;
  final int h;
  final Uint8List bytes;
  final String? caption;

  const ImageEnvelope({
    required this.mime,
    required this.w,
    required this.h,
    required this.bytes,
    this.caption,
  });
}

String encodeImageEnvelope(ImageEnvelope e) {
  final caption = e.caption?.trim();
  return jsonEncode({
    'mercury': 1,
    'type': 'image',
    'mime': e.mime,
    'w': e.w,
    'h': e.h,
    'data': base64Encode(e.bytes),
    if (caption != null && caption.isNotEmpty) 'caption': caption,
  });
}

Map<String, dynamic>? _envelopeMap(String plaintext) {
  if (!plaintext.startsWith('{')) return null;
  try {
    final data = jsonDecode(plaintext);
    if (data is Map<String, dynamic> &&
        data['mercury'] == 1 &&
        data['type'] == 'image') {
      return data;
    }
  } catch (_) {}
  return null;
}

/// True when the text claims to be a picture envelope, valid or not. Lets the
/// UI say "could not be displayed" instead of dumping the raw JSON.
bool looksLikeImageEnvelope(String plaintext) => _envelopeMap(plaintext) != null;

/// Returns the picture, or null when the text is not a valid envelope.
ImageEnvelope? parseImageEnvelope(String plaintext) {
  final m = _envelopeMap(plaintext);
  if (m == null) return null;
  final mime = m['mime'];
  final w = m['w'];
  final h = m['h'];
  final data = m['data'];
  if (mime != 'image/jpeg' && mime != 'image/png') return null;
  if (w is! int || h is! int) return null;
  if (w < 1 || h < 1 || w > _kMaxDimension || h > _kMaxDimension) return null;
  if (data is! String) return null;
  Uint8List bytes;
  try {
    bytes = base64Decode(data);
  } catch (_) {
    return null;
  }
  if (bytes.isEmpty || bytes.length > kMaxReceivedImageBytes) return null;
  // Read the real size from the image header (no pixel decoding).
  final real = peekImageDimensions(bytes);
  if (real == null ||
      real[0] < 1 ||
      real[1] < 1 ||
      real[0] > _kMaxRealDimension ||
      real[1] > _kMaxRealDimension) {
    return null;
  }
  return ImageEnvelope(
    mime: mime as String,
    w: w,
    h: h,
    bytes: bytes,
    caption: _cleanCaption(m['caption']),
  );
}

String? _cleanCaption(Object? raw) {
  if (raw is! String || raw.trim().isEmpty) return null;
  final c = raw.trim();
  return c.length > _kMaxCaptionChars ? c.substring(0, _kMaxCaptionChars) : c;
}

/// [width, height] from the file header, or null if it is not a readable image.
List<int>? peekImageDimensions(Uint8List bytes) {
  try {
    final info = img.findDecoderForData(bytes)?.startDecode(bytes);
    if (info == null) return null;
    return [info.width, info.height];
  } catch (_) {
    return null;
  }
}

/// Shrinks [original] (long side at most 1280 px, EXIF rotation applied,
/// transparency flattened onto white) and encodes it as a JPEG, stepping the
/// quality down from 82 until the envelope fits [kMaxEnvelopeChars].
/// Returns the envelope JSON, or null if the image cannot be decoded or will
/// not fit. CPU heavy: call it off the UI thread (e.g. with `compute`).
String? buildImageEnvelope(Uint8List original, {String? caption}) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(original);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  try {
    var image = img.bakeOrientation(decoded);
    final longest = image.width > image.height ? image.width : image.height;
    if (longest > _kMaxLongSide) {
      image = image.width >= image.height
          ? img.copyResize(image, width: _kMaxLongSide)
          : img.copyResize(image, height: _kMaxLongSide);
    }
    if (image.hasAlpha) {
      final flat = img.Image(width: image.width, height: image.height);
      img.fill(flat, color: img.ColorRgb8(255, 255, 255));
      img.compositeImage(flat, image);
      image = flat;
    }
    for (var quality = 82; quality >= 40; quality -= 6) {
      final jpg = Uint8List.fromList(img.encodeJpg(image, quality: quality));
      final json = encodeImageEnvelope(
        ImageEnvelope(
          mime: 'image/jpeg',
          w: image.width,
          h: image.height,
          bytes: jpg,
          caption: caption,
        ),
      );
      if (json.length <= kMaxEnvelopeChars) return json;
    }
  } catch (_) {
    return null;
  }
  return null;
}

/// Short text for notifications and chat lists: pictures never show raw data.
String previewText(String plaintext) {
  final m = _envelopeMap(plaintext);
  if (m == null) return plaintext;
  final caption = _cleanCaption(m['caption']);
  return caption == null ? 'Photo' : 'Photo: $caption';
}
