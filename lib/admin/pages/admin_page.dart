import 'package:flutter/material.dart';

import '../client_management_page.dart';
import '../role_management/role_management_page.dart'; // Import the new role management page
import '../user_management_page.dart';
import '../work_management.dart/work_management_page.dart';
import 'activity_logs_page.dart'; // Assuming you have this page

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  Widget? _selectedPage; // Variable to hold the currently selected page
  String? _selectedTile; // Tracks the selected tile
  String? _expandedTile; // Variable to hold the currently expanded tile
  final bool _isAddingRole = false; // Track if we are adding a role

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Encrypta',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.grey[300],
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.circle_notifications),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.settings_rounded),
          ),
          const Padding(
            padding: EdgeInsets.only(right: 10),
            child: CircleAvatar(backgroundColor: Colors.grey),
          ),
          const Text(
            'Admin Name',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.file_open_rounded, size: 15),
          ),
        ],
      ),
      body: Row(
        children: [
          // Left side: Management options
          Container(
            color: Colors.grey[300],
            width: 300,
            padding: const EdgeInsets.all(8.0),
            child: ListView(
              children: [
                _buildListTile('Dashboard', const UserManagementPage()),
                _buildExpansionTile(
                  title: 'Administration',
                  icon: Icons.person,
                  children: [
                    _buildListTile(
                      'Role Management',
                      const RoleManagementPage(),
                    ),
                    _buildListTile(
                      'User Management',
                      const UserManagementPage(),
                    ),
                    _buildListTile(
                      'Client Management',
                      const UserManagementPage(),
                    ),
                  ],
                ),
                _buildExpansionTile(
                  title: 'Work Management',
                  icon: Icons.circle_notifications,
                  children: [
                    _buildListTile('Add Work', const ClientManagementPage()),
                    _buildListTile('View Work', const ClientManagementPage()),
                    _buildListTile(
                      'Work Approval',
                      const ClientManagementPage(),
                    ),
                    _buildListTile('Assign Work', const ClientManagementPage()),
                  ],
                ),
                _buildExpansionTile(
                  title: 'Client Management',
                  icon: Icons.work,
                  children: [
                    _buildListTile('New Works', const WorkManagementPage()),
                    _buildListTile('Confirm Work', const WorkManagementPage()),
                    _buildListTile(
                      'Work Completion Status',
                      const WorkManagementPage(),
                    ),
                  ],
                ),
                _buildExpansionTile(
                  title: 'Activity Logs',
                  icon: Icons.local_activity_rounded,
                  children: [
                    _buildListTile('View Logs', const ActivityLogsPage()),
                    _buildListTile('Export Logs', const ActivityLogsPage()),
                  ],
                ),
                _buildExpansionTile(
                  title: 'Settings',
                  icon: Icons.settings,
                  children: [
                    _buildListTile('Profile', const ActivityLogsPage()),
                    _buildListTile('FAQ', const ActivityLogsPage()),
                  ],
                ),
              ],
            ),
          ),
          // Right side: Display selected page or add role form
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16.0),
              child: _isAddingRole
                  ? _buildAddRoleForm() // Show add role form
                  : _selectedPage ??
                      Center(
                        child: const Text('Select a management option'),
                      ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpansionTile({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return ExpansionTile(
      leading: Icon(icon),
      shape: const RoundedRectangleBorder(side: BorderSide.none),
      title: Text(title),
      childrenPadding: EdgeInsets.zero,
      initiallyExpanded: _expandedTile == title,
      onExpansionChanged: (isExpanded) {
        setState(() {
          _expandedTile = isExpanded ? title : null; // Collapse other tiles
        });
      },
      children: children,
    );
  }

  Widget _buildAddRoleForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'Role Name'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                // Handle role addition logic here
                print('Role added'); // Replace with actual logic
              },
              child: const Text('Add Role'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListTile(String title, Widget page) {
    return Container(
      decoration: BoxDecoration(
        color: _selectedTile == title
            ? Colors.grey[400]
            : Colors.transparent, // Change color if selected
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        title: Text(title),
        onTap: () {
          setState(() {
            _selectedPage = page; // Set the selected page
            _selectedTile = title; // Set the selected tile
          });
        },
      ),
    );
  }
}
