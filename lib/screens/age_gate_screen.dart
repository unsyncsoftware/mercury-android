import 'package:flutter/material.dart';

import '../services/age_confirmation.dart';
import '../theme.dart';

/// First-run confirmation that the user is an adult. Shown once; the answer is
/// remembered. Choosing "under 18" blocks use and stores nothing.
class AgeGateScreen extends StatefulWidget {
  const AgeGateScreen({super.key, required this.onConfirmed});

  final VoidCallback onConfirmed;

  @override
  State<AgeGateScreen> createState() => _AgeGateScreenState();
}

class _AgeGateScreenState extends State<AgeGateScreen> {
  bool _ticked = false;
  bool _blocked = false;

  Future<void> _continue() async {
    await AgeConfirmation.confirm();
    if (!mounted) return;
    widget.onConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _blocked ? _blockedView() : _askView(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _blockedView() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Mercury Messenger is only for adults aged 18 and over.',
          textAlign: TextAlign.center,
          style: TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 12),
        Text(
          'You cannot use this app. Please close it and uninstall it.',
          textAlign: TextAlign.center,
          style: TextStyle(color: kMuted),
        ),
      ],
    );
  }

  Widget _askView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Mercury Messenger',
          textAlign: TextAlign.center,
          style: TextStyle(color: kText, fontSize: 26, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        const Text(
          'This app is for adults aged 18 and over.',
          textAlign: TextAlign.center,
          style: TextStyle(color: kText, fontSize: 16),
        ),
        const SizedBox(height: 20),
        CheckboxListTile(
          value: _ticked,
          onChanged: (v) => setState(() => _ticked = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          activeColor: kAccent,
          title: const Text(
            'I confirm that I am 18 or older.',
            style: TextStyle(color: kText),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _ticked ? _continue : null,
          child: const Text('Continue'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _blocked = true),
          child: const Text('I am under 18', style: TextStyle(color: kMuted)),
        ),
        const SizedBox(height: 16),
        const Text(
          'Privacy policy: mercury.unsync.uk/privacy',
          textAlign: TextAlign.center,
          style: TextStyle(color: kMuted, fontSize: 12),
        ),
      ],
    );
  }
}
