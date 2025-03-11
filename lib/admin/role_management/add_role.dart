import 'package:flutter/material.dart';

class AddRole extends StatelessWidget {
  const AddRole({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Role Name',
                  ),
                ),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Role Name',
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 10,
            ),
            ElevatedButton(
              onPressed: () {
                print(
                  'Role added',
                );
              },
              child: const Text('Add Role'),
            ),
          ],
        ),
      ),
    );
  }
}
