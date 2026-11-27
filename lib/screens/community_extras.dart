import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/community_service.dart';
import '../theme.dart';

/// Extra forum.site features that match what Axon offers: members list,
/// direct messages, reporting and editing or deleting your own posts.

void _toast(BuildContext context, Object message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('$message')));
}

String _plainError(Object error) {
  final text = error.toString();
  if (text.contains('429')) return 'Too many tries, wait a minute.';
  if (text.contains('403')) return 'The forum did not allow that.';
  if (text.contains('404')) return 'That could not be found.';
  return text.replaceFirst('Bad state: ', '');
}

class ForumAvatar extends StatelessWidget {
  const ForumAvatar({
    super.key,
    required this.community,
    required this.handle,
    this.avatarId,
    this.size = 34,
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

/// One button of the Community second row: icon, label and a count badge.
class ForumNavButton extends StatelessWidget {
  const ForumNavButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.count = 0,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int count;

  /// Draws the badge in the accent colour (used for unread messages).
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Badge(
                isLabelVisible: count > 0,
                backgroundColor: highlight ? kAccent : kBorder,
                textColor: highlight ? Colors.black : kText,
                label: Text(count > 99 ? '99+' : '$count'),
                child: Icon(icon, color: kText),
              ),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(color: kMuted, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks why, then reports a post or comment to the forum moderators.
Future<void> reportToModerators(
  BuildContext context,
  CommunityService community, {
  required String kind,
  required String id,
}) async {
  final reason = TextEditingController();
  final send = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: kSurface,
      title: Text('Report this $kind', style: const TextStyle(color: kText)),
      content: TextField(
        controller: reason,
        autofocus: true,
        maxLength: 200,
        maxLines: 3,
        style: const TextStyle(color: kText),
        decoration: const InputDecoration(
          labelText: 'Why are you reporting it?',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Report'),
        ),
      ],
    ),
  );
  final text = reason.text.trim();
  reason.dispose();
  if (send != true) return;
  if (text.isEmpty) {
    if (context.mounted) _toast(context, 'Add a short reason.');
    return;
  }
  try {
    await community.report(kind: kind, id: id, reason: text);
    if (context.mounted) _toast(context, 'Reported to the moderators');
  } catch (error) {
    if (context.mounted) _toast(context, _plainError(error));
  }
}

/// Edit dialog for your own post. Returns true when the post was changed.
Future<bool> editOwnPost(
  BuildContext context,
  CommunityService community, {
  required Map<String, dynamic> post,
  required List<String> categories,
}) async {
  final title = TextEditingController(text: '${post['title'] ?? ''}');
  final content = TextEditingController(text: '${post['content'] ?? ''}');
  final current = '${post['category'] ?? 'General'}';
  final choices = categories.isEmpty ? <String>['General'] : categories;
  var category = choices.contains(current) ? current : choices.first;
  var removeImage = false;
  final hasImage = post['image_id'] is int;
  final submitted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Edit post', style: TextStyle(color: kText)),
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
                  items: choices
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
                  decoration: const InputDecoration(labelText: 'Your post'),
                ),
                if (hasImage)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: removeImage,
                    onChanged: (value) =>
                        update(() => removeImage = value == true),
                    title: const Text(
                      'Remove the picture',
                      style: TextStyle(color: kText),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  final titleText = title.text.trim();
  final contentText = content.text.trim();
  title.dispose();
  content.dispose();
  if (submitted != true) return false;
  final keepsPicture = hasImage && !removeImage;
  if (titleText.isEmpty || (contentText.isEmpty && !keepsPicture)) {
    if (context.mounted) _toast(context, 'Add a title and a message.');
    return false;
  }
  try {
    await community.editPost(
      postId: '${post['id']}',
      title: titleText,
      content: contentText,
      category: category,
      removeImage: removeImage,
    );
    if (context.mounted) _toast(context, 'Post updated');
    return true;
  } catch (error) {
    if (context.mounted) _toast(context, _plainError(error));
    return false;
  }
}

/// Confirms, then deletes your own post. Returns true when it was deleted.
Future<bool> deleteOwnPost(
  BuildContext context,
  CommunityService community,
  String postId,
) async {
  final sure = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: kSurface,
      title: const Text('Delete this post?', style: TextStyle(color: kText)),
      content: const Text(
        'It will disappear from the forum for everyone.',
        style: TextStyle(color: kMuted),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (sure != true) return false;
  try {
    await community.deletePost(postId);
    if (context.mounted) _toast(context, 'Post deleted');
    return true;
  } catch (error) {
    if (context.mounted) _toast(context, _plainError(error));
    return false;
  }
}

class CommunityMembersScreen extends StatefulWidget {
  const CommunityMembersScreen({
    super.key,
    required this.community,
    required this.myHandle,
    required this.canWrite,
  });

  final CommunityService community;
  final String? myHandle;
  final bool canWrite;

  @override
  State<CommunityMembersScreen> createState() => _CommunityMembersScreenState();
}

class _CommunityMembersScreenState extends State<CommunityMembersScreen> {
  List<Map<String, dynamic>>? _members;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final members = await widget.community.members();
      if (mounted) setState(() => _members = members);
    } catch (error) {
      if (mounted) setState(() => _error = _plainError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = _members;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        foregroundColor: kText,
        title: const Text('Members'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: members == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator(color: kAccent))
                : Center(
                    child: Text(
                      'Could not load members\n$_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: kMuted),
                    ),
                  )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: members.length,
              separatorBuilder: (_, _) => const Divider(color: kBorder),
              itemBuilder: (context, index) {
                final member = members[index];
                final handle = '${member['handle'] ?? ''}';
                final isMe = handle == widget.myHandle;
                final status = '${member['status'] ?? 'Offline'}';
                return ListTile(
                  leading: ForumAvatar(
                    community: widget.community,
                    handle: handle,
                    avatarId: member['avatar_id'] as int?,
                  ),
                  title: Text(
                    isMe ? '$handle (you)' : handle,
                    style: const TextStyle(color: kText),
                  ),
                  subtitle: Text(
                    status,
                    style: TextStyle(
                      color: status == 'Online' ? kAccent : kMuted,
                    ),
                  ),
                  trailing: widget.canWrite && !isMe
                      ? IconButton(
                          tooltip: 'Message $handle',
                          icon: const Icon(Icons.chat_bubble_outline),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CommunityConversationScreen(
                                community: widget.community,
                                myHandle: widget.myHandle,
                                other: handle,
                              ),
                            ),
                          ),
                        )
                      : null,
                );
              },
            ),
    );
  }
}

