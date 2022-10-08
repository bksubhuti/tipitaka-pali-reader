import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/ui/screens/reader/reader.dart';
import 'package:tipitaka_pali/ui/screens/reader/widgets/openning_book_list_view.dart';
import 'package:tipitaka_pali/ui/widgets/tab_count_icon.dart';
import 'package:tipitaka_pali/services/prefs.dart';

import '../../../business_logic/models/book.dart';
import '../../../services/provider/script_language_provider.dart';
import '../../../utils/pali_script.dart';
import '../home/openning_books_provider.dart';

class MobileReaderContrainer extends StatefulWidget {
  const MobileReaderContrainer({super.key});

  @override
  State<MobileReaderContrainer> createState() => _MobileReaderContrainerState();
}

class _MobileReaderContrainerState extends State<MobileReaderContrainer> {
  late final PageController pageController;

  @override
  void initState() {
    super.initState();
    pageController = PageController();
  }

  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final openningBooks = context.watch<OpenningBooksProvider>().books;
    final selectedBookIndex =
        context.watch<OpenningBooksProvider>().selectedBookIndex;

    return Scaffold(
      appBar: AppBar(
        title: openningBooks.isEmpty
            ? null
            : Text(PaliScript.getScriptOf(
                script: context.read<ScriptLanguageProvider>().currentScript,
                romanText:
                    (openningBooks[selectedBookIndex]['book'] as Book).name)),
        actions: [
          TabCountIcon(
              count: openningBooks.length,
              onPressed: () async {
                final selectedIndex = await _openOpenningBookListView(context);
                if (selectedIndex != null) {
                  context.read<OpenningBooksProvider>().updateSelectedBookIndex(
                      selectedIndex,
                      forceNotify: true);
                  setState(() {
                    // title need to update
                    pageController.jumpToPage(selectedIndex);
                  });
                }
              })
        ],
      ),
      body: openningBooks.isEmpty
          ? const Center(child: Text('There is no more openning book'))
          : PageView.builder(
              controller: pageController,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: openningBooks.length,
              itemBuilder: (context, index) {
                final openedBook = openningBooks[index];
                final book = openedBook['book'] as Book;
                final pageNumber = openedBook['current_page'] as int?;
                final textToHighlight =
                    openedBook['text_to_highlight'] as String?;
                // myLogger.i('openning book index: $index');
                // myLogger.i('openning book name: ${book.name}');

                return Reader(
                  key: Key('$index - ${book.id}'),
                  book: book,
                  initialPage: pageNumber,
                  textToHighlight: textToHighlight,
                );
              }),
    );
  }

  Future<int?> _openOpenningBookListView(BuildContext context) async {
    return await showGeneralDialog<int>(
        context: context,
        transitionDuration:
            Duration(milliseconds: Prefs.animationSpeed.round()),
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: animation, child: child),
          );
        },
        pageBuilder: (context, animation, secondaryAnimation) => const Material(
              child: OpenningBookListView(),
            ));
  }
}
