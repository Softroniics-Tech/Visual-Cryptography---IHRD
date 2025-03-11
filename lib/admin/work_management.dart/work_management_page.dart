import 'package:flutter/material.dart';

class WorkManagementPage extends StatelessWidget {
  const WorkManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Work Management',style: TextStyle(fontSize: 20,fontWeight: FontWeight.bold),),
            
             
          ],
        ),
      ),
    );
  }
}
