import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Outcome of asking the server for a handle.
class HandleClaimResult {
  const HandleClaimResult({required this.ok, this.handle, this.reason});
  final bool ok;
  final String? handle;

  /// taken, held, reserved, invalid, rate_limited, peer_id_taken,
  /// not_authenticated, timeout.
  final String? reason;
}

/// The server's answer to deleting this account.
class AccountDeleteResult {
  const AccountDeleteResult({required this.ok, this.reason});
  final bool ok;

  /// not_authenticated, confirm_required, timeout, or a server error.
  final String? reason;
}

/// What the server says this device's handle is. [supported] is false when
/// the server did not answer (an older server without handle ownership).
class HandleStatus {
  const HandleStatus({required this.supported, this.handle});
  final bool supported;
  final String? handle;
}

/// Rules for the unique `@handle`, matching the signaling server.
class HandleService {
  static const _prefsKey = 'handle';
  static const maxLength = 64; // characters after the @
  static final _pattern = RegExp(r'^@[a-z0-9](?:[a-z0-9._-]{0,62}[a-z0-9])?$');

  /// Lower-case, trimmed, with a leading `@`.
  static String normalize(String input) {
    final h = input.trim().toLowerCase();
    if (h.isEmpty) return '';
    return h.startsWith('@') ? h : '@$h';
  }

  /// A message for the user, or null when the handle is acceptable.
  static String? validate(String input) {
    final h = normalize(input);
    if (h.length <= 1) return 'Choose a handle.';
    if (h.length - 1 > maxLength) return 'Use at most $maxLength characters.';
    if (!_pattern.hasMatch(h)) {
      return 'Use letters, numbers, dots, dashes or underscores. '
          'Start and end with a letter or number.';
    }
    return null;
  }

  /// A valid handle built from [displayName], e.g. "Bat Man!" -> "@bat.man".
  static String suggestFrom(String displayName, {Random? random}) {
    var h = displayName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '.');
    h = h.replaceAll(RegExp(r'[^a-z0-9._-]'), '');
    h = h.replaceAll(RegExp(r'[._-]{2,}'), '.');
    h = _trimSeparators(h);
    if (h.length > maxLength) h = _trimSeparators(h.substring(0, maxLength));
    if (h.isEmpty || validate(h) != null) {
      final n = (random ?? Random()).nextInt(9000) + 1000;
      return '@user$n';
    }
    return '@$h';
  }

  static String _trimSeparators(String s) =>
      s.replaceAll(RegExp(r'^[._-]+|[._-]+$'), '');

  /// Plain words for a refused claim.
  static String reasonText(String? reason) {
    switch (reason) {
      case 'taken':
        return 'That handle is already taken. Try another.';
      case 'held':
        return 'That handle was used recently and is on hold. Try another.';
      case 'reserved':
        return 'That handle is reserved. Try another.';
      case 'invalid':
        return 'That handle is not allowed. Use letters, numbers, dots, dashes or underscores.';
      case 'rate_limited':
        return 'Too many new handles from this network today. Try again tomorrow.';
      case 'peer_id_taken':
        return 'This device ID is already in use. Restart setup to get a new one.';
      case 'not_authenticated':
        return 'Not connected yet. Check your internet connection and try again.';
      case 'timeout':
        return 'The server did not answer. Check your internet connection and try again.';
      default:
        return 'The handle could not be saved. Try again.';
    }
  }

  /// The handle as people see it: no `@` (the server keeps `@name`).
  static String display(String handle) {
    final h = normalize(handle);
    return h.startsWith('@') ? h.substring(1) : h;
  }

  /// The handle is the only name: save it and make it the shown name.
  static Future<void> adopt(
    String handle,
    Future<void> Function(String name) setDisplayName,
  ) async {
    await save(handle);
    await setDisplayName(display(handle));
  }

  static Future<String?> savedHandle() async {
    final prefs = await SharedPreferences.getInstance();
    final h = prefs.getString(_prefsKey);
    return h == null || h.isEmpty ? null : h;
  }

  static Future<void> save(String handle) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, normalize(handle));
  }
}
