import 'package:tipitaka_pali/business_logic/models/dictionary_history.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/utils/pali_script.dart';
import 'package:tipitaka_pali/utils/pali_script_converter.dart';
import 'package:tipitaka_pali/utils/script_detector.dart';

abstract class DictionaryHistoryRepository {
  Future<int> insert(
    String word,
    String context,
    int page,
    String bookID,
  );

  Future<int> delete(String word);

  Future<void> deleteAll();

  Future<List<DictionaryHistory>> getAll();
}

class DictionaryHistoryDatabaseRepository
    implements DictionaryHistoryRepository {
  DictionaryHistoryDatabaseRepository({required this.dbh});
  DatabaseHelper dbh;

  final _historyTable = 'dictionary_history';
  final _columnWord = 'word';

  @override
  Future<int> insert(
      String word, String context, int page, String bookId) async {
    final db = await dbh.database;
    // Kept in Roman, as the dictionary looks words up. A word tapped in Thai
    // or another script lost every letter to the line below and was kept
    // empty, so the flash cards had no word (#340).
    final script = ScriptDetector.getLanguage(word);
    if (script != Script.roman) {
      word = PaliScript.getRomanScriptFrom(script: script, text: word);
    }

    // Remove numbers and punctuation, retaining only specified characters and whitespace
    String sanitizedWord =
        word.replaceAll(RegExp(r'[^\sa-zA-ZāīūṅñṭḍṇḷṃĀĪŪṄÑṬḌṆḶṂ]+'), '');
    // delete first if exists
    await db.delete(_historyTable,
        where: '$_columnWord = ?', whereArgs: [sanitizedWord]);

    return await db.insert(
      _historyTable,
      DictionaryHistory(
              word: sanitizedWord,
              context: context,
              bookId: bookId,
              page: page,
              dateTime: DateTime.now())
          .toMap(),
    );
  }

  @override
  Future<int> delete(String word) async {
    final db = await dbh.database;
    return await db
        .delete(_historyTable, where: '$_columnWord = ?', whereArgs: [word]);
  }

  @override
  Future<void> deleteAll() async {
    final db = await dbh.database;
    await db.delete(_historyTable);
  }

  @override
  Future<List<DictionaryHistory>> getAll() async {
    final db = await dbh.database;
    final maps = await db.query(
      _historyTable,
    );
    return maps.map((entry) => DictionaryHistory.fromMap(entry)).toList();
  }
}
