import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';

import '../../../../business_logic/models/book.dart';
import '../../../../business_logic/models/recent.dart';
import '../../../../services/dao/recent_dao.dart';
import '../../../../services/database/database_helper.dart';
import '../../../../services/prefs.dart';
import '../../../../services/provider/script_language_provider.dart';
import '../../../../services/reading_place.dart';
import '../../../../services/repositories/heading_trail_repo.dart';
import '../../../../services/repositories/recent_repo.dart';
import '../../../../utils/font_utils.dart';
import '../../../../utils/pali_script.dart';
import '../../../../utils/platform_info.dart';
import '../../home/openning_books_provider.dart';
import '../mobile_reader_container.dart';

/// On the home screen, under the verse: where the reader last was, and the
/// last three books of Recent, each a tap from being open again.
class HomeShortcuts extends StatelessWidget {
  const HomeShortcuts({super.key});

  /// How many of Recent to show besides the reading place.
  static const recentCount = 3;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReadingPlace?>(
      valueListenable: ReadingPlace.current,
      builder: (context, place, _) => ValueListenableBuilder<int>(
        // Read again whenever an entry is saved.
        valueListenable: recentChanges,
        builder: (context, _, __) => FutureBuilder<List<Recent>>(
          future: RecentDatabaseRepository(DatabaseHelper(), RecentDao())
              .getRecents(),
          builder: (context, snapshot) {
            final recents = [
              for (final r in snapshot.data ?? const <Recent>[])
                // The reading place's own book is already shown above.
                if (r.bookID != place?.bookId) r
            ].take(recentCount).toList();
            if (place == null && recents.isEmpty) {
              return const SizedBox.shrink();
            }
            final l10n = AppLocalizations.of(context)!;
            return ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (place != null)
                    _Shortcut(
                      icon: Icons.auto_stories_outlined,
                      label: l10n.lastRead,
                      bookId: place.bookId,
                      bookName: place.bookName,
                      page: place.page,
                      strong: true,
                    ),
                  for (final r in recents)
                    _Shortcut(
                      icon: Icons.history,
                      label: l10n.recent,
                      bookId: r.bookID,
                      bookName: r.bookName ?? r.bookID,
                      page: r.pageNumber,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.icon,
    required this.label,
    required this.bookId,
    required this.bookName,
    required this.page,
    this.strong = false,
  });

  final IconData icon;
  final String label;
  final String bookId;
  final String bookName;
  final int page;

  /// The reading place, set a little apart from Recent.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final script = context.watch<ScriptLanguageProvider>().currentScript;
    final l10n = AppLocalizations.of(context)!;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        dense: true,
        leading: Icon(icon),
        title: Text(
          PaliScript.getScriptOf(script: script, romanText: bookName),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: FontUtils.getfontName(script: script),
            fontWeight: strong ? FontWeight.bold : FontWeight.normal,
            fontSize: Prefs.uiFontSize,
          ),
        ),
        // As Recent itself shows it: the page, and the heading it is under,
        // in the Pāḷi font.
        subtitle: FutureBuilder<String?>(
          future:
              HeadingTrailRepository(DatabaseHelper()).lineAtPage(bookId, page),
          builder: (context, heading) => Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: '$label · ${l10n.page}: '
                      '${PaliScript.getScriptOf(script: script, romanText: '$page')}'),
              if (heading.data != null)
                TextSpan(
                    text:
                        ' · ${PaliScript.getScriptOf(script: script, romanText: heading.data!)}',
                    style: TextStyle(
                        fontFamily: FontUtils.getfontName(script: script))),
            ]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        onTap: () =>
            openBookAt(context, Book(id: bookId, name: bookName), page),
      ),
    );
  }
}

/// Opens [book] at [page], in the reader beside the home screen, or over it
/// on a phone.
void openBookAt(BuildContext context, Book book, int page,
    {String? highlight}) {
  context
      .read<OpenningBooksProvider>()
      .add(book: book, currentPage: page, textToHighlight: highlight);
  if (Mobile.isPhone(context)) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const MobileReaderContainer()));
  }
}
