import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypta_completed/view/auth/login_reisgter.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfileScreen extends StatelessWidget {
  final User user;

  const ProfileScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        foregroundColor: Colors.white,
        title: const Text(
          'Profile',
        ),
        backgroundColor: const Color.fromARGB(255, 8, 82, 67),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text('Something went wrong');
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator();
              }

              final userData = snapshot.data?.data() as Map<String, dynamic>?;
              final username = userData?['username'] ?? 'Unknown';
              final role = userData?['role'] ?? 'Unknown';

              return Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(50),
                      color: Colors.grey[300],
                    ),
                    child: Text(
                      role,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  SizedBox(height: 20),
                  CircleAvatar(
                    backgroundColor: Colors.grey[300],
                    radius: 80,
                    child: user.photoURL != null
                        ? Image.network(
                            user.photoURL!,
                            fit: BoxFit.cover,
                          )
                        : Center(
                            child: Text(
                              username[0].toUpperCase(),
                              style: const TextStyle(fontSize: 50),
                            ),
                          ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: Icon(Icons.person_outline_rounded),
                    title: Text(
                      '${username ?? 'Unknown'}',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(
                    height: 8,
                    child: Divider(),
                  ),
                  ListTile(
                    leading: Icon(Icons.email_outlined),
                    title: Text(
                      user.email ?? 'Unknown',
                      style: const TextStyle(
                        fontSize: 18,
                      ),
                    ),
                  ),
                  Spacer(),
                  MaterialButton(
                    color: Colors.red,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                      Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                              builder: (context) => const LoginPage()),
                          (route) => false);
                    },
                    child: const Text('Sign Out',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
