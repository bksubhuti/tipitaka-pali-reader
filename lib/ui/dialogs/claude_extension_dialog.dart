import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:tipitaka_pali/services/claude_share.dart';
import 'package:url_launcher/url_launcher.dart';

/// A hidden way to add the TPR Research extension to Claude Desktop: typing
/// "skill" in the script converter. It makes a TPR folder in the reader's
/// home folder, where Claude saves its papers and reports, puts the extension
/// there and opens it, so Claude Desktop shows its own install dialog.
///
/// On the Mac it also puts a copy of the books there (and keeps it current,
/// see [ClaudeShare]): macOS does not let Claude read the sandboxed app's own
/// files. On Windows Claude reads them where they are.
class ClaudeExtensionDialog {
  static const trigger = 'skill';
  static const _url =
      'https://github.com/bksubhuti/tpr_downloads/releases/download/packages/tpr-research.mcpb';

  /// Claude Desktop runs only on macOS and Windows.
  static bool get available => Platform.isMacOS || Platform.isWindows;

  static Future<void> show(BuildContext context) async {
    final install = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 480),
        title: const Text('TPR Research for Claude'),
        content: SingleChildScrollView(
          child: Text(
            'Adds TPR Research to the Claude Desktop app. Claude can then '
            'read the books in this TPR, and make research papers with Pāḷi '
            'quotes, reading reports, vocabulary reviews of the words you '
            'looked up, and suttas exported with their translation.\n\n'
            'It needs the Claude Desktop app. It works with a free Claude '
            'account; a paid plan (Pro, Max, Team or Enterprise) gives more '
            'room for long papers. TPR\'s files are only read, never '
            'changed. Papers are saved in a TPR folder in your home '
            'folder.\n\n'
            '${Platform.isMacOS ? 'TPR will create a folder named TPR in your '
                'home folder, with a copy of its books for Claude (it takes no '
                'extra space). macOS opens your home folder next: click '
                'Create.\n\n' : 'TPR will create a folder named TPR in your home '
                'folder.\n\n'}'
            'Claude will show a red warning that the extension can access '
            'your computer. Every extension of this kind shows it.\n\n'
            'To remove it later: Claude › Settings › Extensions.',
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Get Claude Desktop'),
            onPressed: () => launchUrl(Uri.parse('https://claude.ai/download'),
                mode: LaunchMode.externalApplication),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Install'),
          ),
        ],
      ),
    );
    if (install != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    void say(String text) => messenger.showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 6)));
    try {
      final tpr = await _tprFolder(say);
      if (tpr == null) return;
      if (Platform.isMacOS) {
        if (!context.mounted) return;
        await _whileBusy(context, 'Copying the books for Claude…', () async {
          await ClaudeShare.remember(tpr);
          await ClaudeShare.refresh(books: true);
        });
        if (!File(p.join(tpr, 'db', 'tipitaka_pali.db')).existsSync()) {
          say('TPR is still setting up its search. The books will be copied '
              'for Claude when it is done.');
        }
      }
      final response = await http.get(Uri.parse(_url));
      if (response.statusCode != 200) {
        say('Could not download the extension (${response.statusCode}).');
        return;
      }
      final file = File(p.join(tpr, 'tpr-research.mcpb'));
      await file.writeAsBytes(response.bodyBytes, flush: true);
      if (!await launchUrl(Uri.file(file.path))) {
        say('Saved in $tpr. Open tpr-research.mcpb to install it.');
        return;
      }
      if (context.mounted) await _howToUse(context);
    } catch (e) {
      say('Could not install the extension: $e');
    }
  }

  /// ~/TPR, made if needed. The Mac app is sandboxed: it may write only where
  /// the reader chooses, so they pick their home folder once.
  static Future<String?> _tprFolder(void Function(String) say) async {
    if (Platform.isWindows) {
      final dir = Directory(p.join(Platform.environment['USERPROFILE'] ?? '', 'TPR'));
      await dir.create(recursive: true);
      return dir.path;
    }
    final home = ClaudeShare.realHome;
    final picked = await ClaudeShare.pickFolder(
      directory: home,
      button: 'Create',
      message: 'TPR will create a TPR folder here, with a copy of its books for Claude.',
    );
    if (picked == null) return null;
    if (p.normalize(picked) != p.normalize(home)) {
      say('Please choose your home folder, ${p.basename(home)}, which holds '
          'Documents and Downloads.');
      return null;
    }
    final dir = Directory(p.join(home, 'TPR'));
    await dir.create(recursive: true);
    return dir.path;
  }

  /// Shown once Claude Desktop has the extension to install: readers did not
  /// know they could just ask, or where its ready-made prompts are.
  static Future<void> _howToUse(BuildContext context) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          constraints: const BoxConstraints(maxWidth: 480),
          title: const Text('How to use it'),
          content: const SingleChildScrollView(
            child: Text(
              'Claude Desktop now asks you to install TPR Research: click '
              'Install.\n\n'
              'The first time Claude uses each TPR tool (about ten: '
              'search, quote, show and so on) it asks your permission. '
              'Choose "Always allow" each time; after the first few papers '
              'it stops asking.\n\n'
              'Then start a new chat and just ask, with "TPR" in the '
              'question, for example:\n'
              '• Using TPR, where do the suttas compare the mind to a '
              'monkey? Make a paper with quotes.\n'
              '• Make my TPR vocabulary review.\n'
              '• Export MN 10 from TPR with the English.\n\n'
              'Ready-made papers and reports are also under the + button '
              'in Claude: + › TPR Research.\n\n'
              'Papers are saved as PDF in the TPR folder in your home '
              'folder.',
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );

  static Future<void> _whileBusy(
      BuildContext context, String message, Future<void> Function() work) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 480),
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          Expanded(child: Text(message)),
        ]),
      ),
    );
    try {
      await work();
    } finally {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
