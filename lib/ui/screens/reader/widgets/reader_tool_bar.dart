// import 'package:aligned_dialog/aligned_dialog.dart';
import 'package:flutter/material.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:provider/provider.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:tipitaka_pali/providers/font_provider.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/ui/screens/dictionary/controller/dictionary_controller.dart';
import 'package:tipitaka_pali/ui/screens/home/openning_books_provider.dart';
import 'package:tipitaka_pali/ui/screens/reader/widgets/mat_button.dart';
import 'package:tipitaka_pali/ui/screens/settings/view_settings_view.dart';
import 'package:tipitaka_pali/utils/pali_script_converter.dart';
import 'package:tipitaka_pali/utils/platform_info.dart';

import '../../../../app.dart';
import '../../../../business_logic/models/book.dart';
import '../../../../business_logic/models/paragraph_mapping.dart';
import '../../../../business_logic/models/toc.dart';
import '../../../../routes.dart';
import '../../../../services/provider/script_language_provider.dart';
import '../../../../utils/pali_script.dart';
import '../../../dialogs/goto_dialog.dart';
import '../../../dialogs/simple_input_dialog.dart';
import '../../../dialogs/toc_dialog.dart';
import '../controller/reader_view_controller.dart';
import 'book_slider.dart';

class ReaderToolbar extends StatelessWidget {
  const ReaderToolbar({super.key});
  @override
  Widget build(BuildContext context) {
    myLogger.i('building control bar');
    return const Material(
      child: SizedBox(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            UpperRow(),
            // SizedBox(height: 8),
            LowerRow(),
          ],
        ),
      ),
    );
  }
}

class UpperRow extends StatelessWidget {
  const UpperRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 45),
        // Dynamically show BookSlider or an Expanded blank widget based on the hideScrollbarPref
        Expanded(
          child: PreferenceBuilder<bool>(
            preference: context
                .read<StreamingSharedPreferences>()
                .getBool(hideScrollbarPref, defaultValue: false),
            builder: (context, hideScrollbar) {
              // If hideScrollbar is false, show the BookSlider
              if (!hideScrollbar) {
                return const BookSlider();
              } else {
                // Otherwise, show an empty SizedBox to take up the space
                return const SizedBox(height: 30);
              }
            },
          ),
        ),
        const SizedBox(width: 45),
      ],
    );
  }
}

class LowerRow extends StatelessWidget {
  const LowerRow({super.key});

