import 'package:collection/collection.dart';
import 'package:flutter/rendering.dart';
import 'package:html/dom.dart' as dom;

import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/business_logic/models/book.dart';
import 'package:tipitaka_pali/business_logic/models/bookmark.dart';
import 'package:tipitaka_pali/business_logic/models/found_info.dart';
import 'package:tipitaka_pali/providers/font_provider.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/provider/script_language_provider.dart';
import 'package:tipitaka_pali/services/repositories/dictionary_history_repo.dart';
import 'package:tipitaka_pali/utils/font_utils.dart';

import '../../../../utils/pali_script_converter.dart';
import '../../../../data/constants.dart';
import '../../../../services/provider/theme_change_notifier.dart';
import '../../../../utils/pali_script.dart';
import '../controller/reader_view_controller.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';

class PaliPageWidget extends StatefulWidget {
  final int pageNumber;
  final String htmlContent;
  final Script script;
  final String? highlightedWord;
  final int? pageToHighlight;
  final double? height;
  final List<FoundInfo>? founds;
  final int? currentOccurrence;
  final Book? book;
  final Function(String clickedWord)? onClick;
  const PaliPageWidget({
    super.key,
    required this.pageNumber,
    required this.htmlContent,
    required this.script,
    this.highlightedWord,
    this.pageToHighlight,
    this.height,
    this.founds,
    this.currentOccurrence,
    this.onClick,
    this.book,
  });

  @override
  State<PaliPageWidget> createState() => _PaliPageWidgetState();
}

final nonPali = RegExp(r'[.,:;\"{}\[\]<>\/\(\) ]+', caseSensitive: false);

// Scroll configuration constants
const _kScrollDelayDuration = Duration(milliseconds: 50);
const _kScrollAnimationDuration = Duration(milliseconds: 100);
const _kScrollVisibilityMargin = 20.0;
const _kScrollAlignment = 0.5; // Center alignment

class _PaliPageWidgetState extends State<PaliPageWidget> {
  String? highlightedWord;
  String? lookupWord;
  int? lookupWordIndex;
  String? lookupParagraph;
  int? highlightedWordIndex;
  late List<Bookmark> bookmarks;
  int? _pageToHighlight;

  final GlobalKey _textKey = GlobalKey();
  final GlobalKey<HtmlWidgetState> _htmlKey = GlobalKey<HtmlWidgetState>();
  final GlobalKey _scrollKey = GlobalKey();
  final GlobalKey _highlightedWordScrollKey = GlobalKey();

  final searchTermCssClass = 'search-term';
  final currentSearchTermCssClass = 'current-search-term';
  final highlightedWordScrollCssClass = 'scroll_to_highlighted_word';

