import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/business_logic/models/book.dart';
import 'package:tipitaka_pali/business_logic/models/xray_link.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/provider/script_language_provider.dart';
import 'package:tipitaka_pali/services/provider/shown_languages_provider.dart';
import 'package:tipitaka_pali/services/repositories/xray_repo.dart';
import 'package:tipitaka_pali/ui/screens/home/openning_books_provider.dart';
import 'package:tipitaka_pali/utils/pali_script.dart';

/// The commentary links of one sentence, drawn under its Pali: a small link
/// for each word the commentary takes up. Tapping one shows what each
/// commentary says of it in place, commentary before sub-commentary, each
/// with a button to open it there.
class XrayLinksView extends StatefulWidget {
  final List<XrayLink> links;
  final double fontSize;

  const XrayLinksView({super.key, required this.links, required this.fontSize});

  @override
  State<XrayLinksView> createState() => _XrayLinksViewState();
}

class _XrayLinksViewState extends State<XrayLinksView> {
  final _repo = XrayRepository(DatabaseHelper());
  String? _open;
  Future<List<_Comment>>? _comments;

  Future<_Comment> _commentOf(XrayLink link) async => _Comment(
        await _repo.sentenceOf(link),
        await _repo.translationsOf(link, DatabaseHelper.installedLanguages),
      );

  /// The words, each once, in the order they come.
  List<String> get _words => {for (final l in widget.links) l.word}.toList();

  List<XrayLink> _linksOf(String word) =>
      widget.links.where((l) => l.word == word).toList()
        ..sort((a, b) => a.book.length.compareTo(b.book.length));

  void _toggle(String word) {
    setState(() {
      if (_open == word) {
        _open = null;
        _comments = null;
      } else {
        _open = word;
        _comments = Future.wait(_linksOf(word).map(_commentOf));
      }
    });
  }

  Future<void> _openCommentary(XrayLink link, String word) async {
    final target = await _repo.targetOf(link);
    if (!mounted) return;
    if (target == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This commentary is not in the library.')));
      return;
    }
    context.read<OpenningBooksProvider>().add(
          book: Book(id: target.bookId, name: target.bookName),
          currentPage: target.page,
          textToHighlight: word,
        );
  }

  @override
  Widget build(BuildContext context) {
    final script = context.watch<ScriptLanguageProvider>().currentScript;
    String inScript(String roman) =>
        PaliScript.getScriptOf(script: script, romanText: roman);
    final theme = Theme.of(context);
    final muted =
        theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6) ?? Colors.grey;
    final small = widget.fontSize * 0.7;

    return Padding(
      padding: EdgeInsets.only(top: small * 0.15, bottom: small * 0.15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: small,
            runSpacing: small * 0.3,
            children: [
              for (final word in _words)
                InkWell(
                  onTap: () => _toggle(word),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: small * 0.3, vertical: small * 0.1),
                    decoration: BoxDecoration(
                      color: _open == word
                          ? theme.colorScheme.primary.withValues(alpha: 0.12)
                          : null,
                      border: Border(
                        bottom: BorderSide(
                            color: muted.withValues(alpha: 0.4), width: 1),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.north_east, size: small * 0.9, color: muted),
                        SizedBox(width: small * 0.3),
                        Text(
                          inScript(word),
                          style: TextStyle(fontSize: small, color: muted),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (_open != null) _panel(_linksOf(_open!), inScript, small),
        ],
      ),
    );
  }

  Widget _panel(
      List<XrayLink> links, String Function(String) inScript, double small) {
    final theme = Theme.of(context);
    final script = context.read<ScriptLanguageProvider>().currentScript;
    // The languages the page shows, each with its own font and colour.
    var paliShown = true;
    var languages = const <String>[];
    try {
      final shown = context.watch<ShownLanguagesProvider>();
      paliShown = shown.paliShown;
      languages = shown.shownLanguages;
    } catch (_) {
      // Not provided, as in a test of the view alone: the Pāḷi only.
    }
    return Container(
      margin: EdgeInsets.only(top: small * 0.5),
      padding: EdgeInsets.all(small * 0.8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(
            left: BorderSide(color: theme.colorScheme.primary, width: 3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: FutureBuilder<List<_Comment>>(
        future: _comments,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LinearProgressIndicator();
          }
          final comments = snapshot.data ?? const [];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < links.length; i++) ...[
                if (i > 0) const Divider(),
                if (i < comments.length) ...[
                  if (paliShown || comments[i].isEmptyIn(languages))
                    HtmlWidget(
                      (comments[i].pali ?? '').isEmpty
                          ? 'Not found.'
                          : PaliScript.getScriptOf(
                              script: script,
                              romanText: comments[i].pali!,
                              isHtmlText: true),
                      textStyle: TextStyle(fontSize: widget.fontSize * 0.85),
                    ),
                  for (final code in languages)
                    if (comments[i].translations[code] case final text?)
                      Padding(
                        padding: EdgeInsets.only(top: small * 0.4),
                        child: HtmlWidget(
                          text,
                          textStyle: TextStyle(
                            fontSize: widget.fontSize * 0.8,
                            color: Color(Prefs.translationColor),
                            fontFamily: Prefs.translationFontName(code).isEmpty
                                ? null
                                : Prefs.translationFontName(code),
                          ),
                        ),
                      ),
                ],
                Row(
                  children: [
                    Text(links[i].book,
                        style:
                            TextStyle(fontSize: small, color: theme.hintColor)),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Open'),
                      onPressed: () =>
                          _openCommentary(links[i], inScript(links[i].word)),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// What one commentary says of a word: its Pāḷi and its translations.
class _Comment {
  final String? pali;
  final Map<String, String> translations;

  const _Comment(this.pali, this.translations);

  /// Nothing to show in any of [languages], so the Pāḷi is shown instead of
  /// an empty panel.
  bool isEmptyIn(List<String> languages) =>
      !languages.any(translations.containsKey);
}
