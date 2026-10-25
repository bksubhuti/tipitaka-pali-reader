import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/provider/theme_change_notifier.dart';
import 'package:tipitaka_pali/services/repositories/dictionary_history_repo.dart';
import 'package:tipitaka_pali/ui/dialogs/show_compound_family_dialog.dart';
import 'package:tipitaka_pali/ui/dialogs/show_declension_dialog.dart';
import 'package:tipitaka_pali/ui/dialogs/show_freq_dialog.dart';
import 'package:tipitaka_pali/ui/dialogs/show_root_family_dialog.dart';
import 'package:tipitaka_pali/ui/screens/dictionary/controller/dictionary_controller.dart';
import 'package:tipitaka_pali/ui/screens/dictionary/controller/dictionary_state.dart';
import 'package:tipitaka_pali/ui/screens/dictionary/widget/dictionary_history_view.dart';
import 'package:tipitaka_pali/ui/screens/settings/download_view.dart';
import 'package:tipitaka_pali/utils/pali_script.dart';
import 'package:tipitaka_pali/utils/pali_script_converter.dart';
import 'package:tipitaka_pali/utils/script_detector.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';

class DictionaryContentView extends StatelessWidget {
  final ScrollController? scrollController;
  const DictionaryContentView({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    final state = context.select<DictionaryController, DictionaryState>(
        (controller) => controller.dictionaryState);
    GlobalKey textKey = GlobalKey();

    return state.when(
        initial: () => ValueListenableBuilder(
            valueListenable: context.read<DictionaryController>().histories,
            builder: (_, histories, __) {
              return DictionaryHistoryView(
                histories: histories,
                onClick: (word) =>
                    context.read<DictionaryController>().onWordClicked(word),
                onDelete: (word) =>
                    context.read<DictionaryController>().onDelete(word),
                scrollController: scrollController,
              );
            }),
        loading: () => const SizedBox(
            height: 100, child: Center(child: CircularProgressIndicator())),
        data: (content) => SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(8.0),
              child: SelectionArea(
                child: GestureDetector(
                  onTapUp: (details) {
                    final box = textKey.currentContext?.findRenderObject()!
                        as RenderBox;
                    final result = BoxHitTestResult();
                    final offset = box.globalToLocal(details.globalPosition);
                    if (!box.hitTest(result, position: offset)) {
                      return;
                    }

                    for (final entry in result.path) {
                      final target = entry.target;
                      if (entry is! BoxHitTestEntry ||
                          target is! RenderParagraph) {
                        continue;
                      }

                      final p =
                          target.getPositionForOffset(entry.localPosition);
                      final text = target.text.toPlainText();
                      if (text.isNotEmpty && p.offset < text.length) {
                        final int offset = p.offset;
                        // print('pargraph: $text');
                        final charUnderTap = text[offset];
                        final leftChars = getLeftCharacters(text, offset);
                        final rightChars = getRightCharacters(text, offset);
                        final word = leftChars + charUnderTap + rightChars;
                        debugPrint(word);
                        writeHistory(
                            word,
                            AppLocalizations.of(context)!.dictionary,
                            1,
                            "dictionary");

                        // loading definitions
                        String romanWord = word;
                        Script inputScript = ScriptDetector.getLanguage(word);
                        if (inputScript != Script.roman) {
                          romanWord = PaliScript.getRomanScriptFrom(
                              script: inputScript, text: romanWord);
                        }

                        context
                            .read<DictionaryController>()
                            .onWordClicked(romanWord);
                      }
                    }
                  },
                  child: _DictionarySections(
                    key: textKey,
                    content: content,
                    html: (part) => HtmlWidget(
                      part,
                      customStylesBuilder: (element) {
                        if (element.classes.contains('dpdheader')) {
                          return {'font-weight:': 'bold'};
                        }
                        return null;
                      },
                      customWidgetBuilder: (element) {
                        final href = element.attributes['href'];
                        if (href != null) {
                          // Determine the link text
                          String linkText = href.contains("wikipedia")
                              ? "Wikipedia"
                              : "Submit a correction";
                          final allowedExtras = [
                            'inflect',
                            'root-family',
                            'compound-family',
                            'freq'
                          ];

                          if (href.startsWith("dpd://")) {
                            // Return a small button for DPD extra links

                            Uri parsedUri = Uri.parse(href);
                            String extra = parsedUri.host;
                            int id = parsedUri.port;

                            return InlineCustomWidget(
                              child: ElevatedButton(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8.0),
                                  minimumSize: const Size(0,
                                      0), // Removes default minimum size constraints
                                  tapTargetSize: MaterialTapTargetSize
                                      .shrinkWrap, // Reduces button padding
                                ),
                                onPressed: () {
                                  if (extra == 'get-extras') {
                                    debugPrint(
                                        'Get Extras button pressed for id: $id');
                                    // Implement logic to direct user to the download screen
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (context) =>
                                              const DownloadView()),
                                    );
                                  } else if (allowedExtras.contains(extra)) {
                                    debugPrint(
                                        'DPD "$extra" extra operation for: $id');
                                    showDpdExtra(context, extra, id);
                                  } else {
                                    debugPrint('Unhandled DPD link: $extra');
                                  }
                                },
                                child: Text(
                                  element.text,
                                  style: const TextStyle(
                                      fontSize: 10), // Set font size to 10pt
                                ),
                              ),
                            );
                          } else {
                            // Use InkWell with 10pt font for other links
                            return InkWell(
                              onTap: () {
                                launchUrl(Uri.parse(href),
                                    mode: LaunchMode.externalApplication);
                                debugPrint('Will launch $href. --> $textKey');
                              },
                              child: Text(
                                linkText,
                                style: const TextStyle(
                                  decoration: TextDecoration.underline,
                                  color: Colors.blue,
                                  fontSize: 10, // Set font size to 10pt
                                ),
                              ),
                            );
                          }
                        }
                        return null;
                      },
                      textStyle: TextStyle(
                          fontSize: Prefs.dictionaryFontSize.toDouble(),
                          color: context.watch<ThemeChangeNotifier>().isDarkMode
                              ? Colors.white
                              : Colors.black,
                          inherit: true),
                    ),
                  ),
                ),
              ),
            ),
        noData: () => const SizedBox(
              height: 100,
              child: Center(child: Text('Not found')),
            ));
  }

  showDpdExtra(BuildContext context, String extra, int wordId) async {
    switch (extra) {
      case "inflect":
        showDeclensionDialog(context, wordId);
        break;
      case "root-family":
        showRootFamilyDialog(context, wordId);
        break;
      case "compound-family":
        showCompoundFamilyDialog(context, wordId);
        break;
      case "freq":
        showFreqDialog(context, wordId);
        break;
    }
  }

  // **Modified code ends here**

  String getLeftCharacters(String text, int offset) {
    RegExp wordBoundary = RegExp(r'[\s\.\-",\+]');
    StringBuffer chars = StringBuffer();
    for (int i = offset - 1; i >= 0; i--) {
      if (wordBoundary.hasMatch(text[i])) break;
      chars.write(text[i]);
    }
    return chars.toString().split('').reversed.join();
  }

  String getRightCharacters(String text, int offset) {
    RegExp wordBoundary = RegExp(r'[\s\.\-",\+]');
    StringBuffer chars = StringBuffer();
    for (int i = offset + 1; i < text.length; i++) {
      if (wordBoundary.hasMatch(text[i])) break;
      chars.write(text[i]);
    }
    return chars.toString();
  }
}

