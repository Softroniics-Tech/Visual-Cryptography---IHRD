import 'package:encrypta_completed/view/auth/login_reisgter.dart';
import 'package:encrypta_completed/view/screens/on_start_page/custom_navbar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyA8CN3FkOVGO-0NNVTUpXgKbMqhakTU8PI",
      appId: "1:900980711359:android:fa17e5bdb6a5ca5823cb0a",
      messagingSenderId: "900980711359",
      projectId: "clone-insta-1c836",
      storageBucket: "clone-insta-1c836.appspot.com",
    ),
  );

  // For release builds
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.playIntegrity,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Encrypta',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: StreamBuilder(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return CustomNavBar();
            } else {
              return LoginPage();
            }
          },
        ));
  }
}
