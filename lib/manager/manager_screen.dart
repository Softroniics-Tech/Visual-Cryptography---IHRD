import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypta/services/chat_service.dart';
import 'package:encrypta/services/document_cryptography_processor.dart'
    as crypto;
import 'package:encrypta/worker/screens/app_home_screen.dart';
import 'package:encrypta/worker/screens/history.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ManagerScreen extends StatefulWidget {
  const ManagerScreen({super.key});

  @override
  State<ManagerScreen> createState() => _ManagerScreenState();
}

class _ManagerScreenState extends State<ManagerScreen> {
  File? _document;
  File? firstShare;
  File? secondShare;
  List<ShareData>? _shares;
  String? _encryptionKey;
  bool _isProcessing = false;
  final TextEditingController _keyController = TextEditingController();
  File? _decryptedDocument;
  String? _decryptedFileName;
  List<ShareData>? _decryptedShares;
  Timer? _timer;
  final _encryptionKeysCollection =
      FirebaseFirestore.instance.collection('encryption_keys');

  @override
  void dispose() {
    _timer?.cancel();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _pickDocument() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'png', 'jpg', 'jpeg'],
      );

      if (result == null ||
          result.files.isEmpty ||
          result.files.first.path == null) {
        return;
      }

      if (!mounted) return;
      setState(() {
        _document = File(result.files.first.path!);
        _isProcessing = true;
      });

      try {
        // Generate shares using the chat service for consistency
        final chatService = ChatService();

        // Create encrypted document
        final file = PlatformFile(
          name: _document!.path.split('/').last,
          size: await _document!.length(),
          path: _document!.path,
        );

        // Use a temporary chat room ID for share generation
        final tempChatRoomId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
        final encryptedDoc = await chatService.uploadEncryptedDocument(
          file,
          tempChatRoomId,
        );

        _encryptionKey = encryptedDoc['encryptionKey'];

        if (!mounted) return;
        setState(() => _isProcessing = false);

        // Show encryption key dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Save This Encryption Key'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(
                  _encryptionKey!,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 10),
                const Text('You will need this key to decrypt the document'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  // Clean up on cancel
                  _cleanupTemporaryShares(encryptedDoc);
                },
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _encryptionKey!));
                  _showSuccess('Key copied to clipboard');
                  Navigator.pop(context);
                  // Show share dialog after copying key
                  _showShareDialog();
                },
                child: const Text('Copy & Share'),
              ),
            ],
          ),
        );

        // Clean up temporary shares if dialog is dismissed
        if (!mounted) {
          _cleanupTemporaryShares(encryptedDoc);
        }
      } catch (e) {
        if (!mounted) return;
        setState(() => _isProcessing = false);

        if (e.toString().contains('Error uploading')) {
          _showError('Failed to process document. Please try again');
        } else {
          _showError('Error processing document: $e');
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showError('Error picking document: $e');
    }
  }

  Future<void> _cleanupTemporaryShares(
      Map<String, dynamic> encryptedDoc) async {
    try {
      if (encryptedDoc['share1Url'] != null) {
        await FirebaseStorage.instance
            .refFromURL(encryptedDoc['share1Url'])
            .delete();
      }
      if (encryptedDoc['share2Url'] != null) {
        await FirebaseStorage.instance
            .refFromURL(encryptedDoc['share2Url'])
            .delete();
      }
    } catch (_) {
      // Ignore cleanup errors
    }
  }

  void _shareDocument() async {
    if (_document != null) {
      setState(() {
        _isProcessing = true;
      });

      // Generate shares and key
      final chatService = ChatService();

      // Create encrypted document
      final file = PlatformFile(
        name: _document!.path.split('/').last,
        size: await _document!.length(),
        path: _document!.path,
      );

      // Use a temporary chat room ID for share generation
      final tempChatRoomId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
      chatService
          .uploadEncryptedDocument(
        file,
        tempChatRoomId,
      )
          .then((encryptedDoc) {
        _encryptionKey = encryptedDoc['encryptionKey'];

        setState(() {
          _isProcessing = false;
        });

        // Show share dialog
        _showShareDialog();
      }).catchError((e) {
        setState(() => _isProcessing = false);
        _showError('Error sharing document: $e');
      });
    }
  }

  Future<void> _shareWithWorker(String workerId, String workerName) async {
    if (_document == null) {
      _showError('No document selected');
      return;
    }

    setState(() => _isProcessing = true);
    Map<String, dynamic>?
        encryptedDoc; // Declare at the top for error handling scope

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw 'Not authenticated';

      // Get chat room ID - sort IDs for consistency
      final participantIds = [currentUser.uid, workerId];
      participantIds.sort();
      final chatRoomId = participantIds.join('_');
      final chatService = ChatService();

      // Create or update chat room

      // Create encrypted document
      final file = PlatformFile(
        name: _document!.path.split('/').last,
        size: await _document!.length(),
        path: _document!.path,
      );

      // Upload and encrypt the document
      encryptedDoc = await chatService.uploadEncryptedDocument(
        file,
        chatRoomId,
      );
      // Send message with encrypted document
      await chatService.sendMessage(
        chatRoomId: chatRoomId,
        senderId: currentUser.uid,
        encryptedDocument: encryptedDoc,
      );

      // Store encryption key in Firestore with proper timestamp
      final now = DateTime.now().millisecondsSinceEpoch;
      await _encryptionKeysCollection.add({
        'senderId': currentUser.uid,
        'receiverId': workerId,
        'key': encryptedDoc['encryptionKey'],
        'createdAt': now,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showSuccess('Document shared with $workerName');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);

      // Show error with specific message
      if (e.toString().contains('Not authenticated')) {
        _showError('Please sign in to share documents');
      } else if (e.toString().contains('Error uploading')) {
        _showError('Failed to upload document. Please try again');
      } else if (e.toString().contains('Error sending message')) {
        _showError('Failed to send document. Please try again');
      } else {
        _showError('Error sharing document: $e');
      }

      // Clean up any uploaded resources on failure
      try {
        if (encryptedDoc != null) {
          // Delete uploaded shares if they exist
          if (encryptedDoc['share1Url'] != null) {
            await FirebaseStorage.instance
                .refFromURL(encryptedDoc['share1Url'])
                .delete();
          }
          if (encryptedDoc['share2Url'] != null) {
            await FirebaseStorage.instance
                .refFromURL(encryptedDoc['share2Url'])
                .delete();
          }
        }
      } catch (_) {
        // Ignore cleanup errors
      }
    }
  }

  Future<void> _decryptShares() async {
    if (firstShare == null || secondShare == null) {
      _showError('Please select both share files');
      return;
    }

    try {
      setState(() => _isProcessing = true);

      final share1Bytes = await firstShare!.readAsBytes();
      final share2Bytes = await secondShare!.readAsBytes();

      // Get the current user
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        _showError('User not authenticated');
        return;
      }

      // Show key input dialog
      final key = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Enter Decryption Key'),
          content: TextField(
            controller: _keyController,
            decoration: const InputDecoration(
              hintText: 'Enter the decryption key',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _keyController.clear();
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final key = _keyController.text.trim();
                _keyController.clear();
                Navigator.pop(context, key);
              },
              child: const Text('Decrypt'),
            ),
          ],
        ),
      );

      if (key == null || key.isEmpty) {
        setState(() => _isProcessing = false);
        return;
      }

      // Verify the key from Firebase
      final keyQuery = await _encryptionKeysCollection
          .where('receiverId', isEqualTo: currentUser.uid)
          .where('key', isEqualTo: key)
          .get();

      if (keyQuery.docs.isEmpty) {
        _showError('Invalid decryption key');
        setState(() => _isProcessing = false);
        return;
      }

      try {
        // Combine shares and decrypt
        final combinedBytes =
            await crypto.DocumentCryptographyProcessor.combineShares(
          [share1Bytes, share2Bytes],
          key,
        );

        // Validate decrypted content
        if (!_isValidDecryption(combinedBytes)) {
          throw 'Invalid decryption result';
        }

        // Save decrypted file
        final directory = await getApplicationDocumentsDirectory();
        final downloadPath = '${directory.path}/Downloads';
        await Directory(downloadPath).create(recursive: true);

        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName =
            'decrypted_$timestamp${_getFileExtension(combinedBytes)}';
        final filePath = '$downloadPath/$fileName';

        final decryptedFile = File(filePath);
        await decryptedFile.writeAsBytes(combinedBytes);

        // Save to history
        await _saveToHistory(combinedBytes, fileName);

        setState(() {
          _decryptedDocument = decryptedFile;
          _decryptedFileName = fileName;
        });

        // Show success and share
        _showSuccess('Document decrypted successfully');
        await Share.shareXFiles([XFile(filePath)]);

        // Clean up
        await decryptedFile.delete();
      } catch (e) {
        _showError('Error decrypting document: $e');
      }
    } catch (e) {
      _showError('Error during decryption: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  String _getFileExtension(Uint8List bytes) {
    if (bytes.length < 4) return '.bin';

    final signature = bytes.sublist(0, 4);

    // Check file signatures
    if (bytes.length >= 4 &&
        signature[0] == 0x25 && // %
        signature[1] == 0x50 && // P
        signature[2] == 0x44 && // D
        signature[3] == 0x46) {
      // F
      return '.pdf';
    }

    if (bytes.length >= 8 &&
        signature[0] == 0x89 &&
        signature[1] == 0x50 && // P
        signature[2] == 0x4E && // N
        signature[3] == 0x47) {
      // G
      return '.png';
    }

    if (bytes.length >= 2 && signature[0] == 0xFF && signature[1] == 0xD8) {
      return '.jpg';
    }

    if (bytes.length >= 4 &&
        signature[0] == 0x50 && // P
        signature[1] == 0x4B && // K
        signature[2] == 0x03 &&
        signature[3] == 0x04) {
      return '.zip';
    }

    return '.bin';
  }

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

  Future<void> _saveDecryptedFile() async {
    if (_decryptedDocument == null) {
      _showError('No decrypted document available');
      return;
    }

    try {
      final directory = await getExternalStorageDirectory();
      final path = '${directory!.path}/DecryptedDocuments';
      await Directory(path).create(recursive: true);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '$path/$timestamp.txt';
      await _decryptedDocument!
          .writeAsBytes(await _decryptedDocument!.readAsBytes());
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
                child: Column(
                  children: [
                    const Text(
                      'Encryption Key',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _encryptionKey!,
                          style: const TextStyle(
                            fontSize: 16,
                            fontFamily: 'monospace',
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: _encryptionKey!));
                            _showSuccess('Key copied to clipboard');
                          },
                        ),
                      ],
                    ),
                  ],
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
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(worker['username'] ?? 'Unknown Worker'),
                      subtitle: Text(worker['email'] ?? ''),
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

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Document Picker
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
