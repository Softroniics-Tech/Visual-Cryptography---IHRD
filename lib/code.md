import 'dart:io';

import 'package:encrypta/services/chat_service.dart';
import 'package:encrypta/worker/constands/colors.dart';
import 'package:encrypta/services/document_cryptography_processor.dart'
    as crypto;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

class ShareData {
  final Uint8List bytes;
  final String fileName;

  ShareData(this.bytes, this.fileName);
}

// Main Page Widget
class AppScreenHome extends StatefulWidget {
  const AppScreenHome({super.key});

  @override
  State<AppScreenHome> createState() => _AppScreenHomeState();
}

// Main Page State
class _AppScreenHomeState extends State<AppScreenHome> {
  File? _document;
  List<ShareData>? _shares;
  Uint8List? _combinedDocument;
  bool _isProcessing = false;
  bool _isMixed = false;
  String? _encryptionKey;

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _pickDocument() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();

      if (result != null) {
        setState(() {
          _document = File(result.files.single.path!);
          _shares = null;
          _combinedDocument = null;
          _isProcessing = true;
        });
        await _generateShares();
        setState(() {
          _isProcessing = false;
        });
      }
    } catch (e) {
      _showError('Error picking document: $e');
    }
  }

  Future<void> _generateShares() async {
    if (_document == null) return;

    try {
      final shares = DocumentCryptographyProcessor.generateShares(_document!);
      // Convert the key share bytes to a hex string
      final keyBytes = shares[2].bytes;
      final hexKey =
          keyBytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

      setState(() {
        _shares = shares;
        _encryptionKey = hexKey;
      });
    } catch (e) {
      _showError('Error generating shares: $e');
    }
  }

  Future<String> _getDownloadsPath() async {
    if (Platform.isAndroid) {
      final directory = await getExternalStorageDirectory();
      return '${directory!.path}/Documents/DocumentCrypto';
    } else {
      final directory = await getApplicationDocumentsDirectory();
      return '${directory.path}/DocumentCrypto';
    }
  }

  Future<void> _saveAndShareFile(Uint8List bytes, String fileName) async {
    if (!await Permission.manageExternalStorage.request().isGranted) {
      _showError('Storage permission is required');
      openAppSettings();
      return;
    }

    try {
      final String dirPath = await _getDownloadsPath();
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final String filePath = '$dirPath/$fileName';
      final File file = File(filePath);
      await file.writeAsBytes(bytes);

      await Share.shareXFiles([XFile(filePath)], text: 'Share $fileName');

      _showSuccess('File saved and ready to share');
    } catch (e) {
      _showError('Error saving file: $e');
    }
  }

  Future<void> _saveShare(ShareData share) async {
    if (!await Permission.manageExternalStorage.request().isGranted) {
      _showError('Storage permission is required');
      openAppSettings();
      return;
    }
    await _saveAndShareFile(share.bytes, share.fileName);
  }

  Future<void> _saveCombinedDocument() async {
    if (_combinedDocument == null || _shares == null) return;

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      String fileName;

      // Get original file extension from the first share's filename
      final String originalFileName = _shares![0].fileName;
      final String originalExtension =
          originalFileName.split('_').last.split('.').first.split('/').last;

      if (_isMixed) {
        final mixedBytes = _mixShares(_shares![0].bytes, _shares![1].bytes);
        fileName = 'mixed_$timestamp.png';
        await _saveAndShareFile(mixedBytes, fileName);
      } else {
        fileName = 'recovered_$timestamp.$originalExtension';
        await _saveAndShareFile(_combinedDocument!, fileName);
      }

      setState(() {
        _isMixed = !_isMixed;
      });
    } catch (e) {
      _showError('Error saving document: $e');
    }
  }

  Uint8List _mixShares(Uint8List share1, Uint8List share2) {
    final List<int> mixed = [];
    for (int i = 0; i < share1.length; i++) {
      mixed.add((share1[i] + share2[i]) ~/ 2); // Simple average for mixing
    }
    return Uint8List.fromList(mixed);
  }

  Future<void> _pickShare() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png'],
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _isProcessing = true;
          _shares = [];
        });

        for (var file in result.files) {
          if (file.path != null) {
            final bytes = await File(file.path!).readAsBytes();
            _shares!.add(ShareData(bytes, file.name));
          }
        }

        // Sort shares so key is last (assuming key file starts with 'key_')
        _shares!.sort((a, b) {
          if (a.fileName.startsWith('key_')) return 1;
          if (b.fileName.startsWith('key_')) return -1;
          return a.fileName.compareTo(b.fileName);
        });

        if (_shares!.length == 3) {
          try {
            final combined = DocumentCryptographyProcessor.combineShares(
              _shares!.map((s) => s.bytes).toList(),
            );
            setState(() {
              _combinedDocument = combined;
            });
            _showSuccess('Document decrypted successfully');
          } catch (e) {
            _showError('Error combining shares: $e');
          }
        } else {
          _showError('Please select all three files (2 shares and 1 key file)');
          setState(() {
            _shares = null;
          });
        }

        setState(() {
          _isProcessing = false;
        });
      }
    } catch (e) {
      _showError('Error picking shares: $e');
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Document Cryptography'),
        actions: [
          if (_document != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                setState(() {
                  _document = null;
                  _shares = null;
                  _combinedDocument = null;
                });
              },
              tooltip: 'Clear All',
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              FirebaseAuth.instance.signOut();
              Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LoginPage(),
                  ),
                  (route) => false);
            },
          ),
        ],
      ),
      body: _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_document == null && _shares == null) ...[
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _pickDocument,
                          icon: const Icon(Icons.file_upload),
                          label: const Text('Encrypt Document'),
                        ),
                        ElevatedButton.icon(
                          onPressed: _pickShare,
                          icon: const Icon(Icons.lock_open),
                          label: const Text('Decrypt Shares'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Center(
                      child: Text(
                        'Select a document to encrypt\nor select all three files to decrypt',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  if (_document != null) ...[
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.description),
                        title: Text(_document!.path.split('/').last),
                        subtitle: const Text('Original Document'),
                      ),
                    ),
                  ],
                  if (_shares != null && _encryptionKey != null) ...[
                    const SizedBox(height: 20),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Encryption Key (Save this securely)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: SelectableText(
                                    _encryptionKey!,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy),
                                  onPressed: () {
                                    // Copy key to clipboard
                                    Clipboard.setData(ClipboardData(
                                      text: _encryptionKey!,
                                    )).then((_) {
                                      _showSuccess('Key copied to clipboard');
                                    });
                                  },
                                  tooltip: 'Copy key',
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'You will need this key to decrypt the document later',
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ...List.generate(_shares!.length, (index) {
                      String shareTitle =
                          index == 2 ? 'Encryption Key' : 'Share ${index + 1}';
                      IconData shareIcon =
                          index == 2 ? Icons.key : Icons.file_copy;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Card(
                          child: ListTile(
                            leading: Icon(shareIcon),
                            title: Text(shareTitle),
                            subtitle: Text(
                                index == 2 ? 'Required for decryption' : ''),
                            trailing: IconButton(
                              icon: const Icon(Icons.share),
                              onPressed: () => _saveShare(_shares![index]),
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () {
                        try {
                          final combined =
                              DocumentCryptographyProcessor.combineShares(
                            _shares!.map((s) => s.bytes).toList(),
                          );
                          setState(() {
                            _combinedDocument = combined;
                          });
                        } catch (e) {
                          _showError('Error combining shares: $e');
                        }
                      },
                      icon: const Icon(Icons.merge_type),
                      label: const Text('Combine Shares'),
                    ),
                  ],
                  if (_combinedDocument != null) ...[
                    const SizedBox(height: 20),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.description),
                        title: Text(
                          _isMixed ? 'Mixed Document' : 'Combined Document',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.share),
                          onPressed: _saveCombinedDocument,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _isMixed = !_isMixed;
                        });
                      },
                      child: Text(_isMixed ? 'Show Combined' : 'Show Mixed'),
                    ),
                  ],
                ],
              ),
            ),
      floatingActionButton: null,
    );
  }
}

