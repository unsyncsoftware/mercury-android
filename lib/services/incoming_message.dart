import 'dart:io';
import 'dart:typed_data';

import 'chat_image.dart';
import 'chat_image_store.dart';
import 'messages_service.dart';
import 'profile_sync.dart';

const String kPictureUnavailableText = 'Picture could not be displayed';

/// Stores a decrypted incoming message and returns the text to use in
/// notifications. Picture envelopes are written to a file and stored as a
/// picture message; a broken envelope becomes a short notice instead of raw
/// JSON; anything else is ordinary text. Profile-photo envelopes are never
/// stored or notified: the photo goes to [onProfile] and the result is null.
/// Shared by the live and relay-queued receive paths.
Future<String?> storeIncomingMessage(
  MessagesService messages,
  String peerId,
  String plaintext, {
  Directory? imageRoot,
  Future<void> Function(String peerId, Uint8List photo)? onProfile,
}) async {
  if (looksLikeProfileEnvelope(plaintext)) {
    final photo = parseProfileEnvelope(plaintext);
    if (photo != null && onProfile != null) {
      try {
        await onProfile(peerId, photo);
      } catch (_) {}
    }
    return null;
  }
  final envelope = parseImageEnvelope(plaintext);
  if (envelope != null) {
    try {
      final path = await ChatImageStore.save(peerId, envelope.bytes, root: imageRoot);
      await messages.addMessage(
        peerId,
        '',
        false,
        imagePath: path,
        caption: envelope.caption,
      );
      return previewText(plaintext);
    } catch (_) {
      // Could not save the file: fall through to the notice below.
    }
  }
  if (envelope != null || looksLikeImageEnvelope(plaintext)) {
    await messages.addMessage(peerId, kPictureUnavailableText, false);
    return kPictureUnavailableText;
  }
  await messages.addMessage(peerId, plaintext, false);
  return plaintext;
}
