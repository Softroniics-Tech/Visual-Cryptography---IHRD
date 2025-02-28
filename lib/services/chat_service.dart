import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Get messages stream
  Stream<QuerySnapshot> getChatMessages(String chatRoomId) {
    return _firestore
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  // Send a message
  Future<void> sendMessage({
    required String chatRoomId,
    required String senderId,
    String? text,
    List<String>? fileUrls,
  }) async {
    try {
      final timestamp = FieldValue.serverTimestamp();
      final messageData = {
        'senderId': senderId,
        'timestamp': timestamp,
        'type': fileUrls != null ? 'file' : 'text',
      };

      if (text != null) {
        messageData['text'] = text;
      }

      if (fileUrls != null) {
        messageData['fileUrls'] = fileUrls;
      }

      await _firestore
          .collection('chatRooms')
          .doc(chatRoomId)
          .collection('messages')
          .add(messageData);

      // Update chatRoom's lastMessage
      await _firestore.collection('chatRooms').doc(chatRoomId).update({
        'lastMessage': text ?? 'Shared a file',
        'lastMessageTime': timestamp,
      });
    } catch (e) {
      throw 'Error sending message: $e';
    }
  }

  // Upload files to Firebase Storage
  Future<List<String>> uploadFiles(
    List<PlatformFile> files,
    String chatRoomId,
  ) async {
    try {
      final List<String> fileUrls = [];

      for (final file in files) {
        if (file.path == null) continue;

        final fileName =
            '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
        final storageRef = _storage
            .ref()
            .child('chats')
            .child(chatRoomId)
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

  // Delete a message
  Future<void> deleteMessage(String chatRoomId, String messageId) async {
    try {
      await _firestore
          .collection('chatRooms')
          .doc(chatRoomId)
          .collection('messages')
          .doc(messageId)
          .delete();
    } catch (e) {
      throw 'Error deleting message: $e';
    }
  }

  // Create or get chat room
  Future<String> createOrGetChatRoom(String userId1, String userId2) async {
    try {
      // Sort user IDs to ensure consistent chat room IDs
      final users = [userId1, userId2]..sort();
      final chatRoomId = '${users[0]}_${users[1]}';

      final chatRoomRef = _firestore.collection('chatRooms').doc(chatRoomId);
      final chatRoom = await chatRoomRef.get();

      if (!chatRoom.exists) {
        await chatRoomRef.set({
          'users': users,
          'createdAt': FieldValue.serverTimestamp(),
          'lastMessage': '',
          'lastMessageTime': FieldValue.serverTimestamp(),
        });
      }

      return chatRoomId;
    } catch (e) {
      throw 'Error creating/getting chat room: $e';
    }
  }

  // Send encrypted document
  Future<void> sendEncryptedDocument({
    required String chatRoomId,
    required String senderId,
    required String originalFileName,
    required String share1Url,
    required String share2Url,
    required String encryptionKey,
  }) async {
    try {
      final timestamp = FieldValue.serverTimestamp();
      final messageData = {
        'senderId': senderId,
        'timestamp': timestamp,
        'type': 'encrypted_document',
        'isEncryptedShare': true,
        'originalFileName': originalFileName,
        'share1Url': share1Url,
        'share2Url': share2Url,
        'encryptionKey': encryptionKey,
      };

      await _firestore
          .collection('chatRooms')
          .doc(chatRoomId)
          .collection('messages')
          .add(messageData);

      // Update chatRoom's lastMessage
      await _firestore.collection('chatRooms').doc(chatRoomId).update({
        'lastMessage': 'Shared an encrypted document',
        'lastMessageTime': timestamp,
      });
    } catch (e) {
      throw 'Error sending encrypted document: $e';
    }
  }
}
