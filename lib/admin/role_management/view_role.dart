import 'package:flutter/material.dart';

class ViewRole extends StatelessWidget {
  const ViewRole({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        ListTile(title: Text('Role 1')),
        ListTile(title: Text('Role 2')),
        ListTile(title: Text('Role 3')),
      ],
    );
  }
}
