import 'dart:io';

import 'package:flutter/material.dart';

import '../services/account_removal.dart';
import '../services/handle_service.dart';
import '../theme.dart';

/// Settings → Delete account. Two choices:
///  * Remove from this device: erases the account here only. It stays on the
///    server and can be restored from a backup on any device.
///  * Delete my account: leaves the Community forum, deletes the account on
///    the server (handle held 90 days, peer id retired), then erases it here.
/// Both end by closing Mercury, so nothing in memory writes the data back.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({
    super.key,
    required this.handle,
    required this.deleteOnServer,
    required this.leaveForum,
    required this.openBackup,
    this.beforeExit,
  });

  /// The handle shown without @, typed back to confirm a full deletion.
  final String? handle;
  final Future<AccountDeleteResult> Function() deleteOnServer;

  /// 'left', 'not_member' or 'unsupported'; throws if the forum refuses.
  final Future<String> Function() leaveForum;
  final VoidCallback openBackup;

  /// Platform clean-up before the app closes (e.g. stopping a service).
  final Future<void> Function()? beforeExit;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  bool _busy = false;
  String? _status;

  String get _name => (widget.handle ?? '').replaceFirst('@', '');

  Future<void> _finish(String message) async {
    await AccountRemoval.wipeThisDevice();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Done', style: TextStyle(color: kText)),
        content: Text(message, style: const TextStyle(color: kMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close Mercury'),
          ),
        ],
      ),
    );
    await widget.beforeExit?.call();
    exit(0);
  }

  Future<void> _removeFromDevice() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text(
          'Remove from this device?',
          style: TextStyle(color: kText),
        ),
        content: const Text(
          'Your contacts, chats and keys are erased from this device and '
          'Mercury closes. Your account and handle stay on the server.\n\n'
          'To use this account again, on this or another device, you need an '
          'account backup. Make one first if you have not.',
          style: TextStyle(color: kMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'backup'),
            child: const Text('Back up first'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'remove'),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (choice == 'backup') {
      widget.openBackup();
      return;
    }
    if (choice != 'remove') return;
    setState(() {
      _busy = true;
      _status = 'Removing from this device...';
    });
    await _finish(
      'Mercury has been removed from this device. Restore your backup to use '
      'the account again.',
    );
  }

  Future<void> _deleteEverywhere() async {
    final typed = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          backgroundColor: kSurface,
          title: const Text(
            'Delete your account?',
            style: TextStyle(color: kText),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This cannot be undone.\n\n'
                '• Your handle is released. Nobody can take it for 90 days.\n'
                '• This account can never sign in again, even from a backup.\n'
                '• Your Community membership, messages and profile picture '
                'are deleted. Your posts stay, shown as "deleted member".\n'
                '• Your contacts and chats are erased from this device.\n\n'
                'Messages you sent are still on your friends\' devices. '
                'A backup file you saved is not deleted; delete it yourself.',
                style: TextStyle(color: kMuted),
              ),
              const SizedBox(height: 12),
              if (_name.isNotEmpty)
                TextField(
                  controller: typed,
                  autofocus: true,
                  onChanged: (_) => update(() {}),
                  style: const TextStyle(color: kText),
                  decoration: InputDecoration(labelText: 'Type $_name to confirm'),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed:
                  _name.isEmpty ||
                      typed.text.trim().replaceFirst('@', '').toLowerCase() ==
                          _name.toLowerCase()
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              child: const Text('Delete my account'),
            ),
          ],
        ),
      ),
    );
    typed.dispose();
    if (confirmed != true) return;

    setState(() {
      _busy = true;
      _status = 'Leaving Community...';
    });
    var forumNote = '';
    try {
      final forum = await widget.leaveForum();
      if (forum == 'unsupported') {
        forumNote =
            '\n\nThe Community forum could not delete your membership '
            'automatically. Email dev@unsync.uk to have it removed.';
      }
    } catch (error) {
      _fail(
        'Mercury could not reach Community, so nothing was deleted. Check '
        'your connection and try again.',
      );
      return;
    }

    if (!mounted) return;
    setState(() => _status = 'Deleting your account...');
    final result = await widget.deleteOnServer();
    if (!result.ok) {
      _fail(
        result.reason == 'timeout' || result.reason == 'not_authenticated'
            ? 'Mercury is not connected to its server, so your account was '
                  'not deleted. Wait until you are online and try again.'
            : 'The server did not delete your account (${result.reason}). '
                  'Nothing was erased from this device. Try again later.',
      );
      return;
    }

    if (!mounted) return;
    setState(() => _status = 'Erasing this device...');
    await _finish('Your Mercury account has been deleted.$forumNote');
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = null;
    });
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Not deleted', style: TextStyle(color: kText)),
        content: Text(message, style: const TextStyle(color: kMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        foregroundColor: kText,
        title: const Text('Delete account'),
      ),
      body: _busy
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: kAccent),
                  const SizedBox(height: 16),
                  Text(_status ?? '', style: const TextStyle(color: kMuted)),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ListTile(
                  leading: const Icon(Icons.phonelink_erase, color: kText),
                  title: const Text(
                    'Remove from this device',
                    style: TextStyle(color: kText),
                  ),
                  subtitle: const Text(
                    'Erase it here only. Your account stays and can be '
                    'restored from a backup.',
                    style: TextStyle(color: kMuted, fontSize: 12),
                  ),
                  onTap: _removeFromDevice,
                ),
                const Divider(color: kBorder),
                ListTile(
                  leading: const Icon(
                    Icons.delete_forever,
                    color: Colors.redAccent,
                  ),
                  title: const Text(
                    'Delete my account',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  subtitle: const Text(
                    'Delete it everywhere: your handle, your Community '
                    'membership and this device. Cannot be undone.',
                    style: TextStyle(color: kMuted, fontSize: 12),
                  ),
                  onTap: _deleteEverywhere,
                ),
              ],
            ),
    );
  }
}
