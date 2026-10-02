import 'package:sqflite/sqflite.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';

/// Removes the page-shaped data once the sentence data has taken over.
///
/// Until now the app has carried the canon several times: the original `pages`
/// table of HTML, the search index built from it, and the sentence data with
/// its own index. That was deliberate while the two lived side by side, so the
/// app still worked if the sentence data was missing. It is also most of the
/// footprint.
///
/// Retiring is done once, and only when everything that depended on the old
/// tables has been provided for. The word list is the last of those: it drives
/// search suggestions and dictionary completion, and was built by reading
/// every page. It is rebuilt here from the sentences instead.
///
/// This is not reversible from inside the app. Reinstalling restores it.
class LegacyDataRetirement {
  LegacyDataRetirement._();

  /// Tables that exist only to serve the page-shaped reader.
  ///
  /// Emptied of the books the sentence data covers rather than dropped
  /// outright, then dropped only if nothing is left in them. See [run].
  static const _tables = [
    'pages',
    'fts_pages',
    'fts_translation_pages',
  ];

  /// How each table names the book it belongs to.
  static const _bookColumn = {
    'pages': 'bookid',
    'fts_pages': 'bookid',
    'fts_translation_pages': 'bookid',
  };

  /// Whether there is still canon page data to remove.
  ///
  /// Not simply "does `pages` exist". [run] keeps the books ePitaka does not
  /// carry, so the table normally survives; asking only whether it is there
  /// would make this true for ever and run the retirement, VACUUM included,
  /// on every start. The question is whether any row remains for a book the
  /// sentence data covers.
  static Future<bool> isPending(Database db) async {
    if (!await _exists(db, 'pages')) return false;
    try {
      final rows = await db.rawQuery(
          'SELECT EXISTS(SELECT 1 FROM pages WHERE bookid IN '
          '(SELECT DISTINCT tpr_book FROM ext.page_break)) AS n');
      return ((rows.first['n'] as int?) ?? 0) > 0;
    } catch (_) {
      // No extension attached: nothing can be retired yet.
      return false;
    }
  }

  /// Whether any page text at all is left, covered or not. This is what the
  /// reader's fallback and the HTML importer care about.
  static Future<bool> hasLegacyPages(Database db) => _exists(db, 'pages');

  /// Rebuilds the word list from sentences, then drops the old tables.
  ///
  /// The word list is rebuilt *before* anything is dropped. If the run is
  /// interrupted between the two, the app still has both, which is a wasteful
  /// state but a working one.
  static Future<void> run(
    Database db, {
    void Function(String message)? onProgress,
  }) async {
    onProgress?.call('Rebuilding the word list…');
    await _buildWordList(db, onProgress: onProgress);
    await buildTranslationWordList(db, onProgress: onProgress);

    onProgress?.call('Removing the old page data…');
    // Only the books the sentence data actually covers. ePitaka does not
    // carry everything TPR can open: a book imported from HTML, or installed
    // from an extension zip, lives nowhere else, and dropping these tables
    // outright would delete it with no way back short of reinstalling. What
    // remains is small, and the reader falls back to it for those books.
    var kept = 0;
    for (final table in _tables) {
      if (!await _exists(db, table)) continue;
      final column = _bookColumn[table]!;
      await db.rawDelete('DELETE FROM $table WHERE $column IN '
          '(SELECT DISTINCT tpr_book FROM ext.page_break)');
      final rows = await db.rawQuery('SELECT count(*) AS n FROM $table');
      final remaining = (rows.first['n'] as int?) ?? 0;
      if (remaining == 0) {
        await db.execute('DROP TABLE IF EXISTS $table');
      } else {
        kept += remaining;
        onProgress?.call('$table keeps $remaining rows not in the sentences');
      }
    }
    if (kept > 0) {
      onProgress?.call('Kept $kept page rows for books ePitaka does not carry');
    }

    onProgress?.call('Reclaiming space…');
    await db.execute('VACUUM');
    onProgress?.call('Done');
  }

  static Future<bool> _exists(Database db, String table) async {
    final rows = await db.rawQuery(
        "SELECT count(*) AS n FROM sqlite_master "
        "WHERE type='table' AND name=?",
        [table]);
    return ((rows.first['n'] as int?) ?? 0) > 0;
  }

