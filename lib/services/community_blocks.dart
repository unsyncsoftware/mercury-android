import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Community members this person has blocked. Kept only on this device: it
/// hides their posts, replies and messages here, and the forum is not told.
class CommunityBlocks {
  static const _key = 'community_blocked_v1';

  final Set<String> _handles = {};
  bool _loaded = false;

  /// Handles are compared without the leading @ and ignoring case.
  static String normalize(String handle) =>
      handle.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase();

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final list = jsonDecode(raw);
        if (list is List) {
          _handles.addAll(list.whereType<String>().map(normalize));
        }
      } catch (_) {
        // A damaged list is treated as empty rather than blocking the app.
      }
    }
    _loaded = true;
  }

  bool isBlocked(String? handle) =>
      handle != null && _handles.contains(normalize(handle));

  List<String> get all => _handles.toList()..sort();

  Future<void> block(String handle) async {
    await ensureLoaded();
    final value = normalize(handle);
    if (value.isEmpty) return;
    _handles.add(value);
    await _save();
  }

  Future<void> unblock(String handle) async {
    await ensureLoaded();
    _handles.remove(normalize(handle));
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(all));
  }
}
