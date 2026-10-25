import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:tipitaka_pali/utils/pali_script.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/services/tts/tts_service.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/ui/screens/reader/intents.dart';

import '../../../../app.dart';
import '../../../../business_logic/models/found_info.dart';
import '../../../../business_logic/models/found_state.dart';

import '../../../../services/provider/script_language_provider.dart';
import '../../../../utils/pali_script.dart';
import '../controller/reader_view_controller.dart';
import '../reader_motion.dart';
import '../../../widgets/keep_while_selecting.dart';
import '../../../widgets/copy_formatted_menu.dart';
import 'pali_page_widget.dart';
import 'vertical_book_slider.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';

class VerticalBookView extends StatefulWidget {
  const VerticalBookView(
      {super.key,
      this.onSearchedSelectedText,
      this.onSharedSelectedText,
      this.onClickedWord,
      this.onSearchedInCurrentBook,
      this.onAiContextRightClick,
      this.onCopyLink,
      this.onShareLink,
      this.onSelectionChanged,
      this.onCopyFormatted,
      this.onCopyPlain});
  final ValueChanged<String>? onSearchedSelectedText;
  final ValueChanged<String>? onSharedSelectedText;
  final ValueChanged<String>? onClickedWord;
  final ValueChanged<String>? onSearchedInCurrentBook;
  final ValueChanged<String>? onAiContextRightClick;
  final ValueChanged<String>? onCopyLink;
  final ValueChanged<String>? onShareLink;
  final ValueChanged<String>? onSelectionChanged;
  final ValueChanged<String>? onCopyFormatted;
  final ValueChanged<String>? onCopyPlain;

  @override
  State<VerticalBookView> createState() => _VerticalBookViewState();
}