// Visual Cryptography Logic
class DocumentCryptographyProcessor {
  // Convert bytes to RGBA image format (4 bytes per pixel)
  static List<int> _convertToRGBAImage(List<int> bytes) {
    final List<int> rgba = [];
    // Add length at the start to help with reconstruction
    final lengthBytes = [
      bytes.length >> 24,
      bytes.length >> 16,
      bytes.length >> 8,
      bytes.length
    ];
    rgba.addAll(lengthBytes);

    for (int i = 0; i < bytes.length; i++) {
      // Convert each byte to RGBA (1 byte becomes 4 bytes)
      int value = bytes[i];
      rgba.add(value); // R
      rgba.add(0); // G
      rgba.add(0); // B
      rgba.add(255); // A (always opaque)
    }
    return rgba;
  }

  // Convert RGBA image format back to original bytes
  static List<int> _convertFromRGBAImage(Uint8List rgbaBytes) {
    final List<int> bytes = [];

    // First 4 bytes contain the original length
    int originalLength = (rgbaBytes[0] << 24) |
        (rgbaBytes[1] << 16) |
        (rgbaBytes[2] << 8) |
        rgbaBytes[3];

    // Skip the length bytes and process the RGBA data
    for (int i = 4;
        i < rgbaBytes.length && bytes.length < originalLength;
        i += 4) {
      bytes.add(rgbaBytes[i]); // Only take the R channel
    }

    return bytes;
  }

  static List<ShareData> generateShares(File documentFile) {
    final Uint8List documentBytes = documentFile.readAsBytesSync();
    final String originalFileName = documentFile.path.split('/').last;
    final String originalExtension = originalFileName.split('.').last;

    // Store the original file extension in the first few bytes of the key
    final List<int> extensionBytes = originalExtension.codeUnits;
    final List<int> extensionLength = [extensionBytes.length];

    final List<int> share1 = [];
    final List<int> share2 = [];
    final List<int> key = [...extensionLength, ...extensionBytes];

    for (int byte in documentBytes) {
      // Generate random byte for key
      final int keyByte = (DateTime.now().microsecondsSinceEpoch % 256);
      key.add(keyByte);

      // Generate share1 using random bytes
      final int randomByte = (DateTime.now().microsecondsSinceEpoch % 256);
      share1.add(randomByte);

      // Generate share2 using XOR operation with key and share1
      share2.add(byte ^ keyByte ^ randomByte);
    }

    // Convert to RGBA format
    final List<int> imageShare1 = _convertToRGBAImage(share1);
    final List<int> imageShare2 = _convertToRGBAImage(share2);
    final List<int> imageKey = _convertToRGBAImage(key);

    return [
      ShareData(
          Uint8List.fromList(imageShare1), 'share1_$originalFileName.png'),
      ShareData(
          Uint8List.fromList(imageShare2), 'share2_$originalFileName.png'),
      ShareData(Uint8List.fromList(imageKey), 'key_$originalFileName.png'),
    ];
  }

  static Uint8List combineShares(List<Uint8List> shares) {
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
}
