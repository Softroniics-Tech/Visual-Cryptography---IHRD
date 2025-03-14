// import 'dart:convert';
// import 'dart:io';
// import 'dart:math';
// import 'dart:typed_data';
// import 'package:encrypt/encrypt.dart' as encrypt;
// import 'package:image/image.dart' as img;

// class ShareData {
//   final Uint8List bytes;
//   final String fileName;
//   final String key;

//   ShareData(this.bytes, this.fileName, this.key);
// }

// class VisualCryptographyProcessor {
//   // Convert bytes to a proper PNG image
//   static Uint8List _convertToImage(List<int> bytes) {
//     // Calculate dimensions to make a roughly square image
//     int byteCount =
//         bytes.length + 8; // Add 8 for metadata (length and dimensions)
//     int pixelsNeeded = (byteCount / 3)
//         .ceil(); // Each pixel holds 3 bytes (RGB), alpha is constant
//     int width = sqrt(pixelsNeeded).ceil();
//     int height = (pixelsNeeded / width).ceil();

//     // Create a new image
//     img.Image image = img.Image(width: width, height: height);

//     // Store metadata in first 8 pixels
//     // First 2 pixels: original width and height
//     image.setPixel(0, 0, img.ColorRgba8(width >> 8, width & 0xFF, 0, 255));
//     image.setPixel(1, 0, img.ColorRgba8(height >> 8, height & 0xFF, 0, 255));

//     // Next 2 pixels: original data length (4 bytes)
//     image.setPixel(
//         2,
//         0,
//         img.ColorRgba8(
//             bytes.length >> 24, bytes.length >> 16, bytes.length >> 8, 255));
//     image.setPixel(3, 0, img.ColorRgba8(bytes.length & 0xFF, 0, 0, 255));

//     // Store actual data in the remaining pixels
//     int byteIndex = 0;
//     for (int y = 0; y < height; y++) {
//       for (int x = (y == 0) ? 4 : 0; x < width; x++) {
//         int r = byteIndex < bytes.length ? bytes[byteIndex] : 0;
//         byteIndex++;

//         int g = byteIndex < bytes.length ? bytes[byteIndex] : 0;
//         byteIndex++;

//         int b = byteIndex < bytes.length ? bytes[byteIndex] : 0;
//         byteIndex++;

//         image.setPixel(x, y, img.ColorRgba8(r, g, b, 255));

//         if (byteIndex >= bytes.length) break;
//       }
//       if (byteIndex >= bytes.length) break;
//     }

//     // Encode as PNG
//     return Uint8List.fromList(img.encodePng(image));
//   }

//   // Convert PNG image back to original bytes
//   static List<int> _convertFromImage(Uint8List pngBytes) {
//     // Decode PNG
//     img.Image? image = img.decodePng(pngBytes);
//     if (image == null) {
//       throw Exception('Failed to decode PNG image');
//     }

//     // Extract metadata from first 4 pixels
//     img.Pixel pixel0 = image.getPixel(0, 0);
//     img.Pixel pixel1 = image.getPixel(1, 0);
//     img.Pixel pixel2 = image.getPixel(2, 0);
//     img.Pixel pixel3 = image.getPixel(3, 0);
//     int storedWidth = ((pixel0.r as int) << 8) | (pixel0.g as int);
//     int storedHeight = ((pixel1.r as int) << 8) | (pixel1.g as int);
//     int originalLength = ((pixel2.r as int) << 24) |
//         ((pixel2.g as int) << 16) |
//         ((pixel2.b as int) << 8) |
//         (pixel3.r as int);

//     // Extract data from the remaining pixels
//     final List<int> bytes = [];
//     int byteIndex = 0;

//     for (int y = 0; y < image.height; y++) {
//       for (int x = (y == 0) ? 4 : 0; x < image.width; x++) {
//         img.Pixel pixel = image.getPixel(x, y);

//         bytes.add(pixel.r as int);
//         bytes.add(pixel.g as int);
//         bytes.add(pixel.b as int);

//         byteIndex += 3;
//         if (bytes.length >= originalLength) break;
//       }
//       if (bytes.length >= originalLength) break;
//     }

