import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../theme.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  static const _storageKey = 'desktop_notes_pages_v1';
  static const _storage = FlutterSecureStorage();
  final List<_NotePage> _pages = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as List;
      if (mounted) {
        setState(
          () => _pages.addAll(
            decoded.map((item) {
              final map = item as Map<String, dynamic>;
              return _NotePage(
                map['title'] as String? ?? 'Untitled',
                map['body'] as String? ?? '',
              );
            }),
          ),
        );
      }
    } catch (_) {
      // Leave the notes screen usable if stored data is damaged.
    }
  }

  Future<void> _save() async {
    await _storage.write(
      key: _storageKey,
      value: jsonEncode(
        _pages.map((page) => {'title': page.title, 'body': page.body}).toList(),
      ),
    );
  }

  void _addPage() {
    setState(() => _pages.add(_NotePage('New page', '')));
    _save();
    _openPage(_pages.last);
  }

  void _openPage(_NotePage page) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _NoteEditor(page: page, onSave: _save),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBg,
    appBar: AppBar(
      title: const Text('Notes'),
      backgroundColor: kBg,
      foregroundColor: kText,
      actions: [
        IconButton(
          tooltip: 'New page',
          icon: const Icon(Icons.add, color: kAccent),
          onPressed: _addPage,
        ),
      ],
    ),
    body: _pages.isEmpty
        ? const Center(
            child: Text(
              'No pages yet. Tap + to create one.',
              style: TextStyle(color: kMuted),
            ),
          )
        : ListView.separated(
            itemCount: _pages.length,
            separatorBuilder: (_, _) =>
                const Divider(color: kBorder, height: 1),
            itemBuilder: (_, index) {
              final page = _pages[index];
              return ListTile(
                title: Text(page.title, style: const TextStyle(color: kText)),
                subtitle: Text(
                  page.body.replaceAll('\n', ' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kMuted),
                ),
                trailing: const Icon(
                  Icons.lock_outline,
                  color: kMuted,
                  size: 18,
                ),
                onTap: () => _openPage(page),
              );
            },
          ),
  );
}

class _NotePage {
  _NotePage(this.title, this.body);
  String title;
  String body;
}

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({required this.page, required this.onSave});
  final _NotePage page;
  final Future<void> Function() onSave;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  bool _unlocked = false;
  late final TextEditingController _title = TextEditingController(
    text: widget.page.title,
  );
  late final TextEditingController _body = TextEditingController(
    text: widget.page.body,
  );

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _lock() async {
    widget.page.title = _title.text.trim().isEmpty
        ? 'Untitled'
        : _title.text.trim();
    widget.page.body = _body.text;
    await widget.onSave();
    if (mounted) setState(() => _unlocked = false);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_unlocked,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _lock();
    },
    child: Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        foregroundColor: kText,
        title: Text(_unlocked ? 'Edit page' : widget.page.title),
        actions: [
          TextButton.icon(
            onPressed: _unlocked
                ? _lock
                : () => setState(() => _unlocked = true),
            icon: Icon(
              _unlocked ? Icons.lock : Icons.lock_open,
              color: kAccent,
            ),
            label: Text(
              _unlocked ? 'Save & lock' : 'Unlock to edit',
              style: const TextStyle(color: kAccent),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _unlocked
            ? Column(
                children: [
                  TextField(
                    controller: _title,
                    style: const TextStyle(
                      color: kText,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: const InputDecoration(labelText: 'Page title'),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: TextField(
                      controller: _body,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      keyboardType: TextInputType.multiline,
                      style: const TextStyle(color: kText, fontSize: 15),
                      decoration: const InputDecoration(
                        hintText: 'Write a note...',
                      ),
                    ),
                  ),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Locked · select text to copy',
                      style: TextStyle(color: kMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 20),
                    SelectableText(
                      widget.page.body.isEmpty
                          ? 'This page is empty.'
                          : widget.page.body,
                      style: const TextStyle(
                        color: kText,
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    ),
  );
}
