import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;

class DocumentCryptographyProcessor {
  static List<Uint8List> generateShares(File document, String encryptionKey) {
    try {
      // Read the file
      final fileBytes = document.readAsBytesSync();

      // Encrypt the file first
      final encrypted = _encryptData(fileBytes, encryptionKey);

      // Split the encrypted data into two shares
      final halfLength = (encrypted.length / 2).ceil();
      final share1Bytes = encrypted.sublist(0, halfLength);
      final share2Bytes = encrypted.sublist(halfLength);

      return [share1Bytes, share2Bytes];
    } catch (e) {
      throw 'Error generating shares: $e';
    }
  }

  static Future<Uint8List> combineShares(List<Uint8List> shares) async {
    try {
      // Combine the shares
      final combinedBytes = Uint8List.fromList([
        ...shares[0],
        ...shares[1],
      ]);

      return combinedBytes;
    } catch (e) {
      throw 'Error combining shares: $e';
    }
  }

  static String generateKey() {
    try {
      final key = encrypt.Key.fromSecureRandom(32);
      return base64Encode(key.bytes);
    } catch (e) {
      throw 'Error generating key: $e';
    }
  }

  static Uint8List _encryptData(Uint8List data, String key) {
    try {
      final keyBytes = base64Decode(key);
      final encrypter = encrypt.Encrypter(
        encrypt.AES(encrypt.Key(Uint8List.fromList(keyBytes))),
      );
      final iv = encrypt.IV.fromSecureRandom(16);

      // Combine IV with encrypted data for later decryption
      final encrypted = encrypter.encryptBytes(data, iv: iv);
      return Uint8List.fromList([...iv.bytes, ...encrypted.bytes]);
    } catch (e) {
      throw 'Error encrypting data: $e';
    }
  }

  static Uint8List decryptData(Uint8List data, String key) {
    try {
      final keyBytes = base64Decode(key);
      final encrypter = encrypt.Encrypter(
        encrypt.AES(encrypt.Key(Uint8List.fromList(keyBytes))),
      );

      // Extract IV from the first 16 bytes
      final iv = encrypt.IV(data.sublist(0, 16));
      final encryptedBytes = data.sublist(16);

      final decrypted = encrypter.decryptBytes(
        encrypt.Encrypted(encryptedBytes),
        iv: iv,
      );

      return Uint8List.fromList(decrypted);
    } catch (e) {
      throw 'Error decrypting data: $e';
    }
  }
}