//     // Trim to original length
//     return bytes.sublist(0, originalLength);
//   }

//   static List<ShareData> generateShares(File document) {
//     final String originalFileName = document.path.split('/').last;
//     final String originalExtension = originalFileName.split('.').last;
//     final documentBytes = document.readAsBytesSync();

//     // Generate a random encryption key
//     final String encryptionKey = generateKey();

//     // First encrypt the document bytes
//     final encryptedBytes =
//         _encryptData(Uint8List.fromList(documentBytes), encryptionKey);

//     final List<int> share1 = [];
//     final List<int> share2 = [];

//     // Generate shares from encrypted data
//     final Random random = Random.secure();
//     for (int byte in encryptedBytes) {
//       final int randomByte = random.nextInt(256);
//       share1.add(randomByte);
//       share2.add(byte ^ randomByte);
//     }

//     // Convert to PNG format for image shares
//     final Uint8List imageShare1 = _convertToImage(share1);
//     final Uint8List imageShare2 = _convertToImage(share2);

//     return [
//       ShareData(
//         imageShare1,
//         'share1_$originalFileName.png',
//         encryptionKey,
//       ),
//       ShareData(
//         imageShare2,
//         'share2_$originalFileName.png',
//         encryptionKey,
//       ),
//       ShareData(
//         Uint8List.fromList(utf8.encode(encryptionKey)),
//         'key_$originalFileName.txt',
//         encryptionKey,
//       ),
//     ];
//   }

//   static String generateKey() {
//     try {
//       final key = encrypt.Key.fromSecureRandom(32);
//       return base64Encode(key.bytes);
//     } catch (e) {
//       throw 'Error generating key: $e';
//     }
//   }

//   static Uint8List combineShares(List<Uint8List> shares, String key) {
//     if (shares.length != 2) {
//       throw Exception('Exactly 2 shares required');
//     }

//     final List<int> share1Bytes = _convertFromImage(shares[0]);
//     final List<int> share2Bytes = _convertFromImage(shares[1]);

//     if (share1Bytes.length != share2Bytes.length) {
//       throw Exception('Shares must be of equal length');
//     }

//     final List<int> combined = [];
//     for (int i = 0; i < share1Bytes.length; i++) {
//       // Combine shares using XOR
//       combined.add(share1Bytes[i] ^ share2Bytes[i]);
//     }

//     // Decrypt the combined data
//     return decryptData(Uint8List.fromList(combined), key);
//   }

//   static Uint8List _encryptData(Uint8List data, String key) {
//     try {
//       final keyBytes = base64Decode(key);
//       final encrypter = encrypt.Encrypter(
//         encrypt.AES(encrypt.Key(Uint8List.fromList(keyBytes))),
//       );
//       final iv = encrypt.IV.fromSecureRandom(16);

//       // Combine IV with encrypted data for later decryption
//       final encrypted = encrypter.encryptBytes(data, iv: iv);
//       return Uint8List.fromList([...iv.bytes, ...encrypted.bytes]);
//     } catch (e) {
//       throw 'Error encrypting data: $e';
//     }
//   }

//   static Uint8List decryptData(Uint8List data, String key) {
//     try {
//       final keyBytes = base64Decode(key);
//       final encrypter = encrypt.Encrypter(
//         encrypt.AES(encrypt.Key(Uint8List.fromList(keyBytes))),
//       );

//       // Extract IV from the first 16 bytes
//       final iv = encrypt.IV(data.sublist(0, 16));
//       final encryptedBytes = data.sublist(16);

//       final decrypted = encrypter.decryptBytes(
//         encrypt.Encrypted(encryptedBytes),
//         iv: iv,
//       );

//       return Uint8List.fromList(decrypted);
//     } catch (e) {
//       throw 'Error decrypting data: $e';
//     }
//   }
// }

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:image/image.dart' as img;

class ShareData {
  final Uint8List bytes;
  final String fileName;
  final String key;

  ShareData(this.bytes, this.fileName, this.key);
}

