/*import 'dart:io';

import 'package:epubx/epubx.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:tipitaka_pali/services/epub_import_service.dart';

class BookImportView extends StatefulWidget {
  const BookImportView({super.key});

  @override
  State<BookImportView> createState() => _BookImportViewState();
}

class _BookImportViewState extends State<BookImportView> {
  String? _filePath;
  String? _statusMessage;

  Future<void> _pickEpubFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'],
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _filePath = result.files.single.path;
        _statusMessage = 'EPUB file selected. Ready to import.';
      });

      final EpubImportService epubService = EpubImportService();

      try {
        await epubService.importFile(_filePath!);
        setState(() {
          _statusMessage = '✅ Import successful!';
        });
      } catch (e) {
        setState(() {
          _statusMessage = '❌ Import failed: $e';
        });
      }
    } else {
      setState(() {
        _statusMessage = 'No file selected.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.importEpub), // Add this key to localization
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(loc.selectAnEpubFileToImport),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.folder_open),
              label: Text(loc.selectFile),
              onPressed: _pickEpubFile,
            ),
            const SizedBox(height: 24),
            if (_filePath != null) Text('📄 $_filePath'),
            if (_statusMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Text(
                  _statusMessage!,
                  style: TextStyle(
                    color: _statusMessage!.contains('Ready')
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
*/
