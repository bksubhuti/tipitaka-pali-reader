@TestOn('windows || linux || mac-os')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:tipitaka_pali/utils/page_composer.dart';

/// Checks that a composed page still gives the reader everything it needs.
///
/// Word tap, text to speech, highlighting and the page-number badges are all
/// implemented inside widgets, reading the page HTML and looking for
/// particular markup. None of them can be driven from a test, but all of them
/// break in the same way: if the markup they look for is not there, they stop
/// working silently and the page still looks fine.
///
/// So this builds real pages from the installed data and asserts the markup
/// each feature depends on is present and well formed.
void main() {
  const dbDir =
      r'C:\Users\Vasil\AppData\Roaming\com.paauk\tipitaka_pali_reader';

  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(
      '$dbDir\\tipitaka_pali.db',
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    await db.execute("ATTACH DATABASE '$dbDir\\epitaka.db' AS epi");
    await db.execute("ATTACH DATABASE '$dbDir\\tpr_extension.db' AS ext");
    if (File('$dbDir\\lang_en.db').existsSync()) {
      await db.execute("ATTACH DATABASE '$dbDir\\lang_en.db' AS lang_en");
    }
  });

  tearDownAll(() async => db.close());

  /// Builds a page the way the reader's repository does.
  Future<String> composePage(String book, int page,
      {bool withTranslation = false}) async {
    final bounds = await db.rawQuery(
      'SELECT book_id, para_id, line_id, word_index FROM ext.page_break '
      'WHERE tpr_book = ? AND tpr_page = ? LIMIT 1',
      [book, page],
    );
    final start = bounds.first;
    final next = await db.rawQuery(
      'SELECT para_id, line_id FROM ext.page_break '
      'WHERE tpr_book = ? AND tpr_page > ? ORDER BY tpr_page LIMIT 1',
      [book, page],
    );

    final rows = await db.rawQuery('''
      SELECT s.para_id, s.line_id, s.pali, s.vripara
      FROM epi.sentences s
      WHERE s.book_id = ?
        AND (s.para_id > ? OR (s.para_id = ? AND s.line_id >= ?))
        AND (s.para_id <= ?)
      ORDER BY s.para_id, s.line_id
    ''', [
      start['book_id'],
      start['para_id'],
      start['para_id'],
      start['line_id'],
      next.isEmpty ? 1 << 30 : next.first['para_id'],
    ]);

    final marks = await db.rawQuery(
      "SELECT para_id, line_id, edition, vol, page, word_index "
      "FROM ext.page_mark WHERE book_id = ? AND edition <> 'M' "
      "AND para_id >= ? LIMIT 40",
      [start['book_id'], start['para_id']],
    );

    final translations = <String, String>{};
    if (withTranslation) {
      final t = await db.rawQuery(
        'SELECT para_id, line_id, translation FROM lang_en.sentences '
        'WHERE book_id = ? AND para_id >= ? LIMIT 200',
        [start['book_id'], start['para_id']],
      );
      for (final row in t) {
        translations['${row['para_id']}.${row['line_id']}'] =
            row['translation'] as String;
      }
    }

    final sentences = <PageSentence>[];
    for (final row in rows) {
      final key = '${row['para_id']}.${row['line_id']}';
      sentences.add(PageSentence(
        paraId: row['para_id'] as int,
        lineId: row['line_id'] as int,
        pali: (row['pali'] as String).replaceAll(RegExp(r'<[^>]*>'), '').trim(),
        paraNum: row['line_id'] == 1 ? row['vripara'] as String? : null,
        anchors: [
          for (final m in marks)
            if (m['para_id'] == row['para_id'] && m['line_id'] == row['line_id'])
              PageAnchor(
                edition: m['edition'] as String,
                volume: (m['vol'] as int?) ?? 0,
                page: (m['page'] as int?) ?? 0,
                wordIndex: m['word_index'] as int,
              ),
        ],
        translations:
            translations[key] == null ? const [] : [translations[key]!],
      ));
    }
    return PageComposer.compose(sentences);
  }

  group('a composed page keeps what the reader looks for', () {
    test('paragraphs are opened and closed in balance', () async {
      final html = await composePage('mula_di_01', 3);
      expect('<p class='.allMatches(html).length, '</p>'.allMatches(html).length,
          reason: 'the reader splits on </p> to insert line breaks');
      expect(html.startsWith('<p class="'), isTrue);
    });

    test('word tap yields clean Pali, never markup', () async {
      // The reader strips everything that is not a Pali letter from the word
      // it was handed. If markup leaked into a text node, the lookup would be
      // for a word that does not exist.
      final html = await composePage('mula_di_01', 3);
      final text = html.replaceAll(RegExp(r'<[^>]*>'), ' ');
      final words = text
          .split(RegExp(r'\s+'))
          .map((w) =>
              w.replaceAll(RegExp(r'[^a-zA-ZāīūṅñṭḍṇḷṃĀĪŪṄÑṬḌHṆḶṂ]'), ''))
          .where((w) => w.isNotEmpty)
          .toList();
      expect(words, isNotEmpty);
      for (final word in words) {
        expect(word, isNot(contains('span')), reason: 'markup leaked');
        expect(word, isNot(contains('class')), reason: 'markup leaked');
        expect(word, isNot(contains('href')), reason: 'markup leaked');
      }
    });

    test('page-number anchors are spelled the way the reader converts', () async {
      // The reader turns <a name="V1.0023"></a> into a visible [V 1.23] badge.
      final html = await composePage('mula_di_01', 3);
      final anchors =
          RegExp(r'<a name="([VPT])(\d+)\.(\d{4})"></a>').allMatches(html);
      expect(anchors, isNotEmpty,
          reason: 'no edition badges would ever appear on this page');
    });

    test('variant readings are wrapped so they can be hidden', () async {
      // The reader removes <span class="note">[...]</span> when the reader has
      // alternate readings turned off.
      var found = false;
      for (final page in [1, 2, 3, 4, 5, 6, 7, 8]) {
        final html = await composePage('mula_di_01', page);
        if (RegExp(r'<span class="note">\[[^\]]*\]</span>').hasMatch(html)) {
          found = true;
          break;
        }
      }
      expect(found, isTrue,
          reason: 'variant readings must be wrapped, or they cannot be hidden');
    });

    test('a bilingual page carries the spans styling and TTS depend on',
        () async {
      if (!File('$dbDir\\lang_en.db').existsSync()) {
        markTestSkipped('no translation installed');
        return;
      }
      final html = await composePage('mula_di_01', 3, withTranslation: true);

      // These two class names drive the Pali-only / both / translation-only
      // setting, and the translation span is what text to speech anchors its
      // highlight to.
      expect(html, contains('<span class="palitext">'));
      expect(html, contains('<span class="translation_text">'));

      // The highlight is injected by finding the span that precedes the
      // spoken text, so a translation must be preceded by its opening tag.
      final translation =
          RegExp(r'<span class="translation_text">([^<]{20,})</span>')
              .firstMatch(html);
      expect(translation, isNotNull);
      final spoken = translation!.group(1)!;
      expect(html.indexOf(spoken), greaterThan(0));
      expect(html.substring(0, html.indexOf(spoken)),
          contains('<span class="translation_text">'));
    });

    test('Pali-only pages carry no bilingual wrapper', () async {
      final html = await composePage('mula_di_01', 3);
      expect(html, isNot(contains('palitext')));
      expect(html, isNot(contains('translation_text')));
    });
  });
}
