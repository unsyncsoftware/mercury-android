import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// The file is not a Mercury backup, is cut short, or is a version we do not know.
class BackupFormatException implements Exception {
  BackupFormatException(this.message);
  final String message;
  @override
  String toString() => 'BackupFormatException: $message';
}

/// Wrong passphrase, or the file was changed or damaged. AES-GCM cannot tell
/// these apart, so neither can we.
class BackupDecryptException implements Exception {
  @override
  String toString() => 'BackupDecryptException: wrong passphrase or damaged file';
}

/// Passphrase-based encryption for the backup file.
///
/// Layout: `MBK1` | version | logN | r | p | salt(16) | nonce(12) | ciphertext+tag.
/// The key comes from scrypt; the whole header is authenticated (AES-256-GCM
/// additional data), so changing any header byte makes decryption fail.
class BackupCrypto {
  static const _magic = [0x4d, 0x42, 0x4b, 0x31]; // "MBK1"
  static const _version = 1;
  static const _saltLength = 16;
  static const _nonceLength = 12;
  static const _tagBits = 128;
  static const _maxLogN = 20; // refuse headers asking for absurd work
  static const defaultLogN = 15;

  /// Bytes before the ciphertext.
  static const headerLength = 4 + 1 + 1 + 1 + 1 + _saltLength + _nonceLength;

  static Uint8List encrypt(
    Uint8List plain,
    String passphrase, {
    int logN = defaultLogN,
    int r = 8,
    int p = 1,
  }) {
    if (passphrase.isEmpty) {
      throw ArgumentError('A passphrase is required');
    }
    final random = Random.secure();
    final salt = _randomBytes(random, _saltLength);
    final nonce = _randomBytes(random, _nonceLength);
    final header = BytesBuilder()
      ..add(_magic)
      ..addByte(_version)
      ..addByte(logN)
      ..addByte(r)
      ..addByte(p)
      ..add(salt)
      ..add(nonce);
    final headerBytes = header.toBytes();
    final key = _deriveKey(passphrase, salt, logN, r, p);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), _tagBits, nonce, headerBytes));
    final sealed = cipher.process(plain);
    return (BytesBuilder()..add(headerBytes)..add(sealed)).toBytes();
  }

  static Uint8List decrypt(Uint8List file, String passphrase) {
    if (file.length < headerLength + _tagBits ~/ 8) {
      throw BackupFormatException('File is too short to be a backup');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (file[i] != _magic[i]) {
        throw BackupFormatException('Not a Mercury backup file');
      }
    }
    if (file[4] != _version) {
      throw BackupFormatException('Unsupported backup version ${file[4]}');
    }
    final logN = file[5], r = file[6], p = file[7];
    if (logN < 1 || logN > _maxLogN || r < 1 || r > 16 || p < 1 || p > 4) {
      throw BackupFormatException('Backup header has invalid settings');
    }
    final salt = Uint8List.sublistView(file, 8, 8 + _saltLength);
    final nonce = Uint8List.sublistView(file, 8 + _saltLength, headerLength);
    final headerBytes = Uint8List.sublistView(file, 0, headerLength);
    final body = Uint8List.sublistView(file, headerLength);
    final key = _deriveKey(passphrase, salt, logN, r, p);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), _tagBits, nonce, headerBytes));
    try {
      return cipher.process(body);
    } on InvalidCipherTextException {
      throw BackupDecryptException();
    } on ArgumentError {
      throw BackupDecryptException();
    }
  }

  static Uint8List _deriveKey(String passphrase, Uint8List salt, int logN, int r, int p) {
    final scrypt = Scrypt()..init(ScryptParameters(1 << logN, r, p, 32, salt));
    return scrypt.process(Uint8List.fromList(utf8.encode(passphrase)));
  }

  static Uint8List _randomBytes(Random random, int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => random.nextInt(256)));
}