class VisualCryptographyProcessor {
  // Convert bytes to a proper PNG image
  static Uint8List _convertToImage(List<int> bytes) {
    // Calculate dimensions to make a roughly square image
    int byteCount =
        bytes.length + 8; // Add 8 for metadata (length and dimensions)
    int pixelsNeeded = (byteCount / 3)
        .ceil(); // Each pixel holds 3 bytes (RGB), alpha is constant
    int width = sqrt(pixelsNeeded).ceil();
    int height = (pixelsNeeded / width).ceil();

    // Create a new image
    img.Image image = img.Image(width: width, height: height);

    // Store metadata in first 8 pixels
    // First 2 pixels: original width and height
    image.setPixel(0, 0, img.ColorRgba8(width >> 8, width & 0xFF, 0, 255));
    image.setPixel(1, 0, img.ColorRgba8(height >> 8, height & 0xFF, 0, 255));

    // Next 2 pixels: original data length (4 bytes)
    image.setPixel(
        2,
        0,
        img.ColorRgba8(
            bytes.length >> 24, bytes.length >> 16, bytes.length >> 8, 255));
    image.setPixel(3, 0, img.ColorRgba8(bytes.length & 0xFF, 0, 0, 255));

    // Store actual data in the remaining pixels
    int byteIndex = 0;
    for (int y = 0; y < height; y++) {
      for (int x = (y == 0) ? 4 : 0; x < width; x++) {
        int r = byteIndex < bytes.length ? bytes[byteIndex] : 0;
        byteIndex++;

        int g = byteIndex < bytes.length ? bytes[byteIndex] : 0;
        byteIndex++;

        int b = byteIndex < bytes.length ? bytes[byteIndex] : 0;
        byteIndex++;

        image.setPixel(x, y, img.ColorRgba8(r, g, b, 255));

        if (byteIndex >= bytes.length) break;
      }
      if (byteIndex >= bytes.length) break;
    }

    // Encode as PNG
    return Uint8List.fromList(img.encodePng(image));
  }

  // Convert PNG image back to original bytes
  static List<int> _convertFromImage(Uint8List pngBytes) {
    // Decode PNG
    img.Image? image = img.decodePng(pngBytes);
    if (image == null) {
      throw Exception('Failed to decode PNG image');
    }

    // Extract metadata from first 4 pixels
    img.Pixel pixel0 = image.getPixel(0, 0);
    img.Pixel pixel1 = image.getPixel(1, 0);
    img.Pixel pixel2 = image.getPixel(2, 0);
    img.Pixel pixel3 = image.getPixel(3, 0);
    int storedWidth = ((pixel0.r as int) << 8) | (pixel0.g as int);
    int storedHeight = ((pixel1.r as int) << 8) | (pixel1.g as int);
    int originalLength = ((pixel2.r as int) << 24) |
        ((pixel2.g as int) << 16) |
        ((pixel2.b as int) << 8) |
        (pixel3.r as int);

    // Extract data from the remaining pixels
    final List<int> bytes = [];
    int byteIndex = 0;

    for (int y = 0; y < image.height; y++) {
      for (int x = (y == 0) ? 4 : 0; x < image.width; x++) {
        img.Pixel pixel = image.getPixel(x, y);

        bytes.add(pixel.r as int);
        bytes.add(pixel.g as int);
        bytes.add(pixel.b as int);

        byteIndex += 3;
        if (bytes.length >= originalLength) break;
      }
      if (bytes.length >= originalLength) break;
    }

    // Trim to original length
    return bytes.sublist(0, originalLength);
  }

