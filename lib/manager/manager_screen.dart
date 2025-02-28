import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
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
      if (result != null) {
        if (!mounted) return; // Check if still mounted
        setState(() {
          _document = File(result.files.single.path!);
          _isProcessing = true;
        });
        // Generate encrypted shares
        _shares = DocumentCryptographyProcessor.generateShares(_document!);
        _encryptionKey = DocumentCryptographyProcessor.generateKey();
        if (!mounted) return; // Check if still mounted
        setState(() {
          _isProcessing = false;
        });
        // Show encryption key dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Save This Encryption Key'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _encryptionKey!,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text('You will need this key to decrypt the document'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return; // Check if still mounted
      _showError('Error picking document: $e');
    }
  }

  void _shareDocument() {
    if (_document != null) {
      setState(() {
        _isProcessing = true;
      });

      // Generate shares and key
      _shares = DocumentCryptographyProcessor.generateShares(_document!);
      _encryptionKey = DocumentCryptographyProcessor.generateKey();

      setState(() {
        _isProcessing = false;
      });

      // Show share dialog
      _showShareDialog();
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
        // Verify the key from Firebase
        final keyQuery = await FirebaseFirestore.instance
            .collection('encryption_keys')
            .where('receiverId', isEqualTo: currentUser.uid)
            .where('key', isEqualTo: key)
            .get();

        if (keyQuery.docs.isEmpty) {
          _showError('Invalid decryption key');
          return;
        }

        final shares = [share1Bytes, share2Bytes];
        try {
          final combined =
              DocumentCryptographyProcessor.combineShares(shares, key);
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/temp_decrypted');
          await tempFile.writeAsBytes(combined);

          setState(() {
            _decryptedDocument = tempFile;
            _decryptedFileName =
                'decrypted_${DateTime.now().millisecondsSinceEpoch}.txt';
          });

          // Save to history and show success
          await _saveToHistory(
              await _decryptedDocument!.readAsBytes(), _decryptedFileName!);
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

  Future<void> _shareWithWorker(String workerId, String workerName) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null || _shares == null) return;

      setState(() => _isProcessing = true);

      // Create chat room ID
      final chatRoomId =
          'chat_${currentUser.uid}_$workerId'.replaceAll(' ', '_');
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();

      // Upload original encrypted document
      final originalDocRef = await FirebaseStorage.instance
          .ref('documents/${chatRoomId}_${timestamp}_original')
          .putFile(_document!);
      final originalDocUrl = await originalDocRef.ref.getDownloadURL();

      // Upload encrypted shares
      final share1Ref = await FirebaseStorage.instance
          .ref('shares/${chatRoomId}_${timestamp}_share1')
          .putData(_shares![0].bytes);
      final share2Ref = await FirebaseStorage.instance
          .ref('shares/${chatRoomId}_${timestamp}_share2')
          .putData(_shares![1].bytes);
      final share1Url = await share1Ref.ref.getDownloadURL();
      final share2Url = await share2Ref.ref.getDownloadURL();

      // Store encryption key and document metadata in Firestore
      final docRef =
          await FirebaseFirestore.instance.collection('encryption_keys').add({
        'senderId': currentUser.uid,
        'receiverId': workerId,
        'key': _encryptionKey,
        'timestamp': FieldValue.serverTimestamp(),
        'fileName': _document!.path.split('/').last,
        'originalDocUrl': originalDocUrl,
        'share1Url': share1Url,
        'share2Url': share2Url,
        'chatRoomId': chatRoomId,
      });

      // Send message with document and shares information
      await FirebaseFirestore.instance
          .collection('chatRooms')
          .doc(chatRoomId)
          .collection('messages')
          .add({
        'text': 'Encrypted Document Shares',
        'senderId': currentUser.uid,
        'timestamp': FieldValue.serverTimestamp(),
        'isEncryptedShare': true,
        'originalDocUrl': originalDocUrl,
        'share1Url': share1Url,
        'share2Url': share2Url,
        'originalFileName': _document!.path.split('/').last,
        'encryptionKey': _encryptionKey,
        'encryptionKeyId':
            docRef.id, // Reference to the encryption key document
      });

      // Update chat room
      await FirebaseFirestore.instance
          .collection('chatRooms')
          .doc(chatRoomId)
          .set({
        'participants': [currentUser.uid, workerId],
        'lastMessage': 'Encrypted Document Shared',
        'lastMessageTime': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      setState(() => _isProcessing = false);
      Navigator.pop(context);
      _showSuccess('Document shared successfully');
    } catch (e) {
      setState(() => _isProcessing = false);
      _showError('Error sharing document: $e');
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
