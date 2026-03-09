import 'package:flutter/material.dart';
import 'package:icloud_storage_example/utils.dart';
import 'package:icloud_storage_plus/icloud_storage.dart';

/// ListContents example widget.
class ListContents extends StatefulWidget {
  /// Create a new [ListContents] widget.
  const ListContents({required this.containerId, super.key});

  /// The iCloud container ID.
  final String containerId;

  @override
  State<ListContents> createState() => _ListContentsState();
}

class _ListContentsState extends State<ListContents> {
  final _relativePathController = TextEditingController();

  List<ContainerItem> _items = [];
  String? _error;
  bool _loading = false;

  Future<void> _handleListContents() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final relativePath = _relativePathController.text.trim();
      final items = await ICloudStorage.listContents(
        containerId: widget.containerId,
        relativePath: relativePath.isEmpty ? null : relativePath,
      );

      setState(() {
        _items = items;
        _loading = false;
      });
    } on Exception catch (ex) {
      setState(() {
        _error = getErrorMessage(ex);
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _relativePathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('List Contents')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _relativePathController,
                decoration: const InputDecoration(
                  labelText: 'relativePath (optional)',
                  hintText: 'Documents/',
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loading ? null : _handleListContents,
                child: Text(_loading ? 'LOADING...' : 'LIST CONTENTS'),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              Expanded(
                child: ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return ListTile(
                      leading: Icon(
                        item.isDirectory
                            ? Icons.folder
                            : Icons.insert_drive_file,
                      ),
                      title: Text(item.relativePath),
                      subtitle: Text(
                        [
                          if (item.downloadStatus != null)
                            'status: ${item.downloadStatus!.name}',
                          if (item.isDownloading) 'downloading',
                          if (item.isUploading) 'uploading',
                          if (item.isUploaded) 'uploaded',
                          if (item.hasUnresolvedConflicts) 'CONFLICTS',
                        ].join(' · '),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
