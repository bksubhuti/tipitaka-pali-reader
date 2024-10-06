import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/business_logic/models/dpd_inflection.dart';
import 'package:tipitaka_pali/business_logic/models/dpd_root_family.dart';
import 'package:tipitaka_pali/routes.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/provider/theme_change_notifier.dart';
import 'package:tipitaka_pali/services/repositories/dictionary_history_repo.dart';
import 'package:tipitaka_pali/ui/screens/dictionary/widget/dictionary_history_view.dart';
import 'package:tipitaka_pali/ui/screens/settings/download_view.dart';
import 'package:tipitaka_pali/utils/pali_script.dart';
import 'package:tipitaka_pali/utils/pali_script_converter.dart';
import 'package:tipitaka_pali/utils/platform_info.dart';
import 'package:tipitaka_pali/utils/script_detector.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../../business_logic/models/dpd_compound_family.dart';
import '../../../../services/prefs.dart';
import '../controller/dictionary_controller.dart';
import '../controller/dictionary_state.dart';

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
                  child: HtmlWidget(
                    key: textKey,
                    content,
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
                          'compound-family'
                        ];

                        if (href.startsWith("dpd://")) {
                          // Return a small button for DPD extra links

                          Uri parsedUri = Uri.parse(href);
                          String extra = parsedUri.host;
                          int id = parsedUri.port;

                          return InlineCustomWidget(
                            child: ElevatedButton(
                              style: TextButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8.0),
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
        noData: () => const SizedBox(
              height: 100,
              child: Center(child: Text('Not found')),
            ));
  }

  String superscripterUni(String text) {
    // Superscript using unicode characters.
    text = text.replaceAllMapped(
      RegExp(r'( )(\d)'),
      (Match match) => '\u200A${match.group(2)}',
    );
    text = text.replaceAll('0', '⁰');
    text = text.replaceAll('1', '¹');
    text = text.replaceAll('2', '²');
    text = text.replaceAll('3', '³');
    text = text.replaceAll('4', '⁴');
    text = text.replaceAll('5', '⁵');
    text = text.replaceAll('6', '⁶');
    text = text.replaceAll('7', '⁷');
    text = text.replaceAll('8', '⁸');
    text = text.replaceAll('9', '⁹');
    text = text.replaceAll('.', '·');
    return text;
  }

  showDpdExtra(BuildContext context, String extra, int wordId) async {
    switch (extra) {
      case "inflect":
        showDeclension(context, wordId);
        break;
      case "root-family":
        showRootFamily(context, wordId);
        break;
      case "compound-family":
        showCompoundFamily(context, wordId);
        break;
    }
  }

  showDeclension(BuildContext context, int wordId) async {
    var dictionaryController = context.read<DictionaryController>();
    DpdInflection? inflection =
        await dictionaryController.getDpdInflection(wordId);

    // Prevent using context across async gaps
    if (!context.mounted) return;

    // Handle case where no inflection data is found
    if (inflection == null) {
      bool? shouldNavigate = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.inflectionNoDataTitle),
          content: Text(AppLocalizations.of(context)!.inflectionNoDataMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(AppLocalizations.of(context)!.close),
            ),
          ],
        ),
      );

      if (shouldNavigate == true) {
        if (!context.mounted) return;
        final route =
            MaterialPageRoute(builder: (context) => const DownloadView());
        NestedNavigationHelper.goto(
            context: context, route: route, navkey: dictionaryNavigationKey);
      }

      return;
    }

    debugPrint('Inflection: $inflection');

    String data = await DefaultAssetBundle.of(context)
        .loadString("assets/inflectionTemplates.json");
    List inflectionTemplates = jsonDecode(data);
    final template = inflectionTemplates
        .firstWhereOrNull((map) => map['pattern'] == inflection.pattern);

    if (template == null) {
      debugPrint('Could not find template...');
      return;
    }

    debugPrint('Template: $template');

    // Prepare the table rows from the template data
    List<TableRow> rows =
        template['data'].asMap().entries.map<TableRow>((rowEntry) {
      int rowIndex = rowEntry.key;
      List<List<String>> row = (rowEntry.value as List)
          .map((e) => (e as List).map((item) => item as String).toList())
          .toList();

      return TableRow(
        children: row
            .asMap()
            .entries
            .map<Padding?>((entry) {
              int colIndex = entry.key;
              List<String> cell = entry.value;
              if (colIndex == 0) {
                return Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(cell[0],
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, color: Colors.orange)),
                );
              }
              if (colIndex % 2 != 1) {
                return null;
              }
              List<InlineSpan> spans = [];

              cell.asMap().forEach((index, value) {
                if (index > 0) {
                  spans.add(const TextSpan(text: '\n'));
                }
                if (rowIndex == 0) {
                  spans.add(TextSpan(
                      text: value,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.orange)));
                } else if (value.isNotEmpty) {
                  spans.add(TextSpan(
                      text: inflection.stem,
                      style: TextStyle(
                          fontSize: Prefs.dictionaryFontSize.toDouble())));
                  spans.add(TextSpan(
                      text: value,
                      style: TextStyle(
                          fontSize: Prefs.dictionaryFontSize.toDouble(),
                          fontWeight: FontWeight.bold)));
                }
              });

              return Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text.rich(TextSpan(children: spans)),
              );
            })
            .where((cell) => cell != null)
            .cast<Padding>()
            .toList(),
      );
    }).toList();

    if (!context.mounted) return;

    // Similar scrollable dialog structure as compound family
    final horizontal = ScrollController();
    final vertical = ScrollController();
    final isMobile = Mobile.isPhone(context);
    const insetPadding = 10.0;

    final content = isMobile
        ? SizedBox(
            width: MediaQuery.of(context).size.width - 2 * insetPadding,
            child: _getInflectionWidget(rows),
          )
        : Container(
            constraints: const BoxConstraints(
              maxHeight: 400,
              maxWidth: 800,
            ),
            child: _getInflectionWidget(rows),
          );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(superscripterUni(inflection.word)),
        contentPadding: isMobile ? EdgeInsets.zero : null,
        insetPadding: isMobile ? const EdgeInsets.all(insetPadding) : null,
        content: content,
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.ok)),
        ],
      ),
    );
  }

  Scrollbar _getInflectionWidget(List<TableRow> rows) {
    final horizontal = ScrollController();
    final vertical = ScrollController();

    return Scrollbar(
      controller: vertical,
      thumbVisibility: true,
      trackVisibility: true,
      child: Scrollbar(
        controller: horizontal,
        thumbVisibility: true,
        trackVisibility: true,
        notificationPredicate: (notification) => notification.depth == 1,
        child: SingleChildScrollView(
          controller: vertical,
          child: SingleChildScrollView(
            controller: horizontal,
            scrollDirection: Axis.horizontal,
            child: Table(
              border: TableBorder.all(),
              defaultColumnWidth: const IntrinsicColumnWidth(),
              children: rows,
            ),
          ),
        ),
      ),
    );
  }

  showRootFamily(BuildContext context, int wordId) async {
    var dictionaryController = context.read<DictionaryController>();
    DpdRootFamily? rootFamily =
        await dictionaryController.getDpdRootFamily(wordId);

    // Prevent using context across async gaps
    if (!context.mounted) return;

    // Handle case where no root family data is found
    if (rootFamily == null) {
      // Optionally, you can add a dialog to handle cases where root family is not found
      return;
    }

    debugPrint('Root family: $rootFamily');

    List<dynamic> jsonData = json.decode(rootFamily.data);

    // Scroll controllers for horizontal and vertical scrolling
    final horizontal = ScrollController();
    final vertical = ScrollController();
    final isMobile = Mobile.isPhone(context);
    const insetPadding = 10.0;

    // Prepare the content widget with scrollbars
    final content = isMobile
        ? SizedBox(
            width: MediaQuery.of(context).size.width - 2 * insetPadding,
            child: _getRootFamilyWidget(rootFamily, jsonData),
          )
        : Container(
            constraints: const BoxConstraints(
              maxHeight: 400,
              maxWidth: 800,
            ),
            child: _getRootFamilyWidget(rootFamily, jsonData),
          );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(superscripterUni(rootFamily.word)),
        contentPadding: isMobile ? EdgeInsets.zero : null,
        insetPadding: isMobile ? const EdgeInsets.all(insetPadding) : null,
        content: content,
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.ok)),
        ],
      ),
    );
  }

  Scrollbar _getRootFamilyWidget(
      DpdRootFamily rootFamily, List<dynamic> jsonData) {
    final horizontal = ScrollController();
    final vertical = ScrollController();

    return Scrollbar(
      controller: vertical,
      thumbVisibility: true,
      trackVisibility: true,
      child: Scrollbar(
        controller: horizontal,
        thumbVisibility: true,
        trackVisibility: true,
        notificationPredicate: (notification) => notification.depth == 1,
        child: SingleChildScrollView(
          controller: vertical,
          child: SingleChildScrollView(
            controller: horizontal,
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _getRootFamilyHeader(rootFamily),
                _getRootFamilyTable(jsonData),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Text _getRootFamilyHeader(DpdRootFamily rootFamily) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(
            text: '${rootFamily.count}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const TextSpan(text: ' words belong to the root family '),
        TextSpan(
            text: rootFamily.rootFamily,
            style: TextStyle(
                fontSize: Prefs.dictionaryFontSize.toDouble(),
                fontWeight: FontWeight.bold)),
        TextSpan(
          text: ' (${rootFamily.rootMeaning})',
        )
      ]),
      textAlign: TextAlign.left,
    );
  }

  Table _getRootFamilyTable(List<dynamic> jsonData) {
    return Table(
      border: TableBorder.all(),
      defaultColumnWidth: const IntrinsicColumnWidth(),
      children: jsonData.map((item) {
        return TableRow(
          children: [
            TableCell(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  item[0],
                  style: TextStyle(
                      fontSize: Prefs.dictionaryFontSize.toDouble(),
                      color: Colors.orange,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
            TableCell(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  item[1],
                  style: TextStyle(
                      fontSize: Prefs.dictionaryFontSize.toDouble(),
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
            TableCell(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text('${item[2]} ${item[3]}',
                    style: TextStyle(
                        fontSize: Prefs.dictionaryFontSize.toDouble())),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  showCompoundFamily(BuildContext context, int wordId) async {
    var dictionaryController = context.read<DictionaryController>();
    List<DpdCompoundFamily>? compoundFamilies =
        await dictionaryController.getDpdCompoundFamilies(wordId);

    // prevent using context across asynch gaps
    if (!context.mounted) return;

    if (compoundFamilies == null || compoundFamilies.isEmpty) {
      // TODO not all words have root family, so need to show a 'install' dialog
      //  only if the root family tables do not exist

      return;
    }

    debugPrint('Compound families count: ${compoundFamilies.length}');
    if (!context.mounted) return;

    List<dynamic> jsonData = [];
    for (final compoundFamily in compoundFamilies) {
      jsonData.addAll(json.decode(compoundFamily.data));
    }

    final DpdCompoundFamily first = compoundFamilies[0];
    final count = compoundFamilies.fold(0, (sum, cf) => sum + cf.count);
    final isMobile = Mobile.isPhone(context);
    const insetPadding = 10.0;
    final word = first.word.replaceAll(RegExp(r" \d.*\$"), '');

    final content = isMobile
        ? SizedBox(
            width: MediaQuery.of(context).size.width - 2 * insetPadding,
            child: _getCompoundFamilyWidget(count, word, jsonData),
          )
        : Container(
            constraints: const BoxConstraints(
              maxHeight: 400,
              maxWidth: 800,
            ),
            child: _getCompoundFamilyWidget(count, word, jsonData));

    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(superscripterUni(first.word)),
              contentPadding: isMobile ? EdgeInsets.zero : null,
              insetPadding:
                  isMobile ? const EdgeInsets.all(insetPadding) : null,
              content: content,
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(AppLocalizations.of(context)!.ok))
              ],
            ));
  }

  Scrollbar _getCompoundFamilyWidget(count, word, jsonData) {
    final horizontal = ScrollController();
    final vertical = ScrollController();
    return Scrollbar(
      controller: vertical,
      thumbVisibility: true,
      trackVisibility: true,
      child: Scrollbar(
        controller: horizontal,
        thumbVisibility: true,
        trackVisibility: true,
        notificationPredicate: (notification) => notification.depth == 1,
        child: SingleChildScrollView(
          controller: vertical,
          child: SingleChildScrollView(
              controller: horizontal,
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _getCompoundFamilyHeader(count, word),
                  _getCompoundFamilyTable(jsonData)
                ],
              )),
        ),
      ),
    );
  }

  Text _getCompoundFamilyHeader(count, word) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(
            text: '$count',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const TextSpan(text: ' compounds which contain '),
        TextSpan(
            text: word,
            style: TextStyle(
                fontSize: Prefs.dictionaryFontSize.toDouble(),
                fontWeight: FontWeight.bold)),
      ]),
      textAlign: TextAlign.left,
    );
  }

  Table _getCompoundFamilyTable(List<dynamic> jsonData) {
    return Table(
      border: TableBorder.all(),
      defaultColumnWidth: const IntrinsicColumnWidth(),
      children: jsonData.map((item) {
        return TableRow(
          children: [
            TableCell(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  item[0],
                  style: TextStyle(
                      fontSize: Prefs.dictionaryFontSize.toDouble(),
                      color: Colors.orange,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
            TableCell(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  item[1],
                  style: TextStyle(
                      fontSize: Prefs.dictionaryFontSize.toDouble(),
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
            TableCell(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text('${item[2]} ${item[3]}',
                    style: TextStyle(
                        fontSize: Prefs.dictionaryFontSize.toDouble())),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

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
