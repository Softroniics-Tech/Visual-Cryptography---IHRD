import 'dart:io';
import 'package:encrypta/services/chat_service.dart';
import 'package:encrypta/worker/constands/colors.dart';
import 'package:encrypta/worker/screens/app_home_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
  final _chatService = ChatService();

  @override
  void dispose() {
    _messageController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage({String? text, List<String>? fileUrls}) async {
    if ((text?.isEmpty ?? true) && (fileUrls?.isEmpty ?? true)) return;

    try {
      await _chatService.sendMessage(
        chatRoomId: widget.chatRoomId,
        senderId: widget.currentUserId,
        text: text,
        fileUrls: fileUrls,
      );

      if (!mounted) return;
      _messageController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending message: $e')),
      );
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

        final fileUrls =
            await _chatService.uploadFiles(result.files, widget.chatRoomId);

        if (!mounted) return;
        Navigator.pop(context);

        if (fileUrls.isNotEmpty) {
          await _sendMessage(fileUrls: fileUrls);
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error uploading files: $e')),
      );
    }
  }

  Future<void> _downloadDocument(
    String share1Url,
    String share2Url,
    String encryptionKey,
    String fileName,
  ) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // Download both shares
      final share1Response = await http.get(Uri.parse(share1Url));
      final share2Response = await http.get(Uri.parse(share2Url));

      if (share1Response.statusCode != 200 ||
          share2Response.statusCode != 200) {
        throw 'Failed to download document shares';
      }

      final shares = [
        share1Response.bodyBytes,
        share2Response.bodyBytes,
      ];

      // Combine shares and decrypt
      final decryptedBytes =
          DocumentCryptographyProcessor.combineShares(shares, encryptionKey);

      // Get the downloads directory
      final directory = await getExternalStorageDirectory();
      if (directory == null) throw 'Could not access storage directory';

      final downloadPath = '${directory.path}/Downloads';
      await Directory(downloadPath).create(recursive: true);

      // Save the decrypted file
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '$downloadPath/${timestamp}_$fileName';
      final file = File(filePath);
      await file.writeAsBytes(decryptedBytes);

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Document downloaded successfully'),
          backgroundColor: Colors.green,
        ),
      );

      await Share.shareXFiles([XFile(filePath)]);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error downloading document: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _downloadFile(String fileUrl, String fileName) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final response = await http.get(Uri.parse(fileUrl));
      if (response.statusCode != 200) throw 'Failed to download file';

      final directory = await getExternalStorageDirectory();
      if (directory == null) throw 'Could not access storage directory';

      final downloadPath = '${directory.path}/Downloads';
      await Directory(downloadPath).create(recursive: true);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '$downloadPath/${timestamp}_$fileName';
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File downloaded successfully'),
          backgroundColor: Colors.green,
        ),
      );

      await Share.shareXFiles([XFile(filePath)]);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error downloading file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildFileMessage(Map<String, dynamic> message, bool isMe) {
    final bool isEncrypted = message['isEncryptedShare'] == true;
    final String fileLabel =
        isEncrypted ? 'Encrypted Document' : 'Shared Document';
    final String fileName =
        message['originalFileName'] ?? message['fileName'] ?? 'Document';

    return Row(
      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          padding: const EdgeInsets.all(12),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.7,
          ),
          decoration: BoxDecoration(
            color: isMe ? primaryColor : Colors.grey[300],
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isEncrypted ? Icons.lock : Icons.insert_drive_file,
                    color: isMe ? Colors.white : Colors.black87,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    fileLabel,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                fileName,
                style: TextStyle(
                  color: isMe ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () {
                  if (isEncrypted) {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Enter decryption key'),
                        content: TextField(
                          controller: _keyController,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(50)),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () {
                              _downloadDocument(
                                message['share1Url'],
                                message['share2Url'],
                                _keyController.text,
                                fileName,
                              );
                              Navigator.pop(context);
                            },
                            child: const Text('Download'),
                          ),
                        ],
                      ),
                    );
                  } else {
                    _downloadFile(message['fileUrl'], fileName);
                  }
                },
                icon: const Icon(Icons.download),
                label: const Text('Download'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
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
    await _chatService.deleteMessage(
      widget.chatRoomId,
      message['id'], // Assuming each message has an 'id'
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Message deleted')),
    );
  }

  Widget _buildTextMessage(Map<String, dynamic> message, bool isMe) {
    return GestureDetector(
      onLongPress: () {
        _showMessageOptions(context, message);
      },
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          padding: const EdgeInsets.all(12),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.7,
          ),
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder(
              stream: _chatService.getChatMessages(widget.chatRoomId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data?.docs ?? [];

                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message =
                        messages[index].data() as Map<String, dynamic>;
                    final isMe = message['senderId'] == widget.currentUserId;

                    if (message['type'] == 'file' ||
                        message['isEncryptedShare'] == true) {
                      return _buildFileMessage(message, isMe);
                    }
                    return _buildTextMessage(message, isMe);
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: _pickAndSendFiles,
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(50),
                    color: primaryColor,
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.send,
                      color: Colors.white,
                    ),
                    onPressed: () =>
                        _sendMessage(text: _messageController.text),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
