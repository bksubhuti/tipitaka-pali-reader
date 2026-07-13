import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controller/search_filter_provider.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import '../../../../services/provider/script_language_provider.dart';
import '../../../../utils/pali_script.dart';

class PostSearchBookFilterView extends StatelessWidget {
  const PostSearchBookFilterView({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<SearchFilterController>();
    final closeButton = Positioned(
        top: -20,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: ClipOval(
            child: Container(
              width: 56,
              height: 56,
              color: Theme.of(context).colorScheme.secondary,
              child: Icon(
                Icons.close,
                color: Theme.of(context).colorScheme.onSecondary,
              ),
            ),
          ),
        ));

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 45),
      child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            ListView(
              shrinkWrap: true,
              children: [
                Container(height: 42),
                _buildBookFilters(notifier, context),
                ButtonBar(
                  alignment: MainAxisAlignment.center,
                  children: [
                    FilledButton(
                      onPressed: notifier.onSelectAllPostSearchBooks,
                      child: Text(AppLocalizations.of(context)!.selectAll),
                    ),
                    FilledButton(
                      onPressed: notifier.onSelectNonePostSearchBooks,
                      child: Text(AppLocalizations.of(context)!.selectNone),
                    ),
                  ],
                ),
              ],
            ),
            closeButton,
          ]),
    );
  }

  Widget _buildBookFilters(SearchFilterController notifier, BuildContext context) {
    final books = notifier.postSearchBooks;
    final selectedBooks = notifier.selectedPostSearchBookIds;
    final script = context.read<ScriptLanguageProvider>().currentScript;

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Card(
        child: ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: books.length,
          itemBuilder: (context, index) {
            final book = books[index];
            final bookName = PaliScript.getScriptOf(
                script: script, romanText: book.name);
            return CheckboxListTile(
              title: Text(bookName),
              value: selectedBooks.contains(book.id),
              onChanged: (bool? isSelected) {
                if (isSelected != null) {
                  notifier.onPostSearchBookChange(book.id, isSelected);
                }
              },
            );
          },
        ),
      ),
    );
  }
}
