import 'package:cloud_firestore/cloud_firestore.dart';

class Message {
  final String message;
  final String senderId;
  final String receiverId;
  final DateTime timestamp;
  final String chatRoomId;

  Message({
    required this.message,
    required this.senderId,
    required this.receiverId,
    required this.timestamp,
    required this.chatRoomId,
  });

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      message: map['message'] ?? '',
      senderId: map['senderId'] ?? '',
      receiverId: map['receiverId'] ?? '',
      timestamp: (map['timestamp'] as Timestamp).toDate(),
      chatRoomId: map['chatRoomId'] ?? '',
    );
  }
}
