import 'package:flutter/material.dart';

class ClientManagementPage extends StatelessWidget {
  const ClientManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {},
              child: const Text('Add New Client'),
            ),
          ],
        ),
      ),
    );
  }
}
