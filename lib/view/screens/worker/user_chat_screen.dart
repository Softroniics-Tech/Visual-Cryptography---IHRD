import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypta_completed/constands/colors.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserChatScreen extends StatefulWidget {
  final String chatRoomId;
  final String currentUserId;
  final String managerId;
  final String managerName;

  const UserChatScreen({
    super.key,
    required this.chatRoomId,
    required this.currentUserId,
    required this.managerId,
    required this.managerName,
  });

  @override
  State<UserChatScreen> createState() => _UserChatScreenState();
}

class _UserChatScreenState extends State<UserChatScreen> {
  final _messageController = TextEditingController();
  final _keyController = TextEditingController();
  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    _messageController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage({String? text, List<String>? fileUrls}) async {
    if ((text?.isEmpty ?? true) && (fileUrls?.isEmpty ?? true)) return;

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final messageId =
          '${widget.currentUserId}_${widget.managerId}_$timestamp';

      await FirebaseFirestore.instance
          .collection("messages")
          .doc(messageId)
          .set({
        "senderId": widget.currentUserId,
        "receiverId": widget.managerId,
        "text": text,
        "type": fileUrls != null ? 'encryptedDocument' : 'text',
        "timestamp": FieldValue.serverTimestamp(),
        "isRead": false,
        "participants": [widget.currentUserId, widget.managerId],
        "chatRoomId": widget.chatRoomId,
      });

      // Update chat room's last message
      await FirebaseFirestore.instance
          .collection('chatRooms')
          .doc(widget.chatRoomId)
          .update({
        'lastMessage': text ?? 'Sent a file',
        'lastMessageTime': FieldValue.serverTimestamp(),
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

  Future<void> uploadFiles(List<PlatformFile> files) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final messageId =
          '${widget.currentUserId}_${widget.managerId}_$timestamp';

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

        await storageRef.putFile(File(file.path!));

        // Create message document with file info
        await FirebaseFirestore.instance
            .collection("messages")
            .doc(messageId)
            .set({
          "senderId": widget.currentUserId,
          "receiverId": widget.managerId,
          "type": "encryptedDocument",
          "fileName": file.name,
          "timestamp": FieldValue.serverTimestamp(),
          "isRead": false,
          "participants": [widget.currentUserId, widget.managerId],
          "chatRoomId": widget.chatRoomId,
          "text": "",
          "share1": {
            "storagePath": 'messages/$messageId/files/${fileName}_share1',
          },
          "share2": {
            "storagePath": 'messages/$messageId/files/${fileName}_share2',
          },
        });
      }
    } catch (e) {
      throw 'Error uploading files: $e';
    }
  }

  Future<void> _pickAndSendFiles() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.image,
      );

      if (result != null && mounted) {
        if (result.files.length > 2) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select only 2 images')),
          );
          return;
        }

        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              const Center(child: CircularProgressIndicator()),
        );

        await uploadFiles(result.files);

        if (!mounted) return;
        Navigator.pop(context);

        await _sendMessage(fileUrls: []);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error uploading files: $e')),
      );
    }
  }

  Future<void> _downloadShare(
      Map<String, dynamic> messageData, int shareNumber) async {
    try {
      _showLoading();

      // Get share information
      final shareInfo =
          messageData['share$shareNumber'] as Map<String, dynamic>?;
      if (shareInfo == null) {
        throw 'Share information not found';
      }

      // Get the download URL
      final downloadUrl = shareInfo['url'] as String?;
      if (downloadUrl == null) {
        throw 'Share URL not found';
      }

      // Download the image share
      final response = await http.get(Uri.parse(downloadUrl));
      if (response.statusCode != 200) {
        throw 'Failed to download share';
      }

      // Get the file name from the share info
      final fileName =
          shareInfo['fileName'] as String? ?? 'share$shareNumber.png';

      // Save and share the image file
      final directory = await getApplicationDocumentsDirectory();
      final downloadPath = '${directory.path}/Downloads';
      await Directory(downloadPath).create(recursive: true);

      final filePath = '$downloadPath/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);

      if (!mounted) return;
      Navigator.pop(context); // Hide loading
      _showSuccess('Share $shareNumber downloaded successfully');

      // Share the image file
      await Share.shareXFiles([XFile(filePath)]);
      await file.delete(); // Clean up
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showError('Error downloading share: $e');
    }
  }

  Future<Uint8List?> _loadSharePreview(Map<String, dynamic>? shareMap) async {
    if (shareMap == null) return null;

    try {
      // First try to use direct URL if available
      String? url = shareMap['url'] as String?;

      // If URL is not directly available, try to get it from the storage path
      if (url == null) {
        final path = shareMap['path'] as String?;
        if (path == null) return null;

        try {
          url = await FirebaseStorage.instance.ref(path).getDownloadURL();
        } catch (e) {
          print('Error getting download URL: $e');
          return null;
        }
      }

      if (url == null) return null;

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
                      future: _loadSharePreview(message['share1']),
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
                      future: _loadSharePreview(message['share2']),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Container(
                            height: 100,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.green),
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
    return Text(
      status,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
      ),
    );
  }

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
                _deleteMessage(message);
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteMessage(Map<String, dynamic> message) async {
    // Implement the delete message functionality here
    await FirebaseFirestore.instance.collection("messages").doc().delete();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Message deleted')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('messages')
                  .where('participants', arrayContains: widget.currentUserId)
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data?.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return data['senderId'] == widget.managerId ||
                          data['receiverId'] == widget.managerId;
                    }).toList() ??
                    [];

                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final messageDoc = messages[index];
                    final messageData =
                        messageDoc.data() as Map<String, dynamic>;
                    final isMe =
                        messageData['senderId'] == widget.currentUserId;

                    if (messageData['type'] == 'encryptedDocument') {
                      return _buildDocumentMessage(messageData, isMe);
                    }

                    // Regular text message
                    return GestureDetector(
                      onLongPress: () =>
                          _showMessageOptions(context, messageData),
                      child: Align(
                        alignment:
                            isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isMe ? primaryColor : Colors.grey[300],
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Text(
                            messageData['text'] as String? ?? '',
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
              if (_messageController.text.trim().isNotEmpty) {
                _sendMessage(text: _messageController.text.trim());
              }
            },
            onAttachFile: _pickAndSendFiles,
          ),
        ],
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
                  borderRadius: BorderRadius.all(Radius.circular(50)),
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
