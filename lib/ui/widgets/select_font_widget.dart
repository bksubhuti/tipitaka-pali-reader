import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:tipitaka_pali/providers/font_provider.dart';
import 'package:tipitaka_pali/services/language_installer.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/provider/shown_languages_provider.dart';
import 'package:tipitaka_pali/services/provider/locale_change_notifier.dart';
import 'package:tipitaka_pali/services/provider/script_language_provider.dart';
import 'package:tipitaka_pali/services/provider/theme_change_notifier.dart';
import 'package:tipitaka_pali/services/system_fonts.dart';
import 'package:tipitaka_pali/utils/font_utils.dart';
import 'package:tipitaka_pali/utils/pali_script.dart';
import 'package:tipitaka_pali/utils/pali_script_converter.dart';

/// Pāḷi to show each font with, in the script it is being chosen for.
const String _paliSample = 'Evaṃ me sutaṃ — ekaṃ samayaṃ bhagavā';

/// There are two fonts to choose, and they are separate:
///
///   * the Pāḷi font draws the text in the reader, the book list and the
///     dictionary, and is chosen for each script on its own, since a font
///     for Devanagari is no use for Sinhala. The tile is for the script
///     selected now;
///   * a translation font draws the translations in one language, and can
///     be chosen for each installed language; without one a translation is
///     drawn in the Pāḷi font;
///   * the app font draws the menus, buttons and settings.
///
/// Each offers what comes with the app, then the fonts on the device that
/// have every letter it needs.
class ScriptFontTile extends StatelessWidget {
  const ScriptFontTile({super.key});

  @override
  Widget build(BuildContext context) {
    final script = context.watch<ScriptLanguageProvider>().currentScript;
    context.watch<ReaderFontProvider>();
    final font = FontUtils.getfontName(script: script);
    final sample =
        PaliScript.getScriptOf(script: script, romanText: _paliSample);
    return ListTile(
      title: Text('Pāḷi font (${_scriptName(script)})'),
      subtitle: Text(
        '${font ?? 'System Font'} — $sample',
        style: TextStyle(fontFamily: font),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        final fonts = context.read<ReaderFontProvider>();
        final List<_Option> builtIn;
        final String? current;
        if (script == Script.roman) {
          builtIn = [
            for (final f in ReaderFontProvider.bundledFonts)
              _Option(f, f == 'System Font' ? null : f, f)
          ];
          current = fonts.selectedFont;
        } else {
          final own = FontUtils.defaultFontName(script);
          builtIn = [_Option('${own ?? 'System Font'} (built in)', own, null)];
          final chosen = Prefs.scriptFontName(script.name);
          current = chosen.isEmpty ? null : chosen;
        }
        showDialog<void>(
          context: context,
          builder: (_) => _FontDialog(
            title: 'Pāḷi font (${_scriptName(script)})',
            sample: sample,
            builtIn: builtIn,
            needs: SystemFonts.lettersFor(script),
            current: current,
            choose: (family, files) =>
                fonts.chooseScriptFont(script, family, files: files),
          ),
        );
      },
    );
  }

  static String _scriptName(Script script) {
    final name = script.name;
    return name[0].toUpperCase() + name.substring(1);
  }
}

/// A translation font tile for each installed translation.
class TranslationFontTiles extends StatelessWidget {
  const TranslationFontTiles({super.key});

  @override
  Widget build(BuildContext context) {
    final installed = context.watch<ShownLanguagesProvider>().installed;
    final script = context.watch<ScriptLanguageProvider>().currentScript;
    context.watch<ReaderFontProvider>();
    final paliFont = FontUtils.getfontName(script: script);
    return Column(
      children: [
        for (final code in installed) _tile(context, code, paliFont),
      ],
    );
  }

