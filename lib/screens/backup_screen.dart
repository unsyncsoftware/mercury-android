import 'package:flutter/material.dart';

import '../services/android_backup_channel.dart';
import '../services/auto_backup.dart';
import '../services/backup_controller.dart';
import '../services/backup_passphrase.dart';
import '../theme.dart';

/// Settings page for the automatic account backup.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  BackupStatus? _status;
  String? _folder; // content:// address of the chosen folder
  String? _folderName;
  String? _error;
  bool _busy = false;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final status = await (await BackupController.autoBackup()).status();
    if (!mounted) return;
    final name = await BackupController.store.readPref('backup_folder_name');
    if (!mounted) return;
    setState(() {
      _status = status;
      _folder ??= status.folder;
      _folderName ??= name;
    });
  }

  Future<void> _chooseFolder() async {
    try {
      final picked = await AndroidBackupChannel.pickFolder();
      if (picked != null && mounted) {
        setState(() {
          _folder = picked.uri;
          _folderName = picked.name;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'That folder could not be used. Try another.');
    }
  }

  Future<void> _turnOn() async {
    final problem = BackupPassphrase.validate(_pass.text, _confirm.text);
    if (_folder == null || _folder!.isEmpty) {
      setState(() => _error = 'Choose a folder for the backup file first.');
      return;
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final backup = AutoBackup(
      store: BackupController.store,
      location: SafBackupLocation(_folder!),
    );
    await backup.configure(passphrase: _pass.text, folder: _folder);
    await BackupController.store.writePref('backup_folder_name', _folderName ?? 'Folder');
    final result = await backup.runIfDue(force: true);
    _pass.clear();
    _confirm.clear();
    await _load();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _editing = false;
      if (result == BackupRunResult.failed) {
        _error = _status?.lastError ?? 'The backup could not be written.';
      }
    });
  }

  Future<void> _backupNow() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await BackupController.runIfDue(force: true);
    await _load();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result == BackupRunResult.failed) {
        _error = _status?.lastError ?? 'The backup could not be written.';
      }
    });
  }

  Future<void> _turnOff() async {
    await (await BackupController.autoBackup()).disable();
    await _load();
  }

  String _when(DateTime? t) {
    if (t == null) return 'never';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} minutes ago';
    if (d.inDays < 1) return '${d.inHours} hours ago';
    return '${d.inDays} days ago';
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final configured = status?.enabled ?? false;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        foregroundColor: kText,
        title: const Text('Account backup'),
      ),
      body: status == null
          ? const Center(child: CircularProgressIndicator(color: kAccent))
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'Keeps an encrypted copy of your account (handle, keys, contacts, '
                  'message text and profile photos) so you can restore it after a '
                  'reinstall or on a new device. Pictures and files sent in chats '
                  'are not included.',
                  style: TextStyle(color: kMuted, height: 1.5),
                ),
                const SizedBox(height: 16),
                if (configured && !_editing) ..._statusView(status) else ..._setupView(),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ],
              ],
            ),
    );
  }

  List<Widget> _statusView(BackupStatus status) {
    final stale = status.isStale(DateTime.now());
    return [
      _row('Folder', _folderName ?? '-'),
      _row('Last backup', _when(status.lastSuccess)),
      if (stale || status.lastError != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            status.lastError != null
                ? 'The last backup failed: ${status.lastError}'
                : 'Your backup is out of date. Open the app with the backup folder available.',
            style: const TextStyle(color: Colors.orangeAccent, height: 1.4),
          ),
        ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _busy ? null : _backupNow,
        child: Text(_busy ? 'Backing up...' : 'Back up now'),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => setState(() => _editing = true),
        child: const Text('Change folder or passphrase'),
      ),
      TextButton(
        onPressed: _turnOff,
        child: const Text('Turn off automatic backup', style: TextStyle(color: kMuted)),
      ),
      const SizedBox(height: 12),
      const Text(
        'Keep your passphrase somewhere safe. It cannot be recovered, and without '
        'it the backup cannot be opened.',
        style: TextStyle(color: kMuted, fontSize: 12, height: 1.4),
      ),
    ];
  }

  List<Widget> _setupView() {
    return [
      OutlinedButton(
        onPressed: _busy ? null : _chooseFolder,
        child: Text(_folder == null ? 'Choose backup folder' : 'Folder: ${_folderName ?? 'chosen'}'),
      ),
      const SizedBox(height: 8),
      const Text(
        'Choose a folder that is not only on this phone, such as Google Drive '
        'or an SD card, or copy the file to a computer now and then. A backup '
        'that sits only on this phone is lost with the phone.',
        style: TextStyle(color: kMuted, fontSize: 12, height: 1.4),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _pass,
        obscureText: true,
        style: const TextStyle(color: kText),
        decoration: const InputDecoration(labelText: 'Passphrase (8+ characters)'),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _confirm,
        obscureText: true,
        style: const TextStyle(color: kText),
        decoration: const InputDecoration(labelText: 'Repeat passphrase'),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _busy ? null : _turnOn,
        child: Text(_busy ? 'Working...' : 'Turn on automatic backup'),
      ),
      if (_editing)
        TextButton(
          onPressed: () => setState(() => _editing = false),
          child: const Text('Cancel', style: TextStyle(color: kMuted)),
        ),
    ];
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(label, style: const TextStyle(color: kMuted)),
            ),
            Expanded(child: Text(value, style: const TextStyle(color: kText))),
          ],
        ),
      );
}