  /// Rebuilds both word lists, Pali and translation, without retiring
  /// anything. This is what the "rebuild the word list" action in settings
  /// does on an install that already runs on sentences.
  static Future<void> rebuildWordLists(
    Database db, {
    void Function(String message)? onProgress,
  }) async {
    await _buildWordList(db, onProgress: onProgress);
    await buildTranslationWordList(db, onProgress: onProgress);
  }

  /// The word list, counted from ePitaka's sentences.
  ///
  /// Same shape as before: the word, a plain form for matching, and how often
  /// it occurs, which is what orders the suggestions.
  static Future<void> _buildWordList(
    Database db, {
    void Function(String message)? onProgress,
  }) async {
    final frequency = <String, int>{};

    final books = await db.rawQuery(
        'SELECT DISTINCT book_id FROM epi.sentences ORDER BY book_id');
    var done = 0;
    for (final row in books) {
      final rows = await db.rawQuery(
        'SELECT pali FROM epi.sentences WHERE book_id = ?',
        [row['book_id']],
      );
      for (final sentence in rows) {
        for (final word in _words(sentence['pali'] as String? ?? '')) {
          frequency[word] = (frequency[word] ?? 0) + 1;
        }
      }
      done++;
      if (done % 20 == 0) {
        onProgress?.call(
            'Rebuilding the word list: ${(done / books.length * 100).round()}%');
      }
    }

    await db.execute('DROP TABLE IF EXISTS words');
    await db.execute('CREATE TABLE words ('
        'word TEXT COLLATE NOCASE, plain TEXT COLLATE NOCASE, '
        'frequency INTEGER)');

    var batch = db.batch();
    var pending = 0;
    for (final entry in frequency.entries) {
      batch.insert('words', {
        'word': entry.key,
        'plain': _plain(entry.key),
        'frequency': entry.value,
      });
      if (++pending >= 100) {
        await batch.commit(noResult: true);
        await Future.delayed(Duration.zero);
        batch = db.batch();
        pending = 0;
      }
    }
    if (pending > 0) await batch.commit(noResult: true);

    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS word_unique_index ON words (word)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS word_plain_index ON words (plain)');
  }

  /// Adds the words of every installed translation to the same list.
  ///
  /// Search-as-you-type reads one `words` table for both languages, telling
  /// them apart by frequency: a count of -1 means the word came from a
  /// translation rather than from the Pali. That convention is the old
  /// download service's, kept so the suggestion code needs no change.
  ///
  /// Previously these were gathered by parsing the `t1` paragraphs out of the
  /// page HTML. There is no such HTML once the pages are retired, and the
  /// Pali rebuild above starts from an empty table, so without this the
  /// English suggestions simply stop appearing.
  ///
  /// Only Latin-script translations yield anything, which is what the parsing
  /// version managed too. For Burmese or Thai the loop finds no words and
  /// adds none, rather than adding nonsense.
  /// Languages whose words the suggestion list can hold. It takes words in
  /// plain Latin letters only, so reading a Sinhala or Myanmar translation —
  /// hundreds of megabytes — finds next to nothing and only makes adding or
  /// removing one look hung.
  static const wordListLanguages = {'en', 'pt', 'de'};

  /// [replace] clears the translation words first and rebuilds them from
  /// [languages]; otherwise [languages] are added to what is there, which is
  /// all installing one needs.
  static Future<void> buildTranslationWordList(
    Database db, {
    List<String>? languages,
    bool replace = true,
    void Function(String message)? onProgress,
  }) async {
    final codes = (languages ?? DatabaseHelper.installedLanguages)
        .where(wordListLanguages.contains)
        .toList();
    // Nothing to put back means nothing is taken away. Someone still on the
    // old path may have an English list built from the page HTML, and
    // clearing that to replace it with nothing would be a plain loss.
    if (codes.isEmpty) return;
    await _createWordLanguages(db);
    if (replace) {
      await db.rawDelete('DELETE FROM words WHERE frequency = -1');
      await db.rawDelete('DELETE FROM $_wordLanguages');
    }

    for (final code in codes) {
      // Read a book at a time. One query for the whole translation pulled
      // some 200 MB across in a single answer and split it in one go: ten
      // seconds of a frozen screen on a phone, with no number to show it
      // was working.
      final words = <String>{};
      try {
        final books = await db.rawQuery(
            'SELECT DISTINCT book_id FROM lang_$code.sentences');
        for (var i = 0; i < books.length; i++) {
          final rows = await db.rawQuery(
              'SELECT translation FROM lang_$code.sentences WHERE book_id = ?',
              [books[i]['book_id']]);
          for (final row in rows) {
            words.addAll(_latinWords(row['translation'] as String? ?? ''));
          }
          if (i % 5 == 0) {
            onProgress?.call('Reading the $code translation: '
                '${((i + 1) / books.length * 100).round()}%');
            await Future.delayed(Duration.zero);
          }
        }
      } catch (e) {
        onProgress?.call('Could not read the $code translations: $e');
        continue;
      }

      var batch = db.batch();
      var pending = 0;
      var written = 0;
      for (final word in words) {
        // Pali wins any collision: it has a real frequency, which is what
        // orders the suggestions, and -1 would demote it.
        batch.rawInsert(
            'INSERT OR IGNORE INTO words (word, plain, frequency) '
            'VALUES (?, ?, -1)',
            [word, word]);
        written++;
        if (++pending >= 100) {
          await batch.commit(noResult: true);
          await Future.delayed(Duration.zero);
          batch = db.batch();
          pending = 0;
          if (written % 2000 == 0) {
            onProgress?.call('Adding $code words: $written of ${words.length}');
          }
        }
      }
      if (pending > 0) await batch.commit(noResult: true);
      // Recorded only once every word is written, so a build cut off part
      // way reads as not done and is done again at the next start.
      await db.rawInsert(
          'INSERT OR IGNORE INTO $_wordLanguages (code) VALUES (?)', [code]);
      onProgress?.call('Added ${words.length} $code words');
    }
  }

