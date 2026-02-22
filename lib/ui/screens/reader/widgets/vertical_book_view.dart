import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:tipitaka_pali/providers/font_provider.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/ui/screens/reader/intents.dart';

import '../../../../app.dart';
import '../../../../business_logic/models/found_info.dart';
import '../../../../business_logic/models/found_state.dart';
import '../../../../business_logic/models/page_content.dart';
import '../../../../services/provider/script_language_provider.dart';
import '../../../../utils/pali_script.dart';
import '../controller/reader_view_controller.dart';
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
      this.onSelectionChanged});
  final ValueChanged<String>? onSearchedSelectedText;
  final ValueChanged<String>? onSharedSelectedText;
  final ValueChanged<String>? onClickedWord;
  final ValueChanged<String>? onSearchedInCurrentBook;
  final ValueChanged<String>? onAiContextRightClick;
  final ValueChanged<String>? onSelectionChanged;

  @override
  State<VerticalBookView> createState() => _VerticalBookViewState();
}

class _VerticalBookViewState extends State<VerticalBookView>
    implements
        PageUp,
        PageDown,
        ScrollUp,
        ScrollDown,
        IncreaseFont,
        DecreaseFont {
  late final ReaderViewController readerViewController;
  late final ItemPositionsListener itemPositionsListener;
  late final ItemScrollController itemScrollController;
  late final ScrollOffsetController scrollOffsetController;
  late final ScrollOffsetListener scrollOffsetListener;

  String searchText = '';

  SelectedContent? _selectedContent;

  // Todo calculate viewport height
  double viewportHeight = 500;
  // text line heihgt
  final double lineHeight = 56;

  @override
  void initState() {
    super.initState();
    readerViewController =
        Provider.of<ReaderViewController>(context, listen: false);
    itemPositionsListener = ItemPositionsListener.create();
    itemScrollController = ItemScrollController();
    scrollOffsetController = ScrollOffsetController();
    scrollOffsetListener = ScrollOffsetListener.create();

    scrollOffsetListener.changes.listen((_) {
      final start = readerViewController.book.firstPage;
      final pos = itemPositionsListener.itemPositions.value.toList();
      int target = -1;

      if (pos.length == 1) {
        target = start + pos.first.index;
      } else if (pos.length >= 3) {
        // When there are more than 3 pages displayed the entire content of the
        // second page is visible on the screen
        target = start + pos[1].index;
      } else if (pos.first.itemTrailingEdge == pos.last.itemLeadingEdge) {
        target = start + pos.first.index;
      } else {
        // At this point we're dealing with 2 pages
        // whichever page covers more area
        final page = pos.first.itemTrailingEdge > pos.last.itemLeadingEdge
            ? pos.first
            : pos.last;
        target = start + page.index;
      }

      readerViewController.gotoPage(pageNumber: target);
    });

    itemPositionsListener.itemPositions.addListener(_listenItemPosition);
    readerViewController.currentPage.addListener(_listenPageChange);
    readerViewController.foundState.addListener(_listenSearchIndexChanged);
  }

  @override
  void dispose() {
    itemPositionsListener.itemPositions.removeListener(_listenItemPosition);
    readerViewController.currentPage.removeListener(_listenPageChange);
    readerViewController.foundState.removeListener(_listenSearchIndexChanged);
    super.dispose();
  }

  static final Map<String, Widget> cachedPages = {};

  @override
  Widget build(BuildContext context) {
    int pageIndex = readerViewController.currentPage.value -
        readerViewController.book.firstPage;

    debugPrint('page index: $pageIndex');
    debugPrint('searchText-searchText: $searchText');

    return LayoutBuilder(builder: (context, constraints) {
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
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.equal):
              const IncreaseFontIntent(),
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.minus):
              const DecreaseFontIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            PageUpIntent: PageUpAction(this, context),
            PageDownIntent: PageDownAction(this, context),
            ScrollUpIntent: ScrollUpAction(this, context),
            ScrollDownIntent: ScrollDownAction(this, context),
            IncreaseFontIntent: IncreaseFontAction(this, context),
            DecreaseFontIntent: DecreaseFontAction(this, context),
          },
          child: Stack(
            children: [
              Row(
                children: [
                  Expanded(
                    child: SelectionArea(
                      contextMenuBuilder: (context, selectableRegionState) {
                        return AdaptiveTextSelectionToolbar.buttonItems(
                          anchors: selectableRegionState.contextMenuAnchors,
                          buttonItems: [
                            ...selectableRegionState.contextMenuButtonItems,
                            ContextMenuButtonItem(
                                onPressed: () {
                                  ContextMenuController.removeAny();
                                  widget.onSearchedSelectedText
                                      ?.call(_selectedContent!.plainText);
                                },
                                label: AppLocalizations.of(context)!.search),
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
                                  widget.onAiContextRightClick?.call(fullText);
                                },
                                label: AppLocalizations.of(context)!.aiContext),
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
                        _selectedContent = value;
                        widget.onSelectionChanged?.call(value?.plainText ?? '');
                      },
                      child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context)
                              .copyWith(scrollbars: false),
                          child: ScrollablePositionedList.builder(
                            initialScrollIndex: pageIndex,
                            itemScrollController: itemScrollController,
                            itemPositionsListener: itemPositionsListener,
                            scrollOffsetController: scrollOffsetController,
                            scrollOffsetListener: scrollOffsetListener,
                            addAutomaticKeepAlives: false,
                            itemCount: readerViewController.pages.length,
                            itemBuilder: (_, index) {
                              final PageContent pageContent =
                                  readerViewController.pages[index];
                              final script = context
                                  .read<ScriptLanguageProvider>()
                                  .currentScript;
                              // transciption

                              final id =
                                  '${readerViewController.book.name}-${readerViewController.book.id}-$index-$script';

                              final stopwatch = Stopwatch()..start();
                              String htmlContent = PaliScript.getCachedScriptOf(
                                script: script,
                                romanText: pageContent.content,
                                cacheId: id,
                                isHtmlText: true,
                              );

                              return Padding(
                                padding: index ==
                                        readerViewController.pages.length - 1
                                    ? const EdgeInsets.only(bottom: 100.0)
                                    : EdgeInsets.zero,
                                child: ValueListenableBuilder(
                                  valueListenable: readerViewController.foundState,
                                  builder: (_, foundState, __) {
                                    return PaliPageWidget(
                                      pageNumber: pageContent.pageNumber!,
                                      htmlContent: htmlContent,
                                      script: script,
                                      highlightedWord:
                                          readerViewController.textToHighlight,
                                      height: constraints.maxHeight,
                                      founds: _getFounds(
                                          pageContent.pageNumber!, foundState),
                                      currentOccurrence: _getCurrentOccurrence(
                                          pageContent.pageNumber!, foundState),
                                      onClick: widget.onClickedWord,
                                      book: readerViewController.book,
                                    );
                                  },
                                ),
                              );
                              // bookmarks: readerViewController.bookmarks,);
                            },
                          )),
                    ),
                  ),
                  PreferenceBuilder<bool>(
                    preference: context
                        .read<StreamingSharedPreferences>()
                        .getBool(hideScrollbarPref, defaultValue: false),
                    builder: (context, hideScrollbar) {
                      if (!hideScrollbar) {
                        return SizedBox(
                          width: 32,
                          height: constraints.maxHeight,
                          child: const VerticalBookSlider(),
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
    if (itemPositionsListener.itemPositions.value.length == 1) return;

    // Normally, maximum pages will not exceed two because of page height
    // Three pages is rare case.

    final firstPageOfBook = readerViewController.book.firstPage;
    final currentPage = readerViewController.currentPage.value;
    final upperPageInView = itemPositionsListener.itemPositions.value.first;
    final pageNumberOfUpperPage = upperPageInView.index + firstPageOfBook;
    final lowerPageInView = itemPositionsListener.itemPositions.value.last;
    final pageNumberOfLowerPage = lowerPageInView.index + firstPageOfBook;

    // scrolling down ( natural scrolling )
    //update lower page as current page
    if (lowerPageInView.itemLeadingEdge < 0.4 &&
        pageNumberOfLowerPage != currentPage) {
      myLogger.i('recorded current page: $currentPage');
      myLogger.i('lower page-height is over half');
      myLogger.i('page number of it: $pageNumberOfLowerPage');
      readerViewController.onGoto(pageNumber: pageNumberOfLowerPage);
      return;
    }

    // scrolling up ( natural scrolling )
    if (upperPageInView.itemTrailingEdge > 0.6 &&
        pageNumberOfUpperPage != currentPage) {
      myLogger.i('recorded current page: $currentPage');
      myLogger.i('upper page-height is over half');
      myLogger.i('page number of it: $pageNumberOfUpperPage');
      readerViewController.onGoto(pageNumber: pageNumberOfUpperPage);
      return;
    }
  }

  void _listenPageChange() {
    // page change are comming from others ( goto, tocs and slider )
    final firstPage = readerViewController.book.firstPage;
    final currenPage = readerViewController.currentPage.value;
    final pageIndex = currenPage - firstPage;

    final pagesInView = itemPositionsListener.itemPositions.value
        .map((itemPosition) => itemPosition.index)
        .toList();

    if (!pagesInView.contains(pageIndex)) {
      itemScrollController.jumpTo(index: pageIndex);
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
    if (mounted) {
      itemScrollController.scrollTo(
        index: currentFound.pageIndex,
        duration: const Duration(milliseconds: 200),
      );
    }
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

  int? _getCurrentOccurrence(int pageNumber, FoundState state) {
    if (state is FoundInitial || state is FoundEmpty) return null;
    final current = (state as FoundData).current;
    if (current == null) {
      return null;
    }
    if (state.founds[current].pageNumber != pageNumber) {
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

  @override
  void onIncreaseFontRequested(BuildContext context) {
    context.read<ReaderFontProvider>().onIncreaseFontSize();
    debugPrint("increase font");
  }

  @override
  void onDecreaseFontRequested(BuildContext context) {
    context.read<ReaderFontProvider>().onDecreaseFontSize();
    debugPrint("increase font");
  }
}
