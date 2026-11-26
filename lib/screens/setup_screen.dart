import 'dart:async';

import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/handle_service.dart';
import '../services/identity_service.dart';
import '../services/signaling_service.dart';
import 'restore_backup_screen.dart';

class SetupScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const SetupScreen({super.key, required this.onComplete});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _handleController = TextEditingController();
  final _identity       = IdentityService();
  SignalingService? _signaling;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _signaling?.disconnect();
    _handleController.dispose();
    super.dispose();
  }

  Future<void> _createIdentity() async {
    final problem = HandleService.validate(_handleController.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final handle = HandleService.normalize(_handleController.text);
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    await _identity.initialize();
    // The handle is the only name; it is also what the login signs.
    await _identity.setDisplayName(HandleService.display(handle));
    final result = await _claimDuringSetup(handle);
    if (!mounted) return;
    if (result.ok) {
      await HandleService.adopt(result.handle ?? handle, _identity.setDisplayName);
    } else if (result.reason != 'timeout' && result.reason != 'not_authenticated') {
      // Taken, held, reserved...: stay here so the user can pick another.
      setState(() {
        _loading = false;
        _error = HandleService.reasonText(result.reason);
      });
      return;
    }
    // Offline or an older server: carry on; the app asks again once online.
    _signaling?.disconnect();
    _signaling = null;
    if (!mounted) return;
    widget.onComplete();
  }

  Future<HandleClaimResult> _claimDuringSetup(String handle) async {
    final signaling = _signaling ??= SignalingService(identityService: _identity);
    if (!signaling.isConnected) {
      final connected = Completer<bool>();
      signaling.onConnectionStateChanged = (ok) {
        if (ok && !connected.isCompleted) connected.complete(true);
      };
      await signaling.connect(_identity.peerId!, handle: _identity.displayName);
      final ok = await connected.future
          .timeout(const Duration(seconds: 15), onTimeout: () => false);
      if (!ok) return const HandleClaimResult(ok: false, reason: 'timeout');
    }
    return signaling.claimHandle(handle);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Row(
                children: [
                  Container(
                    width: 10, height: 10,
                    decoration: const BoxDecoration(
                      color: kAccent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 12),
                  const Text('Mercury',
                    style: TextStyle(color: kText, fontSize: 32,
                      fontWeight: FontWeight.w700, letterSpacing: -1)),
                ],
              ),
              const SizedBox(height: 16),
              const Text('No phone number.\nNo email.\nJust you.',
                style: TextStyle(color: kMuted, fontSize: 18, height: 1.6)),
              const Spacer(),
              const Text('Choose your handle',
                style: TextStyle(color: kText, fontSize: 14,
                  fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('Your name on the network. Nobody else can use it.',
                style: TextStyle(color: kMuted, fontSize: 12)),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: kSurface, border: Border.all(color: kBorder)),
                child: TextField(
                  controller: _handleController,
                  autocorrect: false,
                  style: const TextStyle(color: kText, fontSize: 16),
                  decoration: const InputDecoration(
                    hintText: 'e.g. batman',
                    hintStyle: TextStyle(color: kMuted),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _loading ? null : _createIdentity,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  color: _loading ? kMuted : kAccent,
                  child: Center(
                    child: _loading
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                              color: kBg, strokeWidth: 2))
                        : const Text('Create Identity',
                            style: TextStyle(color: kBg, fontSize: 16,
                              fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _loading
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RestoreBackupScreen(
                                onRestored: widget.onComplete,
                              ),
                            ),
                          ),
                  child: const Text('Restore from backup',
                      style: TextStyle(color: kMuted)),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '🔒 Your identity is stored only on this device.\nWe never see it.',
                style: TextStyle(color: kMuted, fontSize: 11, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