  static List<ShareData> generateShares(File document) {
    final String originalFileName = document.path.split('/').last;
    final String originalExtension = originalFileName.split('.').last;
    final documentBytes = document.readAsBytesSync();

    // Store file extension in the beginning of the data
    final List<int> extensionBytes = utf8.encode(originalExtension);
    final List<int> dataWithExtension = [
      extensionBytes.length, // First byte is the length of extension
      ...extensionBytes, // Then the extension itself
      ...documentBytes // Then the original document bytes
    ];

    // Generate a random encryption key
    final String encryptionKey = generateKey();

    // First encrypt the document bytes with extension
    final encryptedBytes =
        _encryptData(Uint8List.fromList(dataWithExtension), encryptionKey);

    final List<int> share1 = [];
    final List<int> share2 = [];

    // Generate shares from encrypted data
    final Random random = Random.secure();
    for (int byte in encryptedBytes) {
      final int randomByte = random.nextInt(256);
      share1.add(randomByte);
      share2.add(byte ^ randomByte);
    }

    // Convert to PNG format for image shares
    final Uint8List imageShare1 = _convertToImage(share1);
    final Uint8List imageShare2 = _convertToImage(share2);

    return [
      ShareData(
        imageShare1,
        'share1_$originalFileName.png',
        encryptionKey,
      ),
      ShareData(
        imageShare2,
        'share2_$originalFileName.png',
        encryptionKey,
      ),
      ShareData(
        Uint8List.fromList(utf8.encode(encryptionKey)),
        'key_$originalFileName.txt',
        encryptionKey,
      ),
    ];
  }

  static String generateKey() {
    try {
      final key = encrypt.Key.fromSecureRandom(32);
      return base64Encode(key.bytes);
    } catch (e) {
      throw 'Error generating key: $e';
    }
  }

  static Uint8List combineShares(List<Uint8List> shares, String key) {
    if (shares.length != 2) {
      throw Exception('Exactly 2 shares required');
    }

    final List<int> share1Bytes = _convertFromImage(shares[0]);
    final List<int> share2Bytes = _convertFromImage(shares[1]);

    if (share1Bytes.length != share2Bytes.length) {
      throw Exception('Shares must be of equal length');
    }

    final List<int> combined = [];
    for (int i = 0; i < share1Bytes.length; i++) {
      // Combine shares using XOR
      combined.add(share1Bytes[i] ^ share2Bytes[i]);
    }

    // Decrypt the combined data
    final Uint8List decryptedData =
        decryptData(Uint8List.fromList(combined), key);

    // Extract the original file content without the extension metadata
    final int extensionLength = decryptedData[0];

    // Extract the original file extension
    final String fileExtension =
        utf8.decode(decryptedData.sublist(1, extensionLength + 1));

    // Extract the actual file content
    final Uint8List fileContent = decryptedData.sublist(extensionLength + 1);

    return fileContent;
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

  // Method to save the reconstructed file with proper extension
  static File saveReconstructedFile(Uint8List fileData, List<Uint8List> shares,
      String key, String outputPath) {
    // First decrypt and get the data with extension metadata
    final Uint8List decryptedFull =
        decryptData(Uint8List.fromList(_combineSharesRaw(shares)), key);

    // Extract the extension
    final int extensionLength = decryptedFull[0];
    final String fileExtension =
        utf8.decode(decryptedFull.sublist(1, extensionLength + 1));

    // Create output file path with original extension
    final String outputFilePath = '$outputPath/reconstructed.$fileExtension';

    // Write bytes to file
    final File outputFile = File(outputFilePath);
    outputFile.writeAsBytesSync(fileData);

    return outputFile;
  }

  // Helper method to combine shares without decryption
  static List<int> _combineSharesRaw(List<Uint8List> shares) {
    if (shares.length != 2) {
      throw Exception('Exactly 2 shares required');
    }

    final List<int> share1Bytes = _convertFromImage(shares[0]);
    final List<int> share2Bytes = _convertFromImage(shares[1]);

    if (share1Bytes.length != share2Bytes.length) {
      throw Exception('Shares must be of equal length');
    }

    final List<int> combined = [];
    for (int i = 0; i < share1Bytes.length; i++) {
      // Combine shares using XOR
      combined.add(share1Bytes[i] ^ share2Bytes[i]);
    }

    return combined;
  }

  // Method to get the original file extension
  static String getOriginalExtension(List<Uint8List> shares, String key) {
    // Decrypt the combined data
    final Uint8List decryptedData =
        decryptData(Uint8List.fromList(_combineSharesRaw(shares)), key);

    // Extract the extension
    final int extensionLength = decryptedData[0];
    return utf8.decode(decryptedData.sublist(1, extensionLength + 1));
  }
}
