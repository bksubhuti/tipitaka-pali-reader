import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:tipitaka_pali/services/claude_share.dart';
import 'package:tipitaka_pali/ui/dialogs/claude_extension_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

/// Adds TPR Research to Codex (OpenAI's app and CLI), as
/// [ClaudeExtensionDialog] does for Claude Desktop. It is the same server:
/// TPR unpacks it into ~/TPR/codex, puts the tpr-research skill in
/// ~/.codex/skills and registers the server in ~/.codex/config.toml, which
/// the Codex app and the codex command both read. Codex is restarted to
/// pick it up.
///
/// The Codex app ships its own Node (with node:sqlite), so app users need
/// nothing more; the CLI alone needs Node from nodejs.org.
class CodexExtensionDialog {
  /// Typed in the script converter: either name opens this.
  static const triggers = ['codex', 'chatgpt'];
  static const _url =
      'https://github.com/bksubhuti/tpr_downloads/releases/download/packages/tpr-research-codex.zip';

  /// The Codex app runs on macOS and Windows, as Claude Desktop does.
  static bool get available => Platform.isMacOS || Platform.isWindows;

  /// Opens a new Codex chat with the question typed in, asking it to answer
  /// from the reader's TPR books. Codex reads `prompt` from this link.
  static Future<bool> ask(String question) {
    final prompt = 'Using TPR Research (the tpr-research tools), search my '
        'TPR books and answer: $question\n\nQuote the Pāḷi with its '
        'translation and TPR links.';
    return launchUrl(Uri.parse(
        'codex://threads/new?prompt=${Uri.encodeQueryComponent(prompt)}'));
  }

  static Future<void> show(BuildContext context) async {
    final install = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 480),
        title: const Text('TPR Research for ChatGPT'),
        content: SingleChildScrollView(
          child: Text(
            'Adds TPR Research to Codex, the part of the ChatGPT desktop app '
            'that can use tools on your computer. It can then read '
            'the books in this TPR, and make research papers with Pāḷi '
            'quotes, reading reports, vocabulary reviews of the words you '
            'looked up, and suttas exported with their translation.\n\n'
            'It needs the ChatGPT desktop app (Mac or Windows): open Codex '
            'in it. Ordinary ChatGPT chats, on the web or a phone, cannot use '
            'TPR. '
            'TPR\'s files are only read, never changed. Papers are saved in '
            'a TPR folder in your home folder.\n\n'
            '${Platform.isMacOS ? 'TPR will create a folder named TPR in your '
                'home folder, with a copy of its books for Codex (it takes no '
                'extra space), and add TPR Research to Codex\'s settings. '
                'macOS opens your home folder next: click Create.\n\n' : 'TPR '
                'will create a folder named TPR in your home folder, with a '
                'copy of its books for Codex (about 1.5 GB), and add TPR '
                'Research to Codex\'s settings.\n\n'}'
            'Afterwards quit ChatGPT and open it again.',
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Get ChatGPT'),
            onPressed: () => launchUrl(Uri.parse('https://chatgpt.com/codex'),
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
      // The server runs on Node. On Windows Codex does not bring one that
      // stays put (its Store folder changes with each update), so it must
      // be installed; say so before copying anything.
      final node = await findNode();
      if (node == null) {
        if (context.mounted) await _needNode(context);
        return;
      }
      final tpr = await ClaudeExtensionDialog.tprFolder(say, app: 'Codex');
      if (tpr == null) return;
      final home = p.dirname(tpr);
      // The books for Codex: the same copy in ~/TPR/db as for Claude.
      if (!context.mounted) return;
      await ClaudeExtensionDialog.whileBusy(
          context, 'Copying the books for Codex…', () async {
        await ClaudeShare.remember(tpr);
        await ClaudeShare.refresh(books: true);
      });
      if (!File(p.join(tpr, 'db', 'tipitaka_pali.db')).existsSync()) {
        say('TPR is still setting up its search. The books will be copied '
            'for Codex when it is done.');
      }
      final response = await http.get(Uri.parse(_url));
      if (response.statusCode != 200) {
        say('Could not download TPR Research (${response.statusCode}).');
        return;
      }
      final server = await unpack(response.bodyBytes, p.join(tpr, 'codex'));
      await _addSkill(home, p.join(tpr, 'codex', 'SKILL.md'));
      await _register(home, server, node);
      await markSetUp(tpr, 'codex');
      // Settings shows "Set up ✓" only once Codex has started the server, so
      // say plainly that it worked.
      say('TPR Research is added to ChatGPT (Codex). Quit ChatGPT and open '
          'it again.');
      if (context.mounted) await _howToUse(context);
    } catch (e) {
      say('Could not set up TPR Research for ChatGPT: $e');
    }
  }

