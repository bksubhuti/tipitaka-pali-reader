import 'package:sqflite/sqflite.dart';

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
  static const _tables = [
    'pages',
    'fts_pages',
    'fts_translation_pages',
  ];

  /// Whether the old data is still present.
  static Future<bool> isPending(Database db) async {
    final rows = await db.rawQuery(
        "SELECT count(*) AS n FROM sqlite_master "
        "WHERE type='table' AND name='pages'");
    return (rows.first['n'] as int) > 0;
  }

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

    onProgress?.call('Removing the old page data…');
    for (final table in _tables) {
      await db.execute('DROP TABLE IF EXISTS $table');
    }

    onProgress?.call('Reclaiming space…');
    await db.execute('VACUUM');
    onProgress?.call('Done');
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
      if (++pending >= 2000) {
        await batch.commit(noResult: true);
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