  Widget _tile(BuildContext context, String code, String? paliFont) {
    final name = LanguageInstaller.nameOf(code);
    final chosen = Prefs.translationFontName(code);
    final sample = SystemFonts.sampleFor(code);
    final sameAsPali = 'Same as the Pāḷi (${paliFont ?? 'System Font'})';
    return ListTile(
      title: Text('Translation font ($name)'),
      subtitle: Text(
        chosen.isEmpty ? sameAsPali : chosen,
        style: TextStyle(fontFamily: chosen.isEmpty ? paliFont : chosen),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        final fonts = context.read<ReaderFontProvider>();
        showDialog<void>(
          context: context,
          builder: (_) => _FontDialog(
            title: 'Translation font ($name)',
            sample: sample,
            builtIn: [_Option(sameAsPali, paliFont, null)],
            needs: SystemFonts.lettersForLanguage(code),
            current: chosen.isEmpty ? null : chosen,
            choose: (family, files) =>
                fonts.chooseTranslationFont(code, family, files: files),
          ),
        );
      },
    );
  }
}

class AppFontTile extends StatelessWidget {
  const AppFontTile({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeChangeNotifier>();
    final locale = context.watch<LocaleChangeNotifier>().localeString;
    final chosen = theme.appFont;
    final own = FontUtils.defaultAppFontName(locale);
    return ListTile(
      title: const Text('App font'),
      subtitle: Text(
        chosen ?? '${own ?? 'System Font'} (built in)',
        style: TextStyle(fontFamily: chosen ?? own),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => _FontDialog(
          title: 'App font',
          sample: AppLocalizations.of(context)!.settings,
          builtIn: [_Option('${own ?? 'System Font'} (built in)', own, null)],
          needs: SystemFonts.lettersForLanguage(locale),
          current: chosen,
          choose: (family, files) =>
              theme.onChangeAppFont(family, files: files),
        ),
      ),
    );
  }
}

/// A font that comes with the app: its [label], the [family] to draw its
/// sample in, and the [value] that chooses it (null for the default).
class _Option {
  const _Option(this.label, this.family, this.value);
  final String label;
  final String? family;
  final String? value;
}

class _FontDialog extends StatefulWidget {
  const _FontDialog({
    required this.title,
    required this.sample,
    required this.builtIn,
    required this.needs,
    required this.current,
    required this.choose,
  });

  final String title;
  final String sample;
  final List<_Option> builtIn;

  /// The letters a font on the device must have to be offered.
  final Set<int> needs;

  /// What is chosen now: a family, or null for the default.
  final String? current;
  final Future<void> Function(String? family, List<String> files) choose;

  @override
  State<_FontDialog> createState() => _FontDialogState();
}

class _FontDialogState extends State<_FontDialog> {
  final Future<List<SystemFont>> _installed = SystemFonts.list();
  String _filter = '';
  String? _loading;

  Future<void> _choose(String label, String? value, List<String> files) async {
    setState(() => _loading = label);
    try {
      await widget.choose(value, files);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _loading = null);
    }
  }

  bool _shown(String label) =>
      _filter.isEmpty || label.toLowerCase().contains(_filter);

  Widget _tile(
      String label, String? family, String? value, List<String> files) {
    final selected = value == widget.current;
    return ListTile(
      selected: selected,
      title: Text(label),
      subtitle: Text(widget.sample, style: TextStyle(fontFamily: family)),
      trailing: _loading == label
          ? const SizedBox.square(
              dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : selected
              ? const Icon(Icons.check)
              : null,
      onTap: _loading == null ? () => _choose(label, value, files) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final builtInNames = widget.builtIn.map((o) => o.family).toSet();
    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: SizedBox(
        width: 480,
        height: 520,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: AppLocalizations.of(context)!.search,
                ),
                onChanged: (text) =>
                    setState(() => _filter = text.trim().toLowerCase()),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<SystemFont>>(
                future: _installed,
                builder: (context, snapshot) {
                  final installed = (snapshot.data ?? const <SystemFont>[])
                      .where((f) => !builtInNames.contains(f.family))
                      .where((f) => f.hasAll(widget.needs))
                      .where((f) => _shown(f.family))
                      .toList();
                  return ListView(
                    children: [
                      for (final o in widget.builtIn)
                        if (_shown(o.label))
                          _tile(o.label, o.family, o.value, const []),
                      if (snapshot.connectionState != ConnectionState.done)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      if (installed.isNotEmpty) const Divider(),
                      for (final font in installed)
                        _tile(
                            font.family, font.family, font.family, font.files),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
      ],
    );
  }
}
