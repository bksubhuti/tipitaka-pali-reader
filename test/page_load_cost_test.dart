@TestOn('windows || linux || mac-os')
library;

import 'dart:io';

import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:tipitaka_pali/business_logic/models/page_content.dart';
import 'package:tipitaka_pali/utils/page_composer.dart';

/// Opening a book builds its list before showing anything, so what that costs
/// is what the reader waits for.
///
/// The reader's list is indexed by block, not by page, so the number of
/// blocks has to be known up front even though the pages are built one at a
/// time as they are scrolled to. That makes the count and the composer two
/// descriptions of the same thing, and if they ever disagree the list scrolls
/// to the wrong place — silently. So it is checked here against real books.
void main() {
  const dbDir =
      r'C:\Users\Vasil\AppData\Roaming\com.paauk\tipitaka_pali_reader';
  const books = ['mula_di_01', 'annya_vi_12', 'mula_bi_07_04', 'tika_vi_04'];

  late Database db;
  var ready = false;

  setUpAll(() async {
    sqfliteFfiInit();
    if (!File('$dbDir\\epitaka.db').existsSync()) return;
    db = await databaseFactoryFfi.openDatabase('$dbDir\\tipitaka_pali.db',
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
    await db.execute("ATTACH DATABASE '$dbDir\\epitaka.db' AS epi");
    await db.execute("ATTACH DATABASE '$dbDir\\tpr_extension.db' AS ext");
    ready = true;
  });

  tearDownAll(() async {
    if (ready) await db.close();
  });

  /// The pages of a book as lists of sentences, read the way the reader does.
  Future<List<List<PageSentence>>> pagesOf(String book) async {
    final breaks = await db.rawQuery(
      'SELECT book_id, para_id, line_id, tpr_page FROM ext.page_break '
      'WHERE tpr_book = ? ORDER BY tpr_page',
      [book],
    );
    if (breaks.isEmpty) return const [];
    final rows = <String, List<Map<String, Object?>>>{};
    for (final epiBook in {for (final b in breaks) b['book_id'] as String}) {
      rows[epiBook] = await db.rawQuery(
        'SELECT s.para_id, s.line_id, s.pali, e.glue_state '
        'FROM epi.sentences s LEFT JOIN ext.sentence_ext e '
        '  ON e.book_id = s.book_id AND e.para_id = s.para_id '
        '  AND e.line_id = s.line_id '
        'WHERE s.book_id = ? ORDER BY s.para_id, s.line_id',
        [epiBook],
      );
    }

    final out = <List<PageSentence>>[];
    for (var i = 0; i < breaks.length; i++) {
      final book = breaks[i]['book_id'] as String;
      final startPara = breaks[i]['para_id'] as int;
      final endPara =
          i + 1 < breaks.length ? breaks[i + 1]['para_id'] as int : 1 << 30;
      final page = <PageSentence>[];
      for (final row in rows[book] ?? const <Map<String, Object?>>[]) {
        final para = row['para_id'] as int;
        if (para < startPara) continue;
        if (para > endPara) break;
        page.add(PageSentence(
          paraId: para,
          lineId: row['line_id'] as int,
          pali: (row['pali'] as String).replaceAll(RegExp(r'<[^>]*>'), ''),
          glue: switch (row['glue_state'] as String?) {
            'continue' => GlueState.continues,
            'verse' => GlueState.verse,
            _ => GlueState.paragraph,
          },
        ));
      }
      out.add(page);
    }
    return out;
  }

  test('the block count matches what composing actually writes', () async {
    if (!ready) {
      markTestSkipped('databases not installed');
      return;
    }
    var checked = 0;
    for (final book in books) {
      for (final page in await pagesOf(book)) {
        if (page.isEmpty) continue;
        final counted = PageComposer.blockCount(page);
        final written =
            PageContent(content: PageComposer.compose(page)).blocks.length;
        expect(counted, written,
            reason: 'in $book a page counts $counted blocks but composes '
                '$written, so the list would be the wrong length and every '
                'scroll position after it wrong');
        checked++;
      }
    }
    expect(checked, greaterThan(1500));
    // ignore: avoid_print
    print('\nblock counts agreed on $checked pages');
  });

  test('what opening a book costs', () async {
    if (!ready) {
      markTestSkipped('databases not installed');
      return;
    }
    const book = 'annya_vi_12';
    final pages = await pagesOf(book);

    final watch = Stopwatch()..start();
    var blocks = 0;
    for (final page in pages) {
      blocks += PageComposer.blockCount(page);
    }
    final countMs = watch.elapsedMilliseconds;

    watch.reset();
    final composed = [for (final page in pages) PageComposer.compose(page)];
    final composeMs = watch.elapsedMilliseconds;

    watch.reset();
    for (final page in composed) {
      BeautifulSoup(page).body?.children.length;
    }
    final soupMs = watch.elapsedMilliseconds;

    // ignore: avoid_print
    print('\n$book: ${pages.length} pages, $blocks blocks\n'
        '  count blocks only (now, at open) : $countMs ms\n'
        '  compose every page (was)         : $composeMs ms\n'
        '  parse every page (was)           : $soupMs ms\n');
  });
}
