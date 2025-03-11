class ChatMessage {
  final String id;
  final String senderId;
  final String receiverId;
  final String message;
  final DateTime timestamp;
  final String? fileUrl;
  final String? fileName;
  final bool isRead;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.message,
    required this.timestamp,
    this.fileUrl,
    this.fileName,
    this.isRead = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderId': senderId,
      'receiverId': receiverId,
      'message': message,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'fileUrl': fileUrl,
      'fileName': fileName,
      'isRead': isRead,
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'],
      senderId: map['senderId'],
      receiverId: map['receiverId'],
      message: map['message'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      fileUrl: map['fileUrl'],
      fileName: map['fileName'],
      isRead: map['isRead'] ?? false,
    );
  }
}