  @override
  Widget build(BuildContext context) {
    // this gets anoyying very quickly..
    // but could be useful to leave the code
    // so I know the conditions to auto show toc
    Future.delayed(const Duration(milliseconds: 500), () {
      //_openTocDialog(context);
    });

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          IconButton(
              onPressed: () => _openGotoDialog(context),
              icon: const Icon(Icons.directions_walk_outlined),
              tooltip: AppLocalizations.of(context)!.gotoPageParagraph),
          (PlatformInfo.isDesktop)
              ? MATButton(
                  onMulaButtonClicked: () => _onMulaButtonClicked(context),
                  onAtthaButtonClicked: () => _onAtthaButtonClicked(context),
                  onTikaButtonClicked: () => _onTikaButtonClicked(context))
              : buildSpeedDial(context),
          IconButton(
              onPressed: () => _onDecreaseButtonClicked(context),
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: AppLocalizations.of(context)!.decreaseFontSize),
          IconButton(
              onPressed: () => _onIncreaseButtonClicked(context),
              icon: const Icon(Icons.add_circle_outline),
              tooltip: AppLocalizations.of(context)!.increaseFontSize),
          (PlatformInfo.isDesktop)
              ? IconButton(
                  icon: const Icon(Icons.text_format_outlined),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => Dialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        // Wrap in SingleChildScrollView so the ExpansionTile has room to expand
                        child: const SingleChildScrollView(
                          child: ViewSettingsView(
                            isMobilePopup: true,
                          ),
                        ),
                      ),
                    );
                  },
                )
              : const SizedBox.shrink(),
          IconButton(
              onPressed: () => _addBookmark(context),
              icon: const Icon(Icons.bookmark_add_outlined),
              tooltip: AppLocalizations.of(context)!.bookmark),
          IconButton(
              onPressed: () => _openTocDialog(context),
              icon: const Icon(Icons.list),
              tooltip: AppLocalizations.of(context)!.table_of_contents),
          if (!PlatformInfo.isDesktop)
            IconButton(
                onPressed: () => _openSettingPage(context),
                icon: const Icon(Icons.settings_outlined),
                tooltip: AppLocalizations.of(context)!.settings),
        ],
      ),
    );
  }

  void _openSettingPage(BuildContext context) async {
    if (PlatformInfo.isDesktop || Mobile.isTablet(context)) {
    } else {
      await Navigator.pushNamed(context, settingRoute);
    }
  }

  void _addBookmark(BuildContext context) async {
    final vm = context.read<ReaderViewController>();
    String? selectedText = vm.selection;
    if (selectedText?.isEmpty ?? true) {
      selectedText = globalLookupWord.value;
    }

    final note = await showGeneralDialog<String>(
      context: context,
      transitionDuration: Duration(milliseconds: Prefs.animationSpeed.round()),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: animation, child: child),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        return SimpleInputDialog(
          hintText: AppLocalizations.of(context)!.enter_note,
          cancelLabel: AppLocalizations.of(context)!.cancel,
          okLabel: AppLocalizations.of(context)!.save,
        );
      },
    );

    /* if (selectedText?.isEmpty ?? true) {
      // do not save bookmark if no text is selected/highlighted
      return;
    }
    */

    //print(note);
    if (note != null) {
      vm.saveToBookmark(note, selectedText ?? '');
    }
  }

  void _onIncreaseButtonClicked(BuildContext context) {
    context.read<ReaderFontProvider>().onIncreaseFontSize();
  }

  void _onDecreaseButtonClicked(BuildContext context) {
    context.read<ReaderFontProvider>().onDecreaseFontSize();
  }

  void _onMulaButtonClicked(BuildContext context) async {
    final vm = context.read<ReaderViewController>();
    if (vm.book.id.contains('mula')) {
      // do nothing
      return;
    }

    int currentPage = vm.currentPage.value;
    List<ParagraphMapping> paragraphs =
        await vm.getBackWardParagraphs(currentPage);
    bool isResultFromPreviusPage = false;
    if (paragraphs.isEmpty) {
      isResultFromPreviusPage = true;
      while (paragraphs.isEmpty && currentPage-- > 1) {
        paragraphs = await vm.getBackWardParagraphs(currentPage);
      }
    }
    if (context.mounted) {
      if (paragraphs.isEmpty) {
        _showNoExplanationDialog(context);
        return;
      }

      final result = await _showParagraphSelectDialog(
          context, paragraphs, isResultFromPreviusPage);
      if (result != null) {
        final bookId = result['book_id'] as String;
        final bookName = result['book_name'] as String;
        final pageNumber = result['page_number'] as int;

        final book = Book(id: bookId, name: bookName);
        if (context.mounted) {
          final openedBookController = context.read<OpenningBooksProvider>();
          openedBookController.add(book: book, currentPage: pageNumber);
        }
      }
    }
  }

  void _onAtthaButtonClicked(BuildContext context) async {
    final vm = context.read<ReaderViewController>();
    if (vm.book.id.contains('attha')) {
      // do nothing
      return;
    }
    // forward
    if (vm.book.id.contains('mula')) {
      int currentPage = vm.currentPage.value;
      List<ParagraphMapping> paragraphs = await vm.getParagraphs(currentPage);
      bool isResultFromPreviusPage = false;
      if (paragraphs.isEmpty) {
        isResultFromPreviusPage = true;
        while (paragraphs.isEmpty && currentPage-- > 1) {
          paragraphs = await vm.getParagraphs(currentPage);
        }
      }
      if (context.mounted) {
        if (paragraphs.isEmpty) {
          _showNoExplanationDialog(context);
          return;
        }
        final result = await _showParagraphSelectDialog(
            context, paragraphs, isResultFromPreviusPage);
        if (result != null) {
          final bookId = result['book_id'] as String;
          final bookName = result['book_name'] as String;
          final pageNumber = result['page_number'] as int;

          final book = Book(id: bookId, name: bookName);
          if (context.mounted) {
            final openedBookController = context.read<OpenningBooksProvider>();
            openedBookController.add(book: book, currentPage: pageNumber);
          }
        }
      }
      return;
    }

    // backward
    if (vm.book.id.contains('tika')) {
      int currentPage = vm.currentPage.value;
      List<ParagraphMapping> paragraphs =
          await vm.getBackWardParagraphs(currentPage);
      bool isResultFromPreviusPage = false;
      if (paragraphs.isEmpty) {
        isResultFromPreviusPage = true;
        while (paragraphs.isEmpty && currentPage-- > 1) {
          paragraphs = await vm.getBackWardParagraphs(currentPage);
        }
      }
      if (context.mounted) {
        if (paragraphs.isEmpty) {
          _showNoExplanationDialog(context);
          return;
        }

        final result = await _showParagraphSelectDialog(
            context, paragraphs, isResultFromPreviusPage);
        if (result != null) {
          final bookId = result['book_id'] as String;
          final bookName = result['book_name'] as String;
          final pageNumber = result['page_number'] as int;

          final book = Book(id: bookId, name: bookName);
          if (context.mounted) {
            final openedBookController = context.read<OpenningBooksProvider>();
            openedBookController.add(book: book, currentPage: pageNumber);
          }
        }
      }
    }
  }

  void _onTikaButtonClicked(BuildContext context) async {
    final vm = context.read<ReaderViewController>();

    if (vm.book.id.contains('tika')) {
      // do nothing
      return;
    }
    // forward
    if (vm.book.id.contains('attha')) {
      int currentPage = vm.currentPage.value;
      List<ParagraphMapping> paragraphs = await vm.getParagraphs(currentPage);
      bool isResultFromPreviusPage = false;
      if (paragraphs.isEmpty) {
        isResultFromPreviusPage = true;
        while (paragraphs.isEmpty && currentPage-- > 1) {
          paragraphs = await vm.getParagraphs(currentPage);
        }
      }
      if (context.mounted) {
        if (paragraphs.isEmpty) {
          _showNoExplanationDialog(context);
          return;
        }
        final result = await _showParagraphSelectDialog(
            context, paragraphs, isResultFromPreviusPage);
        if (result != null) {
          final bookId = result['book_id'] as String;
          final bookName = result['book_name'] as String;
          final pageNumber = result['page_number'] as int;

          final book = Book(id: bookId, name: bookName);
          if (context.mounted) {
            final openedBookController = context.read<OpenningBooksProvider>();
            openedBookController.add(book: book, currentPage: pageNumber);
          }
        }
      }
    }
    // dobule forward
    if (vm.book.id.contains('mula')) {
      // ToDo
    }
  }

  void _onMATButtomClicked(BuildContext context) async {
    final vm = context.read<ReaderViewController>();
    int currentPage = vm.currentPage.value;
    List<ParagraphMapping> paragraphs = await vm.getParagraphs(currentPage);
    bool isResultFromPreviusPage = false;
    if (paragraphs.isEmpty) {
      isResultFromPreviusPage = true;
      while (paragraphs.isEmpty && currentPage-- > 1) {
        paragraphs = await vm.getParagraphs(currentPage);
      }
    }
    if (context.mounted) {
      if (paragraphs.isEmpty) {
        _showNoExplanationDialog(context);
        return;
      }
      final result = await _showParagraphSelectDialog(
          context, paragraphs, isResultFromPreviusPage);
      if (result != null) {
        final bookId = result['book_id'] as String;
        final bookName = result['book_name'] as String;
        final pageNumber = result['page_number'] as int;

        final book = Book(id: bookId, name: bookName);
        if (context.mounted) {
          final openedBookController = context.read<OpenningBooksProvider>();
          openedBookController.add(book: book, currentPage: pageNumber);
        }
      }
    }
  }

  Future<void> _showNoExplanationDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: true, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          // title: Text('AlertDialog Title'),
          content: SingleChildScrollView(
            child: ListBody(
              // ignore: prefer_const_literals_to_create_immutables
              children: <Widget>[
                // if current book is mula pali , it opens corresponded atthakatha
                // if attha, will open tika
                Text(AppLocalizations.of(context)!.unable_open_page),
              ],
            ),
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

  Future<Map<String, dynamic>?> _showParagraphSelectDialog(
    BuildContext context,
    List<ParagraphMapping> paragraphs,
    bool isResultFromPreviusPage,
  ) async {
    StringBuffer buffer = StringBuffer();
    if (isResultFromPreviusPage) {
      buffer.writeln('There is no paragraph in current page');
      buffer.writeln('Showing previous paragraphs');
    }

    return showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        constraints: const BoxConstraints(maxWidth: 400),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16.0), topRight: Radius.circular(16.0)),
        ),
        builder: (BuildContext bc) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  AppLocalizations.of(context)!.select_paragraph,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Divider(
                height: 1,
                color: Colors.grey.withOpacity(0.5),
              ),
              isResultFromPreviusPage
                  ? Text(buffer.toString())
                  : const SizedBox.shrink(),
              ListView.separated(
                  shrinkWrap: true,
                  itemBuilder: (_, i) {
                    String pageNumberIfFound =
                        (paragraphs[i].expPageNumber != 0)
                            ? {paragraphs[i].expPageNumber}.toString()
                            : "Not Listed";
                    return ListTile(
                      visualDensity:
                          const VisualDensity(horizontal: 0, vertical: -4),
                      title: Text(
                        'Para.${paragraphs[i].paragraph} - ${PaliScript.getScriptOf(script: context.read<ScriptLanguageProvider>().currentScript, romanText: '${paragraphs[i].bookName} - $pageNumberIfFound')}',
                      ),
                      // title: Text(
                      //     '${AppLocalizations.of(context)!.paragraph_number}: ${paragraphs[i].paragraph}'),
                      onTap: () {
                        if (paragraphs[i].expPageNumber != 0) {
                          Navigator.pop(context, {
                            'book_id': paragraphs[i].expBookID,
                            'book_name': paragraphs[i].bookName,
                            'page_number': paragraphs[i].expPageNumber,
                          });
                        }

                        // _openBook(
                        //     context,
                        //     paragraphs[i].expBookID,
                        //     paragraphs[i].bookName,
                        //     paragraphs[i].expPageNumber);
                      },
                    );
                  },
                  separatorBuilder: (_, __) => const Divider(),
                  itemCount: paragraphs.length),
            ],
          );
        });
  }

  void _openGotoDialog(BuildContext context) async {
    final vm = context.read<ReaderViewController>();
    final firstParagraph = await vm.getFirstParagraph();
    final lastParagraph = await vm.getLastParagraph();
    final gotoResult = await showGeneralDialog<GotoDialogResult>(
      context: context,
      transitionDuration: Duration(milliseconds: Prefs.animationSpeed.round()),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: animation, child: child),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) => GotoDialog(
        firstPage: vm.book.firstPage,
        lastPage: vm.book.lastPage,
        firstParagraph: firstParagraph,
        lastParagraph: lastParagraph,
      ),
    );
    if (gotoResult != null) {
      late final int pageNumber;
      int? paragraphNumber;
      String? wordToHighlight;
      if (gotoResult.type == GotoType.page) {
        pageNumber = gotoResult.number;
      } else {
        pageNumber = await vm.getPageNumber(gotoResult.number);
        paragraphNumber = gotoResult.number;
      }
      if (paragraphNumber != null) {
        final currentScript =
            context.read<ScriptLanguageProvider>().currentScript;
        if (currentScript == Script.roman) {
          wordToHighlight = '$paragraphNumber';
        } else {
          wordToHighlight = PaliScript.getScriptOf(
            script: currentScript,
            romanText: '$paragraphNumber',
          );
        }
      }
      vm.onGoto(pageNumber: pageNumber, word: wordToHighlight);
      // vm.gotoPage(pageNumber.toDouble());
    }
  }

  void _openTocDialog(BuildContext context) async {
    final vm = context.read<ReaderViewController>();

    const sideSheetWidth = 400.0;
    final toc = await showGeneralDialog<Toc>(
      context: context,
      barrierLabel: 'TOC',
      barrierDismissible: true,
      transitionDuration: Duration(milliseconds: Prefs.animationSpeed.round()),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position:
              Tween(begin: const Offset(1, 0), end: const Offset(0, 0)).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeInOutSine),
          ),
          child: child,
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        double topPadding = MediaQuery.paddingOf(context).top;
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              padding: EdgeInsets.fromLTRB(8, 8 + topPadding, 8, 8),
              width: MediaQuery.of(context).size.width > 600
                  ? sideSheetWidth
                  : double.infinity,
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.background,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  )),
              child: TocDialog(
                bookID: vm.book.id,
                currentPage: vm.currentPage.value,
              ),
            ),
          ),
        );
      },
    );

    if (toc != null) {
      // not only goto page
      // but also to highlight toc and scroll to it
      late String textToHighlight;
      final currentScript =
          context.read<ScriptLanguageProvider>().currentScript;
      if (currentScript == Script.roman) {
        textToHighlight = toc.name.trim();
      } else {
        textToHighlight = PaliScript.getScriptOf(
          script: currentScript,
          romanText: toc.name.trim(),
        );
      }
      debugPrint('wordToHighlight: $textToHighlight');
      vm.onGoto(
          pageNumber: toc.pageNumber,
          word: textToHighlight,
          bookUuid: vm.bookUuid);
      // vm.gotoPageAndScroll(toc.pageNumber.toDouble(), toc.name);
    }
  }

  SpeedDial buildSpeedDial(BuildContext context) {
    return SpeedDial(
      icon: Icons.collections_outlined,
      //label: Text("MAT"),
      activeIcon: Icons.close,
      visible: true,
      elevation: 0,
      buttonSize: const Size(40, 40),
      //childrenButtonSize: const Size(100, 40),
      closeManually: false,
      renderOverlay: false,
      curve: Curves.bounceIn,
      overlayColor: const Color.fromARGB(255, 231, 184, 184),
      overlayOpacity: 0.5,
      tooltip: 'Linked Books',
      heroTag: 'speed-dial-hero-tag',
      backgroundColor: Prefs.darkThemeOn
          ? Colors.black
          : Colors.white, // use system and theme colors
      foregroundColor: Prefs.darkThemeOn
          ? Colors.white
          : Colors.black, // use system and theme colors
      //elevation: 8.0,
      //shape: const CircleBorder(),
      children: [
        SpeedDialChild(
          child: const Text("Tika"),
          backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
//          label: 'Tika',
          labelStyle: const TextStyle(fontSize: 18.0),
          onTap: () => _onTikaButtonClicked(context),
        ),
        SpeedDialChild(
          child: const Text("Aṭṭh"),
          backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
//          label: 'Aṭṭhakathā',
          labelStyle: const TextStyle(fontSize: 18.0),
          onTap: () => _onAtthaButtonClicked(context),
        ),
        SpeedDialChild(
          child: const Text("Mula"),
          backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
//          label: 'Mula',
          labelStyle: const TextStyle(fontSize: 18.0),
          onTap: () => _onMulaButtonClicked(context),
        ),
      ],
    );
  }
}