class _VerticalBookViewState extends State<VerticalBookView>
    implements PageUp, PageDown, ScrollUp, ScrollDown {
  late final ReaderViewController readerViewController;
  late final ItemPositionsListener itemPositionsListener;
  late final ItemScrollController itemScrollController;
  late final ScrollOffsetController scrollOffsetController;
  late final ScrollOffsetListener scrollOffsetListener;

  String searchText = '';

  StreamSubscription<double>? _scrollOffsetSubscription;

  SelectedContent? _selectedContent;

  /// Whether some text is selected. While it is, every block that has been
  /// built is kept, even once scrolled out of view, as a block let go takes
  /// its part of the selection with it. Selecting a long passage by dragging
  /// down the page lost every block that passed through the view: the copy
  /// held the first block and the last, and nothing between.
  final ValueNotifier<bool> _selecting = ValueNotifier(false);

  // Saved scroll position for layout-change restoration
  bool _hasSavedScrollPosition = false;
  int _savedChunkIndex = 0;
  double _savedAlignment = 0.0;

  // Todo calculate viewport height
  double viewportHeight = 500;
  // text line heihgt
  final double lineHeight = 56;

  @override
  void initState() {
    super.initState();
    readerViewController =
        Provider.of<ReaderViewController>(context, listen: false);
    HardwareKeyboard.instance.addHandler(_onPageKey);
    itemPositionsListener = ItemPositionsListener.create();
    itemScrollController = ItemScrollController();
    scrollOffsetController = ScrollOffsetController();
    scrollOffsetListener = ScrollOffsetListener.create();

    _scrollOffsetSubscription = scrollOffsetListener.changes.listen((_) {
      // itemPositions is an unordered set, so sort it before reading entries
      // by position. Reading pos[1] out of an unsorted set reported a random
      // visible chunk and made the current page jitter.
      final positions = itemPositionsListener.itemPositions.value.toList()
        ..sort((a, b) => a.index.compareTo(b.index));

      if (positions.isEmpty) return;

      // Save current scroll position for layout-change restoration
      _hasSavedScrollPosition = true;
      _savedChunkIndex = positions.first.index;
      _savedAlignment = positions.first.itemLeadingEdge;

      int targetChunkIndex;
      if (positions.length == 1) {
        targetChunkIndex = positions.first.index;
      } else if (positions.length >= 3) {
        targetChunkIndex = positions[1].index;
      } else if (positions.first.itemTrailingEdge ==
          positions.last.itemLeadingEdge) {
        targetChunkIndex = positions.first.index;
      } else {
        final chunk =
            positions.first.itemTrailingEdge > positions.last.itemLeadingEdge
                ? positions.first
                : positions.last;
        targetChunkIndex = chunk.index;
      }

      int targetPage =
          readerViewController.getPageNumberForChunk(targetChunkIndex);
      readerViewController.gotoPage(pageNumber: targetPage);
    });

    itemPositionsListener.itemPositions.addListener(_listenItemPosition);
    readerViewController.currentPage.addListener(_listenPageChange);
    readerViewController.foundState.addListener(_listenSearchIndexChanged);
    _readingPosition = Provider.of<TtsService>(context, listen: false).position
      ..addListener(_followReading);
    readerViewController.revealMark = _revealMark;
    WidgetsBinding.instance.addPostFrameCallback((_) => _glideInIfStuck());
  }

  ValueNotifier<TtsPosition?>? _readingPosition;

  /// Keeps the sentence being read aloud on screen.
  ///
  /// The block holding it draws its own highlight and nudges it into view,
  /// but only a block that is built can do that. When the reading has moved
  /// past the blocks on screen — down the page, or on to the next one —
  /// the list is brought to it first.
  void _followReading() {
    final position = _readingPosition?.value;
    if (position == null ||
        position.bookUuid != readerViewController.bookUuid) {
      return;
    }
    final index = readerViewController.chunkIndexOfSentence(
        position.page, position.sentence);
    if (index < 0) return;
    if (index >= readerViewController.firstVisibleChunk &&
        index <= readerViewController.lastVisibleChunk) {
      return;
    }
    if (!itemScrollController.isAttached) return;
    itemScrollController.scrollTo(
      index: index,
      alignment: 0.1,
      duration: const Duration(milliseconds: 300),
    );
  }

  /// Keeps the same words at the top of the reader when its width changes:
  /// when a second book opens beside it, one beside it closes, or the side
  /// panel opens, closes or is dragged.
  ///
  /// The list holds its place as a distance from the block it last jumped
  /// to. At a new width every block in between is a new height, so that
  /// distance came to a different part of the book, far off after a long
  /// read. Instead, the block at the top and how far into it the view was
  /// are taken before the change, and that point is put back at the top
  /// once the width has settled.
  double? _laidOutWidth;
  Timer? _keepPlaceTimer;
  ({int index, double into})? _place;

  void _onWidth(double width) {
    final before = _laidOutWidth;
    _laidOutWidth = width;
    if (before == null || (before - width).abs() < 0.5) return;
    // Taken once for a run of changes, as while the panel is dragged, from
    // the last layout at the old width.
    _place ??= _topOfView();
    _keepPlaceTimer?.cancel();
    _keepPlaceTimer = Timer(const Duration(milliseconds: 80), () {
      final place = _place;
      _place = null;
      if (place != null) _putAtTop(place, retries: 2);
    });
  }

  /// The block at the top of the view, and the part of it above the top.
  ({int index, double into})? _topOfView() {
    for (final p in itemPositionsListener.itemPositions.value) {
      if (p.itemLeadingEdge <= 0 && p.itemTrailingEdge > 0) {
        final extent = p.itemTrailingEdge - p.itemLeadingEdge;
        return (index: p.index, into: -p.itemLeadingEdge / extent);
      }
    }
    return null;
  }

  void _putAtTop(({int index, double into}) place, {required int retries}) {
    if (!mounted || !itemScrollController.isAttached) return;
    ItemPosition? now;
    for (final p in itemPositionsListener.itemPositions.value) {
      if (p.index == place.index) now = p;
    }
    if (now == null) {
      // Moved out of view by the change. Brought back first, to be measured
      // at its new height.
      if (retries == 0) return;
      itemScrollController.jumpTo(index: place.index);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _putAtTop(place, retries: retries - 1));
      return;
    }
    final alignment =
        -place.into * (now.itemTrailingEdge - now.itemLeadingEdge);
    if ((now.itemLeadingEdge - alignment).abs() < 0.002) return;
    itemScrollController.jumpTo(index: place.index, alignment: alignment);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onPageKey);
    _keepPlaceTimer?.cancel();
    _scrollOffsetSubscription?.cancel();
    itemPositionsListener.itemPositions.removeListener(_listenItemPosition);
    _readingPosition?.removeListener(_followReading);
    readerViewController.currentPage.removeListener(_listenPageChange);
    readerViewController.foundState.removeListener(_listenSearchIndexChanged);
    _selecting.dispose();
    super.dispose();
  }

  static final Map<String, Widget> cachedPages = {};

  final _selectionArea = GlobalKey<SelectionAreaState>();
  final _menu = ContextMenuController();

  /// Where a right click on the selection asked for the menu; the menu goes
  /// there rather than at the selection's ends, which may be scrolled away.
  TextSelectionToolbarAnchors? _menuAt;

  /// The selection's own menu, at [position], for a right click that keeps
  /// the selection; see [CopyFormattedShortcuts.onRightClick].
  void _showMenuAt(Offset position) {
    final area = _selectionArea.currentState;
    final builder = area?.widget.contextMenuBuilder;
    if (area == null || builder == null) return;
    _menuAt = TextSelectionToolbarAnchors(primaryAnchor: position);
    ContextMenuController.removeAny();
    _menu.show(
      context: context,
      contextMenuBuilder: (menuContext) =>
          builder(menuContext, area.selectableRegion),
    );
  }

  void _copyPlain(String text) {
    final onCopyPlain = widget.onCopyPlain;
    if (onCopyPlain != null) {
      onCopyPlain(text);
    } else {
      Clipboard.setData(ClipboardData(text: text));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use saved scroll position if available (preserves offset during layout changes),
    // otherwise fall back to page-level chunk index (initial load)
    int initialScrollChunkIndex;
    double initialAlignment;
    if (_hasSavedScrollPosition) {
      initialScrollChunkIndex = _savedChunkIndex;
      initialAlignment = _savedAlignment;
    } else {
      final page = readerViewController.currentPage.value;
      initialScrollChunkIndex = _chunkHolding(page) ??
          readerViewController.getChunkIndexForPage(page);
      // Opened on a word, from a search result or a link, the block starts
      // low on the screen and the word glides up into place, so the reader
      // sees where it came in. See [_glideInIfStuck].
      final word = readerViewController.textToHighlight?.trim() ?? '';
      initialAlignment =
          word.isNotEmpty && ReaderMotion.glides(context) ? _openLow : 0.0;
      _openingChunk ??= initialScrollChunkIndex;
      _openingGlide ??= initialAlignment > 0;
    }

    debugPrint(
        'chunk index: $initialScrollChunkIndex, alignment: $initialAlignment');
    debugPrint('searchText-searchText: $searchText');

    return LayoutBuilder(builder: (context, constraints) {
      _onWidth(constraints.maxWidth);
      return Shortcuts(
        shortcuts: <LogicalKeySet, Intent>{
          LogicalKeySet(LogicalKeyboardKey.pageUp): const PageUpIntent(),
          LogicalKeySet(LogicalKeyboardKey.pageDown): const PageDownIntent(),
          LogicalKeySet(LogicalKeyboardKey.navigatePrevious):
              const PageUpIntent(),
          LogicalKeySet(LogicalKeyboardKey.navigateNext):
              const PageDownIntent(),
          LogicalKeySet(LogicalKeyboardKey.arrowUp): const ScrollUpIntent(),
          LogicalKeySet(LogicalKeyboardKey.arrowDown): const ScrollDownIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            PageUpIntent: PageUpAction(this, context),
            PageDownIntent: PageDownAction(this, context),
            ScrollUpIntent: ScrollUpAction(this, context),
            ScrollDownIntent: ScrollDownAction(this, context),
          },
          child: Stack(
            children: [
              Row(
                children: [
                  Expanded(
                    child: CopyFormattedShortcuts(
                      selectedText: () => _selectedContent?.plainText ?? '',
                      onCopy: (text) => widget.onCopyFormatted?.call(text),
                      onCopyPlain: _copyPlain,
                      onRightClick: _showMenuAt,
                      child: SelectionArea(
                          key: _selectionArea,
                          contextMenuBuilder: (context, selectableRegionState) {
                            return AdaptiveTextSelectionToolbar.buttonItems(
                              anchors: _menuAt ??
                                  selectableRegionState.contextMenuAnchors,
                              buttonItems: [
                                ...copyButtons(
                                    context,
                                    selectableRegionState,
                                    () => _selectedContent?.plainText ?? '',
                                    widget.onCopyFormatted,
                                    widget.onCopyPlain),
                                ContextMenuButtonItem(
                                    onPressed: () {
                                      ContextMenuController.removeAny();
                                      final bookName = PaliScript.getScriptOf(
                                        script: context
                                            .read<ScriptLanguageProvider>()
                                            .currentScript,
                                        romanText:
                                            readerViewController.book.name,
                                      );
                                      Clipboard.setData(
                                          ClipboardData(text: bookName));
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              '${AppLocalizations.of(context)!.copied}: $bookName'),
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                    label: AppLocalizations.of(context)!
                                        .copyBookName),
                                ContextMenuButtonItem(
                                    onPressed: () {
                                      ContextMenuController.removeAny();
                                      widget.onCopyLink?.call(
                                          _selectedContent?.plainText ?? '');
                                    },
                                    label:
                                        AppLocalizations.of(context)!.copyLink),
                                ContextMenuButtonItem(
                                    onPressed: () {
                                      ContextMenuController.removeAny();
                                      widget.onShareLink?.call(
                                          _selectedContent?.plainText ?? '');
                                    },
                                    label: AppLocalizations.of(context)!
                                        .shareLink),
                                ContextMenuButtonItem(
                                    onPressed: () {
                                      ContextMenuController.removeAny();
                                      widget.onSearchedSelectedText
                                          ?.call(_selectedContent!.plainText);
                                    },
                                    label:
                                        AppLocalizations.of(context)!.search),
                                ContextMenuButtonItem(
                                    onPressed: () {
                                      ContextMenuController.removeAny();
                                      widget.onSearchedInCurrentBook
                                          ?.call(_selectedContent!.plainText);
                                    },
                                    label: AppLocalizations.of(context)!
                                        .searchInCurrent),
                                ContextMenuButtonItem(
                                    onPressed: () {
                                      ContextMenuController.removeAny();
                                      final fullText =
                                          _selectedContent?.plainText ?? '';
                                      //final trimmed = fullText.length > 1800
                                      //  ? fullText.substring(0, 1800)
                                      //: fullText;
                                      widget.onAiContextRightClick
                                          ?.call(fullText);
                                    },
                                    label: AppLocalizations.of(context)!
                                        .aiContext),
                                ContextMenuButtonItem(
                                    onPressed: () {
                                      ContextMenuController.removeAny();
                                      widget.onSharedSelectedText
                                          ?.call(_selectedContent!.plainText);
                                      // Share.share(_selectedContent!.plainText,
                                      //     subject: 'Pāḷi text from TPR');
                                    },
                                    label: AppLocalizations.of(context)!.share),
                              ],
                            );
                          },
                          onSelectionChanged: (value) {
                            _menuAt = null;
                            _selectedContent = value;
                            _selecting.value =
                                value?.plainText.isNotEmpty ?? false;
                            widget.onSelectionChanged
                                ?.call(value?.plainText ?? '');
                          },
                          child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(context)
                                  .copyWith(scrollbars: false),
                              child: ScrollablePositionedList.builder(
                                key: _listKey,
                                initialScrollIndex: initialScrollChunkIndex,
                                initialAlignment: initialAlignment,
                                itemScrollController: itemScrollController,
                                itemPositionsListener: itemPositionsListener,
                                scrollOffsetController: scrollOffsetController,
                                scrollOffsetListener: scrollOffsetListener,
                                // Kept only while text is selected; see
                                // [_selecting].
                                addAutomaticKeepAlives: true,
                                itemCount: readerViewController.chunks.length,
                                itemBuilder: (_, index) {
                                  final pageChunk =
                                      readerViewController.chunks[index];
                                  final script = context
                                      .read<ScriptLanguageProvider>()
                                      .currentScript;
                                  // transciption

                                  final id =
                                      '${readerViewController.book.name}-${readerViewController.book.id}-$index-$script';

                                  final stopwatch = Stopwatch()..start();
                                  String htmlContent =
                                      PaliScript.getCachedScriptOf(
                                    script: script,
                                    romanText: pageChunk.htmlContent,
                                    cacheId: id,
                                    isHtmlText: true,
                                  );

                                  return KeepWhileSelecting(
                                      selecting: _selecting,
                                      child: Padding(
                                        padding: index ==
                                                readerViewController
                                                        .chunks.length -
                                                    1
                                            ? const EdgeInsets.only(
                                                bottom: 100.0)
                                            : EdgeInsets.zero,
                                        child: ValueListenableBuilder(
                                          valueListenable:
                                              readerViewController.foundState,
                                          builder: (_, foundState, __) {
                                            return PaliPageWidget(
                                              pageNumber: pageChunk.pageNumber,
                                              htmlContent: htmlContent,
                                              script: script,
                                              highlightedWord:
                                                  readerViewController
                                                      .textToHighlight,
                                              pageToHighlight:
                                                  readerViewController
                                                      .pageToHighlight,
                                              height: constraints.maxHeight,
                                              founds: _getFounds(
                                                  pageChunk.pageNumber,
                                                  foundState),
                                              currentOccurrence:
                                                  _getCurrentOccurrence(
                                                      index, foundState),
                                              onClick: widget.onClickedWord,
                                              book: readerViewController.book,
                                              isFirstChunkOfPage:
                                                  pageChunk.isFirstChunkOfPage,
                                              blockIndex: index,
                                            );
                                          },
                                        ),
                                      ));
                                  // bookmarks: readerViewController.bookmarks,);
                                },
                              ))),
                    ),
                  ),
                  PreferenceBuilder<bool>(
                    preference: context
                        .read<StreamingSharedPreferences>()
                        .getBool(hideScrollbarPref, defaultValue: false),
                    builder: (context, hideScrollbar) {
                      if (!hideScrollbar) {
                        // The control bar's pull tab sits over the bottom
                        // right corner, so the scrollbar stops short of it.
                        return SizedBox(
                          width: 32,
                          height: constraints.maxHeight,
                          child: const Padding(
                            padding: EdgeInsets.only(bottom: 32),
                            child: VerticalBookSlider(),
                          ),
                        );
                      } else {
                        return const SizedBox
                            .shrink(); // Return an empty widget when hideScrollbar is true.
                      }
                    },
                  ),
                ],
              ),
              if (Prefs.multiTabMode)
                Positioned(
                  top: 5,
                  left: 5,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      borderRadius: const BorderRadius.all(Radius.circular(5)),
                    ),
                    padding: const EdgeInsets.all(5),
                    child: Text(
                      readerViewController.book.name,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }

  // String? _needToHighlight(int index) {
  //   if (readerViewController.textToHighlight == null) return null;
  //   if (readerViewController.initialPage == null) return null;

  //   if (index ==
  //       readerViewController.initialPage! -
  //           readerViewController.book.firstPage) {
  //     return readerViewController.textToHighlight;
  //   }
  //   return null;
  // }

  void _listenItemPosition() {
    // if only one page exist in view, there in no need to update current page
    final positions = itemPositionsListener.itemPositions.value.toList();
    if (positions.isEmpty) return;

    // Which blocks are actually on screen, for reading aloud to start at the
    // top of what is showing and to know when the reading has moved off it.
    final showing = positions
        .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
        .map((p) => p.index)
        .toList()
      ..sort();
    if (showing.isNotEmpty) {
      readerViewController.firstVisibleChunk = showing.first;
      readerViewController.lastVisibleChunk = showing.last;
    }
    if (positions.length == 1) return;

    // ItemPositions are not guaranteed to be ordered by rendering, so we must sort them
    positions.sort((a, b) => a.index.compareTo(b.index));

    // Normally, maximum pages will not exceed two because of page height
    // Three pages is rare case.

    final currentPage = readerViewController.currentPage.value;
    final upperChunkInView = positions.first;
    final pageNumberOfUpperPage =
        readerViewController.getPageNumberForChunk(upperChunkInView.index);
    final lowerChunkInView = positions.last;
    final pageNumberOfLowerPage =
        readerViewController.getPageNumberForChunk(lowerChunkInView.index);

    // scrolling down ( natural scrolling )
    //update lower page as current page
    // Use gotoPage (not onGoto) so we only update the page number
    // without re-arming the highlight jump, which caused snap-back.
    if (lowerChunkInView.itemLeadingEdge < 0.4 &&
        pageNumberOfLowerPage != currentPage) {
      myLogger.i('recorded current page: $currentPage');
      myLogger.i('lower page-height is over half');
      myLogger.i('page number of it: $pageNumberOfLowerPage');
      readerViewController.gotoPage(pageNumber: pageNumberOfLowerPage);
      return;
    }

    // scrolling up ( natural scrolling )
    if (upperChunkInView.itemTrailingEdge > 0.6 &&
        pageNumberOfUpperPage != currentPage) {
      myLogger.i('recorded current page: $currentPage');
      myLogger.i('upper page-height is over half');
      myLogger.i('page number of it: $pageNumberOfUpperPage');
      readerViewController.gotoPage(pageNumber: pageNumberOfUpperPage);
      return;
    }
  }

  /// Where a block opened on a search result starts, as a fraction of the
  /// screen from the top. Low enough for the glide up to be seen, high
  /// enough that the block is built and can find its word.
  static const _openLow = 0.7;

  int? _openingChunk;
  bool? _openingGlide;

  /// The word normally brings itself into view once its block is built. If
  /// it has not by now (the word was not found in the text, or lies in a
  /// block further down), the block it opened on glides to the top instead
  /// of being left low on the screen.
  void _glideInIfStuck() {
    if (_openingGlide != true) return;
    Future.delayed(ReaderMotion.duration * 1.5, () {
      if (!mounted || !readerViewController.highlightScrollPending) return;
      final chunk = _openingChunk;
      if (chunk != null) _glideTo(chunk, alignment: ReaderMotion.landAt);
    });
  }

  /// See [ReaderViewController.revealMark]. A mark already comfortably in
  /// view, between a twentieth and half way down, is left where it is.
  bool _revealMark(int block, double offset, double at) {
    final height = _listKey.currentContext?.size?.height;
    if (!mounted || height == null || height <= 0) return false;
    if (!itemScrollController.isAttached) return false;
    final into = offset / height;
    for (final p in itemPositionsListener.itemPositions.value) {
      if (p.index != block) continue;
      final now = p.itemLeadingEdge + into;
      if (now >= 0.05 && now <= 0.5) return true;
    }
    _glideTo(block, alignment: at - into);
    return true;
  }

  /// The list itself, for its height on screen.
  final GlobalKey _listKey = GlobalKey();

  /// Moves the list to [index], at [alignment] (0 for the top).
  ///
  /// A block already on screen is scrolled to. A block further off is first
  /// jumped to from a little over a screen short of it, on the side it is
  /// coming from, and the text then scrolls that last stretch, so the reader
  /// sees it run in, as the contents list runs to its heading. The list's
  /// own animated move fades across instead of scrolling once the target is
  /// off screen, which showed nothing of where the text went.
  ///
  /// Both steps are in exact pixels, so the block lands where a jump would
  /// have put it, however tall the blocks between.
  void _glideTo(int index, {double alignment = 0}) {
    if (!itemScrollController.isAttached) return;
    final duration = ReaderMotion.of(context);
    final height = _listKey.currentContext?.size?.height;
    if (duration == Duration.zero || height == null || height <= 0) {
      itemScrollController.jumpTo(index: index, alignment: alignment);
      return;
    }
    final shown = itemPositionsListener.itemPositions.value
        .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
        .map((p) => p.index)
        .toList();
    readerViewController.noteGlide(duration + const Duration(milliseconds: 50));
    if (shown.contains(index)) {
      itemScrollController.scrollTo(
          index: index,
          alignment: alignment,
          duration: duration,
          curve: ReaderMotion.curve);
      return;
    }
    // Going forward, the text comes up from below; going back, down from
    // above.
    final forward =
        shown.isEmpty || index > shown.reduce((a, b) => a > b ? a : b);
    // A longer way than a scroll on screen, so a little more time for it:
    // the text on screen slides out, then the new text slides in.
    final outTime = duration * 0.6;
    final inTime = duration * 1.2;
    readerViewController
        .noteGlide(outTime + inTime + const Duration(milliseconds: 100));
    final glide = ++_glides;

    // Every move stays within a screen of what is laid out, alignment 0 to
    // 1, as the list supports. The run used to be made by jumping to screens
    // beyond the target (alignment 3.2), or by stepping screens away in one
    // frame; after a fast trackpad scroll the list could then not settle on
    // an offset ("RenderViewport exceeded its maximum number of layout
    // cycles"), the reader stopped, and the selection code tripped over text
    // that was never laid out. The far run is shown instead as two short
    // ones: what is on screen slides on and away, and the new place slides
    // in from the same side.
    final a = alignment.clamp(0.0, 1.0);
    void slideIn() {
      if (!mounted || glide != _glides || !itemScrollController.isAttached) {
        return;
      }
      if (forward) {
        // In at the foot of the screen, then up into place.
        itemScrollController.jumpTo(index: index, alignment: 1);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || glide != _glides) return;
          scrollOffsetController.animateScroll(
              offset: (1 - a) * height,
              duration: inTime,
              curve: Curves.easeOutCubic);
        });
      } else if (index + 1 < readerViewController.chunks.length) {
        // From the block after it, already laid out, back to it.
        itemScrollController.jumpTo(index: index + 1, alignment: 0);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              glide != _glides ||
              !itemScrollController.isAttached) {
            return;
          }
          itemScrollController.scrollTo(
              index: index,
              alignment: alignment,
              duration: inTime,
              curve: Curves.easeOutCubic);
        });
      } else {
        itemScrollController.jumpTo(index: index, alignment: alignment);
      }
    }

    // Out: the text on screen moves on, a screen's length the way the
    // reader is going, gathering speed.
    scrollOffsetController
        .animateScroll(
            offset: forward ? height : -height,
            duration: outTime,
            curve: Curves.easeInCubic)
        .then((_) => slideIn());
  }

  /// Counts glides, so one begun while another runs takes over from it
  /// rather than the two pulling the list each its own way.
  int _glides = 0;

  /// The block on [page] holding the place asked for: the search group, or
  /// the heading or word to mark. Null when nothing is to be marked or it is
  /// not found.
  ///
  /// That block alone may then scroll to its mark. Any block with one of the
  /// words could take it before: a heading such as "4. okkantasaṃyuttaṃ" was
  /// marked word by word, and the first "4." on the page won, leaving the
  /// heading itself near the bottom of the screen.
  int? _chunkHolding(int page) {
    final rc = readerViewController;
    final group = rc.highlightChunkFor(page);
    if (group != null) return group;
    final textToHighlight = rc.textToHighlight;
    if (textToHighlight == null || textToHighlight.isEmpty) return null;
    for (int i = rc.getChunkIndexForPage(page); i < rc.chunks.length; i++) {
      final chunk = rc.chunks[i];
      if (chunk.pageNumber != page) break;

      // Match exact anchor or literal word
      if (chunk.htmlContent.contains('name="$textToHighlight"') ||
          chunk.htmlContent.contains('id="$textToHighlight"') ||
          chunk.htmlContent.contains(textToHighlight)) {
        return rc.pinHighlightChunk(i);
      }

      // Match space-separated fallback
      final words = textToHighlight.trim().split(' ');
      bool containsAllWords = true;
      for (final word in words) {
        if (!chunk.htmlContent.contains(word)) {
          String trimmedWord = word.replaceAll(RegExp(r'(nti|ti)$'), '');
          if (!chunk.htmlContent.contains(trimmedWord)) {
            containsAllWords = false;
            break;
          }
        }
      }
      if (containsAllWords) return rc.pinHighlightChunk(i);
    }
    return null;
  }

  void _listenPageChange() {
    // A page change has two origins: an explicit navigation ( goto, toc,
    // search result, slider, opening a book ) and ordinary scrolling, which
    // only reports the page that has come into view. Only the first may move
    // the view; acting on the second made the text snap back while the reader
    // was scrolling it.
    if (!readerViewController.takePendingNavigation()) return;

    final currenPage = readerViewController.currentPage.value;
    final holding = _chunkHolding(currenPage);
    final bool foundHighlightChunk = holding != null;
    final int targetChunkIndex =
        holding ?? readerViewController.getChunkIndexForPage(currenPage);

    final chunksInView = itemPositionsListener.itemPositions.value
        .map((itemPosition) => itemPosition.index)
        .toList();

    if (foundHighlightChunk) {
      // Highlighting explicitly requests we look precisely at this chunk
      if (!chunksInView.contains(targetChunkIndex)) {
        _glideTo(targetChunkIndex, alignment: ReaderMotion.landAt);
      }
    } else {
      // Natural scroll page tracking - prevent snapbacks
      bool isPageCurrentlyInView = false;
      for (int chunkIndex in chunksInView) {
        if (readerViewController.getPageNumberForChunk(chunkIndex) ==
            currenPage) {
          isPageCurrentlyInView = true;
          break;
        }
      }

      if (!isPageCurrentlyInView) {
        _glideTo(targetChunkIndex, alignment: ReaderMotion.landAt);
      }
    }
  }

  void _listenSearchIndexChanged() {
    final state = readerViewController.foundState.value;
    if (state is FoundInitial || state is FoundEmpty) return;

    final founds = (state as FoundData).founds;

    final searchIndex = state.current;
    if (searchIndex == null) {
      return;
    }
    final currentFound = founds[searchIndex];
    if (currentFound.pageNumber == readerViewController.currentPage.value) {
      return;
    }
    final itemPositions = itemPositionsListener.itemPositions.value;
    for (var element in itemPositions) {
      if (element.index == currentFound.pageIndex) {
        return;
      }
    }
    myLogger.i('current found: $currentFound');
    if (mounted) _glideTo(currentFound.pageIndex);
  }

  List<FoundInfo>? _getFounds(int pageNumber, FoundState state) {
    if (state is FoundInitial || state is FoundEmpty) return null;
    final founds = (state as FoundData).founds;
    final temp =
        founds.where((element) => element.pageNumber == pageNumber).toList();
    if (temp.isEmpty) {
      return null;
    }
    return temp;
  }

  int? _getCurrentOccurrence(int chunkIndex, FoundState state) {
    if (state is FoundInitial || state is FoundEmpty) return null;
    final current = (state as FoundData).current;
    if (current == null) {
      return null;
    }
    // Occurrences are counted per chunk, so only the chunk that really holds
    // the current match may paint it. Matching on the page number instead
    // marked one match in every chunk of the page.
    if (state.founds[current].pageIndex != chunkIndex) {
      return null;
    }
    return state.founds[current].occurrenceInPage;
  }

  @override
  void onPageDownRequested(BuildContext context) {
    scrollOffsetController.animateScroll(
      offset: viewportHeight,
      duration: const Duration(milliseconds: 300),
    );
  }

  /// Page Up and Page Down turn the page of the book in the selected tab
  /// wherever the keyboard focus is, as Ctrl+F does. Through the reader's own
  /// shortcuts they only worked once its text had been clicked into, and
  /// after opening a book, or with the focus in a side pane, nothing moved.
  /// On a Mac, Fn+↑/↓ sends the same keys, and Option+↑/↓, the Mac's own
  /// way to page, does the same.
  ///
  /// Left alone while a text field has the keys, where they move the
  /// cursor, and while a dialog is open over the reader.
  bool _onPageKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    final optionArrow = defaultTargetPlatform == TargetPlatform.macOS &&
        keyboard.isAltPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isControlPressed;
    final bool down;
    if (key == LogicalKeyboardKey.pageDown ||
        (optionArrow && key == LogicalKeyboardKey.arrowDown)) {
      down = true;
    } else if (key == LogicalKeyboardKey.pageUp ||
        (optionArrow && key == LogicalKeyboardKey.arrowUp)) {
      down = false;
    } else {
      return false;
    }
    if (!mounted || !readerViewController.isSelectedTab()) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null &&
        (focused.widget is EditableText ||
            focused.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return false;
    }
    if (down) {
      onPageDownRequested(context);
    } else {
      onPageUpRequested(context);
    }
    return true;
  }

  @override
  void onPageUpRequested(BuildContext context) {
    scrollOffsetController.animateScroll(
      offset: -viewportHeight,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void onScrollDownRequested(BuildContext context) {
    scrollOffsetController.animateScroll(
      offset: lineHeight,
      duration: const Duration(milliseconds: 100),
    );
  }

  @override
  void onScrollUpRequested(BuildContext context) {
    scrollOffsetController.animateScroll(
      offset: -lineHeight,
      duration: const Duration(milliseconds: 100),
    );
  }
}
