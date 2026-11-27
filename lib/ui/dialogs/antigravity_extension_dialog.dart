import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:tipitaka_pali/services/claude_share.dart';
import 'package:tipitaka_pali/ui/dialogs/claude_extension_dialog.dart';
import 'package:tipitaka_pali/ui/dialogs/codex_extension_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

/// Adds TPR Research to Google Antigravity, as [CodexExtensionDialog] does
/// for Codex. It is the same server and download: TPR unpacks it into
/// ~/TPR/antigravity, puts the tpr-research skill in ~/.gemini/config/skills
/// and registers the server in ~/.gemini/config/mcp_config.json, which the
/// Antigravity app and its agy command both read.
///
/// Antigravity is an Electron app, so its own program runs the server as
/// Node (ELECTRON_RUN_AS_NODE; it has node:sqlite): nothing else to install.
class AntigravityExtensionDialog {
  /// Typed in the script converter: any of these opens this. Readers know
  /// Gemini, so TPR calls it "Gemini (Antigravity)".
  static const triggers = ['gemini', 'antigravity', 'agy'];
  static const _url =
      'https://github.com/bksubhuti/tpr_downloads/releases/download/packages/tpr-research-codex.zip';

  static bool get available => Platform.isMacOS || Platform.isWindows;

  /// Opens a new Antigravity chat with the question typed in
  /// (antigravity://open?prompt=…, Antigravity 2.29+). The question is also
  /// copied, for an older Antigravity that only opens. False if it did not
  /// open.
  static Future<bool> ask(String question) async {
    final prompt = 'Using TPR Research (the tpr-research tools), search my '
        'TPR books and answer: $question\n\nQuote the Pāḷi with its '
        'translation and TPR links.';
    await Clipboard.setData(ClipboardData(text: prompt));
    return _open('open?prompt=${Uri.encodeQueryComponent(prompt)}');
  }

  /// Opens antigravity://[link]. On Windows a link that starts Antigravity
  /// (even a bare antigravity://) opens two windows, the empty one in front;
  /// so when it is not running its program is started as from the Start
  /// menu, and the link follows once its window is up (an open Antigravity
  /// takes the link in its own window).
  static Future<bool> _open(String link) async {
    if (Platform.isWindows && !await _running()) {
      final exe = _windowsApps().firstWhereOrNull((e) => File(e).existsSync());
      if (exe != null) {
        await Process.start(exe, [], mode: ProcessStartMode.detached);
        for (var i = 0; i < 40 && !await _running(); i++) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
        // Running is not yet ready for links: give its window time to load.
        await Future.delayed(const Duration(seconds: 6));
      }
    }
    return launchUrl(Uri.parse('antigravity://$link'));
  }

  /// Where Antigravity's program is on Windows.
  static List<String> _windowsApps() => [
        p.join(Platform.environment['LOCALAPPDATA'] ?? '', 'Programs',
            'Antigravity', 'Antigravity.exe'),
        p.join(Platform.environment['ProgramFiles'] ?? r'C:\Program Files',
            'Antigravity', 'Antigravity.exe'),
      ];

  static Future<bool> _running() async {
    try {
      final r = await Process.run(
          'tasklist', ['/FI', 'IMAGENAME eq Antigravity.exe', '/NH']);
      return '${r.stdout}'.toLowerCase().contains('antigravity.exe');
    } catch (_) {
      return true; // cannot tell: just send the link
    }
  }

