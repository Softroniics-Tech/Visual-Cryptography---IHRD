import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypta/manager/manager_chat_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
      body: StreamBuilder(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final users = snapshot.data?.docs ?? [];
          final workers =
              users.where((doc) => doc.data()['role'] != 'manager').toList();

          if (workers.isEmpty) {
            return const Center(child: Text('No workers available'));
          }

          return ListView.builder(
            itemCount: workers.length,
            itemBuilder: (context, index) {
              final worker = workers[index].data();
              final workerId = workers[index].id;

              return ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.person),
                ),
                title: Text(worker['username'] ?? 'Unknown'),
                subtitle: Text(worker['email'] ?? ''),
                onTap: () => _startChat(context, workerId, worker['username']),
              );
            },
          );
        },
      ),
    );
  }

  void _startChat(
      BuildContext context, String workerId, String workerName) async {
    try {
      // Create or get existing chat room
      final chatRoomId = 'chat_${currentUser!.uid}_$workerId';
      final chatRoom = await FirebaseFirestore.instance
          .collection('chatRooms')
          .doc(chatRoomId)
          .get();

      if (!chatRoom.exists) {
        // Create new chat room
        await FirebaseFirestore.instance
            .collection('chatRooms')
            .doc(chatRoomId)
            .set({
          'participants': [currentUser!.uid, workerId],
          'lastMessage': '',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // Navigate to chat screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ManagerChatScreen(
            chatRoomId: chatRoomId,
            currentUserId: currentUser!.uid,
            otherUserId: workerId,
            otherUserName: workerName,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error starting chat: $e')),
      );
    }
  }
}
