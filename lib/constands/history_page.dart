import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<DecryptedFile> _decryptedFiles = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getStringList('decryption_history') ?? [];

      if (mounted) {
        // Check if widget is still mounted
        setState(() {
          _decryptedFiles = history
              .map((item) => DecryptedFile.fromJson(json.decode(item)))
              .toList();
        });
      }
    } catch (e) {
      log('Error loading history: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading history: $e')),
        );
      }
    }
  }

  Future<void> _downloadFile(DecryptedFile file) async {
    try {
      final directory = await getExternalStorageDirectory();
      final path = '${directory!.path}/DecryptedDocuments';
      await Directory(path).create(recursive: true);

      final filePath = '$path/${file.fileName}';
      final fileBytes = base64Decode(file.fileData);

      await File(filePath).writeAsBytes(fileBytes);
      await Share.shareXFiles([XFile(filePath)]);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File downloaded successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error downloading file: $e')),
      );
    }
  }

  Future<void> _deleteHistoryItem(int index) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getStringList('decryption_history') ?? [];

      if (index < history.length) {
        history.removeAt(index);
        await prefs.setStringList('decryption_history', history);

        setState(() {
          _decryptedFiles.removeAt(index);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Item deleted from history')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting item: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Decryption History'),
        automaticallyImplyLeading: false,
        actions: [
          if (_decryptedFiles.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Clear History'),
                    content: const Text('Delete all history items?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete All'),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('decryption_history');
                  setState(() {
                    _decryptedFiles.clear();
                  });
                }
              },
            ),
        ],
      ),
      body: _decryptedFiles.isEmpty
          ? const Center(child: Text('No decryption history'))
          : ListView.builder(
              itemCount: _decryptedFiles.length,
              itemBuilder: (context, index) {
                final file = _decryptedFiles[index];
                return Dismissible(
                  key: Key(file.timestamp),
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => _deleteHistoryItem(index),
                  child: ListTile(
                    leading: const Icon(Icons.file_present),
                    title: Text(file.fileName),
                    subtitle: Text('Decrypted on: ${file.timestamp}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.download),
                          onPressed: () => _downloadFile(file),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _deleteHistoryItem(index),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class DecryptedFile {
  final String fileName;
  final String fileData;
  final String timestamp;

  DecryptedFile({
    required this.fileName,
    required this.fileData,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'fileData': fileData,
        'timestamp': timestamp,
      };

  factory DecryptedFile.fromJson(Map<String, dynamic> json) => DecryptedFile(
        fileName: json['fileName'],
        fileData: json['fileData'],
        timestamp: json['timestamp'],
      );
}