  static Future<void> show(BuildContext context) async {
    final install = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 480),
        title: const Text('TPR Research for Gemini'),
        content: SingleChildScrollView(
          child: Text(
            'Adds TPR Research to Gemini in Google Antigravity, Google\'s '
            'desktop app where Gemini can use tools on your computer. It can '
            'then read the '
            'books in this TPR, and make research papers with Pāḷi quotes, '
            'reading reports, vocabulary reviews of the words you looked '
            'up, and suttas exported with their translation.\n\n'
            'It needs the Antigravity app (Mac or Windows). Ordinary Gemini '
            'chats, on the web or a phone, cannot use TPR. '
            'TPR\'s files are only read, never changed. Papers are saved in '
            'a TPR folder in your home folder.\n\n'
            '${Platform.isMacOS ? 'TPR will create a folder named TPR in your '
                'home folder, with a copy of its books (it takes no extra '
                'space), and add TPR Research to Antigravity\'s settings. '
                'macOS opens your home folder next: click Create.\n\n' : 'TPR '
                'will create a folder named TPR in your home folder, with a '
                'copy of its books (about 1.5 GB), and add TPR Research to '
                'Antigravity\'s settings.\n\n'}'
            'Afterwards quit Antigravity and open it again.',
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Get Antigravity'),
            onPressed: () => launchUrl(Uri.parse('https://antigravity.google'),
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
      final tpr = await ClaudeExtensionDialog.tprFolder(say, app: 'Gemini');
      if (tpr == null) return;
      final home = p.dirname(tpr);
      // The same copy in ~/TPR/db as for Claude and Codex.
      if (!context.mounted) return;
      await ClaudeExtensionDialog.whileBusy(
          context, 'Copying the books for Gemini…', () async {
        await ClaudeShare.remember(tpr);
        await ClaudeShare.refresh(books: true);
      });
      if (!File(p.join(tpr, 'db', 'tipitaka_pali.db')).existsSync()) {
        say('TPR is still setting up its search. The books will be copied '
            'for Gemini when it is done.');
      }
      final runner = await _runner();
      if (runner == null) {
        say('Antigravity was not found. Install it, open it once, then '
            'press Set up again.');
        return;
      }
      final response = await http.get(Uri.parse(_url));
      if (response.statusCode != 200) {
        say('Could not download TPR Research (${response.statusCode}).');
        return;
      }
      final server = await CodexExtensionDialog.unpack(
          response.bodyBytes, p.join(tpr, 'antigravity'));
      final config = p.join(home, '.gemini', 'config');
      final skill = File(p.join(config, 'skills', 'tpr-research', 'SKILL.md'));
      await skill.parent.create(recursive: true);
      await File(p.join(tpr, 'antigravity', 'SKILL.md')).copy(skill.path);
      await _register(p.join(config, 'mcp_config.json'), server, runner);
      await CodexExtensionDialog.markSetUp(tpr, 'antigravity');
      say('TPR Research is added to Gemini (Antigravity). Quit Antigravity '
          'and open '
          'it again.');
      if (context.mounted) await _howToUse(context);
    } catch (e) {
      say('Could not set up TPR Research for Gemini: $e');
    }
  }

  /// What runs the server: Antigravity's own program as Node, else an
  /// installed Node; null when neither is found.
  static Future<String?> _runner() async {
    final home = Platform.environment['HOME'] ?? '';
    final apps = Platform.isMacOS
        ? [
            '/Applications/Antigravity.app/Contents/MacOS/Antigravity',
            p.join(home, 'Applications', 'Antigravity.app', 'Contents', 'MacOS',
                'Antigravity'),
          ]
        : _windowsApps();
    final app = apps.firstWhereOrNull((e) => File(e).existsSync());
    if (app != null) return app;
    // The Mac sandbox may not see /Applications: the usual place is still
    // the best guess there.
    if (Platform.isMacOS) return apps.first;
    return CodexExtensionDialog.findNode();
  }

  /// Adds (or replaces) tpr-research in mcp_config.json, keeping the other
  /// servers; the first change keeps a backup copy.
  static Future<void> _register(
      String path, String server, String runner) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final text = file.existsSync() ? await file.readAsString() : '';
    final backup = File('$path.before-tpr');
    if (text.trim().isNotEmpty && !backup.existsSync()) {
      await backup.writeAsString(text);
    }
    final config = text.trim().isEmpty
        ? <String, dynamic>{}
        : jsonDecode(text) as Map<String, dynamic>;
    final servers =
        (config['mcpServers'] as Map?)?.cast<String, dynamic>() ?? {};
    servers['tpr-research'] = {
      'command': runner,
      'args': [server],
      'env': {'ELECTRON_RUN_AS_NODE': '1', 'TPR_HOST': 'antigravity'},
    };
    config['mcpServers'] = servers;
    await file.writeAsString(
        const JsonEncoder.withIndent('    ').convert(config),
        flush: true);
  }

  static Future<void> _howToUse(BuildContext context) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          constraints: const BoxConstraints(maxWidth: 480),
          title: const Text('How to use it'),
          content: const SingleChildScrollView(
            child: Text(
              'TPR Research is added to Gemini in Antigravity. If Antigravity '
              'is open, '
              'quit it completely first, then open it again.\n\n'
              'Start a new chat and ask, with "TPR" in the question, for '
              'example:\n'
              '• Using TPR, run tpr_status and tell me what my TPR has.\n'
              '• Using TPR, where do the suttas compare the mind to a '
              'monkey? Make a paper with quotes.\n'
              '• Make my TPR vocabulary review.\n\n'
              'Or type your question in TPR\'s AI search and press '
              'Gemini.\n\n'
              'Antigravity may ask before it runs a TPR tool. Allow only TPR '
              'Research\'s own tools.\n\n'
              'Papers are saved as PDF in the TPR folder in your home '
              'folder.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _open('open?prompt='
                    '${Uri.encodeQueryComponent('Using TPR Research, run tpr_status and tell me what my TPR has.')}');
              },
              child: const Text('Open Antigravity'),
            ),
          ],
        ),
      );
}
