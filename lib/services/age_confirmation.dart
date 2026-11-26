import 'package:shared_preferences/shared_preferences.dart';

/// Records that the user confirmed they are 18 or older. The key is versioned so
/// the wording can be re-asked later by bumping it.
class AgeConfirmation {
  static const String _key = 'age_confirmed_18_v1';

  static Future<bool> isConfirmed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  static Future<void> confirm() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }
}
