import 'dart:async';
import 'dart:io';

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme.dart';
import '../models/contact.dart';
import '../models/message.dart';
import '../services/signaling_service.dart';
import '../services/relay_service.dart';
import '../services/message_notification_service.dart';
import '../services/messages_service.dart';
import '../services/signal_service.dart';
import '../services/chat_image.dart';
import '../services/chat_image_store.dart';
import '../services/profile_sync.dart';
import 'call_screen.dart';

String? _buildEnvelopeInIsolate(List<Object?> args) =>
    buildImageEnvelope(args[0] as Uint8List, caption: args[1] as String?);

class ChatScreen extends StatefulWidget {
  final Contact contact;
  final SignalingService? signaling;
  final RelayService? relayService;
  final ValueNotifier<bool> connectionNotifier;
  final String? myId;
  final String? myName;
  final Future<void> Function(String peerId, Map<String, dynamic> bundle)? onProcessBundle;
  final Future<void> Function(String peerId, Map<String, dynamic> bundle)? onInitializeSession;
  final Function(String text, bool isSent, {String? imagePath, String? caption})? onMessageSaved;
  final MessagesService? messagesService;
  final ValueNotifier<String>? newMessageNotifier;
  final Future<String> Function(String)? onEncrypt;
  final ValueNotifier<bool>? callAnsweredNotifier;
  final ValueNotifier<dynamic>? remoteStreamNotifier;
  final Future<bool> Function(Contact contact)? onStartVoiceCall;

  /// Test seams for picture sending; defaults use the gallery picker and an
  /// isolate for compression.
  @visibleForTesting
  final Future<Uint8List?> Function()? pickPicture;
  @visibleForTesting
  final Future<String?> Function(Uint8List bytes, String? caption)? buildPictureEnvelope;
  @visibleForTesting
  final Directory? imageRoot;

  /// Path of our own profile photo; it is sent to this contact once (and again
  /// whenever it changes) as a small encrypted profile message.
  final String? profilePhotoPath;

