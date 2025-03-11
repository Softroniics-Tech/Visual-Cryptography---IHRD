import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypta/manager/manager_chatlist_screen.dart';
import 'package:encrypta/manager/manager_screen.dart';
import 'package:encrypta/worker/constands/colors.dart';
import 'package:encrypta/worker/screens/chat_screen.dart';
import 'package:encrypta/worker/screens/history.dart';
import 'package:encrypta/worker/screens/profile_screen.dart';
import 'package:encrypta/worker/screens/user_home.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CustomNavBar extends StatefulWidget {
  const CustomNavBar({super.key});

  @override
  State<CustomNavBar> createState() => _CustomNavBarState();
}

class _CustomNavBarState extends State<CustomNavBar> {
  final String userId = FirebaseAuth.instance.currentUser?.uid ?? '';
  int currentIndex = 0;
  Map<String, dynamic>? userData;
  Map<String, dynamic>? managerData;
  String? chatRoomId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    try {
      await Future.wait([
        _fetchUserData(),
        _fetchManagerData(),
      ]);
    } catch (e) {
      print('Error initializing data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchUserData() async {
    try {
      if (userId.isEmpty) return;

      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (mounted && userDoc.exists) {
        setState(() {
          userData = userDoc.data() as Map<String, dynamic>;
        });
      }
    } catch (e) {
      print('Error fetching user data: $e');
    }
  }

  Future<void> _fetchManagerData() async {
    try {
      if (userId.isEmpty) return;

      QuerySnapshot managerQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'manager')
          .limit(1)
          .get();

      if (mounted && managerQuery.docs.isNotEmpty) {
        final manager = managerQuery.docs.first;
        final managerId = manager.id;

        setState(() {
          managerData = {
            ...manager.data() as Map<String, dynamic>,
            'uid': managerId,
          };
          chatRoomId = 'chat_${managerId}_$userId'.replaceAll(' ', '_');
        });

        await FirebaseFirestore.instance
            .collection('chatRooms')
            .doc(chatRoomId)
            .set({
          'participants': [managerId, userId],
          'lastMessage': '',
          'lastMessageTime': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      print('Error fetching manager data: $e');
    }
  }

  List<Widget> managerList = [
    const ManagerScreen(),
    const ManagerChatListScreen(),
    const HistoryPage()
  ];

  List<Widget> _getWorkerScreens() {
    if (_isLoading) {
      return List.generate(
          3,
          (_) => Center(
                  child: CircularProgressIndicator(
                backgroundColor: primaryColor,
                color: Colors.white,
              )));
    }

    return [
      const UserPage(),
      if (managerData != null && chatRoomId != null)
        UserChatScreen(
          chatRoomId: chatRoomId!,
          currentUserId: userId,
          managerId: managerData!['uid'] ?? '',
          managerName: managerData!['username'] ?? 'Manager',
        )
      else
        const Center(child: Text('Chat loading...')),
      const HistoryPage(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
            child: CircularProgressIndicator(
          backgroundColor: primaryColor,
          color: Colors.white,
        )),
      );
    }

    if (userId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Please log in again')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Encrypta'),
        backgroundColor: const Color.fromARGB(255, 8, 82, 67),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () {
              final user = FirebaseAuth.instance.currentUser;
              if (user != null && mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProfileScreen(user: user),
                  ),
                );
              }
            },
            icon: const Icon(Icons.person_2_outlined),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color.fromARGB(255, 8, 82, 67),
        selectedItemColor: const Color.fromRGBO(255, 255, 255, 1),
        unselectedItemColor: Colors.grey,
        onTap: (value) {
          if (mounted) {
            setState(() {
              currentIndex = value;
            });
          }
        },
        currentIndex: currentIndex,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
      body: userData?['role'] == 'manager'
          ? managerList[currentIndex]
          : _getWorkerScreens()[currentIndex],
    );
  }
}
