import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';

class SimpleChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final String collectionName = 'chats';

  // Get chat messages between two users
  Stream<List<ChatMessage>> getMessages(String userId1, String userId2) {
    return _firestore
        .collection(collectionName)
        .where('participants', arrayContainsAny: [userId1, userId2])
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ChatMessage.fromMap(doc.data()))
            .toList());
  }

  // Send a text message
  Future<void> sendMessage({
    required String senderId,
    required String receiverId,
    required String message,
  }) async {
    final chatMessage = ChatMessage(
      id: const Uuid().v4(),
      senderId: senderId,
      receiverId: receiverId,
      message: message,
      timestamp: DateTime.now(),
    );

    await _firestore
        .collection(collectionName)
        .doc(chatMessage.id)
        .set(chatMessage.toMap());
  }

  // Send a file message
  Future<void> sendFileMessage({
    required String senderId,
    required String receiverId,
    required File file,
  }) async {
    // Upload file
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
    final ref = _storage.ref().child('chat_files/$fileName');
    await ref.putFile(file);
    final fileUrl = await ref.getDownloadURL();

    // Create and send message
    final chatMessage = ChatMessage(
      id: const Uuid().v4(),
      senderId: senderId,
      receiverId: receiverId,
      message: 'Sent a file: ${file.path.split('/').last}',
      timestamp: DateTime.now(),
      fileUrl: fileUrl,
      fileName: fileName,
    );

    await _firestore
        .collection(collectionName)
        .doc(chatMessage.id)
        .set(chatMessage.toMap());
  }

  // Mark message as read
  Future<void> markAsRead(String messageId) async {
    await _firestore
        .collection(collectionName)
        .doc(messageId)
        .update({'isRead': true});
  }

  // Delete message
  Future<void> deleteMessage(String messageId) async {
    await _firestore.collection(collectionName).doc(messageId).delete();
  }
}
