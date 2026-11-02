import 'package:sqflite/sqflite.dart';
import 'package:tipitaka_pali/app.dart';

/// DATA PATCHES — corrections the app makes to the shipped databases.
///
/// A database version bump makes every reader download and install the data
/// again, so a mistake found in the data is patched here in code, on the
/// reader's device, and fixed at its source in the next data release that
/// happens anyway.
///
/// Every patch is listed in this file, including the ones that live in code
/// elsewhere, with what is wrong in the data and when the patch comes out.
///
/// WHEN MAKING A NEW DATA RELEASE: fix each entry below in the databases
/// (tpr_extension.db / epitaka.db), then delete the entry and its code. A
/// patch must stay harmless on fixed data until then: each one matches only
/// the wrong rows, so on a corrected database it changes nothing.
///
/// Patches in code elsewhere, to remove when the data is fixed:
///
/// * X-ray link terms. The shipped `book_links` leaves out the word ePitaka
///   records with each link, so the term is read from the bold that opens
///   the commentary sentence (`XrayRepo.termOf`). Fix: ship the word with
///   each link.
/// * End of a volume. A TPR book that is one volume of a longer ePitaka book
///   has no break after its last page, so the reader stops that page where
///   the next volume begins (`SentencePageContentRepository
///   ._nextVolumeStart`). Fix: give each such volume an end break.
///
/// Known faults the app copes with unpatched, to fix in the same release:
///
/// * `tika_sa_05`: `page_break` has a stray page 32 on paragraph 1, before
///   the book's first page, 393.
class DataPatches {
  DataPatches._();

  /// The ePitaka books whose rows were changed when the database was last
  /// opened, for the search index to be brought up to date for them.
  static List<String> changedBooks = const [];

  /// Applies the SQL patches to the attached databases. Run on every open;
  /// a patch that finds nothing to change costs one indexed query.
  static Future<void> apply(Database db) async {
    final changed = <String>{};
    for (final patch in _patches) {
      try {
        final n = await db.rawUpdate(patch.sql, patch.args);
        if (n > 0) {
          changed.add(patch.book);
          myLogger.i('data patch: ${patch.what} ($n rows)');
        }
      } catch (e) {
        myLogger.e('data patch failed: ${patch.what}: $e');
      }
    }
    changedBooks = changed.toList();
  }

  static final _patches = [
    // Page 1 of the second volume of five split books is broken at
    // paragraph 1, the start of the first volume. The page then held the
    // whole first volume (up to 8,700 sentences, 3 MB), and composing it
    // froze the reader long enough for Android to report it not responding
    // (the Play ANRs in the regex engine). The first volume's last page ran
    // on through the second as well, since no volume began after it.
    //
    // Each second volume begins at its "Namo tassa" line, after "Paṭhamo
    // bhāgo niṭṭhito". Fix in tpr_extension.db: page_break for these rows.
    for (final (tprBook, book, para) in const [
      ('annya_vi_08', 'Vin-alaṅke', 1181),
      ('annya_vi_11', 'Vin-vn-t', 2417),
      ('attha_ku_02_02', 'Dhp-a', 2059),
      ('attha_ku_05_02', 'Pj-ii', 1157),
      ('attha_ku_18_02', 'Paṭis-a', 1415),
    ])
      _Patch(
        what: '$tprBook page 1 starts at paragraph $para',
        book: book,
        sql: 'UPDATE ext.page_break SET para_id = ?, line_id = 1, '
            'word_index = 0 '
            'WHERE tpr_book = ? AND tpr_page = 1 AND book_id = ? '
            'AND para_id = 1',
        args: [para, tprBook, book],
      ),
  ];
}

class _Patch {
  const _Patch(
      {required this.what,
      required this.book,
      required this.sql,
      required this.args});

  final String what;

  /// The ePitaka book the patch changes.
  final String book;
  final String sql;
  final List<Object?> args;
}