  /// Which languages' words are in the suggestion list, each written once
  /// all its words were. The words themselves cannot say where they came
  /// from.
  static const _wordLanguages = 'translation_word_languages';

  static Future<void> _createWordLanguages(Database db) => db.execute(
      'CREATE TABLE IF NOT EXISTS $_wordLanguages (code TEXT PRIMARY KEY)');

  /// Brings the translation words into line with the installed languages.
  ///
  /// A reset leaves the language files in place but starts a fresh database,
  /// whose suggestion list has none of their words; a build cut off part way
  /// leaves some of them. Either way the language reads as installed while
  /// its words are missing, so this checks what was actually completed rather
  /// than whether a file is there, and adds what is not.
  static Future<void> ensureTranslationWordLists(
    Database db, {
    void Function(String message)? onProgress,
  }) async {
    await _createWordLanguages(db);
    final done = (await db.rawQuery('SELECT code FROM $_wordLanguages'))
        .map((r) => r['code'] as String)
        .toSet();
    final wanted = DatabaseHelper.installedLanguages
        .where(wordListLanguages.contains)
        .toSet();
    final gone = done.difference(wanted);
    final missing = wanted.difference(done);
    if (gone.isNotEmpty) {
      // A language that has gone takes its words with it. The list cannot
      // tell whose a word is, so the rest are put back from their files.
      if (wanted.isEmpty) {
        await db.rawDelete('DELETE FROM words WHERE frequency = -1');
        await db.rawDelete('DELETE FROM $_wordLanguages');
      } else {
        await buildTranslationWordList(db,
            languages: wanted.toList(), onProgress: onProgress);
      }
      return;
    }
    if (missing.isEmpty) return;
    await buildTranslationWordList(db,
        languages: missing.toList(), replace: false, onProgress: onProgress);
  }

  static final _notLatin = RegExp(r'[^a-z-]+');

  /// Words of three letters or more, lower cased. Short ones are noise in a
  /// suggestion list and there are a great many of them.
  static Iterable<String> _latinWords(String text) => text
      .replaceAll(_tag, ' ')
      .toLowerCase()
      .split(_notLatin)
      .where((w) => w.length >= 3);

  static final _tag = RegExp(r'<[^>]*>');
  static final _notPali = RegExp(r'[^a-zāīūṅñṭḍṇḷṃ]+');
  static const _diacritics = {
    'ā': 'a', 'ī': 'i', 'ū': 'u', 'ṅ': 'n', 'ñ': 'n',
    'ṭ': 't', 'ḍ': 'd', 'ṇ': 'n', 'ḷ': 'l', 'ṃ': 'm',
  };

  static Iterable<String> _words(String pali) => pali
      .replaceAll(_tag, ' ')
      .toLowerCase()
      .split(_notPali)
      .where((w) => w.isNotEmpty);

  /// The accent-free form, so a reader can type without diacritics.
  static String _plain(String word) {
    final buffer = StringBuffer();
    for (final rune in word.runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(_diacritics[ch] ?? ch);
    }
    return buffer.toString();
  }
}