  /// Unpacks the download into [dir] (replacing an older one) and returns
  /// the server's index.js. Antigravity's setup uses it too.
  static Future<String> unpack(List<int> zip, String dir) async {
    final folder = Directory(dir);
    if (folder.existsSync()) await folder.delete(recursive: true);
    for (final entry in ZipDecoder().decodeBytes(zip)) {
      if (!entry.isFile) continue;
      final out = File(p.join(dir, p.joinAll(entry.name.split('/'))));
      // A name must not lead outside the folder.
      if (!p.isWithin(dir, out.path)) continue;
      await out.parent.create(recursive: true);
      await out.writeAsBytes(entry.content as List<int>, flush: true);
    }
    return p.join(dir, 'server', 'index.js');
  }

  /// Writes the note the server writes each time Codex starts it, so the
  /// Codex button and "Set up ✓" show at once: unlike Claude Desktop, TPR
  /// itself did the install. The server keeps it current from then on.
  /// [host] is both the folder in ~/TPR and the note's name.
  static Future<void> markSetUp(String tpr, String host) async {
    var version = '';
    try {
      final manifest = jsonDecode(
          await File(p.join(tpr, host, 'manifest.json')).readAsString());
      version = '${(manifest as Map)['version'] ?? ''}';
    } catch (_) {}
    await File(p.join(tpr, '.tpr-research-$host')).writeAsString(jsonEncode({
      'version': version,
      'seen': DateTime.now().toUtc().toIso8601String()
    }));
  }

  /// The skill tells Codex to call the guide first and save every answer
  /// as a paper; Codex reads skills from ~/.codex/skills.
  static Future<void> _addSkill(String home, String skill) async {
    final to =
        File(p.join(home, '.codex', 'skills', 'tpr-research', 'SKILL.md'));
    await to.parent.create(recursive: true);
    await File(skill).copy(to.path);
  }

  /// Adds (or replaces) the tpr-research server in ~/.codex/config.toml.
  /// Other settings are kept; the first change keeps a backup copy.
  static Future<void> _register(String home, String server, String node) async {
    final file = File(p.join(home, '.codex', 'config.toml'));
    await file.parent.create(recursive: true);
    var text = file.existsSync() ? await file.readAsString() : '';
    final backup = File('${file.path}.before-tpr');
    if (text.isNotEmpty && !backup.existsSync()) {
      await backup.writeAsString(text);
    }
    text = withoutOurServer(text).trimRight();
    // TOML '…' strings take Windows paths as they are.
    final block = '''
# TPR Research, added by Tipitaka Pali Reader (Settings › AI › ChatGPT (Codex) setup).
[mcp_servers.tpr-research]
command = '$node'
args = ['$server']
startup_timeout_sec = 60

[mcp_servers.tpr-research.env]
TPR_HOST = 'codex'
''';
    await file.writeAsString(text.isEmpty ? block : '$text\n\n$block',
        flush: true);
  }

  /// [text] without the tpr-research tables (and our comment above them),
  /// so setting up again replaces them.
  @visibleForTesting
  static String withoutOurServer(String text) {
    final out = <String>[];
    var skipping = false;
    for (final line in text.split('\n')) {
      final t = line.trim();
      if (t.startsWith('[')) {
        skipping = RegExp(r'^\[\s*mcp_servers\.("?)tpr-research\1\s*(\]|\.)')
            .hasMatch(t);
      }
      if (t.startsWith('# TPR Research, added by Tipitaka Pali Reader')) {
        continue;
      }
      if (!skipping) out.add(line);
    }
    return out.join('\n');
  }

  /// The Node that runs the server: the Codex app's own when it is there
  /// (it has node:sqlite), else an installed one; null on Windows when
  /// none is installed.
  static Future<String?> findNode() async {
    // Windows: the Codex app's own Node, in its runtime package. Its folder
    // name holds the version, so it is asked for, not written in here
    // (ordinary apps may not list the WindowsApps folder).
    if (Platform.isWindows) {
      final runtime = await _codexRuntimeNode();
      if (runtime != null) return runtime;
    }
    final candidates = Platform.isMacOS
        ? [
            '/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node',
            '/Applications/Codex.app/Contents/Resources/cua_node/bin/node',
            '/opt/homebrew/bin/node',
            '/usr/local/bin/node',
          ]
        : [
            p.join(Platform.environment['ProgramFiles'] ?? r'C:\Program Files',
                'nodejs', 'node.exe'),
            p.join(Platform.environment['LOCALAPPDATA'] ?? '', 'Programs',
                'nodejs', 'node.exe'),
            // Any other install (nvm, Scoop…) that is on the PATH; the full
            // path is written, as the Codex app may not have that PATH.
            for (final dir in (Platform.environment['PATH'] ?? '').split(';'))
              if (dir.trim().isNotEmpty) p.join(dir.trim(), 'node.exe'),
          ];
    // If the sandbox cannot see any of them, the Codex app's own is still
    // the best guess on the Mac: the app may not have `node` on its PATH.
    return candidates.firstWhereOrNull((e) => File(e).existsSync()) ??
        (Platform.isMacOS ? candidates.first : null);
  }

