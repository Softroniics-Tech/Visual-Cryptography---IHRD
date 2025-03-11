import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypta/admin/pages/admin_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  bool isRegister = false;

  final auth = FirebaseAuth.instance;
  final firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    double sWidth = MediaQuery.of(context).size.width;
    double sHeight = MediaQuery.of(context).size.height;
    double squareSize =
        sWidth > 900 ? sWidth * 0.3 : sWidth * 0.8; // Ensures a square

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/bg.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (sWidth > 900) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildSidePanel(squareSize),
                          _buildAuthForm(squareSize),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          _buildSidePanel(squareSize),
                          const SizedBox(height: 10),
                          _buildAuthForm(squareSize),
                        ],
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidePanel(double size) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: Colors.blueGrey[300],
        // borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset('assets/encryption.png', width: size * 0.5),
          const SizedBox(height: 10),
          const Text(
            'Encrypta',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthForm(double size) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: Colors.deepPurpleAccent,
        // borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isRegister ? 'ADMIN REGISTER' : 'ADMIN LOGIN',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              Column(
                children: [
                  if (isRegister) ...[
                    _buildTextField(
                      controller: usernameController,
                      hintText: 'Username',
                      isPassword: true,
                    ),
                    const SizedBox(height: 10),
                  ],
                  _buildTextField(
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter email';
                        }
                        if (!RegExp(
                                r"^[a-zA-Z0-9+_.-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]+")
                            .hasMatch(value)) {
                          return 'Please enter a valid email';
                        }
                        return '';
                      },
                      controller: emailController,
                      hintText: 'Enter Email',
                      isPassword: false),
                  const SizedBox(height: 10),
                  _buildTextField(
                      controller: passwordController,
                      hintText: 'Enter Password',
                      isPassword: true),
                  if (isRegister) ...[
                    const SizedBox(height: 10),
                    _buildTextField(
                        controller: confirmPasswordController,
                        hintText: 'Confirm Password',
                        isPassword: true),
                  ],
                  const SizedBox(height: 10),
                  if (!isRegister)
                    Align(
                      alignment: Alignment.centerRight,
                      child: InkWell(
                        onTap: () {},
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
              MaterialButton(
                height: 45,
                minWidth: 140,
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    switchLoginReg();
                  }
                },
                color: Colors.grey,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  isRegister ? 'REGISTER' : 'LOGIN',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              InkWell(
                onTap: () {
                  setState(() {
                    isRegister = !isRegister;
                  });
                },
                child: Text(
                  isRegister
                      ? 'Already have an account? Login'
                      : 'Don\'t have an account? Register',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
      {TextEditingController? controller,
      String? hintText,
      final bool? isPassword,
      String Function(String?)? validator}) {
    return TextFormField(
        controller: controller,
        decoration: InputDecoration(
          fillColor: Colors.black26,
          filled: true,
          hintText: hintText,
          hintStyle: TextStyle(color: Colors.grey[200]),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: BorderSide.none,
          ),
        ),
        obscureText: isPassword!,
        validator: validator);
  }

  void switchLoginReg() async {
    if (isRegister) {
      try {
        await auth.createUserWithEmailAndPassword(
            email: emailController.text, password: passwordController.text);
        await firestore
            .collection('administration')
            .doc(auth.currentUser?.uid)
            .collection('admin')
            .add({
          'username': usernameController.text,
          'email': emailController.text,
          'timestamp': Timestamp.now()
        });
        setState(() {
          isRegister = false;
        });
      } catch (e) {
        showSnack(context, msg: 'Something wrong...! $e');
      }
    } else {
      try {
        await auth.signInWithEmailAndPassword(
            email: emailController.text, password: passwordController.text);
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => AdminPage(),
            ),
            (route) => false);
      } catch (e) {
        showSnack(context, msg: 'Something wrong...! $e');
      }
    }
  }
}

void showSnack(BuildContext context, {String? msg}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.all(20),
      content: Text('$msg'),
    ),
  );
}
