import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:encrypta/services/chat_service.dart';
import 'package:encrypta/worker/constands/colors.dart';
import 'package:encrypta/services/document_cryptography_processor.dart'
    as crypto;
import 'package:encrypta/worker/screens/app_home_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markMessagesAsDelivered();
    });
  }

  void _markMessagesAsDelivered() {
    if (!mounted) return;
    _chatService.markAllMessagesAsDelivered(
      chatRoomId: widget.chatRoomId,
      currentUserId: widget.currentUserId,
    );
  }

  void _markMessagesAsRead() {
    if (!mounted) return;
    _chatService.markAllMessagesAsRead(
      chatRoomId: widget.chatRoomId,
      currentUserId: widget.currentUserId,
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage({
    String? text,
    List<String>? fileUrls,
    Map<String, dynamic>? encryptedDocument,
  }) async {
    if ((text?.isEmpty ?? true) &&
        (fileUrls?.isEmpty ?? true) &&
        encryptedDocument == null) return;

    try {
      await _chatService.sendMessage(
        chatRoomId: widget.chatRoomId,
        senderId: widget.currentUserId,
        text: text,
        fileUrls: fileUrls,
        encryptedDocument: encryptedDocument,
      );

      if (!mounted) return;
      _messageController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickAndSendFiles() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result == null || !mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      try {
        // Upload and encrypt the document
        final encryptedDoc = await _chatService.uploadEncryptedDocument(
          result.files.first,
          widget.chatRoomId,
        );

        if (!mounted) return;

        // Send the message with encrypted document data
        await _sendMessage(encryptedDocument: encryptedDoc);

        // Safely pop the dialog
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      } catch (e) {
        if (!mounted) return;
        // Make sure to dismiss the loading dialog
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading document: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error selecting document: $e'),
          backgroundColor: Colors.red,
        ),
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

      try {
        // Combine shares and decrypt using the key
        final combinedBytes =
            await crypto.DocumentCryptographyProcessor.combineShares(
          [share1Response.bodyBytes, share2Response.bodyBytes],
          encryptionKey,
        );

        // Get the application documents directory
        final directory = await getApplicationDocumentsDirectory();
        if (directory == null) throw 'Could not access storage directory';

        final downloadPath = '${directory.path}/Downloads';
        await Directory(downloadPath).create(recursive: true);

        // Save the decrypted file with original filename
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final filePath = '$downloadPath/${timestamp}_$fileName';
        final file = File(filePath);
        await file.writeAsBytes(combinedBytes);

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

        // Share the file
        await Share.shareXFiles([XFile(filePath)]);

        // Clean up the temporary file after sharing
        await file.delete();
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
      setState(() => _isProcessing = true);

      // Get the temporary directory
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$fileName');

      // Download the file
      final response = await http.get(Uri.parse(fileUrl));
      if (response.statusCode != 200) {
        throw 'Failed to download file';
      }

      // Write to temporary file
      await tempFile.writeAsBytes(response.bodyBytes);

      // Get the downloads directory
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) throw 'Downloads directory not found';

      // Create final file path
      var targetFile = File('${downloadsDir.path}/$fileName');

      // Ensure unique filename
      String uniqueFileName = fileName;
      int counter = 1;
      while (await targetFile.exists()) {
        final lastDot = fileName.lastIndexOf('.');
        if (lastDot == -1) {
          uniqueFileName = '$fileName ($counter)';
        } else {
          uniqueFileName =
              '${fileName.substring(0, lastDot)} ($counter)${fileName.substring(lastDot)}';
        }
        targetFile = File('${downloadsDir.path}/$uniqueFileName');
        counter++;
      }

      // Copy to downloads directory
      await tempFile.copy(targetFile.path);

      // Delete temporary file
      await tempFile.delete();

      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showSuccess('File downloaded to ${targetFile.path}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showError('Error downloading file: $e');
    }
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

  void _showMessageOptions(BuildContext context, Map<String, dynamic> message) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message['status'] == ChatService.messageStatusError &&
                message['senderId'] == widget.currentUserId) ...[
              ListTile(
                leading: const Icon(Icons.refresh, color: Colors.blue),
                title: const Text('Retry Sending'),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    await _chatService.retryFailedMessage(
                      chatRoomId: widget.chatRoomId,
                      messageId: message['messageId'],
                    );
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Message resent successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error retrying message: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy Message'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: message['text']));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Message copied to clipboard'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
            ),
            if (message['senderId'] == widget.currentUserId)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
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

  Widget _buildMessageStatus(String status) {
    IconData icon;
    Color color;

    switch (status) {
      case ChatService.messageStatusSending:
        icon = Icons.access_time;
        color = Colors.grey;
        break;
      case ChatService.messageStatusSent:
        icon = Icons.check;
        color = Colors.grey;
        break;
      case ChatService.messageStatusDelivered:
        icon = Icons.done_all;
        color = Colors.grey;
        break;
      case ChatService.messageStatusRead:
        icon = Icons.done_all;
        color = Colors.blue;
        break;
      case ChatService.messageStatusError:
        icon = Icons.error_outline;
        color = Colors.red;
        break;
      default:
        icon = Icons.check;
        color = Colors.grey;
    }

    return Icon(
      icon,
      size: 16,
      color: color,
    );
  }

  // void _markMessageAsRead(String messageId) {
  //   _chatService.markMessageAsRead(

  //     chatRoomId: widget.chatRoomId,
  //     messageId: messageId,

  //   );
  // }

  Widget _buildTextMessage(Map<String, dynamic> message, bool isMe) {
    final status = message['status'] ?? '';
    final hasError = status == ChatService.messageStatusError;

    // Mark message as read if it's not from current user
    if (!isMe && status != ChatService.messageStatusRead) {
      // _markMessageAsRead(message['messageId']);
    }

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
            color: isMe
                ? (hasError ? Colors.red[100] : primaryColor)
                : Colors.grey[300],
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                message['text'] ?? '',
                style: TextStyle(
                  color: isMe
                      ? (hasError ? Colors.red[900] : Colors.white)
                      : Colors.black,
                ),
              ),
              const SizedBox(height: 4),
              if (isMe) _buildMessageStatus(status),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileMessage(Map<String, dynamic> message, bool isMe) {
    final status = message['status'] ?? '';
    final hasError = status == ChatService.messageStatusError;
    final fileMetadata = message['fileMetadata'] as Map<String, dynamic>?;

    // Mark message as read if it's not from current user
    if (!isMe && status != ChatService.messageStatusRead) {
      // _markMessageAsRead(message['messageId']);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: hasError
              ? Colors.red[100]
              : (isMe ? Colors.blue[100] : Colors.grey[200]),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getFileIcon(fileMetadata?['fileType'] ?? ''),
                  color: hasError ? Colors.red[700] : Colors.grey[700],
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileMetadata?['fileName'] ?? 'File',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: hasError ? Colors.red[900] : Colors.black,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            fileMetadata?['fileType'] ?? 'Document',
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  hasError ? Colors.red[700] : Colors.grey[600],
                            ),
                          ),
                          if (fileMetadata?['size'] != null) ...[
                            Text(
                              ' • ${_formatFileSize(fileMetadata!['size'])}',
                              style: TextStyle(
                                fontSize: 12,
                                color: hasError
                                    ? Colors.red[700]
                                    : Colors.grey[600],
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (fileMetadata?['isEncrypted'] == true) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lock,
                              size: 12,
                              color:
                                  hasError ? Colors.red[700] : Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Encrypted',
                              style: TextStyle(
                                fontSize: 12,
                                color: hasError
                                    ? Colors.red[700]
                                    : Colors.grey[600],
                              ),
                            ),
                            if (fileMetadata?['encryptionMethod'] != null) ...[
                              Text(
                                ' • ${_formatEncryptionMethod(fileMetadata!['encryptionMethod'])}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: hasError
                                      ? Colors.red[700]
                                      : Colors.grey[600],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                      Text(
                        _formatUploadTime(fileMetadata?['uploadTime']),
                        style: TextStyle(
                          fontSize: 11,
                          color: hasError ? Colors.red[700] : Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (hasError) ...[
              const SizedBox(height: 8),
              Text(
                'Failed to send file. Tap to retry.',
                style: TextStyle(
                  color: Colors.red[900],
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!hasError)
                  if (message['type'] ==
                      ChatService.messageTypeEncryptedDocument)
                    ElevatedButton.icon(
                      onPressed: () => _downloadDocument(
                        message['share1Url'],
                        message['share2Url'],
                        message['encryptionKey'],
                        message['fileMetadata']['fileName'],
                      ),
                      icon: const Icon(Icons.download),
                      label: const Text('Download'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: () => _downloadFile(
                        fileMetadata?['fileUrl'] ?? '',
                        fileMetadata?['fileName'] ?? 'file',
                      ),
                      icon: const Icon(Icons.download),
                      label: const Text('Download'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    )
                else if (isMe)
                  ElevatedButton.icon(
                    onPressed: () => _retryMessage(message),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                if (isMe) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    color: hasError ? Colors.red[900] : Colors.red,
                    onPressed: () => _deleteMessage(message),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            _buildMessageStatus(status),
          ],
        ),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double size = bytes.toDouble();

    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }

    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _formatEncryptionMethod(String method) {
    return method
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }

  Widget _buildEncryptedMessage(Map<String, dynamic> message, bool isMe) {
    final status = message['status'] ?? '';
    final hasError = status == ChatService.messageStatusError;

    // Mark message as read if it's not from current user
    if (!isMe && status != ChatService.messageStatusRead) {
      // _markMessageAsRead(message['messageId']);
    }

    return Row(
      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: hasError
                ? Colors.red[100]
                : (isMe ? primaryColor : Colors.grey[300]),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.lock,
                    color: hasError ? Colors.red[900] : Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Encrypted Document:',
                    style: TextStyle(
                      color: hasError ? Colors.red[900] : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                message['originalFileName'] ?? 'Document',
                style: TextStyle(
                  color: hasError
                      ? Colors.red[700]
                      : Colors.white.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!hasError)
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
                  if (isMe) ...[
                    const SizedBox(width: 8),
                    _buildMessageStatus(status),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _getFileIcon(String fileType) {
    switch (fileType.toLowerCase()) {
      case 'pdf document':
        return Icons.picture_as_pdf;
      case 'word document':
        return Icons.description;
      case 'text document':
        return Icons.text_snippet;
      case 'image':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatUploadTime(dynamic timestamp) {
    if (timestamp == null) return '';

    final uploadTime = DateTime.fromMillisecondsSinceEpoch(timestamp as int);
    final now = DateTime.now();
    final difference = now.difference(uploadTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  Future<void> _retryMessage(Map<String, dynamic> message) async {
    try {
      setState(() => _isProcessing = true);

      // Delete the failed message first
      await _deleteMessage(message);

      // Retry sending based on message type
      if (message['type'] == ChatService.messageTypeEncryptedDocument) {
        final encryptedDoc = {
          'share1Url': message['share1Url'],
          'share2Url': message['share2Url'],
          'encryptionKey': message['encryptionKey'],
          'originalFileName': message['originalFileName'],
        };
        await _sendMessage(encryptedDocument: encryptedDoc);
      } else {
        await _sendMessage(
          fileUrls: [message['fileUrl']],
          text: message['fileName'],
        );
      }

      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showSuccess('Message resent successfully');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showError('Error retrying message: $e');
    }
  }

  Future<void> _deleteMessage(Map<String, dynamic> message) async {
    try {
      final messageId = message['messageId'];
      if (messageId == null) {
        throw 'Message ID not found';
      }

      await _chatService.deleteMessage(
        widget.chatRoomId,
        // messageId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message deleted'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildMessageList() {
    return StreamBuilder(
      stream: _chatService.getChatMessages(widget.chatRoomId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              color: primaryColor,
            ),
          );
        }

        final messages = snapshot.data?.docs ?? [];

        // Mark messages as read when they appear in the view
        if (messages.isNotEmpty) {
          // Debounce the read status update to prevent rapid updates
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _markMessagesAsRead();
            }
          });
        }

        return ListView.builder(
          reverse: true,
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final messageDoc = messages[index];
            final message = {
              ...messageDoc.data() as Map<String, dynamic>,
              'messageId': messageDoc.id,
            };
            final isMe = message['senderId'] == widget.currentUserId;

            if (message['type'] == ChatService.messageTypeEncryptedDocument) {
              return _buildEncryptedMessage(message, isMe);
            }

            if (message['type'] == ChatService.messageTypeFile) {
              return _buildFileMessage(message, isMe);
            }

            return _buildTextMessage(message, isMe);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.managerName),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
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
                    onPressed: () {
                      if (_messageController.text.trim().isNotEmpty) {
                        _sendMessage(text: _messageController.text.trim());
                        _messageController.clear();
                      }
                    },
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
