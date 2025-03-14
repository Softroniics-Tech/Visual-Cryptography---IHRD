import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypta_completed/constands/functions.dart';
import 'package:encrypta_completed/constands/history_page.dart';
import 'package:encrypta_completed/model/services/visual_cryptography_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/rendering.dart';

class ManagerScreen extends StatefulWidget {
  const ManagerScreen({super.key});

  @override
  State<ManagerScreen> createState() => _ManagerScreenState();
}

class _ManagerScreenState extends State<ManagerScreen> {
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
        _safeSetState(() {
          _document = File(result.files.single.path!);
          _shares = null;
          _combinedDocument = null;
          _isProcessing = true;
        });

        // Generate shares and get encryption key
        final shares = VisualCryptographyProcessor.generateShares(_document!);

        _safeSetState(() {
          _shares = shares;
          _isProcessing = false;
        });

        // Show encryption key dialog
        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('Document Encryption Key'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'This is your document encryption key. Please save it securely:',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    shares[2].key,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'You will need this key to decrypt the document later.',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: shares[2].key));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Key copied to clipboard')),
                    );
                  },
                  child: const Text('Copy Key'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Continue'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Error picking document: $e');
      }
    }
  }

  Future<void> _generateShares() async {
    if (_document == null) return;

    try {
      final shares = VisualCryptographyProcessor.generateShares(_document!);
      final keyBytes = shares[2].bytes;
      final hexKey =
          keyBytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

      _safeSetState(() {
        _shares = shares;
        _encryptionKey = hexKey;
      });
    } catch (e) {
      if (mounted) {
        _showError('Error generating shares: $e');
      }
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
      showError('Error saving file: $e', context);
    }
  }

  Future<void> _saveShare(ShareData share) async {
    if (!await Permission.manageExternalStorage.request().isGranted) {
      showError('Storage permission is required', context);
      openAppSettings();
      return;
    }
    await _saveAndShareFile(share.bytes, share.fileName);
  }

  void _shareDocument() {
    if (_document != null) {
      setState(() {
        _isProcessing = true;
      });

      // Generate shares and key
      _shares = VisualCryptographyProcessor.generateShares(_document!);
      _encryptionKey = VisualCryptographyProcessor.generateKey();

      setState(() {
        _isProcessing = false;
      });

      // Show share dialog
      _showShareDialog();
    }
  }

  // Future<void> _decryptShares() async {
  //   if (firstShare == null || secondShare == null) {
  //     _showError('Please select both share files');
  //     return;
  //   }

  //   try {
  //     setState(() => _isProcessing = true);

  //     final share1Bytes = await firstShare!.readAsBytes();
  //     final share2Bytes = await secondShare!.readAsBytes();

  //     // Get the current user
  //     final currentUser = FirebaseAuth.instance.currentUser;
  //     if (currentUser == null) {
  //       _showError('User not authenticated');
  //       return;
  //     }

  //     // Show key input dialog
  //     final key = await showDialog<String>(
  //       context: context,
  //       barrierDismissible: false,
  //       builder: (context) => AlertDialog(
  //         title: const Text('Enter Decryption Key'),
  //         content: TextField(
  //           controller: _keyController,
  //           decoration: const InputDecoration(
  //             hintText: 'Enter your 12-character key',
  //           ),
  //           maxLength: 12,
  //         ),
  //         actions: [
  //           TextButton(
  //             onPressed: () => Navigator.pop(context),
  //             child: const Text('Cancel'),
  //           ),
  //           TextButton(
  //             onPressed: () => Navigator.pop(context, _keyController.text),
  //             child: const Text('Decrypt'),
  //           ),
  //         ],
  //       ),
  //     );

  //     if (key != null) {
  //       // Verify the key from Firebase
  //       final keyQuery = await FirebaseFirestore.instance
  //           .collection('encryption_keys')
  //           .where('receiverId', isEqualTo: currentUser.uid)
  //           .where('key', isEqualTo: key)
  //           .get();

  //       if (keyQuery.docs.isEmpty) {
  //         _showError('Invalid decryption key');
  //         return;
  //       }

  //       final shares = [share1Bytes, share2Bytes];
  //       try {
  //         final combined =
  //             DocumentCryptographyProcessor.combineShares(shares, key);
  //         final tempDir = await getTemporaryDirectory();
  //         final tempFile = File('${tempDir.path}/temp_decrypted');
  //         await tempFile.writeAsBytes(combined);

  //         setState(() {
  //           _decryptedDocument = tempFile;
  //           _decryptedFileName =
  //               'decrypted_${DateTime.now().millisecondsSinceEpoch}.txt';
  //         });

  //         // Save to history and show success
  //         await _saveToHistory(
  //             await _decryptedDocument!.readAsBytes(), _decryptedFileName!);
  //         _showSuccess('Document decrypted successfully');
  //       } catch (e) {
  //         _showError('Invalid decryption key');
  //         return;
  //       }
  //     }
  //   } catch (e) {
  //     _showError('Error during decryption: $e');
  //   } finally {
  //     setState(() => _isProcessing = false);
  //   }
  // }

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

    int nonZeroCount = 0;
    for (int i = 0; i < min(bytes.length, 100); i++) {
      if (bytes[i] != 0) nonZeroCount++;
    }

    return nonZeroCount > 20; // At least 20% non-zero bytes in first 100 bytes
  }

  // Future<void> _saveDecryptedFile() async {
  //   if (_decryptedDocument == null) {
  //     _showError('No decrypted document available');
  //     return;
  //   }

  //   try {
  //     final directory = await getExternalStorageDirectory();
  //     final path = '${directory!.path}/DecryptedDocuments';
  //     await Directory(path).create(recursive: true);

  //     final timestamp = DateTime.now().millisecondsSinceEpoch;
  //     final filePath = '$path/$timestamp.txt';
  //     await _decryptedDocument!
  //         .writeAsBytes(await _decryptedDocument!.readAsBytes());
  //     await Share.shareXFiles([XFile(filePath)]);

  //     _showSuccess('File saved and ready to share');
  //   } catch (e) {
  //     _showError('Error saving file: $e');
  //   }
  // }

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

  void _showShareDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'worker')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final workers = snapshot.data!.docs;

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16.0),
                child: const Text(
                  'Select Worker to Share Document',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: workers.length,
                  itemBuilder: (context, index) {
                    final worker =
                        workers[index].data() as Map<String, dynamic>;
                    final workerId = workers[index].id;

                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.person),
                        backgroundColor: Colors.blue,
                      ),
                      title: Text(worker['username'] ?? 'Unknown Worker'),
                      subtitle: Text(worker['email'] ?? ''),
                      trailing: const Icon(Icons.send),
                      onTap: () {
                        _shareWithWorker(workerId, worker['username']);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _shareWithWorker(String workerId, String workerName) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null || _document == null) return;

      _safeSetState(() => _isProcessing = true);

      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final messageId = '${currentUser.uid}_${workerId}_$timestamp';
      final originalFileName = _document!.path.split('/').last;

      // Generate visual cryptography shares
      final shares = VisualCryptographyProcessor.generateShares(_document!);

      // Upload shares to Firebase Storage
      final share1Ref = FirebaseStorage.instance
          .ref()
          .child('shares/$messageId/share1_$originalFileName.png');
      final share2Ref = FirebaseStorage.instance
          .ref()
          .child('shares/$messageId/share2_$originalFileName.png');

      // Upload both shares as PNG images
      await share1Ref.putData(shares[0].bytes);
      await share2Ref.putData(shares[1].bytes);

      final share1Url = await share1Ref.getDownloadURL();
      final share2Url = await share2Ref.getDownloadURL();

      // Store the encryption key securely
      await FirebaseFirestore.instance.collection('encryption_keys').add({
        'senderId': currentUser.uid,
        'receiverId': workerId,
        'key': shares[2].key, // Store the encryption key
        'messageId': messageId,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Store message with share information
      await FirebaseFirestore.instance
          .collection('messages')
          .doc(messageId)
          .set({
        'type': 'encryptedDocument',
        'senderId': currentUser.uid,
        'receiverId': workerId,
        'timestamp': FieldValue.serverTimestamp(),
        'fileName': originalFileName,
        'share1': {
          'url': share1Url,
          'storagePath': 'shares/$messageId/share1_$originalFileName.png',
          'fileName': 'share1_$originalFileName.png'
        },
        'share2': {
          'url': share2Url,
          'storagePath': 'shares/$messageId/share2_$originalFileName.png',
          'fileName': 'share2_$originalFileName.png'
        },
        'status': 'sent',
        'isRead': false,
        'participants': [currentUser.uid, workerId],
      });

      // Show success message
      _safeSetState(() => _isProcessing = false);
      if (mounted) {
        _showSuccess('Document shared successfully with $workerName');
      }

      // Show the key in a dialog for copying
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Document Share Key'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Please copy and securely send this key to the recipient:',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                SelectableText(
                  shares[2].key,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'The recipient will need this key to decrypt the document.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: shares[2].key));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Key copied to clipboard')),
                  );
                },
                child: const Text('Copy Key'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _safeSetState(() => _isProcessing = false);
      if (mounted) {
        _showError('Error sharing document: $e');
      }
    }
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

  void _safeSetState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
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
                      _document?.path.split('/').last ?? "Select Document",
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _pickDocument,
                  child: CustomContainer(
                    width: 60,
                    height: 60,
                    child: const Center(child: Icon(Icons.file_copy)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Share Button
            if (_document != null)
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.6,
                height: 50,
                child: MaterialButton(
                  onPressed: () => _showShareDialog(),
                  color: Colors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    "Share Document",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

            if (_isProcessing)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
          ],
        ),
      ),
    );
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
