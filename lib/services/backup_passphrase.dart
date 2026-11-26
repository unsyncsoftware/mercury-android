/// Rules for the backup passphrase. The file holds the account's private key,
/// so a guessable passphrase would defeat the encryption.
class BackupPassphrase {
  static const minLength = 8;

  /// Returns a message for the user, or null when the passphrase is acceptable.
  static String? validate(String passphrase, String confirmation) {
    if (passphrase.length < minLength) {
      return 'Use at least $minLength characters.';
    }
    if (passphrase.trim().isEmpty) {
      return 'The passphrase cannot be only spaces.';
    }
    if (passphrase != confirmation) {
      return 'The two passphrases do not match.';
    }
    return null;
  }
}
