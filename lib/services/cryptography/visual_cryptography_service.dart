import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:pdf_render/pdf_render.dart';
import 'package:path/path.dart' as path;

class VisualCryptographyService {
  final Random _random = Random.secure();

  // Generate three shares from a document: two visual shares and a key
  Future<List<Uint8List>> generateShares(File document) async {
    final documentBytes = await document.readAsBytes();
    final String originalFileName = document.path.split('/').last;
    final String originalExtension = originalFileName.split('.').last;

    // Store the original file extension in the first few bytes of the key
    final List<int> extensionBytes = originalExtension.codeUnits;
    final List<int> extensionLength = [extensionBytes.length];

    final List<int> share1 = [];
    final List<int> share2 = [];
    final List<int> key = [...extensionLength, ...extensionBytes];

    for (int byte in documentBytes) {
      // Generate random byte for key
      final int keyByte = _random.nextInt(256);
      key.add(keyByte);

      // Generate share1 using random bytes
      final int randomByte = _random.nextInt(256);
      share1.add(randomByte);

      // Generate share2 using XOR operation with key and share1
      share2.add(byte ^ keyByte ^ randomByte);
    }

    // Convert to RGBA format for image storage
    final List<int> imageShare1 = _convertToRGBAImage(share1);
    final List<int> imageShare2 = _convertToRGBAImage(share2);
    final List<int> imageKey = _convertToRGBAImage(key);

    return [
      Uint8List.fromList(imageShare1),
      Uint8List.fromList(imageShare2),
      Uint8List.fromList(imageKey),
    ];
  }

  // Combine shares to reconstruct the original document
  Future<Uint8List> combineShares(List<Uint8List> shares) async {
    if (shares.length != 3) {
      throw Exception('Exactly 3 shares (including key) required');
    }

    // Convert from RGBA format back to original bytes
    final List<int> share1Bytes = _convertFromRGBAImage(shares[0]);
    final List<int> share2Bytes = _convertFromRGBAImage(shares[1]);
    final List<int> keyBytes = _convertFromRGBAImage(shares[2]);

    // Extract original file extension from key
    final int extensionLength = keyBytes[0];
    final String originalExtension =
        String.fromCharCodes(keyBytes.sublist(1, 1 + extensionLength));

    // Remove extension info from key
    final List<int> key = keyBytes.sublist(1 + extensionLength);

    if (share1Bytes.length != share2Bytes.length ||
        share1Bytes.length != key.length) {
      throw Exception('Shares and key must be of equal length');
    }

    final List<int> combined = [];
    for (int i = 0; i < share1Bytes.length; i++) {
      combined.add(share1Bytes[i] ^ share2Bytes[i] ^ key[i]);
    }

    return Uint8List.fromList(combined);
  }

  // Convert bytes to RGBA image format (4 bytes per pixel)
  List<int> _convertToRGBAImage(List<int> bytes) {
    final List<int> rgba = [];
    final lengthBytes = [
      bytes.length >> 24,
      bytes.length >> 16,
      bytes.length >> 8,
      bytes.length
    ];
    rgba.addAll(lengthBytes);

    for (int i = 0; i < bytes.length; i++) {
      int value = bytes[i];
      rgba.add(value); // R
      rgba.add(0); // G
      rgba.add(0); // B
      rgba.add(255); // A
    }
    return rgba;
  }

  // Convert RGBA image format back to original bytes
  List<int> _convertFromRGBAImage(Uint8List rgbaBytes) {
    final List<int> bytes = [];

    int originalLength = (rgbaBytes[0] << 24) |
        (rgbaBytes[1] << 16) |
        (rgbaBytes[2] << 8) |
        rgbaBytes[3];

    for (int i = 4;
        i < rgbaBytes.length && bytes.length < originalLength;
        i += 4) {
      bytes.add(rgbaBytes[i]); // Only take the R channel
    }

    return bytes;
  }
}
