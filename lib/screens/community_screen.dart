import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../services/community_service.dart';
import '../services/relay_service.dart';
import '../theme.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({
    super.key,
    required this.relay,
    required this.peerId,
    required this.mercuryHandle,
    this.profilePhotoPath,
  });

  final RelayService relay;
  final String peerId;
  final String mercuryHandle;
  final String? profilePhotoPath;

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final CommunityService _community = CommunityService(
    widget.relay,
    widget.peerId,
  );
  List<Map<String, dynamic>> _posts = [];
  String? _error;
  bool _loading = true;
  Map<String, dynamic>? _session;
  String _category = 'All';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await _community.loadSession();
      await _syncProfilePhoto(session);
      final query = Uri(
        path: '/api/posts',
        queryParameters: {
          'limit': '30',
          if (_category != 'All') 'category': _category,
        },
      );
      final result = await _community.get(query.toString());
      final posts =
          (result['posts'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          [];
      if (!mounted) return;
      setState(() {
        _session = session;
        _posts = posts;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncProfilePhoto(Map<String, dynamic> session) async {
    final path = widget.profilePhotoPath;
    if (path == null || session['canWrite'] != true) return;
    try {
      final file = File(path);
      if (!await file.exists()) return;
      final stat = await file.stat();
      final source = await file.readAsBytes();
      final decoded = img.decodeImage(source);
      if (decoded == null) return;
      var avatar = decoded;
      final side = avatar.width < avatar.height ? avatar.width : avatar.height;
      avatar = img.copyCrop(
        avatar,
        x: (avatar.width - side) ~/ 2,
        y: (avatar.height - side) ~/ 2,
        width: side,
        height: side,
      );
      avatar = img.copyResize(avatar, width: 160, height: 160);
      Uint8List? encoded;
      for (var quality = 82; quality >= 35; quality -= 7) {
        final candidate = Uint8List.fromList(
          img.encodeJpg(avatar, quality: quality),
        );
        if (candidate.length <= 40 * 1024) {
          encoded = candidate;
          break;
        }
      }
      if (encoded == null) return;
      await _community.syncAvatar(
        encoded,
        '${stat.size}:${stat.modified.millisecondsSinceEpoch}',
      );
    } catch (error) {
      debugPrint('Community profile photo sync failed: $error');
    }
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _ask(
    String title,
    String label, {
    bool secret = false,
    int maxLength = 120,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _CommunityTextPrompt(
        title: title,
        label: label,
        secret: secret,
        maxLength: maxLength,
      ),
    );
  }

  Future<void> _account() async {
    var action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kSurface,
        title: Text(
          _session?['handle'] == null
              ? 'Join Community'
              : '${_session!['handle']}',
          style: const TextStyle(color: kText),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_session?['handle'] != null)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, 'copy'),
                child: const Text('Copy my forum key'),
              ),
            if (_session?['handle'] == null) ...[
              if (_session?['openJoin'] == true)
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, 'join'),
                  child: Text('Join as ${widget.mercuryHandle}'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, 'more'),
                child: const Text('More ways to join'),
              ),
            ],
          ],
        ),
      ),
    );
    if (action == 'more' && mounted) {
      action = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: kSurface,
          title: const Text(
            'More ways to join',
            style: TextStyle(color: kText),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (Platform.isAndroid && _session?['axonJoin'] == true)
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, 'axon'),
                  child: const Text('Join with Axon handle'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, 'import'),
                child: const Text('Use key from another device'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, 'invite'),
                child: const Text('Claim with invite code'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    }
    if (action == null || !mounted) return;
    if (action == 'axon') {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: kSurface,
          title: const Text(
            'Join with your Axon handle',
            style: TextStyle(color: kText),
          ),
          content: const Text(
            'Axon will open its start page. In forum.site, choose Join with my Axon handle and approve the signed proof. Then copy your forum key in the forum account and import it in Mercury.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Open Axon'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
      try {
        await const MethodChannel(
          'uk.unsync.messenger/launch_intent',
        ).invokeMethod<void>('openAxonForum');
      } on PlatformException catch (error) {
        _notice(error.message ?? 'Axon browser is not installed.');
      }
      return;
    }
    try {
      if (action == 'copy') {
        final key = await _community.exportKey();
        if (key == null) throw StateError('No forum key saved');
        await Clipboard.setData(ClipboardData(text: key));
        _notice('Forum key copied. Keep it private.');
        return;
      }
      if (action == 'import') {
        final key = await _ask('Use forum key', 'Paste key', secret: true);
        if (key == null || key.isEmpty) return;
        await _community.importKey(key);
      } else if (action == 'invite') {
        final code = await _ask('Claim handle', 'Invite code', maxLength: 40);
        if (code == null || code.isEmpty) return;
        await _community.join(inviteCode: code);
      } else if (action == 'join') {
        final handle = widget.mercuryHandle.trim();
        if (handle.isEmpty) {
          _notice('Set your Mercury display name first.');
          return;
        }
        await _community.join(handle: handle);
      }
      await _load();
      _notice('Signed in to Community');
    } catch (error) {
      _notice(error.toString());
    }
  }

  Future<void> _newPost() async {
    final title = TextEditingController();
    final content = TextEditingController();
    Uint8List? photo;
    final categories =
        (_session?['categories'] as List?)?.whereType<String>().toList() ??
        ['General'];
    var category = categories.contains('General')
        ? 'General'
        : categories.first;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          backgroundColor: kSurface,
          title: const Text('New post', style: TextStyle(color: kText)),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    maxLength: 120,
                    style: const TextStyle(color: kText),
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  DropdownButton<String>(
                    value: category,
                    isExpanded: true,
                    dropdownColor: kSurface,
                    items: categories
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(
                              value,
                              style: const TextStyle(color: kText),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) update(() => category = value);
                    },
                  ),
                  TextField(
                    controller: content,
                    maxLength: 3000,
                    maxLines: 8,
                    style: const TextStyle(color: kText),
                    decoration: InputDecoration(
                      labelText: 'Write your post',
                      suffixIcon: IconButton(
                        tooltip: 'Add emoji',
                        icon: const Icon(Icons.emoji_emotions_outlined),
                        onPressed: () => _insertEmoji(context, content),
                      ),
                    ),
                  ),
                  if (_session?['features'] is Map &&
                      _session!['features']['postImages'] == true) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          final picked = await _pickPicture();
                          if (picked != null) update(() => photo = picked);
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(error.toString())),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.image_outlined),
                      label: Text(
                        photo == null ? 'Add picture' : 'Change picture',
                      ),
                    ),
                    if (photo != null) ...[
                      const SizedBox(height: 8),
                      Image.memory(photo!, height: 150, fit: BoxFit.contain),
                      TextButton(
                        onPressed: () => update(() => photo = null),
                        child: const Text('Remove picture'),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Post'),
            ),
          ],
        ),
      ),
    );
    final titleText = title.text.trim();
    final contentText = content.text.trim();
    title.dispose();
    content.dispose();
    if (submitted != true) return;
    if (titleText.isEmpty || (contentText.isEmpty && photo == null)) {
      _notice('Add a title and message or picture.');
      return;
    }
    try {
      await _community.writePost(
        title: titleText,
        content: contentText,
        category: category,
        imageBytes: photo,
      );
      await _load();
      _notice('Post published');
    } catch (error) {
      _notice(error.toString());
    }
  }

  Future<Uint8List?> _pickPicture() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return null;
    final source = await picked.readAsBytes();
    if (source.length > 20 * 1024 * 1024) {
      throw StateError('Choose a picture under 20 MB');
    }
    final image = img.decodeImage(source);
    if (image == null) {
      throw StateError('This picture format is not supported');
    }
    var decoded = image;
    for (var attempt = 0; attempt < 12; attempt++) {
      final longest = decoded.width > decoded.height
          ? decoded.width
          : decoded.height;
      if (longest > 1200) {
        final ratio = 1200 / longest;
        decoded = img.copyResize(
          decoded,
          width: (decoded.width * ratio).round(),
          height: (decoded.height * ratio).round(),
        );
      }
      final quality = (82 - attempt * 5).clamp(35, 82);
      final encoded = Uint8List.fromList(
        img.encodeJpg(decoded, quality: quality),
      );
      if (encoded.length <= 40 * 1024) return encoded;
      decoded = img.copyResize(
        decoded,
        width: (decoded.width * 0.8).round(),
        height: (decoded.height * 0.8).round(),
      );
    }
    throw StateError('Could not shrink this picture enough');
  }

  Widget _categoryDrawer() {
    final categories = [
      'All',
      ...?(_session?['categories'] as List?)?.whereType<String>(),
    ];
    return Drawer(
      backgroundColor: kSurface,
      child: SafeArea(
        child: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text(
                'Community',
                style: TextStyle(
                  color: kText,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.arrow_back, color: kText),
              title: const Text(
                'Back to Mercury',
                style: TextStyle(color: kText),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
            ),
            const Divider(color: kBorder),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(
                'CATEGORIES',
                style: TextStyle(color: kMuted, fontSize: 11),
              ),
            ),
            for (final name in categories)
              ListTile(
                selected: _category == name,
                selectedColor: kAccent,
                leading: Icon(
                  name == 'All'
                      ? Icons.view_list_outlined
                      : Icons.folder_outlined,
                  color: _category == name ? kAccent : kMuted,
                ),
                title: Text(name == 'All' ? 'All posts' : name),
                trailing: _category == name
                    ? const Icon(Icons.check, color: kAccent)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  if (_category == name) return;
                  setState(() => _category = name);
                  _load();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: kBg,
      drawer: _categoryDrawer(),
      appBar: AppBar(
        backgroundColor: kBg,
        foregroundColor: kText,
        leading: IconButton(
          tooltip: 'Categories',
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('Community'),
        actions: [
          IconButton(
            tooltip: _session?['handle'] == null ? 'Join' : 'Account',
            onPressed: _account,
            icon: const Icon(Icons.person_outline),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_session != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _category == 'All' ? 'All posts' : _category,
                          style: const TextStyle(
                            color: kText,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _session?['canWrite'] == true
                              ? 'Posting as ${_session?['handle']}'
                              : 'Browsing as guest',
                          style: const TextStyle(color: kMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (_session?['canWrite'] != true)
                    TextButton(onPressed: _account, child: const Text('Join')),
                ],
              ),
            ),
          ],
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kAccent))
                : _error != null
                ? _MessageState(
                    icon: Icons.wifi_off_outlined,
                    message: 'Could not load forum.site\n$_error',
                    onRetry: _load,
                  )
                : _posts.isEmpty
                ? _MessageState(
                    icon: Icons.forum_outlined,
                    message: _category == 'All'
                        ? 'No community posts yet.'
                        : 'No posts in $_category yet.',
                    onRetry: _load,
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    color: kAccent,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 92),
                      itemCount: _posts.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final post = _posts[index];
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _CommunityPostScreen(
                                community: _community,
                                postId: '${post['id']}',
                                canWrite: _session?['canWrite'] == true,
                              ),
                            ),
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: kSurface,
                              border: Border.all(color: kBorder),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    _ForumAvatar(
                                      community: _community,
                                      handle: '${post['author'] ?? 'Unknown'}',
                                      avatarId:
                                          post['author_avatar_id'] as int?,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${post['category'] ?? 'General'}  ·  ${post['author'] ?? 'Unknown'}',
                                        style: const TextStyle(
                                          color: kAccent,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${post['title'] ?? ''}',
                                  style: const TextStyle(
                                    color: kText,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  '${post['content'] ?? ''}',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFAAAAAA),
                                  ),
                                ),
                                if (post['image_id'] is int) ...[
                                  const SizedBox(height: 10),
                                  _ForumPicture(
                                    community: _community,
                                    imageId: post['image_id'] as int,
                                    height: 150,
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Text(
                                  '${post['comment_count'] ?? 0} replies',
                                  style: const TextStyle(
                                    color: kMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: _session != null && !_loading
          ? FloatingActionButton.extended(
              onPressed: _session?['canWrite'] == true ? _newPost : _account,
              backgroundColor: kAccent,
              tooltip: _session?['canWrite'] == true
                  ? 'New post'
                  : 'Join to post',
              icon: const Icon(Icons.edit_outlined, color: kBg),
              label: Text(
                _session?['canWrite'] == true ? 'New post' : 'Join to post',
                style: const TextStyle(color: kBg),
              ),
            )
          : null,
    );
  }
}

class _CommunityPostScreen extends StatefulWidget {
  const _CommunityPostScreen({
    required this.community,
    required this.postId,
    required this.canWrite,
  });

  final CommunityService community;
  final String postId;
  final bool canWrite;

  @override
  State<_CommunityPostScreen> createState() => _CommunityPostScreenState();
}

class _CommunityPostScreenState extends State<_CommunityPostScreen> {
  Map<String, dynamic>? _post;
  String? _error;
  final _reply = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _sendReply() async {
    final body = _reply.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.community.writeComment(postId: widget.postId, body: body);
      _reply.clear();
      await _load();
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Reply published')));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final result = await widget.community.get('/api/posts/${widget.postId}');
      if (mounted)
        setState(() => _post = result['post'] as Map<String, dynamic>?);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    final comments =
        (post?['comments'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        foregroundColor: kText,
        title: const Text('Community'),
      ),
      body: post == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator(color: kAccent))
                : _MessageState(
                    icon: Icons.wifi_off_outlined,
                    message: 'Could not load post\n$_error',
                    onRetry: _load,
                  )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    _ForumAvatar(
                      community: widget.community,
                      handle: '${post['author'] ?? 'Unknown'}',
                      avatarId: post['author_avatar_id'] as int?,
                      size: 36,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${post['category'] ?? 'General'}  ·  ${post['author'] ?? 'Unknown'}',
                        style: const TextStyle(color: kAccent, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SelectableText(
                  '${post['title'] ?? ''}',
                  style: const TextStyle(
                    color: kText,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                SelectableText(
                  '${post['content'] ?? ''}',
                  style: const TextStyle(
                    color: kText,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                if (post['image_id'] is int) ...[
                  const SizedBox(height: 14),
                  _ForumPicture(
                    community: widget.community,
                    imageId: post['image_id'] as int,
                    height: 280,
                  ),
                ],
                const SizedBox(height: 24),
                const Divider(color: kBorder),
                Text(
                  '${comments.length} replies',
                  style: const TextStyle(
                    color: kText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                for (final comment in comments)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _ForumAvatar(
                              community: widget.community,
                              handle: '${comment['author'] ?? 'Unknown'}',
                              avatarId: comment['author_avatar_id'] as int?,
                              size: 28,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${comment['author'] ?? 'Unknown'}',
                              style: const TextStyle(
                                color: kAccent,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          '${comment['body'] ?? ''}',
                          style: const TextStyle(color: kText),
                        ),
                      ],
                    ),
                  ),
                if (widget.canWrite) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _reply,
                    maxLength: 1000,
                    maxLines: 4,
                    style: const TextStyle(color: kText),
                    decoration: InputDecoration(
                      labelText: 'Write a reply',
                      suffixIcon: IconButton(
                        tooltip: 'Add emoji',
                        icon: const Icon(Icons.emoji_emotions_outlined),
                        onPressed: () => _insertEmoji(context, _reply),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _sending ? null : _sendReply,
                      child: Text(_sending ? 'Posting...' : 'Reply'),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _ForumAvatar extends StatelessWidget {
  const _ForumAvatar({
    required this.community,
    required this.handle,
    this.avatarId,
    this.size = 30,
  });

  final CommunityService community;
  final String handle;
  final int? avatarId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final id = avatarId;
    if (id == null) {
      final initial = handle.replaceFirst('@', '').trim();
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: kBorder,
        foregroundColor: kAccent,
        child: Text(initial.isEmpty ? '?' : initial[0].toUpperCase()),
      );
    }
    return FutureBuilder<Uint8List>(
      future: community.avatar(id),
      builder: (context, snapshot) => CircleAvatar(
        radius: size / 2,
        backgroundColor: kBorder,
        foregroundImage: snapshot.hasData ? MemoryImage(snapshot.data!) : null,
        child: snapshot.hasData
            ? null
            : const Icon(Icons.person_outline, color: kMuted, size: 17),
      ),
    );
  }
}

class _ForumPicture extends StatelessWidget {
  const _ForumPicture({
    required this.community,
    required this.imageId,
    required this.height,
  });

  final CommunityService community;
  final int imageId;
  final double height;

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: community.image(imageId),
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            snapshot.data!,
            height: height,
            width: double.infinity,
            fit: BoxFit.contain,
          ),
        );
      }
      if (snapshot.hasError) {
        return const Text(
          'Picture unavailable',
          style: TextStyle(color: kMuted),
        );
      }
      return SizedBox(
        height: height,
        child: const Center(child: CircularProgressIndicator(color: kAccent)),
      );
    },
  );
}

Future<void> _insertEmoji(
  BuildContext context,
  TextEditingController controller,
) async {
  const emoji = [
    '😀',
    '😄',
    '😂',
    '🥰',
    '😍',
    '😎',
    '🤔',
    '😢',
    '👍',
    '👏',
    '🙏',
    '❤️',
    '🔥',
    '🎉',
    '✨',
    '💯',
    '👋',
    '🙌',
    '🤝',
    '💪',
    '👀',
    '🚀',
    '💡',
    '✅',
  ];
  final chosen = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: kSurface,
    builder: (sheetContext) => SafeArea(
      child: SizedBox(
        height: 230,
        child: GridView.count(
          crossAxisCount: 8,
          padding: const EdgeInsets.all(12),
          children: [
            for (final value in emoji)
              InkWell(
                onTap: () => Navigator.pop(sheetContext, value),
                child: Center(
                  child: Text(value, style: const TextStyle(fontSize: 25)),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  if (chosen == null) return;
  final value = controller.value;
  final selection = value.selection;
  final start = selection.isValid ? selection.start : value.text.length;
  final end = selection.isValid ? selection.end : value.text.length;
  controller.value = TextEditingValue(
    text: value.text.replaceRange(start, end, chosen),
    selection: TextSelection.collapsed(offset: start + chosen.length),
  );
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.message,
    required this.onRetry,
  });

  final IconData icon;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: kMuted, size: 40),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kText),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

class _CommunityTextPrompt extends StatefulWidget {
  const _CommunityTextPrompt({
    required this.title,
    required this.label,
    required this.secret,
    required this.maxLength,
  });

  final String title;
  final String label;
  final bool secret;
  final int maxLength;

  @override
  State<_CommunityTextPrompt> createState() => _CommunityTextPromptState();
}

class _CommunityTextPromptState extends State<_CommunityTextPrompt> {
  final _controller = TextEditingController();

  Future<void> _close([String? value]) async {
    FocusScope.of(context).unfocus();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    Navigator.pop(context, value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kSurface,
      title: Text(widget.title, style: const TextStyle(color: kText)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: widget.secret,
        maxLength: widget.maxLength,
        style: const TextStyle(color: kText),
        decoration: InputDecoration(labelText: widget.label),
      ),
      actions: [
        TextButton(onPressed: _close, child: const Text('Cancel')),
        TextButton(
          onPressed: () => _close(_controller.text.trim()),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
