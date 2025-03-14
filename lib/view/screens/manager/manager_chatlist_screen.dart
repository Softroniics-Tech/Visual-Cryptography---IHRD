import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:encrypta/view/screens/manager/manager_chat_screen.dart';

class ManagerChatListScreen extends StatefulWidget {
  const ManagerChatListScreen({super.key});

  @override
  State<ManagerChatListScreen> createState() => _ManagerChatListScreenState();
}

class _ManagerChatListScreenState extends State<ManagerChatListScreen> {
  final currentUser = FirebaseAuth.instance.currentUser;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(
      //   title: const Text('Messages'),
      //   backgroundColor: Colors.blue,
      // ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('messages')
            .where('type', isEqualTo: 'encryptedDocument')
            .where('participants', arrayContains: currentUser?.uid)
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, messageSnapshot) {
          if (messageSnapshot.hasError) {
            return Center(child: Text('Error: ${messageSnapshot.error}'));
          }

          if (messageSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final messages = messageSnapshot.data?.docs ?? [];

          if (messages.isEmpty) {
            return const Center(
              child: Text(
                'No encrypted documents shared yet',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          // Get unique user IDs and their latest messages
          final Map<String, DocumentSnapshot> latestMessagesByUser = {};
          for (var message in messages) {
            final data = message.data() as Map<String, dynamic>;
            final otherUserId = data['senderId'] == currentUser?.uid
                ? data['receiverId']
                : data['senderId'];

            // Only store the first (latest) message for each user
            if (!latestMessagesByUser.containsKey(otherUserId)) {
              latestMessagesByUser[otherUserId] = message;
            }
          }

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where(FieldPath.documentId,
                    whereIn: latestMessagesByUser.keys.toList())
                .snapshots(),
            builder: (context, userSnapshot) {
              if (!userSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final userDocs = userSnapshot.data!.docs;
              final userMap = {
                for (var doc in userDocs)
                  doc.id: doc.data() as Map<String, dynamic>
              };

              final uniqueUsers = latestMessagesByUser.keys.toList();

              return ListView.builder(
                itemCount: uniqueUsers.length,
                itemBuilder: (context, index) {
                  final otherUserId = uniqueUsers[index];
                  final userData = userMap[otherUserId];
                  final messageDoc = latestMessagesByUser[otherUserId]!;
                  final messageData = messageDoc.data() as Map<String, dynamic>;

                  if (userData == null) return const SizedBox.shrink();

                  final isRead = messageData['isRead'] ?? false;
                  final timestamp = messageData['timestamp'] as Timestamp?;

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue,
                      child: Icon(
                        userData['role'] == 'worker'
                            ? Icons.work
                            : Icons.person,
                        color: Colors.white,
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(userData['username'] ?? 'Unknown User'),
                        ),
                        if (timestamp != null)
                          Text(
                            _formatTimestamp(timestamp),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                      ],
                    ),
                    subtitle: Row(
                      children: [
                        const Icon(Icons.file_present, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            messageData['fileName'] ?? 'Document shared',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isRead &&
                            messageData['receiverId'] == currentUser?.uid)
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                            ),
                          ),
                        const SizedBox(width: 8),
                        const Icon(Icons.lock, size: 16, color: Colors.grey),
                      ],
                    ),
                    onTap: () => _openMessageDetails(
                      context,
                      otherUserId,
                      userData['username'] ?? 'Unknown User',
                      messageData,
                      messageDoc.id,
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    final now = DateTime.now();
    final date = timestamp.toDate();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  void _openMessageDetails(
    BuildContext context,
    String otherUserId,
    String otherUserName,
    Map<String, dynamic> messageData,
    String messageId,
  ) {
    // Navigate to chat screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ManagerChatScreen(
          currentUserId: currentUser!.uid,
          otherUserId: otherUserId,
          otherUserName: otherUserName,
          initialMessage: messageData,
        ),
      ),
    );

    // Mark message as read if needed
    if (!messageData['isRead'] &&
        messageData['receiverId'] == currentUser?.uid) {
      FirebaseFirestore.instance
          .collection('messages')
          .doc(messageId)
          .update({'isRead': true});
    }
  }
}