  const ChatScreen({
    super.key,
    required this.contact,
    this.signaling,
    this.relayService,
    required this.connectionNotifier,
    this.myId,
    this.myName,
    this.onProcessBundle,
    this.onInitializeSession,
    this.onMessageSaved,
    this.messagesService,
    this.newMessageNotifier,
    this.onEncrypt,
    this.callAnsweredNotifier,
    this.remoteStreamNotifier,
    this.onStartVoiceCall,
    this.pickPicture,
    this.buildPictureEnvelope,
    this.imageRoot,
    this.profilePhotoPath,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller       = TextEditingController();
  final _scrollController = ScrollController();
  List<Message> _messages = [];
  bool _showE2ee = true;

  @override
  void initState() {
    super.initState();
    // Opening the conversation is the user reading it — drop its notification.
    // Done here rather than at the call sites so every route into a chat is
    // covered: contact tap, notification tap, and the killed-state resume.
    unawaited(
      MessageNotificationService.cancelForPeer(
        widget.contact.id,
      ).catchError((_) {}),
    );
    widget.messagesService?.getMessages(widget.contact.id).then((stored) {
      if (mounted && stored.isNotEmpty) {
        setState(() {
          _messages = stored.map((m) => Message(
            text: m.text, isSent: m.isSent, time: m.time,
            imagePath: m.imagePath, caption: m.caption,
          )).toList();
        });
      }
      _scrollToBottom(jump: true);
    });

    widget.newMessageNotifier?.addListener(_onNewMessage);
    
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(jump: true));
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_syncProfile()));
  }

  void _onNewMessage() {
    if (widget.newMessageNotifier!.value.startsWith(widget.contact.id)) {
      print(
        'ChatScreen _onNewMessage fired notifier=${widget.newMessageNotifier!.value} contactId=${widget.contact.id}',
      );
      print('ChatScreen _onNewMessage startsWith passed');
      widget.messagesService?.getMessages(widget.contact.id).then((stored) {
        if (mounted) {
          setState(() {
            _messages = stored.map((m) => Message(
              text: m.text, isSent: m.isSent, time: m.time,
              imagePath: m.imagePath, caption: m.caption,
            )).toList();
          });
          _scrollToBottom();
        }
      });
    } else {
      print(
        'ChatScreen _onNewMessage fired notifier=${widget.newMessageNotifier!.value} contactId=${widget.contact.id}',
      );
      print('ChatScreen _onNewMessage startsWith failed');
    }
  }

  @override
  void dispose() {
    widget.newMessageNotifier?.removeListener(_onNewMessage);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (jump) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      } else {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final payload = await _encryptPlaintext(text);
    if (payload == null) return;

    try {
      await _transmitPayload(payload);
    } catch (_) {
      _showSecureSessionError();
      return;
    }

    widget.onMessageSaved?.call(text, true);
    setState(() {
      _messages.add(Message(text: text, isSent: true, time: _currentTime()));
      _controller.clear();
    });
    _scrollToBottom();
    unawaited(_syncProfile());
  }

  /// Encrypts [plaintext] for the contact, setting up a session if needed.
  /// Shows the secure-session error and returns null on failure.
  Future<String?> _encryptPlaintext(String plaintext) async {
    try {
      return await _encryptForSend(plaintext);
    } on SignalSessionMissingException {
      final recovered = await _establishSessionAndEncrypt(plaintext);
      if (recovered == null) _showSecureSessionError();
      return recovered;
    } catch (_) {
      _showSecureSessionError();
      return null;
    }
  }

  bool _syncingProfile = false;

  /// Sends our profile photo to this contact if they have not got the current
  /// one. Silent on every failure (no session yet, offline): it simply tries
  /// again at the next trigger. Never sets up a session or shows an error.
  Future<void> _syncProfile() async {
    if (_syncingProfile) return;
    _syncingProfile = true;
    try {
      final photoPath = widget.profilePhotoPath;
      final envelope = await ProfileSync.pendingProfileEnvelope(widget.contact.id, photoPath);
      if (envelope == null) return;
      final p2p = widget.signaling?.isPeerConnected(widget.contact.id) ?? false;
      final relay = widget.relayService;
      // The relay silently drops stored messages while disconnected, so only
      // mark the photo as sent when it really had a way out.
      if (!p2p && relay != null && !relay.isConnected) return;
      final payload = await _encryptForSend(envelope);
      await _transmitPayload(payload);
      await ProfileSync.markSent(widget.contact.id, photoPath);
    } catch (_) {
      // Retried at the next trigger.
    } finally {
      _syncingProfile = false;
    }
  }

  bool _sendingPicture = false;

  Future<Uint8List?> _pickPictureBytes() async {
    final custom = widget.pickPicture;
    if (custom != null) return custom();
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2560,
      maxHeight: 2560,
    );
    return picked?.readAsBytes();
  }

  Future<String?> _buildEnvelope(Uint8List bytes, String? caption) {
    final custom = widget.buildPictureEnvelope;
    if (custom != null) return custom(bytes, caption);
    return compute(_buildEnvelopeInIsolate, <Object?>[bytes, caption]);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Picks a picture, compresses it, and sends it as an encrypted envelope.
  /// Anything typed in the message box becomes the caption.
  Future<void> _sendPicture() async {
    if (_sendingPicture) return;
    setState(() => _sendingPicture = true);
    try {
      final bytes = await _pickPictureBytes();
      if (bytes == null) return;
      final typed = _controller.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final caption = typed.isEmpty ? null : typed;
      final envelope = await _buildEnvelope(bytes, caption);
      if (envelope == null) {
        _toast('Picture too large to send');
        return;
      }
      final payload = await _encryptPlaintext(envelope);
      if (payload == null) return;
      try {
        await _transmitPayload(payload);
      } catch (_) {
        _showSecureSessionError();
        return;
      }
      final sent = parseImageEnvelope(envelope);
      if (sent == null) return;
      // The picture is already sent; a failure to keep a local copy must not
      // read as "could not send" (the user would send it again).
      String path;
      try {
        path = await ChatImageStore.save(
          widget.contact.id,
          sent.bytes,
          root: widget.imageRoot,
        );
      } catch (_) {
        _toast('Sent, but a copy could not be saved on this device');
        return;
      }
      widget.onMessageSaved?.call('', true, imagePath: path, caption: caption);
      if (!mounted) return;
      setState(() {
        _messages.add(Message(
          text: '',
          isSent: true,
          time: _currentTime(),
          imagePath: path,
          caption: caption,
        ));
        _controller.clear();
      });
      _scrollToBottom();
      unawaited(_syncProfile());
    } catch (_) {
      _toast('Could not send that picture');
    } finally {
      if (mounted) setState(() => _sendingPicture = false);
    }
  }

  Future<String> _encryptForSend(String text) async {
    final encrypt = widget.onEncrypt;
    if (encrypt == null) throw SignalSessionMissingException(widget.contact.id);
    return encrypt(text);
  }

  Future<String?> _establishSessionAndEncrypt(String text) async {
    try {
      final bundle = await widget.relayService?.getBundle(widget.contact.id);
      if (bundle == null) return null;
      final initializeSession = widget.onInitializeSession ?? widget.onProcessBundle;
      if (initializeSession == null) return null;
      await initializeSession(widget.contact.id, bundle);
      return await _encryptForSend(text);
    } catch (_) {
      return null;
    }
  }

  Future<void> _transmitPayload(String payload) async {
    if (widget.signaling?.isPeerConnected(widget.contact.id) ?? false) {
      await widget.signaling?.sendMessage(widget.contact.id, payload);
    } else {
      await widget.relayService?.storeMessage(
        widget.contact.id,
        widget.myId ?? 'unknown',
        payload,
      );
    }
  }

  void _showSecureSessionError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Secure session could not be established. Message not sent.'),
      ),
    );
  }

  String _currentTime() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final photoFile = widget.contact.photoPath == null
        ? null
        : File(widget.contact.photoPath!);
    final hasPhoto = photoFile != null && photoFile.existsSync();

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kText),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            Stack(
              children: [
                if (hasPhoto)
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: FileImage(photoFile),
                    backgroundColor: kAccentDim,
                  )
                else
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: kAccentDim,
                      border: Border.all(color: kBorder),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(widget.contact.initials,
                        style: const TextStyle(color: kAccent, fontSize: 14,
                          fontWeight: FontWeight.w700)),
                    ),
                  ),
                if (widget.contact.online)
                  Positioned(
                    right: 0, bottom: 0,
                    child: Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(
                        color: kAccent, shape: BoxShape.circle,
                        border: Border.all(color: kBg, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.contact.name,
                  style: const TextStyle(color: kText, fontSize: 15,
                    fontWeight: FontWeight.w600)),
                const Text('p2p connected · e2e encrypted',
                  style: TextStyle(color: kAccent, fontSize: 10)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_outlined, color: kMuted),
            onPressed: () async {
              final startVoiceCall = widget.onStartVoiceCall;
              if (startVoiceCall != null) {
                await startVoiceCall(widget.contact);
                return;
              }

              final started = await widget.signaling?.startVoiceCall(
                    widget.contact.id,
                    callerName: widget.myName ?? '',
                  ) ??
                  false;
              if (!started) return;
              if (context.mounted) {
                bool isMuted = false;
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => StatefulBuilder(
                    builder: (ctx, setS) => CallScreen(
                      contactName: widget.contact.name,
                      isOutgoing: true,
                      isMuted: isMuted,
                      onMuteTap: () {
                        setS(() => isMuted = !isMuted);
                        widget.signaling?.setMicMuted(isMuted);
                      },
                      onHangUp: () {
                        widget.signaling?.endVoiceCall();
                        Navigator.pop(ctx);
                      },
                      callAnsweredNotifier: widget.callAnsweredNotifier,
                      remoteStreamNotifier: widget.remoteStreamNotifier,
                    ),
                  ),
                ));
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: kMuted),
            onPressed: () {},
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: kBorder),
        ),
      ),
      body: Column(
        children: [
          if (_showE2ee)
            GestureDetector(
              onTap: () => setState(() => _showE2ee = false),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: kAccentDim,
                child: const Row(
                  children: [
                    Icon(Icons.lock_outline, color: kAccent, size: 14),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Messages are end-to-end encrypted. Server never sees them.',
                        style: TextStyle(color: kAccent, fontSize: 11),
                      ),
                    ),
                    Icon(Icons.close, color: kAccent, size: 14),
                  ],
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _messages.length,
              itemBuilder: (context, index) =>
                  MessageBubble(message: _messages[index]),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: kBorder)),
              color: kBg,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Attach picture',
                  icon: const Icon(Icons.image_outlined, color: kMuted),
                  onPressed: _sendingPicture ? null : _sendPicture,
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: kSurface,
                      border: Border.all(color: kBorder),
                    ),
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(color: kText, fontSize: 14),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: const InputDecoration(
                        hintText: 'Message...',
                        hintStyle: TextStyle(color: kMuted, fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    width: 44, height: 44,
                    color: kAccent,
                    child: const Icon(Icons.send, color: kBg, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  final Message message;
  const MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isSent ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: message.isSent
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: message.isSent ? kBubbleSent : kBubbleReceived,
                border: Border.all(
                  color: message.isSent
                      ? const Color(0xFF00CC6A).withValues(alpha: 0.2)
                      : kBorder,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(8),
                  topRight: const Radius.circular(8),
                  bottomLeft: Radius.circular(message.isSent ? 8 : 2),
                  bottomRight: Radius.circular(message.isSent ? 2 : 8),
                ),
              ),
              child: message.imagePath != null
                  ? _PictureContent(message: message)
                  : Text(
                      message.text,
                      style: TextStyle(
                        color: message.isSent
                            ? const Color(0xFFB3FFD9)
                            : kText,
                        fontSize: 14, height: 1.5,
                      ),
                    ),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message.time,
                  style: const TextStyle(color: kMuted, fontSize: 10)),
                if (message.isSent) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.done_all, color: kAccent, size: 12),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A picture message: the image (tap for full screen) and optional caption.
class _PictureContent extends StatelessWidget {
  final Message message;
  const _PictureContent({required this.message});

  @override
  Widget build(BuildContext context) {
    final path = message.imagePath!;
    final caption = message.caption;
    const unavailable = Text(
      'Picture could not be displayed',
      style: TextStyle(color: kMuted, fontSize: 13),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                backgroundColor: Colors.black,
                appBar: AppBar(
                  backgroundColor: Colors.black,
                  iconTheme: const IconThemeData(color: Colors.white),
                ),
                body: Center(
                  child: InteractiveViewer(
                    child: Image.file(
                      File(path),
                      errorBuilder: (context, error, stack) => unavailable,
                    ),
                  ),
                ),
              ),
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260, maxHeight: 320),
            child: Image.file(
              File(path),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) => unavailable,
            ),
          ),
        ),
        if (caption != null && caption.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            caption,
            style: TextStyle(
              color: message.isSent ? const Color(0xFFB3FFD9) : kText,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}
