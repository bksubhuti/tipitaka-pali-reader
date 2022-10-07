// import 'package:aligned_dialog/aligned_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/providers/font_provider.dart';
import 'package:tipitaka_pali/ui/screens/home/openning_books_provider.dart';
import 'package:tipitaka_pali/utils/platform_info.dart';

import '../../../../app.dart';
import '../../../../business_logic/models/book.dart';
import '../../../../business_logic/models/paragraph_mapping.dart';
import '../../../../business_logic/models/toc.dart';
import '../controller/reader_view_controller.dart';
import '../../../../routes.dart';
import '../../../../services/provider/script_language_provider.dart';
import '../../../../utils/pali_script.dart';
import '../../../dialogs/goto_dialog.dart';
import '../../../dialogs/simple_input_dialog.dart';
import '../../../dialogs/toc_dialog.dart';
import 'book_slider.dart';

class ReaderToolbar extends StatelessWidget {
  const ReaderToolbar({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    myLogger.i('building control bar');
    return Material(
      child: SizedBox(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
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
  const UpperRow({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: BookSlider()),
      ],
    );
  }
}

class LowerRow extends StatelessWidget {
  const LowerRow({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          IconButton(
              onPressed: () => _openGotoDialog(context),
              icon: const Icon(Icons.directions_walk_outlined)),
          IconButton(
              onPressed: () => _onMATButtomClicked(context),
              icon: const Icon(Icons.comment_outlined)),
          IconButton(
              onPressed: () => _onIncreaseButtonClicked(context),
              icon: const Icon(Icons.add_circle_outline)),
          IconButton(
              onPressed: () => _onDecreaseButtonClicked(context),
              icon: const Icon(Icons.remove_circle_outline)),
          IconButton(
              onPressed: () => _addBookmark(context),
              icon: const Icon(Icons.bookmark_add_outlined)),
          if (!PlatformInfo.isDesktop)
            IconButton(
                onPressed: () => _openSettingPage(context),
                icon: const Icon(Icons.settings_outlined)),
          IconButton(
              onPressed: () => _openTocDialog(context),
              icon: const Icon(Icons.list_outlined)),
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
    final note = await showGeneralDialog<String>(
      context: context,
      transitionDuration: const Duration(milliseconds: 300),
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
    //print(note);
    if (note != null) {
      vm.saveToBookmark(note);
    }
  }

  void _onIncreaseButtonClicked(BuildContext context) {
    context.read<FontProvider>().onIncreaseFontSize();
  }

  void _onDecreaseButtonClicked(BuildContext context) {
    context.read<FontProvider>().onDecreaseFontSize();
  }

  void _onMATButtomClicked(BuildContext context) async {
    final vm = context.read<ReaderViewController>();
    final paragraphs = await vm.getParagraphs();
    if (paragraphs.isEmpty) {
      _showNoExplanationDialog(context);
      return;
    }
    final result = await _showParagraphSelectDialog(context, paragraphs);
    if (result != null) {
      final bookId = result['book_id'] as String;
      final bookName = result['book_name'] as String;
      final pageNumber = result['page_number'] as int;

      final book = Book(id: bookId, name: bookName);

      final openedBookController = context.read<OpenningBooksProvider>();
      openedBookController.add(book: book, currentPage: pageNumber);
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
      BuildContext context, List<ParagraphMapping> paragraphs) {
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
              ListView.separated(
                  shrinkWrap: true,
                  itemBuilder: (_, i) {
                    return ListTile(
                      subtitle: Text(
                        PaliScript.getScriptOf(
                            script: context
                                .read<ScriptLanguageProvider>()
                                .currentScript,
                            romanText:
                                '${paragraphs[i].bookName} - ${paragraphs[i].expPageNumber}'),
                      ),
                      title: Text(
                          '${AppLocalizations.of(context)!.paragraph_number}: ${paragraphs[i].paragraph}'),
                      onTap: () {
                        Navigator.pop(context, {
                          'book_id': paragraphs[i].expBookID,
                          'book_name': paragraphs[i].bookName,
                          'page_number': paragraphs[i].expPageNumber,
                        });

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
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: animation, child: child),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) => GotoDialog(
        firstPage: vm.book.firstPage!,
        lastPage: vm.book.lastPage!,
        firstParagraph: firstParagraph,
        lastParagraph: lastParagraph,
      ),
    );
    if (gotoResult != null) {
      final int pageNumber = gotoResult.type == GotoType.page
          ? gotoResult.number
          : await vm.getPageNumber(gotoResult.number);
      vm.onGoto(pageNumber: pageNumber);
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
      transitionDuration: const Duration(milliseconds: 300),
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
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
              width: MediaQuery.of(context).size.width > 600
                  ? sideSheetWidth
                  : double.infinity,
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.background,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  )),
              child: TocDialog(bookID: vm.book.id),
            ),
          ),
        );
      },
    );

    if (toc != null) {
      // not only goto page
      // but also to highlight toc and scroll to it
      vm.onGoto(pageNumber: toc.pageNumber);
      // vm.gotoPageAndScroll(toc.pageNumber.toDouble(), toc.name);
    }
  }
}
