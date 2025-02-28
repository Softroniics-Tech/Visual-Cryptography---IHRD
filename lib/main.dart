import 'package:encrypta/worker/auth_user/login_page.dart';
import 'package:encrypta/worker/constands/nav_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SharedPreferences.getInstance();

  // Initialize Firebase first
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyA8CN3FkOVGO-0NNVTUpXgKbMqhakTU8PI",
      appId: "1:900980711359:android:fa17e5bdb6a5ca5823cb0a",
      messagingSenderId: "900980711359",
      projectId: "clone-insta-1c836",
      storageBucket: "clone-insta-1c836.appspot.com",
    ),
  );

  // Initialize Appwrite
  // Client client = Client();
  // client.setProject('67aed32f0005a368113a');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Document Cryptography',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: StreamBuilder(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return const CustomNavBar();
          }
          return const LoginPage();
        },
      ),
      // initialRoute: '/appScreenHome',
      // routes: {
      //   '/appScreenHome': (context) => const AppScreenHome(),
      //   '/': (context) => const AuthPage(),
      //   '/admin': (context) => const AdminPage(),
      //   '/user_management': (context) => const UserManagementPage(),
      //   '/client_management': (context) => const ClientManagementPage(),
      //   '/work_management': (context) => const WorkManagementPage(),
      //   '/activity_logs': (context) => const ActivityLogsPage(),
      // },
    );
  }
}

// Models
