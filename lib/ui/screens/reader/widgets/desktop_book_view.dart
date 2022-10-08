import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:tipitaka_pali/app.dart';
import 'package:tipitaka_pali/ui/screens/reader/widgets/vertical_book_slider.dart';
import 'package:tipitaka_pali/services/prefs.dart';

import '../../../../business_logic/models/page_content.dart';
import '../../../../providers/navigation_provider.dart';
import '../../../../services/provider/script_language_provider.dart';
import '../../../../utils/pali_script.dart';
import '../../../dialogs/dictionary_dialog.dart';
import '../../dictionary/controller/dictionary_controller.dart';
import '../controller/reader_view_controller.dart';
import 'pali_page_widget.dart';

class DesktopBookView extends StatefulWidget {
  const DesktopBookView({Key? key}) : super(key: key);

  @override
  State<DesktopBookView> createState() => _DesktopBookViewState();
}

class _DesktopBookViewState extends State<DesktopBookView> {
  late final ReaderViewController readerViewController;
  late final ItemPositionsListener itemPositionsListener;
  late final ItemScrollController itemScrollController;

  @override
  void initState() {
    super.initState();
    readerViewController =
        Provider.of<ReaderViewController>(context, listen: false);
    itemPositionsListener = ItemPositionsListener.create();
    itemScrollController = ItemScrollController();
    itemPositionsListener.itemPositions.addListener(_listenItemPosition);
    readerViewController.currentPage.addListener(_listenPageChange);
  }

  @override
  void dispose() {
    itemPositionsListener.itemPositions.removeListener(_listenItemPosition);
    readerViewController.currentPage.removeListener(_listenPageChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int pageIndex = readerViewController.currentPage.value -
        readerViewController.book.firstPage!;

    debugPrint('page index: $pageIndex');

    return LayoutBuilder(builder: (context, constraints) {
      return Row(
        children: [
          Expanded(
            child: ScrollConfiguration(
                behavior:
                    ScrollConfiguration.of(context).copyWith(scrollbars: false),
                child: ScrollablePositionedList.builder(
                  initialScrollIndex: pageIndex,
                  itemScrollController: itemScrollController,
                  itemPositionsListener: itemPositionsListener,
                  itemCount: readerViewController.pages.length,
                  itemBuilder: (_, index) {
                    final PageContent pageContent =
                        readerViewController.pages[index];
                    final script =
                        context.read<ScriptLanguageProvider>().currentScript;
                    // transciption
                    String htmlContent = PaliScript.getScriptOf(
                      script: script,
                      romanText: pageContent.content,
                      isHtmlText: true,
                    );

                    // return Text(content);
                    return PaliPageWidget(
                      pageNumber: pageContent.pageNumber!,
                      htmlContent: htmlContent,
                      script: script,
                      highlightedWord: _needToHighlight(index),
                      onClick: onClickedWord,
                    );
                  },
                )),
          ),
          SizedBox(
              width: 32,
              height: constraints.maxHeight,
              child: const VerticalBookSlider()),
        ],
      );
    });
  }

  String? _needToHighlight(int index) {
    if (readerViewController.textToHighlight == null) return null;
    if (readerViewController.initialPage == null) return null;

    if (index ==
        readerViewController.initialPage! -
            readerViewController.book.firstPage!) {
      return readerViewController.textToHighlight;
    }
    return null;
  }

  void _listenItemPosition() {
    // if only one page exist in view, there in no need to update current page
    if (itemPositionsListener.itemPositions.value.length == 1) return;

    // Normally, maximum pages will not exceed two because of page height
    // Three pages is rare case.

    final firstPageOfBook = readerViewController.book.firstPage!;
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
    final firstPage = readerViewController.book.firstPage!;
    final currenPage = readerViewController.currentPage.value;
    final pageIndex = currenPage - firstPage;

    final pagesInView = itemPositionsListener.itemPositions.value
        .map((itemPosition) => itemPosition.index)
        .toList();

    if (!pagesInView.contains(pageIndex)) {
      itemScrollController.jumpTo(index: pageIndex);
    }
  }

  Future<void> onClickedWord(String word) async {
    // removing puntuations etc.
    // convert to roman if display script is not roman
    word = PaliScript.getRomanScriptFrom(
        script: context.read<ScriptLanguageProvider>().currentScript,
        text: word);
    word = word.replaceAll(RegExp(r'[^a-zA-ZāīūṅñṭḍṇḷṃĀĪŪṄÑṬḌHṆḶṂ]'), '');
    // convert ot lower case
    word = word.toLowerCase();

    // displaying dictionary in the side navigation view
    if (context.read<NavigationProvider>().isNavigationPaneOpened) {
      context.read<NavigationProvider>().moveToDictionaryPage();
      // delay a little miliseconds to wait for DictionaryPage Initialation
      await Future.delayed(const Duration(milliseconds: 50),
          () => globalLookupWord.value = word);
      return;
    }

    // displaying dictionary in dialog
    const sideSheetWidth = 350.0;
    showGeneralDialog(
      context: context,
      barrierLabel: 'TOC',
      barrierDismissible: true,
      transitionDuration: Duration(milliseconds: Prefs.animationSpeed.round()),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween(begin: const Offset(-1, 0), end: const Offset(0, 0))
              .animate(
            CurvedAnimation(parent: animation, curve: Curves.linear),
          ),
          child: child,
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerLeft,
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
              width: sideSheetWidth,
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.background,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  )),
              child: DictionaryDialog(word: word),
            ),
          ),
        );
      },
    );
  }
}