  @override
  void initState() {
    super.initState();
    highlightedWord = widget.highlightedWord;
    highlightedWordIndex = null;
    _pageToHighlight = widget.pageToHighlight;

    bookmarks = Provider.of<ReaderViewController>(context, listen: false)
        .bookmarks
        .where((bm) => bm.pageNumber == widget.pageNumber)
        .toList();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Handle highlighted word scroll on initial load
      if (widget.highlightedWord != null &&
          widget.pageToHighlight == widget.pageNumber) {
        _scrollToHighlightedWordResult();
      }
    });
  }

  @override
  void didUpdateWidget(PaliPageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Handle search result scroll - uses Scrollable.ensureVisible for better alignment
      if (widget.founds != null && widget.currentOccurrence != null) {
        _scrollToCurrentSearchResult();
      }
    });
  }

  void _scrollToCurrentSearchResult() {
    _scrollToResultContext(_scrollKey.currentContext);
  }

  void _scrollToHighlightedWordResult() {
    Future.delayed(_kScrollDelayDuration, () {
      if (!mounted) return;

      final context = _highlightedWordScrollKey.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(context, alignment: _kScrollAlignment);
      }
    });
  }

  void _scrollToResultContext(BuildContext? currentContext,
      {double alignment = _kScrollAlignment}) {
    if (currentContext != null) {
      final RenderObject? box = currentContext.findRenderObject();
      if (box != null) {
        final double yPosition =
            (box as RenderBox).localToGlobal(Offset.zero).dy;
        final double effectiveHeight =
            widget.height ?? MediaQuery.of(context).size.height;
        final bool isVisible = yPosition >= 0 &&
            yPosition <= (effectiveHeight - _kScrollVisibilityMargin);

        if (!isVisible) {
          Scrollable.ensureVisible(
            currentContext,
            alignment: alignment,
            duration: _kScrollAnimationDuration,
          );
        }
      }
    }
  }

  int findOccurrencesBefore(String word, RenderParagraph target) {
    List<Element> richTexts = [];
    void pickRichTexts(Element element) {
      if (element.widget is RichText) {
        richTexts.add(element);
      }
      element.visitChildren(pickRichTexts);
    }

    _textKey.currentContext?.visitChildElements((element) {
      pickRichTexts(element);
    });

    int occurrencesBefore = 0;
    for (final rte in richTexts) {
      if (rte.renderObject == target) {
        break;
      }
      final paragraphText = (rte.widget as RichText).text.toPlainText();
      final matchesInParagraph = word.allMatches(paragraphText).length;
      occurrencesBefore += matchesInParagraph;
    }
    return occurrencesBefore;
  }

  @override
  Widget build(BuildContext context) {
    int fontSize = context.watch<ReaderFontProvider>().fontSize;
// Get the font name based on the current script
//  final fontName = context.read<ScriptLanguageProvider>().getScriptFont();

    String html = _formatContent(widget.htmlContent, widget.script, context);

    final fontName = FontUtils.getfontName(
        script: context.read<ScriptLanguageProvider>().currentScript);

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Container(
        color: Colors.transparent,
        child: GestureDetector(
          onTapUp: (details) {
            final renderObject = _textKey.currentContext?.findRenderObject();
            if (renderObject == null) return;

            final box = renderObject as RenderBox;

            final result = BoxHitTestResult();
            final offset = box.globalToLocal(details.globalPosition);
            if (!box.hitTest(result, position: offset)) {
              return;
            }

            for (final entry in result.path) {
              final target = entry.target;
              if (entry is! BoxHitTestEntry || target is! RenderParagraph) {
                continue;
              }

              final p = target.getPositionForOffset(entry.localPosition);
              final text =
                  target.text.toPlainText(); //.replaceAll('\ufffc', '');

              if (text.isNotEmpty && p.offset < text.length) {
                final int offset = p.offset;

                final leftSentence = getLeftSentence(text, offset);
                final rightSentence = getRightSentence(text, offset);
                final sentence = leftSentence + rightSentence;

                final charUnderTap = text[offset];
                final leftChars = getLeftCharacters(text, offset);
                final rightChars = getRightCharacters(text, offset);

                final word = leftChars + charUnderTap + rightChars;
                writeHistory(
                    word, sentence, widget.pageNumber, widget.book!.id);

                final textBefore =
                    text.substring(0, p.offset - leftChars.length);
                final occurrencesInTextBefore =
                    word.allMatches(textBefore).length;
                final wordIndex = findOccurrencesBefore(word, target) +
                    occurrencesInTextBefore;

                if (word == lookupWord && highlightedWordIndex == wordIndex) {
                  setState(() {
                    highlightedWord = null;
                    lookupWord = null;
                    highlightedWordIndex = null;
                    _pageToHighlight = null;
                  });
                } else {
                  setState(() {
                    widget.onClick?.call(word);
                    highlightedWord = null;
                    lookupWord = word;
                    highlightedWordIndex = wordIndex;

                    _pageToHighlight = widget.pageNumber;
                  });
                }
              }
            }
          },
          child: Container(
            key: _textKey,
            child: HtmlWidget(
              key: _htmlKey,
              html,
              factoryBuilder: () => WidgetFactory(),
              textStyle: TextStyle(
                  fontSize: fontSize.toDouble(),
                  inherit: true,
                  fontFamily: fontName),
              customStylesBuilder: (element) {
                if (element.localName == 'a') {
                  final isHighlight =
                      element.parent!.className.contains('search-highlight') ==
                          true;
                  if (isHighlight) {
                    return {'color': '#000', 'text-decoration': 'none'};
                  }

                  if (context.read<ThemeChangeNotifier>().isDarkMode) {
                    return {
                      'color': 'white',
                      'text-decoration': 'none',
                    };
                  } else {
                    return {
                      'color': 'black',
                      'text-decoration': 'none',
                    };
                  }
                }

                if (element.className == 'highlighted') {
                  String styleColor = (Prefs.darkThemeOn) ? "white" : "black";
                  Color c = Theme.of(context).primaryColorLight;

                  // Converting the Flutter Color object to a CSS hex string for the text color
                  String colorHex =
                      '#${c.value.toRadixString(16).padLeft(8, '0').substring(2)}';

                  return {
                    'color': 'inherit', // Uses the default text color
                    'background-color':
                        colorHex, // Highlights the text with colorHex
                    //'font-weight': '500', // Sets the font weight to 500
                    'text-decoration': 'underline', // Underlines the text
                    'text-decoration-color':
                        colorHex, // Sets underline color to match colorHex
                  };
                }
                // no style
                return {'text-decoration': 'none'};
              },
              customWidgetBuilder: (element) {
                if (element.localName == 'span' &&
                    element.className == 'linebreak') {
                  return const InlineCustomWidget(
                      child: SizedBox(
                    height: 0.0,
                    child: Text('\n '),
                  ));
                }

                if (element.localName == 'a' &&
                    element.className == 'bookmark') {
                  final bookmark = element.text;
                  return InlineCustomWidget(
                    child: IconButton(
                        onPressed: () {
                          onClickBookmark(bookmark);
                        },
                        tooltip: bookmark,
                        icon: const Icon(Icons.note, color: Colors.red)),
                  );
                }

                // Anchor element for scrolling to current search result
                if (element.localName == 'a' &&
                    element.className == 'scroll_to_term') {
                  return InlineCustomWidget(
                    child: SizedBox.shrink(key: _scrollKey),
                  );
                }
                if (element.localName == 'a' &&
                    element.className == highlightedWordScrollCssClass) {
                  return InlineCustomWidget(
                    child: SizedBox.shrink(key: _highlightedWordScrollKey),
                  );
                }

                return null;
              },
              onTapUrl: (word) {
                if (widget.onClick != null) {
                  // #goto is used for scrolling to selected text
                  if (word != '#goto') {
                    setState(() {
                      highlightedWord = word;
                      widget.onClick!(word);
                    });
                  }
                }
                return false;
              },
            ),
          ),
        ),
      ),
    );
  }

  void onClickBookmark(String bookmark) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context)!.bookmark),
          content: SingleChildScrollView(
            child: Text(_insertBookmarkNewlines(bookmark)),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(AppLocalizations.of(context)!.close),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  String _formatContent(String content, Script script, BuildContext context) {
    content = _removeHiddenTags(content);
    content = _addLineBreak(content);

    if (lookupWord != null) {
      content = _addUnderline(content, lookupWord!);
    }

    if (highlightedWord != null) {
      content = _addHighlight(content, highlightedWord!);
      content = _addHighlightedWordScrollAnchor(content);
    }

    if (widget.founds != null) {
      content = _addHighlightToSearchIndex(content);
    }

    if (!Prefs.isShowAlternatePali) {
      content = _removeAlternatePali(content);
    }
    content = _formatWithUserSetting(content);
    content = _changeToInlineStyle(content);

    return content;
  }

  String _removeHiddenTags(String content) {
    return content.replaceAll(RegExp(r'<a name="para[^"]*">'), '');
  }

  String _removeAlternatePali(String content) {
    return content.replaceAll(RegExp(r'<span class="note">\[.+?\]</span>'), '');
  }

  String _addLineBreak(String content) {
    return content.replaceAll('</p>', '<span class="linebreak"></span><p>');
  }

  String _addUnderline(String content, String lookupWord) {
    final hwi = highlightedWordIndex;
    final underlinedHighlight =
        '<span class = "underlined_highlight">$lookupWord</span>';
    final matches = lookupWord.allMatches(content);
    if (hwi != null && matches.length > hwi) {
      final match = matches.elementAt(hwi);
      return content.replaceRange(match.start, match.end, underlinedHighlight);
    }
    return content;
  }

  String _addHighlightToSearchIndex(String content) {
    if (widget.founds?.isEmpty ?? true) return content;

    final termInScript = PaliScript.getScriptOf(
      script: context.read<ScriptLanguageProvider>().currentScript,
      romanText: widget.founds!.first.term,
    );
    if (termInScript.isEmpty) return content;

    final pattern = RegExp(RegExp.escape(termInScript), caseSensitive: false);
    final soup = BeautifulSoup(content);
    final List<ReplaceResult> toReplace = [];
    var occurrence = 0;

    for (final node in (soup.body?.nodes ?? <dom.Node>[])) {
      occurrence = _highlightSearchTermInNode(
        node: node,
        pattern: pattern,
        toReplace: toReplace,
        currentOccurrence: widget.currentOccurrence,
        occurrence: occurrence,
      );
    }

    for (final result in toReplace) {
      for (final newNode in result.newNodes) {
        result.node.parent?.insertBefore(newNode, result.node);
      }
      result.node.remove();
    }

    return soup.toString();
  }

  String _addHighlightedWordScrollAnchor(String content) {
    final soup = BeautifulSoup(content);
    final highlightedNode = soup.find('span', id: kGotoID);
    if (highlightedNode == null) return content;

    final anchor = highlightedNode.newTag(
      'a',
      attrs: {'class': highlightedWordScrollCssClass},
    );
    highlightedNode.parent?.insertBefore(anchor, highlightedNode);
    return soup.toString();
  }

  int _highlightSearchTermInNode({
    required dom.Node node,
    required RegExp pattern,
    required List<ReplaceResult> toReplace,
    required int? currentOccurrence,
    required int occurrence,
  }) {
    if (node.nodeType == dom.Node.TEXT_NODE) {
      final text = node.text;
      if (text == null || text.isEmpty) return occurrence;

      final matches = pattern.allMatches(text).toList();
      if (matches.isEmpty) return occurrence;

      final buffer = StringBuffer();
      var start = 0;
      for (final match in matches) {
        buffer.write(text.substring(start, match.start));
        occurrence++;

        final matchedText = match.group(0)!;
        final isCurrent =
            currentOccurrence != null && occurrence == currentOccurrence;
        if (isCurrent) {
          buffer.write('<a class="scroll_to_term"></a>');
          buffer.write(
              '<span class="$currentSearchTermCssClass">$matchedText</span>');
        } else {
          buffer.write('<span class="$searchTermCssClass">$matchedText</span>');
        }

        start = match.end;
      }
      buffer.write(text.substring(start));

      final highlighted = BeautifulSoup(buffer.toString());
      final newNodes = (highlighted.body?.nodes ?? <dom.Node>[])
          .toList(growable: false)
          .cast<dom.Node>();
      toReplace.add(ReplaceResult(node, newNodes));
      return occurrence;
    }

    if (node is dom.Element) {
      if (node.localName == 'script' || node.localName == 'style') {
        return occurrence;
      }
      // Avoid highlighting injected bookmark header text.
      if (node.localName == 'a' && node.className == 'bookmark') {
        return occurrence;
      }
    }

    for (final child in node.nodes) {
      occurrence = _highlightSearchTermInNode(
        node: child,
        pattern: pattern,
        toReplace: toReplace,
        currentOccurrence: currentOccurrence,
        occurrence: occurrence,
      );
    }

    return occurrence;
  }

  String _toCssHex(int colorValue) {
    return '#${(colorValue & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }

  String _changeToInlineStyle(String content) {
    Color c = Theme.of(context).primaryColorLight;

    String colorHex =
        '#${c.value.toRadixString(16).padLeft(8, '0').substring(2)}';

    // 1. Detect if this is a Bilingual book or Pāḷi-only
    final bool isBilingual = content.contains('class="palitext"') ||
        content.contains('class="english_text"');

    // 2. Determine visibility for bilingual modes
    final bool showTranslation =
        Prefs.textDisplayMode == TextDisplayMode.paliAndTranslation ||
            Prefs.textDisplayMode == TextDisplayMode.translationOnly;

    final bool showPali = Prefs.textDisplayMode == TextDisplayMode.paliOnly ||
        Prefs.textDisplayMode == TextDisplayMode.paliAndTranslation;

    // 3. Join lines if only one language is showing
    if (isBilingual && (!showTranslation || !showPali)) {
      content =
          content.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ');
    }

    // 4. Styles for Bilingual Spans
    final String boldStyle = Prefs.isPaliBold ? "font-weight:bold; " : "";

    final translationStyle = showTranslation
        ? "font-size: 0.9em; color: ${_toCssHex(Prefs.translationColor)};"
        : "display: none;";

    final paliStyle = showPali
        ? "${boldStyle}color: ${_toCssHex(Prefs.paliTextColor)};"
        : "display: none;";

    // 5. Logic for Pāḷi-only books (the "raw" text inside paragraphs)
    // If it's Pāḷi-only, we use the custom Pāḷi color/bold for the base text.
    // If it's Bilingual, we use standard black/white for structural classes.
    String baseStyle;
    if (isBilingual) {
      String themeColor = (Prefs.darkThemeOn) ? "white" : "black";
      baseStyle = "color: $themeColor;";
    } else {
      baseStyle = "${boldStyle}color: ${_toCssHex(Prefs.paliTextColor)};";
    }

    final styleMaps = <String, String>{
      r'class="bld"':
          'style="font-weight:bold; color: ${_toCssHex(Prefs.paliTextColor)};"',
      r'class="t5"':
          'style="font-weight:bold; color: ${_toCssHex(Prefs.paliTextColor)};"',
      r'class="t1"': 'style="$baseStyle"',
      r'class="t3"':
          'style="font-size: 1.7em; font-weight:bold; color: ${_toCssHex(Prefs.paliTextColor)};"',
      r'class="t2"':
          'style="font-size: 1.7em; font-weight:bold; color: ${_toCssHex(Prefs.paliTextColor)};"',
      r'class="th31"':
          'style="font-size: 1.7em; text-align:center; font-weight: bold; color: ${_toCssHex(Prefs.paliTextColor)};"',
      r'class="centered"': 'style="text-align:center; $baseStyle"',
      r'class="paranum"': 'style="font-weight: bold; $baseStyle"',
      r'class="indent"':
          'style="text-indent:1.3em; margin-left:2em; $baseStyle"',
      r'class="bodytext"': 'style="text-indent:1.3em; $baseStyle"',
      r'class="unindented"': 'style="$baseStyle"',
      r'class="noindentbodytext"': 'style="$baseStyle"',
      r'class="book"':
          'style="font-size: 1.9em; text-align:center; font-weight: bold; $baseStyle"',
      r'class="chapter"':
          'style="font-size: 1.7em; text-align:center; font-weight: bold; $baseStyle"',
      r'class="nikaya"':
          'style="font-size: 1.6em; text-align:center; font-weight: bold; $baseStyle"',
      r'class="title"':
          'style="font-size: 1.3em; text-align:center; font-weight: bold; $baseStyle"',
      r'class="subhead"':
          'style="font-size: 1.6em; text-align:center; font-weight: bold; $baseStyle"',
      r'class="subsubhead"':
          'style="font-size: 1.6em; text-align:center; font-weight: bold; $baseStyle"',

      // Verses
      r'class="gatha1"':
          'style="margin-bottom: 0em; margin-left: 5em; $baseStyle"',
      r'class="gatha2"':
          'style="margin-bottom: 0em; margin-left: 5em; $baseStyle"',
      r'class="gatha3"':
          'style="margin-bottom: 0em; margin-left: 5em; $baseStyle"',
      r'class="gathalast"':
          'style="margin-bottom: 1.3em; margin-left: 5em; $baseStyle"',

      r'class="note"': 'style="font-size: 0.8em; color: gray;"',
      r'class = "highlightedSearch"':
          'style="background: #FFE959; color: #000;"',

      // Bilingual Spans
      r'class="pageheader"': 'style="$translationStyle"',
      r'class="english_text"': 'style="$translationStyle"',
      r'class="vietnamese_text"': 'style="$translationStyle"',
      r'class="translation_text"': 'style="$translationStyle"',
      r'class="palitext"': 'style="$paliStyle"',

      'class = "underlined_highlight"':
          'style="font-weight: 500; color: $colorHex; text-decoration: underline; text-decoration-color: $colorHex;"'
    };

    styleMaps.forEach((key, value) {
      content = content.replaceAll(key, value);
    });

    return content;
  }

  String _formatWithUserSetting(String pageContent) {
    var publicationKeys = <String>['P', 'T', 'V'];
    if (!Prefs.isShowPtsNumber) publicationKeys.remove('P');
    if (!Prefs.isShowThaiNumber) publicationKeys.remove('T');
    if (!Prefs.isShowVriNumber) publicationKeys.remove('V');

    if (publicationKeys.isNotEmpty) {
      for (var publicationKey in publicationKeys) {
        final publicationFormat =
            RegExp('<a name="$publicationKey(\\d+)\\.(\\d+)"></a>');
        pageContent = pageContent.replaceAllMapped(publicationFormat, (match) {
          final volume = match.group(1)!;
          final pageNumber = int.parse(match.group(2)!).toString();
          return '<span style="color:brown;">[$publicationKey $volume.$pageNumber]</span>';
        });
      }
    }
    pageContent = pageContent.replaceAll(
        RegExp('<a name="[MPTV](\\d+)\\.(\\d+)"></a>'), '');

    final bookmarkTags = bookmarks.foldIndexed(
        '',
        (index, previousValue, element) =>
            '$previousValue<a id="bookmark_${index + 1}" class="bookmark">${element.toString()}</a>');

    return '''
            <p style="color:brown;text-align:right;">$bookmarkTags ${_getScriptPageNumber(widget.pageNumber)}</p>
            <div id="page_content">
              $pageContent
            </div>
    ''';
  }

  String _getScriptPageNumber(int pageNumber) {
    return PaliScript.getScriptOf(
      script: context.watch<ScriptLanguageProvider>().currentScript,
      romanText: (pageNumber.toString()),
    );
  }

  String _addHighlight(String content, String textToHighlight,
      {highlightClass = "highlighted", addId = true}) {
    final hwi = highlightedWordIndex;
    if (!Prefs.multiHighlight && hwi != null) {
      final highlighted =
          '<span id="$kGotoID" class = "$highlightClass">$textToHighlight</span>';
      final matches = textToHighlight.allMatches(content);
      if (matches.length > hwi) {
        final match = matches.elementAt(hwi);
        return content.replaceRange(match.start, match.end, highlighted);
      }
    }

    textToHighlight = PaliScript.getScriptOf(
        script: context.read<ScriptLanguageProvider>().currentScript,
        romanText: textToHighlight);

    if (!textToHighlight.contains(' ')) {
      final pattern = RegExp('(?<=[\\s", ])$textToHighlight(?=[\\s", ])');
      if (content.contains(pattern)) {
        final replace =
            '<span id="$kGotoID" class = "$highlightClass">$textToHighlight</span>';
        content = content.replaceAll(pattern, replace);
        return content;
      }
    }

    final words = textToHighlight.trim().split(' ');
    for (final word in words) {
      if (content.contains(word)) {
        final String replace = '<span class = "$highlightClass">$word</span>';
        content = content.replaceAll(word, replace);
      } else {
        String trimmedWord = word.replaceAll(RegExp(r'(nti|ti)$'), '');
        final replace = '<span class = "$highlightClass">$trimmedWord</span>';

        content = content.replaceAll(trimmedWord, replace);
      }
    }

    if (addId) {
      content = content.replaceFirst('<span class = "$highlightClass">',
          '<span id="$kGotoID" class="$highlightClass">');
    }

    return content;
  }

  String addIDforScroll(String content, String tocHeader) {
    String tocHeaderWithID = '<span id="$kGotoID">$tocHeader</span>';
    content = content.replaceAll(tocHeader, tocHeaderWithID);

    return content;
  }

  String getLeftCharacters(String text, int offset) {
    StringBuffer chars = StringBuffer();
    for (int i = offset - 1; i >= 0; i--) {
      if (nonPali.hasMatch(text[i]) && text[i] != '"' && text[i] != "'") {
        break;
      }
      chars.write(text[i]);
    }
    return chars.toString().split('').reversed.join();
  }

  String getRightCharacters(String text, int offset) {
    StringBuffer chars = StringBuffer();

    for (int i = offset + 1; i < text.length; i++) {
      if (nonPali.hasMatch(text[i]) && text[i] != '"' && text[i] != "'") break;
      chars.write(text[i]);
    }
    return chars.toString();
  }

  String getLeftSentence(String text, int offset) {
    StringBuffer chars = StringBuffer();
    for (int i = offset - 1; i >= 0; i--) {
      if (text[i] == '.' || text[i] == '?' || text[i] == '!') break;
      chars.write(text[i]);
    }
    return chars.toString().split('').reversed.join().trimLeft();
  }

  String getRightSentence(String text, int offset) {
    StringBuffer chars = StringBuffer();
    for (int i = offset; i < text.length; i++) {
      chars.write(text[i]);
      if (text[i] == '.' || text[i] == '?' || text[i] == '!') break;
    }
    return chars.toString().trimRight();
  }
}

writeHistory(String word, String context, int page, String bookId) async {
  final DictionaryHistoryDatabaseRepository dictionaryHistoryRepository =
      DictionaryHistoryDatabaseRepository(dbh: DatabaseHelper());

  await dictionaryHistoryRepository.insert(word, context, page, bookId);
}

String _insertBookmarkNewlines(String bookmark) {
  return bookmark
      .replaceAll("name:", "\nname:")
      .replaceAll("pageNumber:", "\npageNumber:")
      .replaceAll("note:", "\nnote:")
      .replaceAll("selected_text:", "\nselected_text:");
}

class ReplaceResult {
  dom.Node node;
  List<dom.Node> newNodes;
  ReplaceResult(this.node, this.newNodes);
}
