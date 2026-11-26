import 'package:flutter_test/flutter_test.dart';
import 'package:unsync/services/backup_passphrase.dart';

void main() {
  test('accepts a long matching passphrase', () {
    expect(BackupPassphrase.validate('correct horse', 'correct horse'), isNull);
  });

  test('rejects a short passphrase', () {
    expect(BackupPassphrase.validate('short', 'short'), isNotNull);
  });

  test('rejects eight spaces', () {
    expect(BackupPassphrase.validate('        ', '        '), isNotNull);
  });

  test('rejects a mismatched confirmation', () {
    expect(BackupPassphrase.validate('correct horse', 'correct hors'), contains('match'));
  });
}
