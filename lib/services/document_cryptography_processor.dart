import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:encrypta/services/cryptography/visual_cryptography_service.dart';

class DocumentCryptographyProcessor {
  static List<Uint8List> generateShares(File document, String encryptionKey) {
    try {
      // Read the file
      final fileBytes = document.readAsBytesSync();

      // Generate random share of same length as input
      final random = Random.secure();
      final share1 = Uint8List(fileBytes.length);
      for (var i = 0; i < share1.length; i++) {
        share1[i] = random.nextInt(256);
      }

      // Generate second share using XOR
      final share2 = Uint8List(fileBytes.length);
      for (var i = 0; i < fileBytes.length; i++) {
        // XOR: original = share1 ⊕ share2
        // Therefore: share2 = original ⊕ share1
        share2[i] = fileBytes[i] ^ share1[i];
      }

      // Encrypt both shares with the provided key
      final encryptedShare1 = _encryptData(share1, encryptionKey);
      final encryptedShare2 = _encryptData(share2, encryptionKey);

      return [encryptedShare1, encryptedShare2];
    } catch (e) {
      throw 'Error generating shares: $e';
    }
  }

  static Future<Uint8List> combineShares(
      List<Uint8List> shares, String key) async {
    try {
      if (shares.length != 2) {
        throw 'Invalid number of shares. Expected 2 shares.';
      }

      // Decrypt both shares
      final decryptedShare1 = decryptData(shares[0], key);
      final decryptedShare2 = decryptData(shares[1], key);

      if (decryptedShare1.length != decryptedShare2.length) {
        throw 'Invalid shares: Lengths do not match';
      }

      // Combine shares using XOR operation
      final result = Uint8List(decryptedShare1.length);
      for (var i = 0; i < result.length; i++) {
        result[i] = decryptedShare1[i] ^ decryptedShare2[i];
      }

      return result;
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

      // Combine IV with encrypted data
      final encrypted = encrypter.encryptBytes(data, iv: iv);
      return Uint8List.fromList([...iv.bytes, ...encrypted.bytes]);
    } catch (e) {
      throw 'Error encrypting data: $e';
    }
  }

  static Uint8List decryptData(Uint8List data, String key) {
    try {
      if (data.length < 16) {
        throw 'Invalid encrypted data: Too short';
      }

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
