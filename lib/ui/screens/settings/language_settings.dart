import 'package:flutter/material.dart';

import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/language_installer.dart';
import 'package:tipitaka_pali/services/prefs.dart';

/// Choosing which translations are installed and the order they read in.
///
/// Order matters and is the reader's own, the way the dictionary list is
/// ordered: Pali always first, then each chosen language beneath it. Dragging
/// a language changes where it appears on the page.
class LanguageSettings extends StatefulWidget {
  const LanguageSettings({super.key});

  @override
  State<LanguageSettings> createState() => _LanguageSettingsState();
}

class _LanguageSettingsState extends State<LanguageSettings> {
  String? _busy;
  String _message = '';
  double? _progress;

  List<String> get _installed => DatabaseHelper.installedLanguages;

  /// Every installed language: the ones being shown first, in the order they
  /// appear beneath the Pali, then the ones switched off.
  ///
  /// Switched off is not the same as not installed, so both belong in this
  /// list. Only the shown ones have an order worth keeping.
  List<String> get _ordered {
    // The remembered order covers switched-off languages too, so one does not
    // jump to the bottom of the list the moment it is turned off.
    final order = Prefs.knownLanguages.where(_installed.contains).toList();
    for (final code in Prefs.activeLanguages) {
      if (_installed.contains(code) && !order.contains(code)) order.add(code);
    }
    for (final code in _installed) {
      if (!order.contains(code)) order.add(code);
    }
    return order;
  }


  static String _nameOf(String code) => LanguageInstaller.available
      .firstWhere((o) => o.code == code,
          orElse: () => LanguageOption(code, code.toUpperCase()))
      .name;

  Future<void> _install(LanguageOption option) async {
    setState(() {
      _busy = option.code;
      _message = '';
      _progress = null;
    });
    try {
      await LanguageInstaller.install(option, onProgress: (progress, message) {
        if (mounted) {
          setState(() {
            _progress = progress;
            _message = message;
          });
        }
      });
      await LanguageInstaller.applyChanges(onProgress: (progress, message) {
        if (mounted) setState(() => _message = message);
      });
    } catch (e) {
      if (mounted) setState(() => _message = 'Could not install: $e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _remove(String code) async {
    setState(() {
      _busy = code;
      _message = '';
    });
    try {
      await LanguageInstaller.remove(code);
      await LanguageInstaller.applyChanges(onProgress: (progress, message) {
        if (mounted) setState(() => _message = message);
      });
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordered = _ordered;
    return Scaffold(
      appBar: AppBar(title: const Text('Translations')),
      body: ListView(
        children: [
          if (_busy != null || _message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_busy != null)
                    LinearProgressIndicator(value: _progress),
                  if (_message.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_message),
                    ),
                ],
              ),
            ),
          if (ordered.isNotEmpty) ...[
            const _Heading('Installed'),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Switch a translation off to read the Pali alone. '
                'It stays on the device, so turning it back on costs nothing. '
                'Drag to change the order they appear in.',
              ),
            ),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              onReorder: (oldIndex, newIndex) {
                final list = [...ordered];
                if (newIndex > oldIndex) newIndex -= 1;
                list.insert(newIndex, list.removeAt(oldIndex));
                setState(() {
                  // The full order, including the ones switched off, and the
                  // reader's own list narrowed to what is shown.
                  Prefs.knownLanguages = list;
                  Prefs.activeLanguages =
                      list.where(LanguageInstaller.isShown).toList();
                });
              },
              children: [
                for (final code in ordered)
                  ListTile(
                    key: ValueKey(code),
                    leading: const Icon(Icons.drag_handle),
                    title: Text(_nameOf(code)),
                    subtitle: Text(LanguageInstaller.isShown(code)
                        ? 'Shown beneath the Pali'
                        : 'On the device, not shown'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: LanguageInstaller.isShown(code),
                          onChanged: _busy == code
                              ? null
                              : (on) => setState(
                                  () => LanguageInstaller.setShown(code, on)),
                        ),
                        if (_busy != code)
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Remove from the device',
                            onPressed: () => _remove(code),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          const _Heading('Available to install'),
          for (final option in LanguageInstaller.available)
            if (!_installed.contains(option.code))
              ListTile(
                title: Text(option.name),
                trailing: _busy == option.code
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(
                        icon: const Icon(Icons.download_outlined),
                        tooltip: 'Install',
                        onPressed:
                            _busy == null ? () => _install(option) : null,
                      ),
              ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Translations come from the ePitaka project. They are produced '
              'with machine assistance and each sentence carries a confidence '
              'rating, so they are a reading aid rather than a published '
              'translation.',
            ),
          ),
        ],
      ),
    );
  }
}

/// The entry in the settings list that opens the page above.
class TranslationSettingsView extends StatelessWidget {
  const TranslationSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final installed = DatabaseHelper.installedLanguages;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.translate_outlined),
        title: Text('Translations',
            style: Theme.of(context).textTheme.titleLarge),
        subtitle: Text(installed.isEmpty
            ? 'None installed'
            : installed.map(_LanguageSettingsState._nameOf).join(', ')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LanguageSettings()),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}