  /// node.exe in the Codex app's runtime package on Windows
  /// (OpenAI.CodexPrimaryRuntime…\dependencies\node\bin), newest first;
  /// null if Codex is not installed.
  static Future<String?> _codexRuntimeNode() async {
    try {
      final r = await Process.run('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        r"Get-AppxPackage -Name 'OpenAI.CodexPrimaryRuntime*' | "
            r"Sort-Object { [version]$_.Version } -Descending | "
            r"ForEach-Object { Join-Path $_.InstallLocation "
            r"'dependencies\node\bin\node.exe' }",
      ]);
      return '${r.stdout}'
          .split(RegExp(r'\r?\n'))
          .map((e) => e.trim())
          .firstWhereOrNull((e) => e.isNotEmpty && File(e).existsSync());
    } catch (_) {
      return null; // no PowerShell
    }
  }

  /// At TPR's start on Windows: when Codex has updated, the Node written in
  /// its settings is gone with the old runtime folder; write the new one.
  /// Does nothing unless TPR set Codex up.
  static Future<void> keepNodeCurrent() async {
    if (!Platform.isWindows) return;
    try {
      final file = File(p.join(
          Platform.environment['USERPROFILE'] ?? '', '.codex', 'config.toml'));
      if (!file.existsSync()) return;
      final text = await file.readAsString();
      final ours = RegExp(
              r"^\[mcp_servers\.tpr-research\]\s*\ncommand = '([^']*)'",
              multiLine: true)
          .firstMatch(text);
      if (ours == null || File(ours.group(1)!).existsSync()) return;
      final node = await findNode();
      if (node == null) return;
      await file.writeAsString(
          text.replaceRange(ours.start, ours.end,
              "[mcp_servers.tpr-research]\ncommand = '$node'"),
          flush: true);
    } catch (_) {
      // Codex set up by hand, or not readable: left alone
    }
  }

  static Future<void> _needNode(BuildContext context) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          constraints: const BoxConstraints(maxWidth: 480),
          title: const Text('Node is needed first'),
          content: const Text(
            'TPR Research runs on Node, which comes with the ChatGPT app. '
            'If ChatGPT is installed, open it once, then press Set up '
            'again. Otherwise install Node from '
            'nodejs.org (the LTS version, with the default settings), then '
            'press Set up again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                launchUrl(Uri.parse('https://nodejs.org/en/download'),
                    mode: LaunchMode.externalApplication);
              },
              child: const Text('Get Node'),
            ),
          ],
        ),
      );

  static Future<void> _howToUse(BuildContext context) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          constraints: const BoxConstraints(maxWidth: 480),
          title: const Text('How to use it'),
          content: const SingleChildScrollView(
            child: Text(
              'TPR Research is added to Codex in the ChatGPT app. If ChatGPT '
              'is open, quit it completely first; then press Open ChatGPT for '
              'a first '
              'test.\n\n'
              'Then start a new chat and just ask, with "TPR" in the '
              'question, for example:\n'
              '• Using TPR, where do the suttas compare the mind to a '
              'monkey? Make a paper with quotes.\n'
              '• Make my TPR vocabulary review.\n'
              '• Export MN 10 from TPR with the English.\n\n'
              'Or type your question in TPR\'s AI search and press ChatGPT.\n\n'
              'Codex may ask before it runs a TPR tool. Allow only TPR '
              'Research\'s own tools; it does not need to control your '
              'browser or other apps.\n\n'
              'Papers are saved as PDF in the TPR folder in your home '
              'folder.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            // Codex has no install screen of its own (TPR has written its
            // settings), so this shows that it worked: a new chat that
            // checks TPR Research.
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                launchUrl(Uri.parse('codex://threads/new?prompt='
                    '${Uri.encodeQueryComponent('Using TPR Research, run tpr_status and tell me what my TPR has.')}'));
              },
              child: const Text('Open ChatGPT'),
            ),
          ],
        ),
      );
}
