import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypta/worker/screens/chat_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Messages')),
        body: const Center(child: Text('Please log in to see messages')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chatRooms')
            .where('participants', arrayContains: currentUser.uid)
            .snapshots(),
        builder: (context, chatSnapshot) {
          if (chatSnapshot.hasError) {
            return Center(child: Text('Error: ${chatSnapshot.error}'));
          }

          if (chatSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final chats = chatSnapshot.data?.docs ?? [];

          if (chats.isEmpty) {
            return const Center(child: Text('No messages yet'));
          }

          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final chatData = chats[index].data() as Map<String, dynamic>;
              final participants =
                  List<String>.from(chatData['participants'] ?? []);
              final otherUserId = participants.firstWhere(
                (id) => id != currentUser.uid,
                orElse: () => '',
              );

              if (otherUserId.isEmpty) return const SizedBox();

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(otherUserId)
                    .get(),
                builder: (context, userSnapshot) {
                  if (!userSnapshot.hasData) {
                    return const ListTile(
                      leading: CircleAvatar(child: Icon(Icons.person)),
                      title: Text('Loading...'),
                    );
                  }

                  final userData =
                      userSnapshot.data!.data() as Map<String, dynamic>;
                  final userName = userData['username'] ?? 'Unknown User';
                  final lastMessage = chatData['lastMessage'] ?? 'No messages';
                  final lastMessageTime =
                      chatData['lastMessageTime'] as Timestamp?;

                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(userName),
                    subtitle: Text(lastMessage),
                    trailing: lastMessageTime != null
                        ? Text(_formatTimestamp(lastMessageTime))
                        : null,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => UserChatScreen(
                            chatRoomId: chats[index].id,
                            currentUserId: currentUser.uid,
                            managerId: otherUserId,
                            managerName: userName,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showManagerList(context, currentUser.uid),
        child: const Icon(Icons.message),
      ),
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    final now = DateTime.now();
    final date = timestamp.toDate();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  void _showManagerList(BuildContext context, String currentUserId) {
    showModalBottomSheet(
      context: context,
      builder: (context) => StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'manager')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final managers = snapshot.data!.docs;

          return ListView.builder(
            itemCount: managers.length,
            itemBuilder: (context, index) {
              final manager = managers[index].data() as Map<String, dynamic>;
              final managerId = managers[index].id;

              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(manager['name'] ?? 'Unknown Manager'),
                subtitle: Text(manager['email'] ?? ''),
                onTap: () async {
                  String chatRoomId =
                      _generateChatRoomId(managerId, currentUserId);
                  Navigator.pop(context); // Close bottom sheet

                  final chatRoomRef = FirebaseFirestore.instance
                      .collection('chatRooms')
                      .doc(chatRoomId);

                  if (!(await chatRoomRef.get()).exists) {
                    await chatRoomRef.set({
                      'participants': [managerId, currentUserId],
                      'lastMessage': '',
                      'lastMessageTime': FieldValue.serverTimestamp(),
                    });
                  }

                  if (context.mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UserChatScreen(
                          chatRoomId: chatRoomId,
                          currentUserId: currentUserId,
                          managerId: managerId,
                          managerName: manager['name'] ?? 'Unknown Manager',
                        ),
                      ),
                    );
                  }
                },
              );
            },
          );
        },
      ),
    );
  }

  String _generateChatRoomId(String user1, String user2) {
    List<String> ids = [user1, user2]..sort();
    return 'chat_${ids[0]}_${ids[1]}';
  }
}