class CommunityMessagesScreen extends StatefulWidget {
  const CommunityMessagesScreen({
    super.key,
    required this.community,
    required this.myHandle,
  });

  final CommunityService community;
  final String? myHandle;

  @override
  State<CommunityMessagesScreen> createState() =>
      _CommunityMessagesScreenState();
}

class _CommunityMessagesScreenState extends State<CommunityMessagesScreen> {
  List<Map<String, dynamic>>? _threads;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final threads = await widget.community.dmThreads();
      if (mounted) setState(() => _threads = threads);
    } catch (error) {
      if (mounted) setState(() => _error = _plainError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final threads = _threads;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        foregroundColor: kText,
        title: const Text('Messages'),
        actions: [
          IconButton(
            tooltip: 'Members',
            icon: const Icon(Icons.people_outline),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CommunityMembersScreen(
                    community: widget.community,
                    myHandle: widget.myHandle,
                    canWrite: true,
                  ),
                ),
              );
              _load();
            },
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: threads == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator(color: kAccent))
                : Center(
                    child: Text(
                      'Could not load messages\n$_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: kMuted),
                    ),
                  )
          : threads.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No messages yet.\nOpen Members to start a conversation.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kMuted),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: threads.length,
              separatorBuilder: (_, _) => const Divider(color: kBorder),
              itemBuilder: (context, index) {
                final thread = threads[index];
                final peer = '${thread['peer'] ?? ''}';
                final unread = (thread['unread'] as num?)?.toInt() ?? 0;
                final mine = '${thread['sender']}' == widget.myHandle;
                return ListTile(
                  leading: ForumAvatar(
                    community: widget.community,
                    handle: peer,
                  ),
                  title: Text(
                    peer,
                    style: TextStyle(
                      color: kText,
                      fontWeight: unread > 0
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                  subtitle: Text(
                    '${mine ? 'You: ' : ''}${thread['body'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kMuted),
                  ),
                  trailing: unread > 0
                      ? CircleAvatar(
                          radius: 11,
                          backgroundColor: kAccent,
                          foregroundColor: Colors.black,
                          child: Text(
                            '$unread',
                            style: const TextStyle(fontSize: 11),
                          ),
                        )
                      : null,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CommunityConversationScreen(
                          community: widget.community,
                          myHandle: widget.myHandle,
                          other: peer,
                        ),
                      ),
                    );
                    _load();
                  },
                );
              },
            ),
    );
  }
}

class CommunityConversationScreen extends StatefulWidget {
  const CommunityConversationScreen({
    super.key,
    required this.community,
    required this.myHandle,
    required this.other,
  });

  final CommunityService community;
  final String? myHandle;
  final String other;

  @override
  State<CommunityConversationScreen> createState() =>
      _CommunityConversationScreenState();
}

class _CommunityConversationScreenState
    extends State<CommunityConversationScreen> {
  List<Map<String, dynamic>>? _messages;
  String? _error;
  final _text = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final messages = await widget.community.dmWith(widget.other);
      if (mounted) setState(() => _messages = messages);
    } catch (error) {
      if (mounted) setState(() => _error = _plainError(error));
    }
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.community.sendDm(to: widget.other, body: body);
      _text.clear();
      await _load();
    } catch (error) {
      if (mounted) _toast(context, _plainError(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = _messages;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        foregroundColor: kText,
        title: Text(widget.other),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages == null
                ? _error == null
                      ? const Center(
                          child: CircularProgressIndicator(color: kAccent),
                        )
                      : Center(
                          child: Text(
                            'Could not load messages\n$_error',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: kMuted),
                          ),
                        )
                : messages.isEmpty
                ? const Center(
                    child: Text('Say hello.', style: TextStyle(color: kMuted)),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[messages.length - 1 - index];
                      final mine = '${message['sender']}' == widget.myHandle;
                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          constraints: const BoxConstraints(maxWidth: 420),
                          decoration: BoxDecoration(
                            color: mine ? kAccentDim : kSurface,
                            border: Border.all(color: mine ? kAccent : kBorder),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SelectableText(
                            '${message['body'] ?? ''}',
                            style: const TextStyle(color: kText),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      maxLength: 1000,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(color: kText),
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        counterText: '',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Send',
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send, color: kAccent),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
