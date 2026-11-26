import 'package:flutter/material.dart';

import '../services/handle_service.dart';
import '../theme.dart';

/// Lets the user pick a unique `@handle`. Used for accounts made before
/// handles existed; the claim itself is passed in so it can be tested.
class ChooseHandleScreen extends StatefulWidget {
  const ChooseHandleScreen({
    super.key,
    required this.initial,
    required this.claim,
    required this.onDone,
    this.onLater,
  });

  final String initial;
  final Future<HandleClaimResult> Function(String handle) claim;
  final void Function(String handle) onDone;

  /// When set, a "Later" button is shown.
  final VoidCallback? onLater;

  @override
  State<ChooseHandleScreen> createState() => _ChooseHandleScreenState();
}

class _ChooseHandleScreenState extends State<ChooseHandleScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial.startsWith('@') ? widget.initial.substring(1) : widget.initial,
  );
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final problem = HandleService.validate(_controller.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final handle = HandleService.normalize(_controller.text);
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.claim(handle);
    if (!mounted) return;
    if (result.ok) {
      widget.onDone(result.handle ?? handle);
      return;
    }
    setState(() {
      _busy = false;
      _error = HandleService.reasonText(result.reason);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        foregroundColor: kText,
        automaticallyImplyLeading: widget.onLater != null,
        title: const Text('Choose your handle'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Your handle is your name on the network, like batman. It is '
            'unique: nobody else can use it while it is yours.',
            style: TextStyle(color: kMuted, height: 1.5),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _controller,
            enabled: !_busy,
            autocorrect: false,
            style: const TextStyle(color: kText, fontSize: 16),
            decoration: const InputDecoration(labelText: 'Handle'),
            onSubmitted: (_) => _busy ? null : _save(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving...' : 'Save handle'),
          ),
          if (widget.onLater != null)
            TextButton(
              onPressed: _busy ? null : widget.onLater,
              child: const Text('Later', style: TextStyle(color: kMuted)),
            ),
        ],
      ),
    );
  }
}