typedef WordChanged = void Function(String word);

// put in a common place?  also used in paliPageWidget
writeHistory(String word, String context, int page, String bookId) async {
  final DictionaryHistoryDatabaseRepository dictionaryHistoryRepository =
      DictionaryHistoryDatabaseRepository(dbh: DatabaseHelper());

  await dictionaryHistoryRepository.insert(word, context, page, bookId);
}

/// The definitions, each dictionary's under its heading, which folds it
/// away to the heading alone and opens it again (#118). A long entry in one
/// dictionary, DPPN's for Buddha, was a long scroll to reach the next. A
/// folded dictionary stays folded for the words after, until it is opened.
///
/// The headings are the <h3> bars the controller writes before each
/// dictionary's entry; the HTML between one and the next is that entry.
class _DictionarySections extends StatefulWidget {
  const _DictionarySections(
      {super.key, required this.content, required this.html});

  final String content;
  final Widget Function(String part) html;

  @override
  State<_DictionarySections> createState() => _DictionarySectionsState();
}

class _DictionarySectionsState extends State<_DictionarySections> {
  static final _heading = RegExp(r'<h3([^>]*)>(.*?)</h3>', dotAll: true);
  static final _font = RegExp(r'font-family:\s*([^;"]+)');
  static final _tags = RegExp(r'<[^>]+>');

  void _toggle(String name) {
    final folded = Prefs.foldedDictionaries;
    setState(() {
      Prefs.foldedDictionaries = folded.contains(name)
          ? folded.where((n) => n != name).toList()
          : [...folded, name];
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    final headings = _heading.allMatches(content).toList();
    if (headings.isEmpty) return widget.html(content);

    final theme = Theme.of(context);
    final folded = Prefs.foldedDictionaries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (headings.first.start > 0)
          widget.html(content.substring(0, headings.first.start)),
        for (var i = 0; i < headings.length; i++)
          ...() {
            final heading = headings[i];
            final name = heading.group(2)!.replaceAll(_tags, '').trim();
            final font = _font.firstMatch(heading.group(1)!)?.group(1)?.trim();
            final end = i + 1 < headings.length
                ? headings[i + 1].start
                : content.length;
            final isFolded = folded.contains(name);
            return [
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 16),
                child: Material(
                  color: theme.primaryColor,
                  child: InkWell(
                    onTap: () => _toggle(name),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      child: Row(
                        children: [
                          // The arrow's width on the left too, so the name
                          // stays centred as it was.
                          const SizedBox(width: 24),
                          Expanded(
                            child: Text(
                              name,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: theme.canvasColor,
                                fontWeight: FontWeight.bold,
                                fontSize: Prefs.dictionaryFontSize * 1.17,
                                fontFamily: font,
                              ),
                            ),
                          ),
                          Icon(isFolded ? Icons.expand_more : Icons.expand_less,
                              color: theme.canvasColor),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (!isFolded) widget.html(content.substring(heading.end, end)),
            ];
          }(),
      ],
    );
  }
}
