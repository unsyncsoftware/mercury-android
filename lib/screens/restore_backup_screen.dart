import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/android_backup_channel.dart';

import '../services/backup_controller.dart';
import '../services/backup_crypto.dart';
import '../services/backup_service.dart';
import '../theme.dart';

/// First-run screen: bring an account back from a backup file.
class RestoreBackupScreen extends StatefulWidget {
  const RestoreBackupScreen({super.key, required this.onRestored});

  /// Called after a successful restore.
  final VoidCallback onRestored;

  @override
  State<RestoreBackupScreen> createState() => _RestoreBackupScreenState();
}

class _RestoreBackupScreenState extends State<RestoreBackupScreen> {
  final _pass = TextEditingController();
  String? _filePath; // file name shown to the user
  Uint8List? _fileBytes;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pass.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final file = await AndroidBackupChannel.pickFile();
      if (file != null && mounted) {
        setState(() {
          _filePath = file.name;
          _fileBytes = file.bytes;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'That file could not be read.');
    }
  }

  Future<void> _restore() async {
    if (_fileBytes == null) {
      setState(() => _error = 'Choose your backup file first.');
      return;
    }
    if (_pass.text.isEmpty) {
      setState(() => _error = 'Enter the backup passphrase.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await BackupController.restoreFromBytes(_fileBytes!, _pass.text);
      if (!mounted) return;
      widget.onRestored();
    } on BackupDecryptException {
      _fail('Wrong passphrase, or the file is damaged.');
    } on BackupFormatException catch (e) {
      _fail('This is not a usable Mercury backup (${e.message}).');
    } on BackupTargetNotEmptyException {
      _fail('This device already has an account.');
    } catch (_) {
      _fail('The backup could not be restored.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        foregroundColor: kText,
        title: const Text('Restore from backup'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            const Text(
              'Choose your Mercury backup file and enter its passphrase. Your '
              'handle, contacts and message text come back. Pictures and files '
              'from old chats are not in the backup.',
              style: TextStyle(color: kMuted, height: 1.5),
            ),
            const SizedBox(height: 8),
            const Text(
              'Restoring moves your account to this device. Stop using it on '
              'the old device.',
              style: TextStyle(color: kMuted, height: 1.5),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: _busy ? null : _pickFile,
              child: Text(_filePath == null ? 'Choose backup file' : _filePath!),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pass,
              obscureText: true,
              style: const TextStyle(color: kText),
              decoration: const InputDecoration(labelText: 'Passphrase'),
              onSubmitted: (_) => _busy ? null : _restore(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _restore,
              child: Text(_busy ? 'Restoring...' : 'Restore'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ],
        ),
      ),
    );
  }
}
