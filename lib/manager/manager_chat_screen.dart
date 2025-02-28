import 'dart:io';
import 'package:encrypta/services/chat_service.dart';
import 'package:encrypta/worker/constands/colors.dart';
import 'package:encrypta/services/document_cryptography_processor.dart'
    as crypto;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ManagerChatScreen extends StatefulWidget {
  final String chatRoomId;
  final String currentUserId;
  final String otherUserId;
  final String otherUserName;

  const ManagerChatScreen({
    super.key,
    required this.chatRoomId,
    required this.currentUserId,
    required this.otherUserId,
    required this.otherUserName,
  });

  @override
  State<ManagerChatScreen> createState() => _ManagerChatScreenState();
}

class _ManagerChatScreenState extends State<ManagerChatScreen> {
  final _messageController = TextEditingController();
  final _chatService = ChatService();
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
      final fileUrls = await _chatService.uploadFiles(
        [...result1.files, ...result2.files],
        widget.chatRoomId,
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
        // Clean up any resources before popping
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
                stream: _chatService.getChatMessages(widget.chatRoomId),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: CircularProgressIndicator(
                        color: primaryColor,
                      ),
                    );
                  }

                  final messages = snapshot.data?.docs ?? [];

                  return ListView.builder(
                    reverse: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message =
                          messages[index].data() as Map<String, dynamic>;
                      final isMe = message['senderId'] == widget.currentUserId;

                      if (message['type'] == 'file') {
                        return Row(
                          mainAxisAlignment: isMe
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isMe ? primaryColor : Colors.grey[300],
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Shared Document:',
                                    style: TextStyle(
                                      color: isMe ? Colors.white : Colors.black,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    message['fileName'] ?? 'Document',
                                    style: TextStyle(
                                      color: isMe
                                          ? Colors.white70
                                          : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: () => _downloadFile(
                                          message['fileUrl'],
                                          message['fileName'],
                                        ),
                                        icon: const Icon(Icons.download),
                                        label: const Text('Download'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }

                      if (message['isEncryptedShare'] == true) {
                        return Row(
                          mainAxisAlignment: isMe
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isMe ? primaryColor : Colors.grey[300],
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Encrypted Document:',
                                    style: TextStyle(
                                      color: isMe ? Colors.white : Colors.black,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    message['originalFileName'] ?? 'Document',
                                    style: TextStyle(
                                      color: isMe
                                          ? Colors.white70
                                          : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: () => _downloadDocument(
                                          message['share1Url'],
                                          message['share2Url'],
                                          message['encryptionKey'],
                                          message['originalFileName'],
                                        ),
                                        icon: const Icon(Icons.download),
                                        label: const Text('Download'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }

                      return GestureDetector(
                        onLongPress: () {
                          _showMessageOptions(context, message);
                        },
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
                              message['text'],
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

      try {
        // Combine shares and decrypt using the key
        final combinedBytes =
            await crypto.DocumentCryptographyProcessor.combineShares(
          [share1Response.bodyBytes, share2Response.bodyBytes],
        );

        // Decrypt the combined data
        final decryptedBytes = crypto.DocumentCryptographyProcessor.decryptData(
          combinedBytes,
          encryptionKey,
        );

        // Get the downloads directory
        final directory = await getExternalStorageDirectory();
        if (directory == null) throw 'Could not access storage directory';

        final downloadPath = '${directory.path}/Downloads';
        await Directory(downloadPath).create(recursive: true);

        // Save the decrypted file with original filename
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final filePath = '$downloadPath/${timestamp}_$fileName';
        final file = File(filePath);
        await file.writeAsBytes(decryptedBytes);

        // Close loading indicator
        if (!mounted) return;
        Navigator.pop(context);

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Document downloaded successfully'),
            backgroundColor: Colors.green,
          ),
        );

        // Open the file
        await Share.shareXFiles([XFile(filePath)]);
      } catch (e) {
        throw 'Error decrypting document: Invalid encryption key or corrupted shares';
      }
    } catch (e) {
      // Close loading indicator if it's showing
      if (!mounted) return;
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // Show error message
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
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // Download file
      final response = await http.get(Uri.parse(fileUrl));

      if (response.statusCode != 200) {
        throw 'Failed to download file';
      }

      // Get the downloads directory
      final directory = await getExternalStorageDirectory();
      final downloadPath = '${directory!.path}/Downloads';
      await Directory(downloadPath).create(recursive: true);

      // Save the file
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '$downloadPath/${timestamp}_$fileName';
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);

      // Close loading indicator
      if (!mounted) return;
      Navigator.pop(context);

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File downloaded successfully'),
          backgroundColor: Colors.green,
        ),
      );

      // Open the file
      await Share.shareXFiles([XFile(filePath)]);
    } catch (e) {
      // Close loading indicator
      if (!mounted) return;
      Navigator.pop(context);

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error downloading file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
