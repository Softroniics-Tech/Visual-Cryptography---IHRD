import 'package:encrypta/admin/role_management/add_role.dart';
import 'package:encrypta/admin/role_management/view_role.dart';
import 'package:flutter/material.dart';

class RoleManagementPage extends StatefulWidget {
  const RoleManagementPage({super.key});

  @override
  State<RoleManagementPage> createState() => _RoleManagementPageState();
}

class _RoleManagementPageState extends State<RoleManagementPage> {
  // This variable tracks which view is currently selected: 0 for List Roles, 1 for Add Role
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title for the Role Management page
            Text(
              'Role Management',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
            ),
            const SizedBox(
              height: 20,
            ), // Space between title and toggle buttons
            // Toggle buttons to switch between List Roles and Add Role
            ToggleButtons(
              borderRadius: BorderRadius.circular(5),
              selectedColor: Colors.black,
              fillColor: Colors.grey,
              isSelected: [
                selectedIndex == 0,
                selectedIndex == 1,
              ], // Highlight selected button
              onPressed: (int index) {
                setState(() {
                  selectedIndex = index; // Update the selected index
                });
              },
              children: const [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text('View Roles'), // Button for listing roles
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text('Add Role'), // Button for adding a role
                ),
              ],
            ),
            const SizedBox(
              height: 20,
            ),
            Expanded(child: buildView()),
          ],
        ),
      ),
    );
  }

  Widget buildView() {
    if (selectedIndex == 0) {
      return AddRole();
    } else {
      return ViewRole();
    }
  }
}
