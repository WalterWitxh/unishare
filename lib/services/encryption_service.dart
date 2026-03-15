import 'dart:typed_data';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

/// AES-256 E2E Encryption Patch (UniShare)
class EncryptionService {
  /// Derive 32-byte key from PIN using SHA-256
  static List<int> generateKeyFromPin(String pin) {
    final bytes = utf8.encode(pin);
    final digest = sha256.convert(bytes);
    return digest.bytes;
  }

  /// Encrypt bytes using AES-256-CBC with PKCS7 padding.
  /// Returns bytes with IV (16 bytes) prepended: [IV | ciphertext]
  static Future<Uint8List> encryptBytes(Uint8List data, String pin) async {
    final key = encrypt.Key(Uint8List.fromList(generateKeyFromPin(pin)));
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
    );
    final encrypted = encrypter.encryptBytes(data, iv: iv);
    final out = Uint8List(iv.bytes.length + encrypted.bytes.length);
    out.setRange(0, iv.bytes.length, iv.bytes);
    out.setRange(iv.bytes.length, out.length, encrypted.bytes);
    return out;
  }

  /// Decrypt bytes produced by [encryptBytes]
  static Future<Uint8List> decryptBytes(
    Uint8List encryptedData,
    String pin,
  ) async {
    if (encryptedData.length < 16) {
      throw ArgumentError('Invalid encrypted data');
    }
    final key = encrypt.Key(Uint8List.fromList(generateKeyFromPin(pin)));
    final ivBytes = encryptedData.sublist(0, 16);
    final cipherBytes = encryptedData.sublist(16);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
    );
    final iv = encrypt.IV(ivBytes);
    final decrypted = encrypter.decryptBytes(
      encrypt.Encrypted(cipherBytes),
      iv: iv,
    );
    return Uint8List.fromList(decrypted);
  }
}
