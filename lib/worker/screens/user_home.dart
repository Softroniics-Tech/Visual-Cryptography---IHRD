import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypta/worker/screens/app_home_screen.dart';
import 'package:encrypta/worker/screens/history.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserPage extends StatefulWidget {
  const UserPage({super.key});

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  String? firstFileName;
  String? secondFileName;
  File? firstFile;
  File? secondFile;
  Uint8List? _combinedDocument;
  bool _isProcessing = false;
  final TextEditingController _keyController = TextEditingController();

  Future<void> _pickFile(bool isFirstFile) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final bytes = await file.readAsBytes();

        setState(() {
          if (isFirstFile) {
            firstFileName = result.files.single.name;
            firstFile = file;
          } else {
            secondFileName = result.files.single.name;
            secondFile = file;
          }
        });
      }
    } catch (e) {
      _showError('Error picking file: $e');
    }
  }

  Future<void> _decryptShares() async {
    if (firstFile == null || secondFile == null) {
      _showError('Please select both share files');
      return;
    }

    try {
      setState(() => _isProcessing = true);

      final share1Bytes = await firstFile!.readAsBytes();
      final share2Bytes = await secondFile!.readAsBytes();

      // Show key input dialog
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
            maxLength: 12,
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

      if (key != null) {
        final shares = [share1Bytes, share2Bytes];
        try {
          final combined =
              DocumentCryptographyProcessor.combineShares(shares, key);
          setState(() {
            _combinedDocument = combined;
          });

          // Save to history and show success
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final originalName = firstFileName!.split('_').last.split('.');
          final extension = originalName.length > 2
              ? originalName[originalName.length - 2]
              : 'txt';
          final fileName = 'decrypted_$timestamp.$extension';

          await _saveToHistory(_combinedDocument!, fileName);
          _showSuccess('Document decrypted successfully');
        } catch (e) {
          _showError('Invalid decryption key');
          return;
        }
      }
    } catch (e) {
      _showError('Error during decryption: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  // Add this method to check if decryption was successful
  bool _isValidDecryption(Uint8List bytes) {
    if (bytes.length < 4) return false;

    // Check common file signatures
    final signature = bytes.sublist(0, 4);

    // PDF signature
    if (bytes.length >= 4 &&
        signature[0] == 0x25 && // %
        signature[1] == 0x50 && // P
        signature[2] == 0x44 && // D
        signature[3] == 0x46) {
      // F
      return true;
    }

    // PNG signature
    if (bytes.length >= 8 &&
        signature[0] == 0x89 &&
        signature[1] == 0x50 && // P
        signature[2] == 0x4E && // N
        signature[3] == 0x47) {
      // G
      return true;
    }

    // JPEG signature
    if (bytes.length >= 2 && signature[0] == 0xFF && signature[1] == 0xD8) {
      return true;
    }

    // ZIP signature
    if (bytes.length >= 4 &&
        signature[0] == 0x50 && // P
        signature[1] == 0x4B && // K
        signature[2] == 0x03 &&
        signature[3] == 0x04) {
      return true;
    }

    // For other file types, check if content seems valid
    // (not all zeros or random bytes)
    int nonZeroCount = 0;
    for (int i = 0; i < min(bytes.length, 100); i++) {
      if (bytes[i] != 0) nonZeroCount++;
    }

    return nonZeroCount > 20; // At least 20% non-zero bytes in first 100 bytes
  }

  Future<void> _saveDecryptedFile() async {
    if (_combinedDocument == null) {
      _showError('No decrypted document available');
      return;
    }

    try {
      final directory = await getExternalStorageDirectory();
      final path = '${directory!.path}/DecryptedDocuments';
      await Directory(path).create(recursive: true);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      // Get extension from first share file name (assuming format: share1_originalname.ext.png)
      final originalName =
          firstFileName!.split('_').last.split('.'); // split by dots
      final extension = originalName.length > 2
          ? originalName[originalName.length - 2]
          : 'txt';

      final filePath = '$path/decrypted_$timestamp.$extension';
      await File(filePath).writeAsBytes(_combinedDocument!);
      await Share.shareXFiles([XFile(filePath)]);

      _showSuccess('File saved and ready to share');
    } catch (e) {
      _showError('Error saving file: $e');
    }
  }

  Future<void> _saveToHistory(Uint8List fileBytes, String fileName) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('decryption_history') ?? [];

    final decryptedFile = DecryptedFile(
      fileName: fileName,
      fileData: base64Encode(fileBytes),
      timestamp: DateTime.now().toString(),
    );

    history.add(json.encode(decryptedFile.toJson()));
    await prefs.setStringList('decryption_history', history);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CustomContainer(
                        width: MediaQuery.of(context).size.width * 0.6,
                        height: 60,
                        child: Center(
                          child: Text(
                            firstFileName ?? "add first share",
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => _pickFile(true),
                        child: CustomContainer(
                          width: 60,
                          height: 60,
                          child: const Center(child: Icon(Icons.file_copy)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CustomContainer(
                        width: MediaQuery.of(context).size.width * 0.6,
                        height: 60,
                        child: Center(
                          child: Text(
                            secondFileName ?? "add second share",
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => _pickFile(false),
                        child: CustomContainer(
                          width: 60,
                          height: 60,
                          child: const Center(child: Icon(Icons.file_copy)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Select two share files and click Decrypt\nYou will be prompted for the key',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: MediaQuery.of(context).size.width * 0.6,
                        height: 50,
                        child: MaterialButton(
                          onPressed: firstFile != null && secondFile != null
                              ? _decryptShares
                              : null,
                          color: Colors.green,
                          disabledColor: Colors.grey,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            "Decrypt",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: _combinedDocument != null
                            ? _saveDecryptedFile
                            : null,
                        child: CustomContainer(
                          width: 50,
                          height: 50,
                          child: Center(
                            child: Icon(
                              Icons.download,
                              color: _combinedDocument != null
                                  ? Colors.black
                                  : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }
}

class CustomContainer extends StatelessWidget {
  final double width;
  final double height;
  final Widget child;

  const CustomContainer({
    super.key,
    required this.width,
    required this.height,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.black,
        ),
      ),
      child: child,
    );
  }
}
