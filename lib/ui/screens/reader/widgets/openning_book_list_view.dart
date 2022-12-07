import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/ui/screens/home/openning_books_provider.dart';

import '../../../../business_logic/models/book.dart';
import '../../../../services/provider/script_language_provider.dart';
import '../../../../utils/pali_script.dart';
import 'package:tipitaka_pali/ui/widgets/colored_text.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class OpenningBookListView extends StatelessWidget {
  const OpenningBookListView({super.key});

  @override
  Widget build(BuildContext context) {
    final openningBooks = context.read<OpenningBooksProvider>().books;
    final selectedBookIndex =
        context.watch<OpenningBooksProvider>().selectedBookIndex;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
        title: ColoredText(AppLocalizations.of(context)!.openingBook),
      ),
      body: ListView.builder(
          itemCount: openningBooks.length,
          itemBuilder: (_, index) {
            final book = openningBooks[index]['book'] as Book;
            final pageNumber = openningBooks[index]['current_page'] as int?;
            return Dismissible(
              key: Key('$index - ${book.id}'),
              onDismissed: (direction) {
                context.read<OpenningBooksProvider>().remove(index: index);
              },
              child: Padding(
                padding: const EdgeInsets.all(2.0),
                child: Card(
                  elevation: 2.0,
                  child: ListTile(
                    onTap: () => Navigator.pop(context, index),
                    title: Text(
                      PaliScript.getScriptOf(
                          script: context
                              .read<ScriptLanguageProvider>()
                              .currentScript,
                          romanText: book.name),
                      style: const TextStyle(fontSize: 20),
                    ),
                    trailing: Text('page - ${pageNumber?.toString()}'),
                    selected: index == selectedBookIndex,
                  ),
                ),
              ),
            );
          }),
      bottomNavigationBar: SizedBox(
          height: 56,
          child: Row(
            children: [
              const SizedBox(width: 56),
              Expanded(
                child: Center(
                  child: IconButton(
                      onPressed: () => _openBookShelfDialog(context),
                      icon: const Icon(Icons.add_outlined)),
                ),
              ),
              SizedBox(
                width: 56,
                child: IconButton(
                  onPressed: () {
                    Navigator.pop(context); // close current
                    Navigator.pop(context); // go back to home
                    context.read<OpenningBooksProvider>().removeAll();
                  },
                  icon: const Icon(Icons.delete),
                ),
              ),
            ],
          )),
    );
  }

  void _openBookShelfDialog(BuildContext context) async {
    Navigator.pop(context); // closing current openning book list
    Navigator.pop(context); // closing reader view. now in home page

    // showGeneralDialog<Book>(
    //     context: context,
    //     transitionDuration: const Duration(milliseconds: 300),
    //     transitionBuilder: (context, animation, secondaryAnimation, child) {
    //       return FadeTransition(
    //         opacity: animation,
    //         child: ScaleTransition(scale: animation, child: child),
    //       );
    //     },
    //     pageBuilder: (context, animation, secondaryAnimation) => Material(
    //           child: BookListPage(isAddtoOpenningBooks: true),
    //         ));
  }
}
