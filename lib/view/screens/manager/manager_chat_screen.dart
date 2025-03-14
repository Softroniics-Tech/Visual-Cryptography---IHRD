import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypta_completed/constands/colors.dart';
import 'package:encrypta_completed/model/services/visual_cryptography_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ManagerChatScreen extends StatefulWidget {
  final String currentUserId;
  final String otherUserId;
  final String otherUserName;
  final Map<String, dynamic>? initialMessage;

  const ManagerChatScreen({
    super.key,
    required this.currentUserId,
    required this.otherUserId,
    required this.otherUserName,
    this.initialMessage,
  });

  @override
  State<ManagerChatScreen> createState() => _ManagerChatScreenState();
}

class _ManagerChatScreenState extends State<ManagerChatScreen> {
  final _messageController = TextEditingController();
  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    _messageController.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!_isDisposed && mounted) {
      setState(fn);
    }
  }

  Future<void> _sendMessage({String? text, List<String>? fileUrls}) async {
    if ((text?.isEmpty ?? true) && (fileUrls?.isEmpty ?? true)) return;

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final messageId =
          '${widget.currentUserId}_${widget.otherUserId}_$timestamp';

      await FirebaseFirestore.instance
          .collection("messages")
          .doc(messageId)
          .set({
        "senderId": widget.currentUserId,
        "receiverId": widget.otherUserId,
        "text": text,
        "type": fileUrls != null ? 'file' : 'text',
        "timestamp": FieldValue.serverTimestamp(),
        "isRead": false,
        "participants": [widget.currentUserId, widget.otherUserId],
      });

      if (!mounted) return;
      _messageController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending message: $e')),
      );
    }
  }

  Future<List<String>> uploadFiles(List<PlatformFile> files) async {
    try {
      final List<String> fileUrls = [];
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final messageId =
          '${widget.currentUserId}_${widget.otherUserId}_$timestamp';

      for (final file in files) {
        if (file.path == null) continue;

        final fileName =
            '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('messages')
            .child(messageId)
            .child('files')
            .child(fileName);

        final uploadTask = await storageRef.putFile(File(file.path!));
        final downloadUrl = await uploadTask.ref.getDownloadURL();
        fileUrls.add(downloadUrl);
      }

      return fileUrls;
    } catch (e) {
      throw 'Error uploading files: $e';
    }
  }

  Future<void> _pickAndSendFiles() async {
    if (!mounted) return;

    try {
      // First document selection
      FilePickerResult? result1 = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result1 == null || !mounted) return;

      // Second document selection
      FilePickerResult? result2 = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result2 == null || !mounted) return;

      if (!mounted) return;

      BuildContext dialogContext;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          dialogContext = context;
          return const Center(child: CircularProgressIndicator());
        },
      );

      // Upload both files together
      final fileUrls = await uploadFiles(
        [...result1.files, ...result2.files],
      );

      if (!mounted) return;

      // Safely pop the dialog
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (fileUrls.isNotEmpty && mounted) {
        await _sendMessage(fileUrls: fileUrls);
      }
    } catch (e) {
      if (!mounted) return;

      // Make sure to dismiss the loading dialog if it's showing
      Navigator.of(context, rootNavigator: true).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error uploading files: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (mounted) {
          _messageController.clear();
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          foregroundColor: Colors.white,
          title: Text(
            widget.otherUserName,
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: primaryColor,
        ),
        body: Column(
          children: [
            Expanded(
              child: StreamBuilder(
                stream: FirebaseFirestore.instance
                    .collection("messages")
                    .where('participants', arrayContains: widget.currentUserId)
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: CircularProgressIndicator(color: primaryColor),
                    );
                  }

                  final messages = snapshot.data?.docs.where((doc) {
                        final data = doc.data();
                        return data['senderId'] == widget.otherUserId ||
                            data['receiverId'] == widget.otherUserId;
                      }).toList() ??
                      [];

                  return ListView.builder(
                    reverse: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isMe = message['senderId'] == widget.currentUserId;

                      if (message['type'] == 'encryptedDocument') {
                        return _buildDocumentMessage(message.data(), isMe);
                      }

                      // Mark message as read if received
                      if (!isMe && !(message['isRead'] ?? false)) {
                        FirebaseFirestore.instance
                            .collection('messages')
                            .doc(message.id)
                            .update({'isRead': true});
                      }

                      return GestureDetector(
                        onLongPress: () =>
                            _showMessageOptions(context, message.data()),
                        child: Align(
                          alignment: isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isMe ? primaryColor : Colors.grey[300],
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Text(
                              message['text'] ?? '',
                              style: TextStyle(
                                color: isMe ? Colors.white : Colors.black,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            ChatInput(
              controller: _messageController,
              onSendMessage: () {
                if (mounted) {
                  _sendMessage(text: _messageController.text);
                }
              },
              onAttachFile: _pickAndSendFiles,
            ),
          ],
        ),
      ),
    );
  }

  Future<Uint8List?> _loadSharePreview(String? path) async {
    if (path == null) return null;
    try {
      // Get the download URL first
      final ref = FirebaseStorage.instance.ref(path);
      final url = await ref.getDownloadURL();

      print('Download URL: $url');

      // Download the image data
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e) {
      print('Error loading share preview: $e');
      return null;
    }
  }

  Widget _buildDocumentMessage(Map<String, dynamic> message, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.all(12),
        width: 280,
        decoration: BoxDecoration(
          color: isMe ? primaryColor : Colors.grey[300],
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.file_present, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message['fileName'] ?? 'Document',
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!isMe && message['type'] == 'encryptedDocument') ...[
              Row(
                children: [
                  // Share 1 preview
                  Expanded(
                    child: FutureBuilder<Uint8List?>(
                      future: _loadSharePreview(message['share1']?['path']),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Container(
                            height: 100,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.blue),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                                child: CircularProgressIndicator()),
                          );
                        }
                        if (snapshot.hasData) {
                          return Container(
                            height: 100,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.blue),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                snapshot.data!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Center(
                                    child: Icon(Icons.error_outline),
                                  );
                                },
                              ),
                            ),
                          );
                        }
                        return Container(
                          height: 100,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.blue),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                              child: Icon(Icons.image_not_supported)),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Share 2 preview
                  Expanded(
                    child: FutureBuilder<Uint8List?>(
                      future: _loadSharePreview(message['share2']?['path']),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Container(
                            height: 100,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.green),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                                child: CircularProgressIndicator(
                              backgroundColor: primaryColor,
                            )),
                          );
                        }
                        if (snapshot.hasData) {
                          return Container(
                            height: 100,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.green),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                snapshot.data!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Center(
                                    child: Icon(Icons.error_outline),
                                  );
                                },
                              ),
                            ),
                          );
                        }
                        return Container(
                          height: 100,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.green),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                              child: Icon(Icons.image_not_supported)),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Download buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _downloadShare(message, 1),
                      icon: const Icon(Icons.file_download, size: 18),
                      label: const Text('Share 1'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _downloadShare(message, 2),
                      icon: const Icon(Icons.file_download, size: 18),
                      label: const Text('Share 2'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (isMe) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 8),
                  _buildMessageStatus(message['status'] ?? ''),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _downloadDocument(Map<String, dynamic> messageData) async {
    try {
      _showLoading();

      // Debug message data
      print('Message Data: $messageData'); // Add this for debugging

      // Get current user token
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw 'User not authenticated';
      }

      // Get encryption key from encryption_keys collection
      final keyId = messageData['keyId'];
      if (keyId == null) {
        throw 'Key ID not found in message data';
      }

      print('Fetching key document: $keyId'); // Debug log

      final keyDoc = await FirebaseFirestore.instance
          .collection('encryption_keys')
          .doc(keyId)
          .get();

      if (!keyDoc.exists) {
        throw 'Encryption key document not found';
      }

      final keyData = keyDoc.data() as Map<String, dynamic>;
      final encryptionKey = keyData['key'];
      if (encryptionKey == null) {
        throw 'Encryption key is null in key document';
      }

      // Get share paths from message data
      final share1Data = messageData['share1'] as Map<String, dynamic>?;
      final share2Data = messageData['share2'] as Map<String, dynamic>?;

      if (share1Data == null || share2Data == null) {
        throw 'Share data is missing in message';
      }

      final share1Path = share1Data['storagePath'] as String?;
      final share2Path = share2Data['storagePath'] as String?;

      if (share1Path == null || share2Path == null) {
        throw 'Storage paths not found in share data';
      }

      print('Share1 Path: $share1Path'); // Debug log
      print('Share2 Path: $share2Path'); // Debug log

      // Download shares from Firebase Storage
      try {
        final storage = FirebaseStorage.instance;

        print('Downloading share 1...'); // Debug log
        final share1Bytes = await storage.ref(share1Path).getData();
        if (share1Bytes == null) throw 'Share 1 download failed';

        print('Downloading share 2...'); // Debug log
        final share2Bytes = await storage.ref(share2Path).getData();
        if (share2Bytes == null) throw 'Share 2 download failed';

        print('Both shares downloaded successfully'); // Debug log

        // Combine shares using visual cryptography
        final combinedBytes = await compute(
          (data) {
            final shares = data['shares'] as List<Uint8List>;
            final key = data['key'] as String;
            return VisualCryptographyProcessor.combineShares(shares, key);
          },
          {
            'shares': [share1Bytes, share2Bytes],
            'key': utf8.decode(encryptionKey),
          },
        );

        // Save and share file
        final directory = await getApplicationDocumentsDirectory();
        final downloadPath = '${directory.path}/Downloads';
        await Directory(downloadPath).create(recursive: true);

        final originalFileName =
            messageData['fileName'] as String? ?? 'document.txt';
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final filePath = '$downloadPath/${timestamp}_$originalFileName';

        final file = File(filePath);
        await file.writeAsBytes(combinedBytes);

        if (!mounted) return;
        Navigator.pop(context); // Hide loading
        _showSuccess('Document downloaded successfully');

        await Share.shareXFiles([XFile(filePath)]);
        await file.delete(); // Clean up
      } catch (e) {
        print('Storage Error: $e'); // Debug log
        throw 'Error accessing Firebase Storage: $e';
      }
    } catch (e) {
      print('Download Error: $e'); // Debug log
      if (!mounted) return;
      Navigator.pop(context);
      _showError('Error downloading document: $e');
    }
  }

  // Widget _buildDocumentMessage(Map<String, dynamic> message, bool isMe) {
  //   return Align(
  //     alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
  //     child: Container(
  //       margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  //       padding: const EdgeInsets.all(12),
  //       decoration: BoxDecoration(
  //         color: isMe ? primaryColor : Colors.grey[300],
  //         borderRadius: BorderRadius.circular(15),
  //       ),
  //       child: Column(
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: [
  //           Row(
  //             mainAxisSize: MainAxisSize.min,
  //             children: [
  //               const Icon(Icons.file_present, size: 20),
  //               const SizedBox(width: 8),
  //               Flexible(
  //                 child: Text(
  //                   message['fileName'] ?? 'Document',
  //                   style: TextStyle(
  //                     color: isMe ? Colors.white : Colors.black,
  //                     fontWeight: FontWeight.bold,
  //                   ),
  //                 ),
  //               ),
  //             ],
  //           ),
  //           const SizedBox(height: 12),
  //           if (!isMe) ...[
  //             Row(
  //               mainAxisSize: MainAxisSize.min,
  //               children: [
  //                 Expanded(
  //                   child: ElevatedButton.icon(
  //                     onPressed: () => _downloadShare(message, 1),
  //                     icon: const Icon(Icons.file_download),
  //                     label: const Text('Share 1'),
  //                     style: ElevatedButton.styleFrom(
  //                       backgroundColor: Colors.blue,
  //                       foregroundColor: Colors.white,
  //                       padding: const EdgeInsets.symmetric(horizontal: 8),
  //                     ),
  //                   ),
  //                 ),
  //                 const SizedBox(width: 8),
  //                 Expanded(
  //                   child: ElevatedButton.icon(
  //                     onPressed: () => _downloadShare(message, 2),
  //                     icon: const Icon(Icons.file_download),
  //                     label: const Text('Share 2'),
  //                     style: ElevatedButton.styleFrom(
  //                       backgroundColor: Colors.green,
  //                       foregroundColor: Colors.white,
  //                       padding: const EdgeInsets.symmetric(horizontal: 8),
  //                     ),
  //                   ),
  //                 ),
  //               ],
  //             ),
  //           ],
  //           if (isMe) ...[
  //             const SizedBox(height: 4),
  //             Row(
  //               mainAxisSize: MainAxisSize.min,
  //               children: [
  //                 const SizedBox(width: 8),
  //                 _buildMessageStatus(message['status'] ?? ''),
  //               ],
  //             ),
  //           ],
  //         ],
  //       ),
  //     ),
  //   );
  // }

  Future<void> _downloadShare(
      Map<String, dynamic> messageData, int shareNumber) async {
    try {
      _showLoading();

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw 'User not authenticated';
      }

      // Get share path from message data
      final sharePath =
          messageData['share$shareNumber']?['storagePath'] as String?;
      if (sharePath == null) {
        throw 'Share path not found';
      }

      // Download share from Firebase Storage
      try {
        final shareData =
            await FirebaseStorage.instance.ref().child(sharePath).getData();

        if (shareData == null) {
          throw 'Failed to download share';
        }

        // Save and share file
        final directory = await getApplicationDocumentsDirectory();
        final downloadPath = '${directory.path}/Downloads';
        await Directory(downloadPath).create(recursive: true);

        final originalFileName =
            messageData['fileName'] as String? ?? 'document.txt';
        final fileNameWithoutExt = originalFileName.split('.').first;
        final fileExt = originalFileName.split('.').last;
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final filePath =
            '$downloadPath/${fileNameWithoutExt}_share$shareNumber.$fileExt';

        final file = File(filePath);
        await file.writeAsBytes(shareData);

        if (!mounted) return;
        Navigator.pop(context);
        _showSuccess('Share $shareNumber downloaded successfully');

        await Share.shareXFiles([XFile(filePath)]);
        await file.delete();
      } catch (e) {
        throw 'Error accessing Firebase Storage: $e';
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showError('Error downloading share: $e');
    }
  }

  // Widget _buildEncryptedDocumentMessage(
  //     Map<String, dynamic> message, bool isMe) {
  //   return Align(
  //     alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
  //     child: Container(
  //       margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  //       padding: const EdgeInsets.all(12),
  //       decoration: BoxDecoration(
  //         color: isMe ? primaryColor : Colors.grey[300],
  //         borderRadius: BorderRadius.circular(15),
  //       ),
  //       child: Column(
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: [
  //           Row(
  //             mainAxisSize: MainAxisSize.min,
  //             children: [
  //               const Icon(Icons.file_present, size: 20),
  //               const SizedBox(width: 8),
  //               Flexible(
  //                 child: Text(
  //                   message['fileName'] ?? 'Document',
  //                   style: TextStyle(
  //                     color: isMe ? Colors.white : Colors.black,
  //                     fontWeight: FontWeight.bold,
  //                   ),
  //                 ),
  //               ),
  //             ],
  //           ),
  //           const SizedBox(height: 12),
  //           if (!isMe) ...[
  //             Row(
  //               mainAxisSize: MainAxisSize.min,
  //               children: [
  //                 Expanded(
  //                   child: ElevatedButton.icon(
  //                     onPressed: () => _downloadShare(message, 1),
  //                     icon: const Icon(Icons.file_download),
  //                     label: const Text('Share 1'),
  //                     style: ElevatedButton.styleFrom(
  //                       backgroundColor: Colors.blue,
  //                       foregroundColor: Colors.white,
  //                       padding: const EdgeInsets.symmetric(horizontal: 8),
  //                     ),
  //                   ),
  //                 ),
  //                 const SizedBox(width: 8),
  //                 Expanded(
  //                   child: ElevatedButton.icon(
  //                     onPressed: () => _downloadShare(message, 2),
  //                     icon: const Icon(Icons.file_download),
  //                     label: const Text('Share 2'),
  //                     style: ElevatedButton.styleFrom(
  //                       backgroundColor: Colors.green,
  //                       foregroundColor: Colors.white,
  //                       padding: const EdgeInsets.symmetric(horizontal: 8),
  //                     ),
  //                   ),
  //                 ),
  //               ],
  //             ),
  //             const SizedBox(height: 8),
  //             ElevatedButton.icon(
  //               onPressed: () => _downloadDocument(message),
  //               icon: const Icon(Icons.download),
  //               label: const Text('Download Combined'),
  //               style: ElevatedButton.styleFrom(
  //                 backgroundColor: Colors.purple,
  //                 foregroundColor: Colors.white,
  //                 padding:
  //                     const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  //               ),
  //             ),
  //           ],
  //           if (isMe) ...[
  //             const SizedBox(height: 4),
  //             Row(
  //               mainAxisSize: MainAxisSize.min,
  //               children: [
  //                 const SizedBox(width: 8),
  //                 _buildMessageStatus(message['status'] ?? ''),
  //               ],
  //             ),
  //           ],
  //         ],
  //       ),
  //     ),
  //   );
  // }

  void _showMessageOptions(BuildContext context, Map<String, dynamic> message) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy Message'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: message['text']));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Message copied to clipboard')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('Delete Message'),
              onTap: () {
                FirebaseFirestore.instance
                    .collection('messages')
                    .doc()
                    .delete();
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  void _showLoading() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildMessageStatus(String status) {
    // Implement the status widget based on the status
    return Text(
      status,
      style: TextStyle(
        color: Colors.white,
        fontSize: 12,
      ),
    );
  }
}

class ChatInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSendMessage;
  final VoidCallback onAttachFile;

  const ChatInput({
    super.key,
    required this.controller,
    required this.onSendMessage,
    required this.onAttachFile,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.attach_file),
            onPressed: onAttachFile,
          ),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(
                    Radius.circular(50),
                  ),
                ),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primaryColor,
            ),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: onSendMessage,
            ),
          ),
        ],
      ),
    );
  }
}
