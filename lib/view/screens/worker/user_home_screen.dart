import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:async';
import 'package:encrypta/constands/history_page.dart';
import 'package:encrypta/model/services/visual_cryptography_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:ui' as ui;

class UserPage extends StatefulWidget {
  const UserPage({super.key});

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  File? firstShare;
  File? secondShare;
  String? firstFileName;
  String? secondFileName;
  Uint8List? _combinedDocument;
  bool _isProcessing = false;
  final TextEditingController _keyController = TextEditingController();

  Future<void> _pickShare(bool isFirstShare) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);

        // Verify it's an image file
        try {
          final bytes = await file.readAsBytes();
          await decodeImageFromList(bytes);

          setState(() {
            if (isFirstShare) {
              firstShare = file;
              firstFileName = result.files.single.name;
            } else {
              secondShare = file;
              secondFileName = result.files.single.name;
            }
          });
        } catch (e) {
          _showError('Selected file is not a valid image');
        }
      }
    } catch (e) {
      _showError('Error picking file: $e');
    }
  }

  Future<void> _decryptShares() async {
    if (firstShare == null || secondShare == null) {
      _showError('Please select both share files');
      return;
    }

    try {
      setState(() => _isProcessing = true);

      // Show key input dialog
      final key = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Enter Decryption Key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter the decryption key provided by the sender:',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _keyController,
                decoration: const InputDecoration(
                  hintText: 'Paste decryption key here',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, _keyController.text),
              child: const Text('Decrypt'),
            ),
          ],
        ),
      );

      if (key == null || key.isEmpty) {
        setState(() => _isProcessing = false);
        return;
      }

      final share1Bytes = await firstShare!.readAsBytes();
      final share2Bytes = await secondShare!.readAsBytes();

      try {
        // Decrypt the shares
        final combined = await compute(
          (args) => VisualCryptographyProcessor.combineShares(
            [args[0] as Uint8List, args[1] as Uint8List],
            args[2] as String,
          ),
          [share1Bytes, share2Bytes, key],
        );

        setState(() {
          _combinedDocument = combined;
        });

        // Extract original file info for history
        final originalNameWithExt = firstFileName!.split('_')[1];
        final parts = originalNameWithExt.split('.');
        final originalName = parts[0];
        final originalExtension = parts.length > 2 ? parts[1] : 'pdf';

        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName =
            'decrypted_${originalName}_$timestamp.$originalExtension';

        // Save to history
        await _saveToHistory(_combinedDocument!, fileName);
        _showSuccess('Document decrypted successfully');
      } catch (e) {
        _showError('Invalid decryption key or corrupted shares');
        return;
      }
    } catch (e) {
      _showError('Error during decryption: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _saveDecryptedFile() async {
    if (_combinedDocument == null) {
      _showError('No decrypted document available');
      return;
    }

    try {
      // Get the application documents directory for better compatibility
      final directory = await getApplicationDocumentsDirectory();
      final path = '${directory.path}/DecryptedDocuments';
      await Directory(path).create(recursive: true);

      // Always use PDF extension for now to ensure compatibility
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'decrypted_$timestamp.pdf';
      final filePath = '$path/$fileName';

      // Write the decrypted bytes directly to file
      final file = File(filePath);
      await file.writeAsBytes(_combinedDocument!);

      // Log file size for debugging
      print('Saved file size: ${await file.length()} bytes');

      // Create intent to view the PDF
      try {
        // Use a more reliable method to open the PDF
        final result = await Share.shareXFiles(
          [XFile(filePath, mimeType: 'application/pdf')],
          subject: 'Decrypted Document',
          text: 'Here is your decrypted document',
        );

        print('Share result: $result');
        _showSuccess('PDF document saved successfully');
      } catch (e) {
        _showError('Error opening PDF: $e');
        print('Error opening PDF: $e');
      }
    } catch (e) {
      _showError('Error saving file: $e');
      print('Error saving file: $e');
    }
  }

  String _getMimeType(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
      case 'docx':
        return 'application/msword';
      case 'xls':
      case 'xlsx':
        return 'application/vnd.ms-excel';
      case 'ppt':
      case 'pptx':
        return 'application/vnd.ms-powerpoint';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
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
                  // First Share Selection
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CustomContainer(
                        width: MediaQuery.of(context).size.width * 0.6,
                        height: 60,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              firstShare != null
                                  ? Icons.check_circle
                                  : Icons.image,
                              color: firstShare != null
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                firstFileName ?? "Select First Share Image",
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: firstShare != null
                                      ? Colors.black
                                      : Colors.grey[600],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => _pickShare(true),
                        child: CustomContainer(
                          width: 60,
                          height: 60,
                          child: const Center(
                              child: Icon(Icons.add_photo_alternate)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Second Share Selection
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CustomContainer(
                        width: MediaQuery.of(context).size.width * 0.6,
                        height: 60,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              secondShare != null
                                  ? Icons.check_circle
                                  : Icons.image,
                              color: secondShare != null
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                secondFileName ?? "Select Second Share Image",
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: secondShare != null
                                      ? Colors.black
                                      : Colors.grey[600],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => _pickShare(false),
                        child: CustomContainer(
                          width: 60,
                          height: 60,
                          child: const Center(
                              child: Icon(Icons.add_photo_alternate)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: MediaQuery.of(context).size.width * 0.6,
                        height: 50,
                        child: MaterialButton(
                          onPressed: firstShare != null && secondShare != null
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
                              color: Colors.white,
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

  Future<ui.Image> decodeImageFromList(Uint8List list) {
    return Future.microtask(() {
      final Completer<ui.Image> completer = Completer<ui.Image>();
      ui.decodeImageFromList(list, (ui.Image img) {
        completer.complete(img);
      });
      return completer.future;
    });
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
