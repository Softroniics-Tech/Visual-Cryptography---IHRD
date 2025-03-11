import 'package:cloud_firestore/cloud_firestore.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Send message
  Future<void> sendMessage({
    required String message,
    required String senderId,
    required String receiverId,
    required String chatRoomId,
  }) async {
    final timestamp = FieldValue.serverTimestamp();

    // Create message
    final newMessage = {
      'message': message,
      'senderId': senderId,
      'receiverId': receiverId,
      'timestamp': timestamp,
      'chatRoomId': chatRoomId,
    };

    // Add message to chat room
    await _firestore
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .add(newMessage);

    // Update last message in chat room
    await _firestore.collection('chatRooms').doc(chatRoomId).set({
      'lastMessage': message,
      'lastMessageTime': timestamp,
      'participants': [senderId, receiverId],
    }, SetOptions(merge: true));
  }

  // Get chat room ID
  List<String> getChatRoomId(String userId, String managerId) {
    return [userId, managerId].toList().toList();
  }

  // Get all messages for a chat room
  Stream<QuerySnapshot> getMessages(String chatRoomId) {
    return _firestore
        .collection('chatRooms')
        .doc(chatRoomId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  // Get all users for manager
  Stream<QuerySnapshot> getAllUsers() {
    return _firestore.collection('users').snapshots();
  }

  // Get all chat rooms for manager
  Stream<QuerySnapshot> getManagerChatRooms(String managerId) {
    return _firestore
        .collection('chatRooms')
        .where('participants', arrayContains: managerId)
        .orderBy('lastMessageTime', descending: true)
        .snapshots();
  }
}
