import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
// Make sure this points to where you saved the new service file
import 'package:tipitaka_pali/services/html_import_service.dart';

class BookImportView extends StatefulWidget {
  const BookImportView({super.key});

  @override
  State<BookImportView> createState() => _BookImportViewState();
}

class _BookImportViewState extends State<BookImportView> {
  String? _filePath;
  String _statusMessage = '';
  bool _isImporting = false; // Add loading state

  Future<void> _pickHtmlFile() async {
    // Reset state
    setState(() {
      _statusMessage = '';
      _isImporting = false;
    });

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['html', 'htm'], // Changed from epub
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;

      setState(() {
        _filePath = path;
        _isImporting = true;
        _statusMessage = 'Importing ${path.split('/').last}...';
      });

      final HtmlImportService htmlService = HtmlImportService();

      try {
        // Run the import
        await htmlService.importHtmlFile(path);

        if (mounted) {
          setState(() {
            _isImporting = false;
            _statusMessage = '✅ Import successful!';
          });

          // Optional: Show a snackbar or go back
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Book imported successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isImporting = false;
            _statusMessage = '❌ Import failed: $e';
          });
        }
      }
    } else {
      setState(() {
        _statusMessage = 'No file selected.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Fallback if l10n keys are missing
    final loc = AppLocalizations.of(context);
    final title = loc?.importEpub ?? 'Import eBook';
    final selectMsg =
        loc?.selectAnHtmlFileToImport ?? 'Select an HTML file to import';
    final selectBtn = loc?.selectFile ?? 'Select File';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(selectMsg, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 16),

            // Import Button
            ElevatedButton.icon(
              icon:
                  const Icon(Icons.description), // Changed icon to generic doc
              label: Text(selectBtn),
              onPressed: _isImporting
                  ? null
                  : _pickHtmlFile, // Disable while importing
            ),

            const SizedBox(height: 24),

            // Loading Indicator
            if (_isImporting)
              const Padding(
                padding: EdgeInsets.only(bottom: 20.0),
                child: LinearProgressIndicator(),
              ),

            // File Path Display
            if (_filePath != null)
              Text(
                '📄 ...${_filePath!.split(Platform.pathSeparator).last}',
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),

            // Status Message
            if (_statusMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Text(
                  _statusMessage,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _statusMessage.contains('success')
                        ? Colors.green
                        : _statusMessage.contains('failed')
                            ? Colors.red
                            : Colors.blue,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
