import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:encrypta/worker/auth_user/login_page.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  final TextEditingController _keyController = TextEditingController();

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<bool> _checkAndRequestPermissions() async {
    if (Platform.isAndroid) {
      final status = await Permission.storage.status;
      if (status.isDenied) {
        await Permission.storage.request();
      }

      if (await Permission.manageExternalStorage.isRestricted) {
        if (!await Permission.manageExternalStorage.request().isGranted) {
          _showError('Storage permission is required for handling documents');
          return false;
        }
      }

      // Request media permissions
      await Permission.photos.request();
      await Permission.videos.request();

      return true;
    }
    return true;
  }

  Future<void> _pickDocument() async {
    if (!await _checkAndRequestPermissions()) {
      return;
    }

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'doc',
          'docx',
          'txt',
          'png',
          'jpg',
          'jpeg',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
          'csv',
          'rtf',
          'zip',
          'rar'
        ],
        withData: true, // This ensures we get the file data
        allowCompression: false, // Prevent compression of files
      );

      if (result != null && result.files.single.bytes != null) {
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
      } else {
        _showError('Could not read the selected file');
      }
    } catch (e) {
      _showError('Error picking document: $e');
    }
  }

  Future<void> _generateShares() async {
    if (_document == null) return;

    try {
      final shares = DocumentCryptographyProcessor.generateShares(_document!);
      setState(() {
        _shares = shares;
        _encryptionKey = DocumentCryptographyProcessor.generateKey();
      });

      // Show key in dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Save This Decryption Key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _encryptionKey!,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'You will need this key to decrypt your document.\n'
                'Please save it in a secure place.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _encryptionKey!));
                _showSuccess('Key copied to clipboard');
              },
              child: const Text('Copy Key'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
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
    if (!await _checkAndRequestPermissions()) {
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
      await file.writeAsBytes(bytes, flush: true);

      // Ensure the file exists before sharing
      if (await file.exists()) {
        await Share.shareXFiles([XFile(filePath)], text: 'Share $fileName');
        _showSuccess('File saved and ready to share');
      } else {
        _showError('Error: File not saved properly');
      }
    } catch (e) {
      _showError('Error saving file: $e');
    }
  }

  Future<void> _saveShare(ShareData share) async {
    if (!await _checkAndRequestPermissions()) {
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

      if (result != null && result.files.length == 2) {
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
        final key = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Enter Decryption Key'),
            content: TextField(
              controller: _keyController,
              decoration: const InputDecoration(
                hintText: 'Enter your 12-character key',
              ),
              maxLength: DocumentCryptographyProcessor._keyLength,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, _keyController.text),
                child: const Text('Decrypt'),
              ),
            ],
          ),
        );

        if (key != null &&
            key.length == DocumentCryptographyProcessor._keyLength) {
          try {
            final combined = DocumentCryptographyProcessor.combineShares(
              _shares!.map((s) => s.bytes).toList(),
              key,
            );
            setState(() {
              _combinedDocument = combined;
            });
            _showSuccess('Document decrypted successfully');
          } catch (e) {
            _showError('Error decrypting: Invalid key or corrupted shares');
          }
        } else if (key != null) {
          _showError(
              'Invalid key length. Key must be exactly ${DocumentCryptographyProcessor._keyLength} characters');
        }

        setState(() {
          _isProcessing = false;
        });
      } else {
        _showError('Please select exactly 2 share files');
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
                                    maxLines: 10,
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
                            _encryptionKey!,
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
  static const _keyLength = 12;
  static String generateKey() {
    final random = Random.secure();
    const chars =
        'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
    return List.generate(12, (index) => chars[random.nextInt(chars.length)])
        .join();
  }

  static List<ShareData> generateShares(File documentFile) {
    final Uint8List documentBytes = documentFile.readAsBytesSync();
    final String originalFileName = documentFile.path.split('/').last;
    final String key = generateKey();

    // Store key in first few bytes of share2
    final keyBytes = utf8.encode(key);
    final List<int> share1 = [];
    final List<int> share2 = [];

    // Add key verification bytes to share2
    share2.addAll(keyBytes);

    for (int i = 0; i < documentBytes.length; i++) {
      final int keyByte = keyBytes[i % keyBytes.length];
      final int randomByte = Random.secure().nextInt(256);
      share1.add(randomByte);
      share2.add(documentBytes[i] ^ keyByte ^ randomByte);
    }

    return [
      ShareData(Uint8List.fromList(share1), 'share1_$originalFileName.png'),
      ShareData(Uint8List.fromList(share2), 'share2_$originalFileName.png'),
    ];
  }

  static Uint8List combineShares(List<Uint8List> shares, String key) {
    if (shares.length != 2) throw Exception('Exactly 2 shares required');

    final keyBytes = utf8.encode(key);
    final share1Bytes = shares[0];
    final share2Bytes = shares[1];

    // Extract and verify key from share2
    final storedKeyBytes = share2Bytes.sublist(0, keyBytes.length);
    final storedKey = utf8.decode(storedKeyBytes);

    if (key != storedKey) {
      throw Exception('Invalid decryption key');
    }

    // Remove key bytes from share2
    final encryptedData = share2Bytes.sublist(keyBytes.length);

    if (share1Bytes.length != encryptedData.length) {
      throw Exception('Shares must be of equal length');
    }

    final List<int> combined = [];
    for (int i = 0; i < share1Bytes.length; i++) {
      combined.add(
          share1Bytes[i] ^ encryptedData[i] ^ keyBytes[i % keyBytes.length]);
    }

    return Uint8List.fromList(combined);
  }

  static combineSharesWithKey(List<ShareData> shares, Uint8List keyBytes) {}
}
