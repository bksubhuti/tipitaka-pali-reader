import 'package:sqflite/sqflite.dart';

/// Rebuilds a search unit's text from the sentences it was indexed from.
///
/// The search indexes are contentless, so the text they matched on is not
/// stored. It does not need to be: the Pali is in `epi.sentences` and each
/// translation in its own file, and a unit records which book and which
/// paragraphs it covers. Rebuilding is a keyed range read.
///
/// This must reproduce what the builder indexed exactly, character for
/// character, because the highlight and the page a result opens on are both
/// worked out by finding the phrase's offset in this string. The cleaning
/// below is therefore the same as the builder's, and a test checks a sample
/// against the real index rather than trusting that it stays so.
class UnitText {
  UnitText._();

  static final _tag = RegExp(r'<[^>]*>');
  static final _space = RegExp(r'\s+');

  static String _clean(String text) =>
      text.replaceAll(_tag, ' ').replaceAll(_space, ' ').trim();

  /// The Pali of one unit.
  static Future<String> pali(
    DatabaseExecutor db, {
    required String epiBook,
    required int startPara,
    required int endPara,
  }) async {
    final rows = await db.rawQuery(
      'SELECT pali FROM epi.sentences '
      'WHERE book_id = ? AND para_id BETWEEN ? AND ? '
      'ORDER BY para_id, line_id',
      [epiBook, startPara, endPara],
    );
    return _join(rows, 'pali');
  }

  /// One unit in one installed language.
  static Future<String> translation(
    DatabaseExecutor db, {
    required String lang,
    required String epiBook,
    required int startPara,
    required int endPara,
  }) async {
    try {
      final rows = await db.rawQuery(
        'SELECT translation FROM lang_$lang.sentences '
        'WHERE book_id = ? AND para_id BETWEEN ? AND ? '
        'ORDER BY para_id, line_id',
        [epiBook, startPara, endPara],
      );
      return _join(rows, 'translation');
    } catch (_) {
      // A language removed since the index was built. The result still has a
      // page to open; only its snippet is lost.
      return '';
    }
  }

  /// Several units at once, keyed by unit id, so a page of results costs one
  /// query per language rather than one per row.
  static Future<Map<int, String>> paliForAll(
    DatabaseExecutor db,
    List<({int id, String epiBook, int startPara, int endPara})> units,
  ) async {
    final out = <int, String>{};
    for (final unit in units) {
      out[unit.id] = await pali(db,
          epiBook: unit.epiBook,
          startPara: unit.startPara,
          endPara: unit.endPara);
    }
    return out;
  }

  static String _join(List<Map<String, Object?>> rows, String column) {
    final buffer = StringBuffer();
    for (final row in rows) {
      final text = _clean(row[column] as String? ?? '');
      if (text.isEmpty) continue;
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(text);
    }
    return buffer.toString();
  }
}
