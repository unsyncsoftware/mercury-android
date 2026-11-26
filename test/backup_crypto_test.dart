import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:unsync/services/backup_crypto.dart';

void main() {
  final data = Uint8List.fromList(utf8.encode('{"peerId":"1795315617380"}'));
  const pass = 'correct horse battery staple';
  // A low cost keeps the tests fast; the format stores it in the header.
  const fast = 10;

  test('round trip returns the original bytes', () {
    final sealed = BackupCrypto.encrypt(data, pass, logN: fast);
    expect(BackupCrypto.decrypt(sealed, pass), data);
  });

  test('the file does not contain the plain text', () {
    final sealed = BackupCrypto.encrypt(data, pass, logN: fast);
    expect(utf8.decode(sealed, allowMalformed: true), isNot(contains('1795315617380')));
  });

  test('two backups of the same data differ (random salt and nonce)', () {
    final a = BackupCrypto.encrypt(data, pass, logN: fast);
    final b = BackupCrypto.encrypt(data, pass, logN: fast);
    expect(a, isNot(b));
  });

  test('wrong passphrase is rejected', () {
    final sealed = BackupCrypto.encrypt(data, pass, logN: fast);
    expect(
      () => BackupCrypto.decrypt(sealed, 'not the passphrase'),
      throwsA(isA<BackupDecryptException>()),
    );
  });

  test('a changed byte in the encrypted part is rejected', () {
    final sealed = BackupCrypto.encrypt(data, pass, logN: fast);
    sealed[sealed.length - 5] ^= 0x01;
    expect(
      () => BackupCrypto.decrypt(sealed, pass),
      throwsA(isA<BackupDecryptException>()),
    );
  });

  test('a changed header byte is rejected', () {
    final sealed = BackupCrypto.encrypt(data, pass, logN: fast);
    sealed[BackupCrypto.headerLength - 1] ^= 0x01; // inside the nonce
    expect(
      () => BackupCrypto.decrypt(sealed, pass),
      throwsA(isA<BackupDecryptException>()),
    );
  });

  test('something that is not a backup is a format error', () {
    expect(
      () => BackupCrypto.decrypt(Uint8List.fromList(utf8.encode('hello world, not a backup at all....')), pass),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('a truncated file is a format error', () {
    final sealed = BackupCrypto.encrypt(data, pass, logN: fast);
    expect(
      () => BackupCrypto.decrypt(Uint8List.sublistView(sealed, 0, 10), pass),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('an unknown version is a format error', () {
    final sealed = BackupCrypto.encrypt(data, pass, logN: fast);
    sealed[4] = 99;
    expect(
      () => BackupCrypto.decrypt(sealed, pass),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('a header asking for absurd cost is refused before any work', () {
    final sealed = BackupCrypto.encrypt(data, pass, logN: fast);
    sealed[5] = 30;
    expect(
      () => BackupCrypto.decrypt(sealed, pass),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('an empty passphrase is refused', () {
    expect(
      () => BackupCrypto.encrypt(data, '', logN: fast),
      throwsArgumentError,
    );
  });

  test('empty data round trips', () {
    final sealed = BackupCrypto.encrypt(Uint8List(0), pass, logN: fast);
    expect(BackupCrypto.decrypt(sealed, pass), isEmpty);
  });
}
