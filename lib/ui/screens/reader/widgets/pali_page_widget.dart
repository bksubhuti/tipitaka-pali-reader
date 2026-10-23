import 'dart:math';
import 'package:collection/collection.dart';
import 'package:flutter/rendering.dart';

import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:flutter/material.dart';
import 'package:tipitaka_pali/utils/html_text_map.dart';
import 'package:tipitaka_pali/services/tts/tts_service.dart';
import 'package:tipitaka_pali/utils/page_composer.dart';
import 'package:tipitaka_pali/utils/formatted_copy.dart';
import 'package:tipitaka_pali/utils/search_cluster.dart';
import 'package:tipitaka_pali/utils/search_highlight.dart';
import 'package:tipitaka_pali/utils/side_by_side.dart';
import 'package:tipitaka_pali/services/provider/shown_languages_provider.dart';
import 'package:tipitaka_pali/utils/tts_highlight.dart';
import 'package:tipitaka_pali/ui/screens/reader/reader_motion.dart';
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
import '../../home/search_page/search_page.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:tipitaka_pali/utils/script_detector.dart';
import 'package:tipitaka_pali/business_logic/models/xray_link.dart';
import 'xray_links_view.dart';

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
  final bool isFirstChunkOfPage;

  /// Where the block is in the book, to keep the blocks drawn in order; the
  /// page number when a page is drawn whole.
  final int? blockIndex;
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
    this.isFirstChunkOfPage = true,
    this.blockIndex,
  });

  @override
  State<PaliPageWidget> createState() => _PaliPageWidgetState();
}

// Whitespace of every kind ends a word, not just the space: a line break
// separates a sentence from its translation, and without it a word at the end
// of the Pali ran on into the translation's first word.
final nonPali = RegExp(r'[.,:;?!\"{}\[\]<>\/\(\)\s]+', caseSensitive: false);

