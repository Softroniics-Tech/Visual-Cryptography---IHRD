import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:encrypta/services/document_cryptography_processor.dart'
    as crypto;

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Collection references
  final CollectionReference _usersCollection =
      FirebaseFirestore.instance.collection('users');
  final CollectionReference _chatRoomsCollection =
      FirebaseFirestore.instance.collection('chatRooms');
  final CollectionReference _messagesCollection =
      FirebaseFirestore.instance.collection('messages');
  final CollectionReference _encryptionKeysCollection =
      FirebaseFirestore.instance.collection('encryption_keys');

  // Message status enum
  static const messageStatusSending = 'sending';
  static const messageStatusSent = 'sent';
  static const messageStatusDelivered = 'delivered';
  static const messageStatusRead = 'read';
  static const messageStatusError = 'error';

  // Message type enum
  static const messageTypeText = 'text';
  static const messageTypeFile = 'file';
  static const messageTypeEncryptedDocument = 'encrypted_document';

  // Get messages stream
  Stream<QuerySnapshot> getChatMessages(String chatRoomId) {
    return _messagesCollection
        .where('chatRoomId', isEqualTo: chatRoomId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // Upload file to Firebase Storage
  Future<String> uploadFile(
      File file, String chatRoomId, String fileName) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final storagePath = 'chats/$chatRoomId/files/${now}_$fileName';
      final fileRef = _storage.ref().child(storagePath);

      // Upload file
      await fileRef.putFile(file);

      // Get download URL
      return await fileRef.getDownloadURL();
    } catch (e) {
      throw 'Error uploading file: $e';
    }
  }

  // Upload encrypted document shares
  Future<Map<String, dynamic>> uploadEncryptedDocument(
    PlatformFile file,
    String chatRoomId,
  ) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${now}_${file.name}';
      final encryptionKey = crypto.DocumentCryptographyProcessor.generateKey();

      // Generate shares using visual cryptography
      final document = File(file.path!);
      final shares = crypto.DocumentCryptographyProcessor.generateShares(
        document,
        encryptionKey,
      );

      // Upload both shares to Firebase Storage
      final share1Ref = _storage
          .ref()
          .child('chats/$chatRoomId/encrypted_documents/${fileName}_share1');
      final share2Ref = _storage
          .ref()
          .child('chats/$chatRoomId/encrypted_documents/${fileName}_share2');

      await share1Ref.putData(shares[0]);
      await share2Ref.putData(shares[1]);

      // Get download URLs
      final share1Url = await share1Ref.getDownloadURL();
      final share2Url = await share2Ref.getDownloadURL();

      return {
        'share1Url': share1Url,
        'share2Url': share2Url,
        'encryptionKey': encryptionKey,
        'originalFileName': file.name,
      };
    } catch (e) {
      throw 'Error uploading encrypted document: $e';
    }
  }

  // Create or get chat room
  Future<String> createChatRoom(String managerId, String workerId) async {
    try {
      // Create a unique chat room ID
      final users = [managerId, workerId]..sort();
      final chatRoomId = users.join('_');

      // Check if chat room exists
      final chatRoomDoc = await _chatRoomsCollection.doc(chatRoomId).get();

      if (!chatRoomDoc.exists) {
        // Create new chat room
        final now = DateTime.now().millisecondsSinceEpoch;
        await _chatRoomsCollection.doc(chatRoomId).set({
          'chatRoomId': chatRoomId,
          'participants': users,
          'managerId': managerId,
          'workerId': workerId,
          'createdAt': now,
          'updatedAt': FieldValue.serverTimestamp(),
          'lastMessage': null,
        });
      }

      return chatRoomId;
    } catch (e) {
      throw 'Error creating chat room: $e';
    }
  }

  // Send a message
  Future<void> sendMessage({
    required String chatRoomId,
    required String senderId,
    String? text,
    List<String>? fileUrls,
    Map<String, dynamic>? encryptedDocument,
  }) async {
    try {
      // Create message data with millisecondsSinceEpoch timestamp
      final now = DateTime.now().millisecondsSinceEpoch;
      final messageId = _messagesCollection.doc().id;

      final messageData = {
        'messageId': messageId,
        'chatRoomId': chatRoomId,
        'senderId': senderId,
        'text': text,
        'type': encryptedDocument != null
            ? messageTypeEncryptedDocument
            : (fileUrls != null && fileUrls.isNotEmpty
                ? messageTypeFile
                : messageTypeText),
        'status': messageStatusSending,
        'createdAt': now,
        'updatedAt': now,
      };

      // Add file metadata for regular files
      if (fileUrls != null && fileUrls.isNotEmpty) {
        messageData['fileMetadata'] = {
          'fileName': text, // Using text field as filename for regular files
          'fileUrl': fileUrls.first,
          'fileType': _getFileType(text ?? ''),
          'uploadTime': now,
          'size': await _getFileSize(fileUrls.first),
          'isEncrypted': false,
        };
      }

      // Add encrypted document data if present
      if (encryptedDocument != null) {
        messageData.addAll({
          'share1Url': encryptedDocument['share1Url'],
          'share2Url': encryptedDocument['share2Url'],
          'encryptionKey': encryptedDocument['encryptionKey'],
          'fileMetadata': {
            'fileName': encryptedDocument['originalFileName'],
            'fileType': _getFileType(encryptedDocument['originalFileName']),
            'uploadTime': now,
            'isEncrypted': true,
            'encryptionMethod': 'visual_cryptography',
            'size': await _getFileSize(encryptedDocument['share1Url']),
          },
        });
      }

      // Use transaction to update both message and chat room
      await _firestore.runTransaction((transaction) async {
        // Add message
        transaction.set(_messagesCollection.doc(messageId), messageData);

        // Update chat room
        transaction.update(_chatRoomsCollection.doc(chatRoomId), {
          'lastMessage': messageData,
          'lastMessageTime': now,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      // Mark message as sent
      await updateMessageStatus(
        chatRoomId: chatRoomId,
        messageId: messageId,
        status: messageStatusSent,
      );
    } catch (e) {
      throw 'Error sending message: $e';
    }
  }

  // Update message status
  Future<void> updateMessageStatus({
    required String chatRoomId,
    required String messageId,
    required String status,
  }) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _messagesCollection.doc(messageId).update({
        'status': status,
        'updatedAt': now,
      });

      // Update chat room's last message status if this is the last message
      final chatRoom = await _chatRoomsCollection.doc(chatRoomId).get();
      final lastMessage = chatRoom.data() as Map<String, dynamic>?;

      if (lastMessage?['lastMessage']?['messageId'] == messageId) {
        await _chatRoomsCollection.doc(chatRoomId).update({
          'lastMessage.status': status,
          'lastMessage.updatedAt': now,
        });
      }
    } catch (e) {
      throw 'Error updating message status: $e';
    }
  }

  // Delete message
  Future<void> deleteMessage(String messageId) async {
    try {
      final message = await _messagesCollection.doc(messageId).get();
      final messageData = message.data() as Map<String, dynamic>;
      final chatRoomId = messageData['chatRoomId'];

      await _firestore.runTransaction((transaction) async {
        // Delete message
        transaction.delete(_messagesCollection.doc(messageId));

        // Update chat room's last message if needed
        final chatRoom = await _chatRoomsCollection.doc(chatRoomId).get();
        final lastMessage = chatRoom.data() as Map<String, dynamic>?;

        if (lastMessage?['lastMessage']?['messageId'] == messageId) {
          // Get the previous message
          final previousMessage = await _messagesCollection
              .where('chatRoomId', isEqualTo: chatRoomId)
              .orderBy('createdAt', descending: true)
              .limit(1)
              .get();

          if (previousMessage.docs.isNotEmpty) {
            transaction.update(_chatRoomsCollection.doc(chatRoomId), {
              'lastMessage': previousMessage.docs.first.data(),
              'lastMessageTime': previousMessage.docs.first.get('createdAt'),
            });
          } else {
            transaction.update(_chatRoomsCollection.doc(chatRoomId), {
              'lastMessage': null,
              'lastMessageTime': null,
            });
          }
        }
      });
    } catch (e) {
      throw 'Error deleting message: $e';
    }
  }

  Future<int?> _getFileSize(String url) async {
    try {
      final ref = FirebaseStorage.instance.refFromURL(url);
      final metadata = await ref.getMetadata();
      return metadata.size;
    } catch (_) {
      return null;
    }
  }

  String _getFileType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return 'PDF Document';
      case 'doc':
      case 'docx':
        return 'Word Document';
      case 'txt':
        return 'Text Document';
      case 'png':
      case 'jpg':
      case 'jpeg':
        return 'Image';
      default:
        return 'Document';
    }
  }

  // Upload files to Firebase Storage
  Future<List<String>> uploadFiles(
    List<PlatformFile> files,
    String chatRoomId,
  ) async {
    try {
      final List<String> fileUrls = [];
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      for (final file in files) {
        if (file.path == null) continue;

        final fileName = '${timestamp}_${file.name}';
        final storageRef = _storage
            .ref()
            .child('chat_files')
            .child(chatRoomId)
            .child(fileName);

        final uploadTask = await storageRef.putFile(
          File(file.path!),
          SettableMetadata(
            contentType: file.extension != null
                ? 'application/${file.extension}'
                : 'application/octet-stream',
            customMetadata: {
              'uploadedAt': timestamp.toString(),
              'originalName': file.name,
            },
          ),
        );

        final downloadUrl = await uploadTask.ref.getDownloadURL();
        fileUrls.add(downloadUrl);
      }

      return fileUrls;
    } catch (e) {
      throw 'Error uploading files: $e';
    }
  }

  // Get chat rooms stream
  Stream<QuerySnapshot> getChatRooms(String userId) {
    return _chatRoomsCollection
        .where('participants', arrayContains: userId)
        .orderBy('updatedAt', descending: true)
        .snapshots();
  }

  // Mark all messages as read
  Future<void> markAllMessagesAsRead({
    required String chatRoomId,
    required String currentUserId,
  }) async {
    try {
      // First get messages that are not from current user
      final messagesQuery = await _messagesCollection
          .where('chatRoomId', isEqualTo: chatRoomId)
          .where('senderId', isNotEqualTo: currentUserId)
          .get();

      // Filter messages that need to be marked as read
      final messagesToUpdate = messagesQuery.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final status = data['status'] as String?;
        return status != messageStatusRead;
      }).toList();

      if (messagesToUpdate.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      final now = DateTime.now().millisecondsSinceEpoch;

      for (var doc in messagesToUpdate) {
        batch.update(doc.reference, {
          'status': messageStatusRead,
          'updatedAt': now,
        });
      }

      await batch.commit();

      // Update lastMessages array
      final chatRoomDoc = await _chatRoomsCollection.doc(chatRoomId).get();
      final chatRoomData = chatRoomDoc.data() as Map<String, dynamic>;
      final lastMessage = chatRoomData['lastMessage'];

      if (lastMessage != null && lastMessage['senderId'] != currentUserId) {
        await _chatRoomsCollection.doc(chatRoomId).update({
          'lastMessage.status': messageStatusRead,
          'lastMessage.updatedAt': now,
        });
      }
    } catch (e) {
      throw 'Error marking messages as read: $e';
    }
  }

  // Mark all messages as delivered
  Future<void> markAllMessagesAsDelivered({
    required String chatRoomId,
    required String currentUserId,
  }) async {
    try {
      // First get messages that are not from current user
      final messagesQuery = await _messagesCollection
          .where('chatRoomId', isEqualTo: chatRoomId)
          .where('senderId', isNotEqualTo: currentUserId)
          .get();

      // Filter messages that need to be marked as delivered
      final messagesToUpdate = messagesQuery.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final status = data['status'] as String?;
        return status == messageStatusSent || status == messageStatusSending;
      }).toList();

      if (messagesToUpdate.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      final now = DateTime.now().millisecondsSinceEpoch;

      for (var doc in messagesToUpdate) {
        batch.update(doc.reference, {
          'status': messageStatusDelivered,
          'updatedAt': now,
        });
      }

      await batch.commit();

      // Update lastMessages array
      final chatRoomDoc = await _chatRoomsCollection.doc(chatRoomId).get();
      final chatRoomData = chatRoomDoc.data() as Map<String, dynamic>;
      final lastMessage = chatRoomData['lastMessage'];

      if (lastMessage != null &&
          lastMessage['senderId'] != currentUserId &&
          (lastMessage['status'] == messageStatusSent ||
              lastMessage['status'] == messageStatusSending)) {
        await _chatRoomsCollection.doc(chatRoomId).update({
          'lastMessage.status': messageStatusDelivered,
          'lastMessage.updatedAt': now,
        });
      }
    } catch (e) {
      throw 'Error marking messages as delivered: $e';
    }
  }

  // Retry failed message
  Future<void> retryFailedMessage({
    required String chatRoomId,
    required String messageId,
  }) async {
    try {
      final messageDoc = await _messagesCollection.doc(messageId).get();

      if (!messageDoc.exists) {
        throw 'Message not found';
      }

      final message = messageDoc.data() as Map<String, dynamic>;
      if (message['status'] != messageStatusError) {
        throw 'Message is not in error state';
      }

      // Update message status to sending
      await updateMessageStatus(
        chatRoomId: chatRoomId,
        messageId: messageId,
        status: messageStatusSending,
      );

      // Attempt to resend based on message type
      if (message['type'] == messageTypeEncryptedDocument) {
        await sendMessage(
          chatRoomId: chatRoomId,
          senderId: message['senderId'],
          encryptedDocument: {
            'share1Url': message['share1Url'],
            'share2Url': message['share2Url'],
            'encryptionKey': message['encryptionKey'],
            'originalFileName': message['originalFileName'],
          },
        );
      } else {
        await sendMessage(
          chatRoomId: chatRoomId,
          senderId: message['senderId'],
          text: message['text'],
          fileUrls: message['fileUrls'],
        );
      }

      // Delete the original failed message
      await deleteMessage(messageId);
    } catch (e) {
      throw 'Error retrying message: $e';
    }
  }
}