// Scroll configuration constants
const _kScrollDelayDuration = Duration(milliseconds: 50);
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
  late final ReaderViewController _readerViewController;

  /// True when [highlightedWord] was set by tapping a link inside this chunk
  /// rather than coming from a goto/search navigation. A local highlight is
  /// left alone by the book-wide clear.
  bool _isLocalHighlight = false;

  final GlobalKey _textKey = GlobalKey();
  final GlobalKey<HtmlWidgetState> _htmlKey = GlobalKey<HtmlWidgetState>();
  final GlobalKey _scrollKey = GlobalKey();
  final GlobalKey _highlightedWordScrollKey = GlobalKey();
  final GlobalKey _ttsScrollKey = GlobalKey();

  final searchTermCssClass = 'search-term';
  final currentSearchTermCssClass = 'current-search-term';
  final highlightedWordScrollCssClass = 'scroll_to_highlighted_word';

  @override
  void initState() {
    super.initState();
    highlightedWord = widget.highlightedWord;
    highlightedWordIndex = null;
    _pageToHighlight = widget.pageToHighlight;

    _readerViewController =
        Provider.of<ReaderViewController>(context, listen: false);
    _readerViewController.isHighlightShown
        .addListener(_onHighlightVisibilityChanged);
    _readerViewController.tappedWordOwner.addListener(_onWordTappedElsewhere);
    bookmarks = _readerViewController.bookmarks
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

  int get _blockKey => widget.blockIndex ?? widget.pageNumber;

  /// What this block last put in the controller's [shownBlocks]. Taken out
  /// only if it is still there, not one put in since by a new widget for
  /// the same block.
  ShownBlock? _shown;

  static final _firstSentence = RegExp(r'<a name="s(\d+)_\d+"></a>');
  static final _xrayThenBreak =
      RegExp(r'(<xray data-x="\d+"></xray></span>)\s*<br>');

  void _forgetShown(int key) {
    if (identical(_readerViewController.shownBlocks[key], _shown)) {
      _readerViewController.shownBlocks.remove(key);
    }
  }

  @override
  void dispose() {
    _forgetShown(_blockKey);
    _readerViewController.isHighlightShown
        .removeListener(_onHighlightVisibilityChanged);
    _readerViewController.tappedWordOwner
        .removeListener(_onWordTappedElsewhere);
    super.dispose();
  }

  void _onHighlightVisibilityChanged() {
    if (mounted) setState(() {});
  }

  /// A word tapped in another block takes the mark from this one.
  void _onWordTappedElsewhere() {
    if (!mounted || lookupWord == null) return;
    if (identical(_readerViewController.tappedWordOwner.value, this)) return;
    setState(() {
      lookupWord = null;
      highlightedWordIndex = null;
    });
  }

  @override
  void didUpdateWidget(PaliPageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldKey = oldWidget.blockIndex ?? oldWidget.pageNumber;
    if (oldKey != _blockKey) _forgetShown(oldKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Handle search result scroll - uses Scrollable.ensureVisible for better
      // alignment. Only when the current match actually moved, so that
      // unrelated rebuilds ( font size, theme, tts ) leave the scroll alone.
      if (widget.founds != null &&
          widget.currentOccurrence != null &&
          widget.currentOccurrence != oldWidget.currentOccurrence) {
        _scrollToCurrentSearchResult();
      }

      // Handle highlighted word scroll only when the highlight actually changed
      // (i.e., a new TOC/goto jump), not on every rebuild
      if (widget.highlightedWord != oldWidget.highlightedWord &&
          widget.highlightedWord != null &&
          widget.pageToHighlight == widget.pageNumber) {
        _scrollToHighlightedWordResult();
      }
    });
  }

  void _scrollToCurrentSearchResult() {
    // Waits out a glide to another page, as the highlight scroll does.
    Future.delayed(_readerViewController.untilGlideEnds, () {
      if (mounted) _scrollToResultContext(_scrollKey.currentContext);
    });
  }

  void _scrollToHighlightedWordResult() {
    // After the glide that brought the block here, if one is running: a
    // scroll started during it cut it short.
    Future.delayed(_kScrollDelayDuration + _readerViewController.untilGlideEnds,
        () {
      if (!mounted) return;

      final context = _highlightedWordScrollKey.currentContext;
      if (context == null) return;

      // A page is drawn as several chunk widgets and each of them is built
      // afresh every time it scrolls back into view. The controller hands out
      // one ticket per navigation, so only the first chunk holding a match
      // scrolls. Without it every rebuilt chunk pulled the list towards its own
      // highlight, which is what dragged the reader back to the last match on
      // the page as soon as they tried to scroll.
      if (!_readerViewController.mayScrollToHighlight(widget.blockIndex)) {
        return;
      }
      if (!_readerViewController.takePendingHighlightScroll()) {
        return;
      }

      if (_revealInList(context, ReaderMotion.landAt)) return;

      Scrollable.ensureVisible(context,
          alignment: ReaderMotion.landAt,
          duration: ReaderMotion.of(context),
          curve: ReaderMotion.curve);
    });
  }

  void _scrollToTtsNode() {
    Future.delayed(_kScrollDelayDuration, () {
      if (!mounted) return;

      final context = _ttsScrollKey.currentContext;
      if (context == null) return;
      final target = context.findRenderObject();
      final scrollable = Scrollable.maybeOf(context);
      if (target == null || scrollable == null) return;
      final viewport = RenderAbstractViewport.maybeOf(target);
      if (viewport == null) return;

      // Where the sentence begins, as a fraction of the screen from the top.
      // Left alone while it is comfortably in view, so the page does not
      // move at every sentence; brought up to a fifth of the way down once
      // it nears the bottom or has gone off either edge. The marker has no
      // height, so revealing it only at the bottom edge — which is what
      // "keep visible" does — left the words being spoken just out of view.
      final position = scrollable.position;
      final top = viewport.getOffsetToReveal(target, 0.0).offset;
      final fraction = (top - position.pixels) / position.viewportDimension;
      if (fraction >= 0.02 && fraction <= 0.6) return;
      Scrollable.ensureVisible(context,
          alignment: 0.2, duration: const Duration(milliseconds: 300));
    });
  }

  /// Brings the mark at [markContext] to [at] by moving this whole block in
  /// the reader's list; see [ReaderViewController.revealMark]. False where
  /// that cannot be done, and the caller scrolls the old way.
  bool _revealInList(BuildContext markContext, double at) {
    final block = widget.blockIndex;
    final reveal = _readerViewController.revealMark;
    final mark = markContext.findRenderObject();
    final self = context.findRenderObject();
    if (block == null ||
        reveal == null ||
        mark is! RenderBox ||
        self is! RenderBox ||
        !mark.attached ||
        !self.attached) {
      return false;
    }
    final offset = mark.localToGlobal(Offset.zero, ancestor: self).dy;
    return reveal(block, offset, at);
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
          if (_revealInList(currentContext, alignment)) return;
          Scrollable.ensureVisible(
            currentContext,
            alignment: alignment,
            duration: ReaderMotion.of(context),
            curve: ReaderMotion.curve,
          );
        }
      }
    }
  }

  /// Tags what is drawn in a block but is not its text.
  static const _notText = Object();

  int findOccurrencesBefore(String word, RenderParagraph target) {
    final root = _textKey.currentContext?.findRenderObject();
    if (root == null) return 0;
    int occurrencesBefore = 0;
    for (final paragraph in _paragraphsIn(root)) {
      if (paragraph == target) break;
      occurrencesBefore += word.allMatches(_fullText(paragraph)).length;
    }
    return occurrencesBefore;
  }

  /// The outermost paragraphs in [root], in reading order.
  ///
  /// Not the X-ray links: they are drawn between the lines but are no part
  /// of the text the marks are placed in.
  List<RenderParagraph> _paragraphsIn(RenderObject root) {
    final found = <RenderParagraph>[];
    void visit(RenderObject o) {
      if (o is RenderMetaData && identical(o.metaData, _notText)) return;
      if (o is RenderParagraph) {
        found.add(o);
      } else {
        o.visitChildren(visit);
      }
    }

    visit(root);
    return found;
  }

  /// The text of [paragraph] with the text of each widget in its lines in
  /// that widget's place. A boxed word is such a widget, with a paragraph of
  /// its own, and the line around it has only a placeholder for it; read
  /// alone, the word was missing from the line and the words after it were
  /// counted one short. [offsets] is given, for each paragraph read, where
  /// each of its own characters falls in the whole.
  String _fullText(RenderParagraph paragraph,
      [Map<RenderParagraph, List<int>>? offsets]) {
    final out = StringBuffer();
    void read(RenderParagraph paragraph) {
      final own = paragraph.text.toPlainText();
      final children = <RenderObject>[];
      paragraph.visitChildren(children.add);
      final at = <int>[];
      var child = 0;
      for (var i = 0; i < own.length; i++) {
        at.add(out.length);
        if (own.codeUnitAt(i) == 0xFFFC && child < children.length) {
          _paragraphsIn(children[child++]).forEach(read);
        } else {
          out.writeCharCode(own.codeUnitAt(i));
        }
      }
      at.add(out.length);
      offsets?[paragraph] = at;
    }

    read(paragraph);
    return out.toString();
  }

  @override
  Widget build(BuildContext context) {
    int fontSize = context.watch<ReaderFontProvider>().fontSize;
    // Turning X-ray, the alternate Pāḷi or the page numbers on or off
    // redraws the page with or without them.
    context.watch<ThemeChangeNotifier>().xray;
    final fontName = FontUtils.getfontName(
        script: context.read<ScriptLanguageProvider>().currentScript);
    final readerViewController =
        Provider.of<ReaderViewController>(context, listen: false);

    return ValueListenableBuilder<TtsPosition?>(
      valueListenable: context.read<TtsService>().position,
      builder: (context, position, child) {
        // Only the block holding the sentence being read marks it.
        final spoken = position != null &&
                position.bookUuid == readerViewController.bookUuid &&
                position.page == widget.pageNumber &&
                widget.htmlContent
                    .contains('<a name="${position.sentence}"></a>')
            ? position
            : null;
        if (spoken != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToTtsNode();
          });
        }
        final beside = _sideBySideLanguage(context);
        String html = _formatContent(
            widget.htmlContent, widget.script, context, spoken, beside);
        final rows = beside == null ? null : SideBySide.split(html);
        // A block that could not be split is drawn whole, without the marks
        // left for cutting it, which would show as boxes.
        if (rows == null && beside != null) {
          html = html
              .replaceAll(SideBySide.rowBreak, '')
              .replaceAll(SideBySide.columnBreak, '');
        }

        return _withinReadingWidth(
            fontSize,
            rows != null,
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Container(
                color: Colors.transparent,
                child: GestureDetector(
                  onTapUp: (details) {
                    final renderObject =
                        _textKey.currentContext?.findRenderObject();
                    if (renderObject == null) return;

                    final box = renderObject as RenderBox;

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

                      // A boxed word has a paragraph of its own inside the
                      // line's; the word is read in the line around it.
                      var line = target;
                      var inText = true;
                      for (var o = target.parent;
                          o != null && o != box;
                          o = o.parent) {
                        if (o is RenderParagraph) line = o;
                        if (o is RenderMetaData &&
                            identical(o.metaData, _notText)) {
                          inText = false;
                        }
                      }
                      // An X-ray link takes its own tap.
                      if (!inText) break;
                      final offsets = <RenderParagraph, List<int>>{};
                      final text = _fullText(line, offsets);
                      final own = offsets[target]!;
                      final p =
                          target.getPositionForOffset(entry.localPosition);
                      if (p.offset >= own.length - 1) break;
                      final int offset = own[p.offset];

                      if (offset < text.length) {
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
                            text.substring(0, offset - leftChars.length);
                        final occurrencesInTextBefore =
                            word.allMatches(textBefore).length;
                        final wordIndex = findOccurrencesBefore(word, line) +
                            occurrencesInTextBefore;

                        // Reading aloud starts from the sentence tapped.
                        readerViewController.noteTappedSentence(
                            widget.pageNumber,
                            TtsHighlight.sentenceAt(
                                widget.htmlContent, word, wordIndex));

                        // Tapping a word puts the goto/search highlight away for
                        // the whole book. It used to be cleared only in the chunk
                        // that was tapped, leaving the rest of the page marked.
                        _readerViewController.clearHighlights();

                        if (word == lookupWord &&
                            highlightedWordIndex == wordIndex) {
                          setState(() {
                            highlightedWord = null;
                            _isLocalHighlight = false;
                            lookupWord = null;
                            highlightedWordIndex = null;
                            _pageToHighlight = null;
                          });
                        } else {
                          setState(() {
                            widget.onClick?.call(word);
                            highlightedWord = null;
                            _isLocalHighlight = false;
                            lookupWord = word;
                            highlightedWordIndex = wordIndex;

                            _pageToHighlight = widget.pageNumber;
                          });
                          _readerViewController.tappedWordOwner.value = this;
                        }
                      }
                      // The line around a boxed word is in the path too, and
                      // would take the tap a second time.
                      break;
                    }
                  },
                  child: Container(
                    key: _textKey,
                    child: rows == null
                        ? _htmlView(html, fontSize, fontName, key: _htmlKey)
                        : _sideBySideView(rows, fontSize, fontName),
                  ),
                ),
              ),
            ));
      },
    );
  }

  /// The translation shown beside the Pāḷi, when the reader has asked for
  /// the two side by side: the first of those shown. Null to draw the block
  /// as usual, one language under the other.
  String? _sideBySideLanguage(BuildContext context) {
    if (!Prefs.sideBySide ||
        Prefs.textDisplayMode != TextDisplayMode.paliAndTranslation) {
      return null;
    }
    try {
      return context.read<ShownLanguagesProvider>().shownLanguages.firstOrNull;
    } catch (_) {
      return null; // not provided, as in a test of the page alone
    }
  }

  /// A bilingual block side by side, one row to a sentence.
  Widget _sideBySideView(
      List<(String, String)> rows, int fontSize, String? fontName) {
    return Padding(
      padding: EdgeInsets.only(bottom: fontSize.toDouble()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (pali, translation) in rows)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _htmlView(pali, fontSize, fontName)),
                SizedBox(width: fontSize.toDouble()),
                Expanded(
                    child: translation.isEmpty
                        ? const SizedBox.shrink()
                        : _htmlView(translation, fontSize, fontName)),
              ],
            ),
        ],
      ),
    );
  }

  /// The block, or one cell of it side by side, as the reader draws it.
  Widget _htmlView(String html, int fontSize, String? fontName, {Key? key}) {
    return HtmlWidget(
      key: key,
      html,
      factoryBuilder: () => WidgetFactory(),
      textStyle: TextStyle(
          fontSize: fontSize.toDouble(), inherit: true, fontFamily: fontName),
      customStylesBuilder: (element) {
        if (element.localName == 'a') {
          final isHighlight =
              element.parent!.className.contains('search-highlight') == true;
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
          // A phrase in a box could not wrap at the end of a line.
          return _markStyle(boxed: !element.text.trim().contains(' '));
        }
        // no style
        return {'text-decoration': 'none'};
      },
      customWidgetBuilder: (element) {
        if (element.localName == 'xray') {
          final links = XrayIndex.linksOf(
              int.tryParse(element.attributes['data-x'] ?? '') ?? -1);
          if (links == null || links.isEmpty) return const SizedBox.shrink();
          // Marked as not the text: its labels are drawn on the page but
          // are not in the block's HTML, and counted as words they put a
          // tapped word's mark on the wrong one, or on none.
          return MetaData(
              metaData: _notText,
              child:
                  XrayLinksView(links: links, fontSize: fontSize.toDouble()));
        }

        if (element.localName == 'span' && element.className == 'linebreak') {
          return const InlineCustomWidget(
              child: SizedBox(
            height: 0.0,
            child: Text('\n '),
          ));
        }

        if (element.localName == 'a' && element.className == 'bookmark') {
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
        if (element.localName == 'a' && element.className == 'scroll_to_term') {
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
        if (element.localName == 'a' && element.className == 'scroll_to_tts') {
          return InlineCustomWidget(
            child: SizedBox.shrink(key: _ttsScrollKey),
          );
        }

        // Hide empty anchor tags that are causing red 'X' rendering errors
        if (element.localName == 'a' &&
            element.attributes.containsKey('name') &&
            !element.attributes.containsKey('href') &&
            element.text.trim().isEmpty) {
          return const SizedBox.shrink();
        }

        return null;
      },
      onTapUrl: (word) {
        if (widget.onClick != null) {
          // #goto is used for scrolling to selected text
          if (word != '#goto') {
            setState(() {
              highlightedWord = word;
              // Asked for by this tap, so the book-wide clear does
              // not apply to it.
              _isLocalHighlight = true;
              widget.onClick!(word);
            });
          }
        }
        return false;
      },
    );
  }

  /// Keeps lines to a comfortable length on wide screens.
  ///
  /// Text that ran the full width of a desktop window made lines too long to
  /// follow back to the next one. The limit is in step with the font size, so
  /// a larger font keeps about the same number of words to a line.
  ///
  /// Side by side there are two columns of text, each given that width.
  Widget _withinReadingWidth(int fontSize, bool twoColumns, Widget child) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: fontSize * (twoColumns ? 80.0 : 40.0)),
        child: child,
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

  String _formatContent(
      String content, Script script, BuildContext context, TtsPosition? spoken,
      [String? sideBySide]) {
    // Side by side, only the translation beside the Pāḷi is drawn. Taken out
    // first, so what is counted and underlined below is what is shown.
    if (sideBySide != null) {
      content = SideBySide.keepOnly(content, sideBySide);
    }
    content = _removeHiddenTags(content);
    content = _addLineBreak(content);

    if (lookupWord != null) {
      content = _addUnderline(content, lookupWord!);
    }

    if (highlightedWord != null &&
        (_isLocalHighlight || _readerViewController.isHighlightShown.value)) {
      content = _addHighlight(content, highlightedWord!);
      content = _addHighlightedWordScrollAnchor(content);
    }

    if (widget.founds != null) {
      content = _addHighlightToSearchIndex(content);
    }

    if (spoken != null) {
      content =
          TtsHighlight.highlight(content, spoken.sentence, spoken.language);
    }
    // The sentence markers have done their work; drawn, each would be an
    // empty widget in the middle of the text.
    // Side by side, the places to cut the block into rows are marked while
    // the sentence markers are still there to show where sentences begin.
    if (sideBySide != null) content = SideBySide.mark(content);
    content = content.replaceAll(PageComposer.sentenceMarkers, '');
    if (!Prefs.xray ||
        Prefs.textDisplayMode == TextDisplayMode.translationOnly) {
      content = content.replaceAll(PageComposer.xrayTags, '');
    } else {
      // The links are a block of their own, so the line break before the
      // translation would leave a blank line under them, and the
      // translation would sit nearer the next Pāḷi than its own.
      content = content.replaceAllMapped(_xrayThenBreak, (m) => m.group(1)!);
    }

    if (!Prefs.isShowAlternatePali) {
      content = _removeAlternatePali(content);
    }
    content = _formatWithUserSetting(content);
    _readerViewController.shownBlocks[_blockKey] = _shown = ShownBlock(
        widget.pageNumber,
        content
            .replaceAll(SideBySide.rowBreak, '')
            .replaceAll(SideBySide.columnBreak, '')
            .replaceAll(PageComposer.xrayTags, ''),
        paraId: int.tryParse(
            _firstSentence.firstMatch(widget.htmlContent)?.group(1) ?? ''));
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

  static final _tagPattern = RegExp(r'<[^>]*>');

  /// Where [word] is in the text of [html], not in its tags. The tapped word
  /// is found by counting it in the text on screen; counted in the tags too,
  /// a short word such as "te" or "ti" (in `palitext`, `translation`) was
  /// marked somewhere else, or nowhere.
  static List<Match> _inText(String word, String html) {
    final tags = _tagPattern.allMatches(html).toList();
    var t = 0;
    final out = <Match>[];
    for (final m in word.allMatches(html)) {
      while (t < tags.length && tags[t].end <= m.start) {
        t++;
      }
      if (t < tags.length && tags[t].start < m.end) continue; // in a tag
      out.add(m);
    }
    return out;
  }

  String _addUnderline(String content, String lookupWord) {
    if (lookupWord.isEmpty) return content;
    final hwi = highlightedWordIndex;
    final underlinedHighlight =
        '<span class = "underlined_highlight">$lookupWord</span>';
    final matches = _inText(lookupWord, content);
    if (hwi != null && matches.length > hwi) {
      final match = matches.elementAt(hwi);
      return content.replaceRange(match.start, match.end, underlinedHighlight);
    }
    return content;
  }

  String _addHighlightToSearchIndex(String content) {
    if (widget.founds?.isEmpty ?? true) return content;

    final termInScript = _inReadingScript(widget.founds!.first.term);
    if (termInScript.isEmpty) return content;

    return SearchHighlight.highlight(
      content,
      termInScript,
      current: widget.currentOccurrence,
      cssClass: searchTermCssClass,
      currentCssClass: currentSearchTermCssClass,
      anchorCssClass: 'scroll_to_term',
      hiddenClasses: SearchHighlight.hiddenIn(Prefs.textDisplayMode),
    );
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
    // The block alone. Written out whole, the parser wraps it in
    // <html><head></head><body>, and side by side then could not find the
    // paragraph to split and drew its cut marks as boxes in the text.
    return soup.body?.innerHtml ?? soup.toString();
  }

  /// A word picked out on the page, by a tap or by a search, tinted and
  /// boxed in the theme's colour. [boxed] false gives the tint alone,
  /// [strong] a deeper one.
  Map<String, String> _markStyle({bool boxed = true, bool strong = false}) {
    final accent = Theme.of(context).colorScheme.primary;
    final argb = accent.toARGB32();
    final alpha = (Prefs.darkThemeOn ? 0.28 : 0.14) * (strong ? 2 : 1);
    return {
      'color': 'inherit',
      'background-color': 'rgba(${(argb >> 16) & 0xFF}, ${(argb >> 8) & 0xFF}, '
          '${argb & 0xFF}, $alpha)',
      // A block in the line, so the tint fills the rounded box with a
      // little room either side of the word.
      if (boxed) ...{
        'display': 'inline-block',
        'border': '1px solid ${_toCssHex(argb)}',
        'border-radius': '4px',
        'padding': '0 2px',
      },
    };
  }

  String _markCss({bool boxed = true, bool strong = false}) =>
      _markStyle(boxed: boxed, strong: strong)
          .entries
          .map((e) => '${e.key}: ${e.value};')
          .join(' ');

  String _toCssHex(int colorValue) {
    return '#${(colorValue & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }

  String _changeToInlineStyle(String content) {
    // 1. SETUP VARIABLES (Same as your original code)
    int paliTextColorInt = Prefs.paliTextColor;
    if (paliTextColorInt == 0xFF000000 && Prefs.darkThemeOn) {
      paliTextColorInt = 0xFFFFFFFF;
    }
    String paliTextColorCss = _toCssHex(paliTextColorInt);

    // Detect Bilingual
    final bool isBilingual = content.contains('palitext') ||
        content.contains('english_text') ||
        content.contains('translation_text');

    final bool showTranslation =
        Prefs.textDisplayMode == TextDisplayMode.paliAndTranslation ||
            Prefs.textDisplayMode == TextDisplayMode.translationOnly;

    final bool showPali = Prefs.textDisplayMode == TextDisplayMode.paliOnly ||
        Prefs.textDisplayMode == TextDisplayMode.paliAndTranslation;

    // Join lines if needed
    if (isBilingual && (!showTranslation || !showPali)) {
      content =
          content.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ');
    }

    // Prepare Base Styles
    final String boldStyle = Prefs.isPaliBold ? "font-weight:bold; " : "";

    final translationStyle = showTranslation
        ? "font-size: 0.9em; color: ${_toCssHex(Prefs.translationColor)};"
        : "display: none;";

    final paliStyle =
        showPali ? "${boldStyle}color: $paliTextColorCss;" : "display: none;";

    String baseStyle;
    if (isBilingual) {
      String themeColor = (Prefs.darkThemeOn) ? "white" : "black";
      baseStyle = "color: $themeColor;";
    } else {
      baseStyle = "${boldStyle}color: $paliTextColorCss;";
    }

    // 2. DEFINE THE STYLE MAP
    // Map class names (keys) to their CSS styles (values)
    final Map<String, String> styleMap = {
      // Dynamic Classes
      'palitext': paliStyle,
      'translation_text': translationStyle,
      'english_text': translationStyle,
      'vietnamese_text': translationStyle,
      'pageheader': translationStyle,

      // Formatting
      'bld': 'font-weight:bold; color: inherit;',
      't5': 'font-weight:bold; color: inherit;',
      't1': baseStyle,
      't3': 'font-size: 1.7em; font-weight:bold; color: $paliTextColorCss;',
      't2': 'font-size: 1.7em; font-weight:bold; color: $paliTextColorCss;',
      'th31':
          'font-size: 1.7em; text-align:center; font-weight: bold; color: $paliTextColorCss;',
      'centered': 'text-align:center; $baseStyle',
      'paranum': 'font-weight: bold; $baseStyle',
      'indent': 'text-indent:1.3em; margin-left:2em; $baseStyle',
      'bodytext': 'text-indent:1.3em; $baseStyle',
      'unindented': baseStyle,
      'noindentbodytext': baseStyle,

      // Headings from the sentence data, sized by level: 1 is the book,
      // 2 a vagga or sutta, then sections. 0 is a title line at the head of
      // a book ("Namo tassa…", the nikāya's name).
      'heading0':
          'font-size: 1.3em; text-align:center; font-weight: bold; $baseStyle',
      'heading1':
          'font-size: 1.8em; text-align:center; font-weight: bold; $baseStyle',
      'heading2':
          'font-size: 1.55em; text-align:center; font-weight: bold; $baseStyle',
      'heading3':
          'font-size: 1.4em; text-align:center; font-weight: bold; $baseStyle',
      'heading4':
          'font-size: 1.25em; text-align:center; font-weight: bold; $baseStyle',
      'heading5':
          'font-size: 1.15em; text-align:center; font-weight: bold; $baseStyle',
      'heading6':
          'font-size: 1.1em; text-align:center; font-weight: bold; $baseStyle',
      'heading7':
          'font-size: 1.05em; text-align:center; font-weight: bold; $baseStyle',

      // Headers
      'book':
          'font-size: 1.9em; text-align:center; font-weight: bold; $baseStyle',
      'chapter':
          'font-size: 1.7em; text-align:center; font-weight: bold; $baseStyle',
      'nikaya':
          'font-size: 1.6em; text-align:center; font-weight: bold; $baseStyle',
      'title':
          'font-size: 1.3em; text-align:center; font-weight: bold; $baseStyle',
      'subhead':
          'font-size: 1.6em; text-align:center; font-weight: bold; $baseStyle',
      'subsubhead':
          'font-size: 1.6em; text-align:center; font-weight: bold; $baseStyle',

      // Verses
      'gatha1': 'margin-bottom: 0em; margin-left: 5em; $baseStyle',
      'gatha2': 'margin-bottom: 0em; margin-left: 5em; $baseStyle',
      'gatha3': 'margin-bottom: 0em; margin-left: 5em; $baseStyle',
      'gathalast': 'margin-bottom: 1.3em; margin-left: 5em; $baseStyle',

      // Misc
      'note': 'font-size: 0.8em; color: gray;',
      'highlightedSearch': 'background: #FFE959; color: #000;',

      // Variables from your class
      // A match can be part of a word, or cut in pieces by a tag, so these
      // are tinted only: a box could break the word at the end of a line.
      searchTermCssClass: _markCss(boxed: false),
      currentSearchTermCssClass: _markCss(boxed: false, strong: true),
      'tts_highlighted': 'background: yellow; color: black;',
      'underlined_highlight': _markCss(),
    };

    // 3. SINGLE PASS REPLACEMENT (The Fix)
    // Matches class="..." and captures the content inside.
    final classRegex = RegExp(r'class\s*=\s*"([^"]*)"');

    content = content.replaceAllMapped(classRegex, (match) {
      String classNames = match.group(1) ?? "";
      List<String> classes = classNames.split(RegExp(r'\s+'));
      List<String> styles = [];

      for (var className in classes) {
        if (styleMap.containsKey(className)) {
          styles.add(styleMap[className]!);
        }
      }

      // If we found styles, return a style attribute.
      // If we didn't find any known classes, we return the original class attribute (optional safe fallback)
      if (styles.isNotEmpty) {
        return 'style="${styles.join(' ')}"';
      } else {
        return match.group(0)!;
      }
    });

    return _withTranslationFonts(content);
  }

  static final _translationStyle = RegExp(r'style="([^"]*)" lang="([^"]*)"');

  /// Each translation in the font chosen for its language in Settings ›
  /// Theme. Without one it is drawn in the Pāḷi font, as it always was.
  String _withTranslationFonts(String content) {
    if (!content.contains(' lang="')) return content;
    return content.replaceAllMapped(_translationStyle, (m) {
      final font = Prefs.translationFontName(m.group(2)!);
      if (font.isEmpty) return m.group(0)!;
      return 'style="${m.group(1)} font-family: \'$font\';" '
          'lang="${m.group(2)}"';
    });
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

    if (widget.isFirstChunkOfPage) {
      return '''
              <p style="color:brown;text-align:right;">$bookmarkTags ${_getScriptPageNumber(widget.pageNumber)}</p>
              $pageContent
      ''';
    } else {
      return pageContent;
    }
  }

  String _getScriptPageNumber(int pageNumber) {
    return PaliScript.getScriptOf(
      script: context.watch<ScriptLanguageProvider>().currentScript,
      romanText: (pageNumber.toString()),
    );
  }

  /// [text] in the script the Pali is shown in, when it is Roman Pali.
  ///
  /// Words in any other script are a translation's, found by searching the
  /// translations as typed, and are highlighted as they are. Converted, a
  /// Sinhala word came out half Roman (අතැවැසි as "atැvැsi") and matched
  /// nothing on the page.
  String _inReadingScript(String text) {
    if (ScriptDetector.getLanguage(text) != Script.roman) return text;
    return PaliScript.getScriptOf(
        script: context.read<ScriptLanguageProvider>().currentScript,
        romanText: text);
  }

  String _addHighlight(String content, String textToHighlight,
      {highlightClass = "highlighted", addId = true}) {
    // Nothing to find. Searching for "" matches between every character and
    // would put a span between each letter of the page.
    if (textToHighlight.trim().isEmpty) return content;
    final hwi = highlightedWordIndex;
    if (!Prefs.multiHighlight && hwi != null) {
      final highlighted =
          '<span id="$kGotoID" class = "$highlightClass">$textToHighlight</span>';
      final matches = _inText(textToHighlight, content);
      if (matches.length > hwi) {
        final match = matches.elementAt(hwi);
        return content.replaceRange(match.start, match.end, highlighted);
      }
    }

    // Determine the query mode from the controller
    final queryMode =
        Provider.of<ReaderViewController>(context, listen: false).queryMode;

    // Convert search term to current script
    final scriptTextToHighlight = _inReadingScript(textToHighlight);

    // ==============================
    // PREFIX and DISTANCE modes:
    // Each word is a prefix — highlight any word starting with it
    // ==============================
    if (queryMode == QueryMode.prefix || queryMode == QueryMode.distance) {
      final words = scriptTextToHighlight
          .trim()
          .split(' ')
          .where((w) => w.isNotEmpty)
          .toList();

      if (words.length > 1) {
        words.insert(0, words.join(''));
      }

      for (final word in words) {
        // Match the prefix word followed by any word characters (covers kamma -> kammassa, etc.)
        // Use lookahead/lookbehind for word boundaries: whitespace, quotes (including smart quotes), dashes, angle brackets, start/end
        final escapedWord = RegExp.escape(word);
        final pattern = RegExp(
          r'(?<=[\s",\u00a0>“”‘’\-\–\—]|^)' +
              escapedWord +
              r'[^\s",<“”‘’\-\–\—]*',
          caseSensitive: false,
        );
        // Only the text, never the tags. A match already inside a highlight
        // span is left alone; the old check looked back a fixed 60 characters,
        // which dropped the second of two adjacent search words.
        content = mapHtmlText(content, highlightClass, (text, insideHighlight) {
          if (insideHighlight) return text;
          return text.replaceAllMapped(
              pattern,
              (match) =>
                  '<span class="$highlightClass">${match.group(0)}</span>');
        });
      }
      // Land where the words come together, not on the first stray one.
      if (addId) {
        final searchWords = words.length > 1 ? words.sublist(1) : words;
        content = SearchCluster.markStart(content, highlightClass, searchWords,
            queryMode == QueryMode.distance ? Prefs.wordDistance : 0, kGotoID);
      }
      return content;
    }

    // ==============================
    // ANYWHERE mode:
    // Highlight any substring occurrence
    // ==============================
    if (queryMode == QueryMode.anywhere) {
      final pattern =
          RegExp(RegExp.escape(scriptTextToHighlight), caseSensitive: false);
      bool firstMatch = true;
      return mapHtmlText(content, highlightClass, (text, insideHighlight) {
        if (insideHighlight) return text;
        return text.replaceAllMapped(pattern, (match) {
          final matched = match.group(0)!;
          if (firstMatch && addId) {
            firstMatch = false;
            return '<span id="$kGotoID" class="$highlightClass">$matched</span>';
          }
          return '<span class="$highlightClass">$matched</span>';
        });
      });
    }

    // ==============================
    // EXACT mode (or no queryMode): existing behavior
    // ==============================
    textToHighlight = scriptTextToHighlight;

    if (!textToHighlight.contains(' ')) {
      final pattern = RegExp(
          '(?<=[\\s", ]|^)${RegExp.escape(textToHighlight)}(?=[\\s", ]|\$)');
      var found = false;
      final replaced = mapHtmlText(content, highlightClass, (text, _) {
        return text.replaceAllMapped(pattern, (match) {
          found = true;
          return '<span id="$kGotoID" class = "$highlightClass">'
              '${match.group(0)}</span>';
        });
      });
      if (found) return replaced;
    }

    // Word by word, as the bookmark text is: each word is marked wherever it
    // occurs in the text, and a word not found as it is is tried without a
    // closing quotative (ti, nti).
    final words =
        textToHighlight.trim().split(' ').where((w) => w.isNotEmpty).toList();
    for (final word in words) {
      final target = content.replaceAll(anyHtmlTag, ' ').contains(word)
          ? word
          : word.replaceAll(RegExp(r'(nti|ti)$'), '');
      if (target.isEmpty) continue;
      content = mapHtmlText(content, highlightClass, (text, insideHighlight) {
        if (insideHighlight) return text;
        return text.replaceAll(
            target, '<span class = "$highlightClass">$target</span>');
      });
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
