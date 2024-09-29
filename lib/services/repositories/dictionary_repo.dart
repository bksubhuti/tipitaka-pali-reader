import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:flutter/material.dart';
import 'package:tipitaka_pali/business_logic/models/definition.dart';
import 'package:tipitaka_pali/business_logic/models/dictionary.dart';
import 'package:tipitaka_pali/business_logic/models/dpd_root_family.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/prefs.dart';

import '../../business_logic/models/dictionary_history.dart';
import 'package:tipitaka_pali/business_logic/models/dpd_inflection.dart';

abstract class DictionaryRepository {
  Future<List<Definition>> getDefinition(String id);
  Future<Definition> getDpdDefinition(String headwords);
  Future<Definition> getDpdGrammarDefinition(String word);
  Future<List<String>> getSuggestions(String word);
  Future<String> getDpdWordSplit(String word);
  Future<String> getDprStem(String word);
  Future<DpdInflection?> getDpdInflection(int wordId);
  Future<DpdRootFamily?> getDpdRootFamily(int wordId);
  Future<String> getDpdHeadwords(String word);
  Future<String> getDpdLikeHeadwords(String word);
  Future<int> insertOrReplace(DictionaryHistory dictionaryHistory);

  Future<int> delete(DictionaryHistory dictionaryHistory);

  Future<int> deleteAll();

  Future<List<DictionaryHistory>> getDictionaryHistory();
}

class DictionaryDatabaseRepository implements DictionaryRepository {
  final DatabaseHelper databaseHelper;
  DictionaryDatabaseRepository(this.databaseHelper);

  @override
  Future<List<Definition>> getDefinition(String word) async {
    final db = await databaseHelper.database;
    String wordplus = "$word 2";
    String sqlCheckWord = '''
      SELECT word from dictionary, dictionary_books
      WHERE word = '$wordplus' AND dictionary.book_id = 8
      AND dictionary_books.user_choice = 1
      ORDER BY dictionary_books.user_order
    ''';

    List<Map<String, dynamic>> mapsNeedGlob = await db.rawQuery(sqlCheckWord);

    String sql = '''
      SELECT word, definition, dictionary_books.name,user_order from dictionary, dictionary_books
      WHERE word = '$word' AND dictionary.book_id = dictionary_books.id
      AND dictionary.book_id = dictionary_books.id
      AND dictionary_books.user_choice = 1
      ORDER BY dictionary_books.user_order
    ''';

    String sqlGLOB = '''
      SELECT word, definition, dictionary_books.name,user_order
      FROM dictionary, dictionary_books
      WHERE (word = '$word' or word GLOB '$word [0-9]*')
      AND dictionary.book_id = dictionary_books.id
      AND dictionary_books.user_choice = 1
      ORDER BY dictionary_books.user_order
    ''';

    List<Map<String, dynamic>> maps =
        await db.rawQuery(mapsNeedGlob.isNotEmpty ? sqlGLOB : sql);
    List<Definition> defs = maps.map((x) => Definition.fromJson(x)).toList();

    return _adjustPEU(word, defs);
  }

  @override
  Future<Definition> getDpdDefinition(String headwords) async {
    final db = await databaseHelper.database;

    String line = headwords.replaceAll('[', "");
    line = line.replaceAll(']', "");
    line = line.replaceAll('\'', "");
    String htmlDefs = "";
    String stripDefs = '';
    String word = "";
    List<String> words = line.split(',');
    String bookName = '';
    int order = 0;

    for (var element in words) {
      word = element.trimLeft();
      final sql = '''
      SELECT dpd.id as id, word, definition, user_order, name from dpd, dictionary_books 
      WHERE word = '$word' AND user_choice =1  AND dictionary_books.id = dpd.book_id
    ''';
      List<Map<String, dynamic>> maps = await db.rawQuery(sql);
      List<Definition> defs = maps.map((x) => Definition.fromJson(x)).toList();
      if (defs.isNotEmpty) {
        String def = defs[0].definition;

        // Replace the last occurrence of the "Submit a correction" row start tag
        final extras = {
          "inflect": "Inflect",
          "root-family": "Root Family"
        };
        final links = extras.entries.map((entry) => '<a href="dpd://${entry.key}:${defs[0].id}">${entry.value}</a>').toList().join(' ');
        def = replaceLast(
          def,
          '<tr><td colspan="2">',
          '<tr><td><b>Extras</b></td><td>$links</td></tr><tr><td colspan="2">',
        );

        htmlDefs = def;

        if (htmlDefs.isNotEmpty) {} // added this extra
        stripDefs += htmlDefs;
        order = maps.first['user_order'];
        bookName = maps.first['name'];
      }
    }

    // We will build a list from the headwords (if mulitple headwords)
    // Then we will do a raw query for each word and add to definition
    //

    Definition def = Definition(
        word: word, //line,
        definition: stripDefs,
        bookName: bookName,
        userOrder: order);

    return def;
  }

  @override
  Future<DpdInflection?> getDpdInflection(int wordId) async {
    final db = await databaseHelper.database;
    final sql = '''
      SELECT 
        dpd__inflections.id as id,
        dpd__inflections.stem as stem,
        dpd__inflections.pattern as pattern,
        dpd__inflections.inflections as inflections,
        dpd.word as word
      FROM
        dpd__inflections 
      JOIN 
        dpd on dpd.id = dpd__inflections.id
      WHERE dpd__inflections.id = '$wordId';
    ''';

    try {
      List<Map<String, dynamic>> maps = await db.rawQuery(sql);
      List<DpdInflection> defs =
          maps.map((x) => DpdInflection.fromJson(x)).toList();
      if (defs.isNotEmpty) {
        return defs[0];
      }
    } catch (e) {
      // will get error if the table is not created from extension
      // return no data
      return null;
    }

    return null;
  }

  @override
  Future<DpdRootFamily?> getDpdRootFamily(int wordId) async {
    final db = await databaseHelper.database;
    final sql = '''
      SELECT 
        dpd.word as word,
        dpd__family_root.*
      FROM
        dpd 
      JOIN 
        dpd__word_family_root on dpd__word_family_root.id = dpd.id
      JOIN
        dpd__family_root on dpd__family_root.root_family = dpd__word_family_root.family_root
      WHERE dpd.id = '$wordId';
    ''';

    try {
      List<Map<String, dynamic>> maps = await db.rawQuery(sql);
      List<DpdRootFamily> defs =
      maps.map((x) => DpdRootFamily.fromJson(x)).toList();
      if (defs.isNotEmpty) {
        return defs[0];
      }
    } catch (e) {
      // will get error if the table is not created from extension
      // return no data
      return null;
    }

    return null;
  }

  @override
  Future<Definition> getDpdGrammarDefinition(String word) async {
    Definition def = Definition();
    final db = await databaseHelper.database;
    final sql = '''
      SELECT word, definition from dpd_grammar 
      WHERE word = '$word';
    ''';
    List<Map<String, dynamic>> maps = await db.rawQuery(sql);
    List<Definition> defs = maps.map((x) => Definition.fromJson(x)).toList();
    if (defs.isNotEmpty) {
      defs[0].definition =
          "<hr style='margin-top: 10px; margin-bottom: 10px;'><div style='text-align: center; margin-bottom: 10px;'>DPD Grammar</div><hr style='margin-top: 10px; margin-bottom: 10px;'><br>${defs[0].definition}";
      defs[0].bookName = "DPD Grammar";
      return defs[0];
    } else {
      return def;
    }
  }

  @override
  Future<List<String>> getSuggestions(String word) async {
    final db = await databaseHelper.database;
    String sql = '';

    // if dpd is selected
    sql = '''
  SELECT dpd.word as word , length(word) as si from dictionary_books, dpd
      WHERE dpd.word LIKE ? AND dictionary_books.id = 11
      AND dictionary_books.user_choice = 1
      ORDER by si
	    LIMIT 80
    ''';

    List<Map<String, dynamic>> maps = await db.rawQuery(sql, ['$word%']);
    List<String> list = maps.map((e) => e['word'] as String).toList();

    // because sqlflite does not support regex, we need to fix this
    // manually in code from the resultant dataset.
    for (int x = 0; x < list.length; x++) {
      String s = list[x];
      if (s.contains(RegExp(r'[0-9]'))) {
        // remove the number and add it back.
        List<String> pureWords = s.split(' ');
        if (pureWords.isNotEmpty) {
          list[x] = pureWords[0];
        }
      }
    }
    for (int x = 0; x < list.length; x++) {
      String s = list[x];
      if (s.contains(RegExp(r'[0-9]'))) {
        // remove the number and add it back.
        List<String> pureWords = s.split(' ');
        if (pureWords.isNotEmpty) {
          list[x] = pureWords[0];
        }
      }
    }

    // we are in hack mode.. to tweak things better
    // we have two tables.. and dpd is its own table.. so
    // now need to get from the original dictionary table and merge
    sql = '''
      SELECT word from dictionary, dictionary_books 
      WHERE word LIKE ? AND dictionary.book_id = dictionary_books.id
      AND dictionary_books.user_choice = 1
      ORDER BY dictionary_books.user_order LIMIT 200
    ''';
    List<Map<String, dynamic>> maps2 = await db.rawQuery(sql, ['$word%']);
    List<String> list2 = maps2.map((e) => e['word'] as String).toList();

    for (String x in list2) {
      list.add(x);
    }

    // Lasty one more item.. Often they will paste a word that is found only in the inflections to headwords table
    // so we need to add that one too.  So often it is empty even though we should find the word.

    if (list.isEmpty) {
      sql = '''
      SELECT inflection  from dpd_inflections_to_headwords 
      WHERE inflection = ?
    ''';

      List<Map<String, dynamic>> maps3 = await db.rawQuery(sql, [word]);
      List<String> list3 = maps3.map((e) => e["inflection"] as String).toList();

      for (String x in list3) {
        list.add(x);
      }
    }
    // remove duplicates (code from SO)  easiest way..
    // and sort'em
    List<String> distinctIds = list.toSet().toList();
    distinctIds.sort();
    // Sort the list of strings according to the length of each string
    distinctIds.sort((a, b) => a.length.compareTo(b.length));
    return distinctIds;
  }

  @override
  Future<String> getDpdWordSplit(String word) async {
    final db = await databaseHelper.database;
    final List<Map<String, dynamic>> maps = await db.query('dpd_word_split',
        columns: ['breakup'], where: 'word = ?', whereArgs: [word]);
    // word column is unqiue
    // so list always one entry
    if (maps.isEmpty) return '';
    return maps.first['breakup'] as String;
  }

  @override
  Future<String> getDprStem(String word) async {
    final db = await databaseHelper.database;

    String sql = '''
      SELECT stem from dpr_stem where word = '$word'
''';

    final List<Map<String, dynamic>> maps = await db.rawQuery(sql);
    // word column is unqiue
    // so list always one entry
    if (maps.isEmpty) return '';
    return maps.first['stem'] as String;
  }

  @override
  Future<String> getDpdHeadwords(String word) async {
    final db = await databaseHelper.database;

    String sql = '''
        SELECT headwords 
        FROM dpd_inflections_to_headwords
        WHERE inflection = "$word";
''';
    final List<Map<String, dynamic>> maps = await db.rawQuery(sql);
    // word column is unqiue
    // so list always one entry
    if (maps.isEmpty) return '';
    return maps.first['headwords'] as String;
  }

  @override
  Future<String> getDpdLikeHeadwords(String word) async {
    final db = await databaseHelper.database;

    String sql = '''
        SELECT headwords 
        FROM dpd_inflections_to_headwords
        WHERE headwords Like "$word%";
''';
    final List<Map<String, dynamic>> maps = await db.rawQuery(sql);
    // word column is unqiue
    // so list always one entry
    if (maps.isEmpty) return '';
    return maps.first['headwords'] as String;
  }

  Future<List<Definition>> _adjustPEU(
      String word, List<Definition> defs) async {
    final db = await databaseHelper.database;
    bool hasPeu = defs.any((def) => def.bookName.contains("PEU"));

    if (Prefs.isPeuOn) {
      if (hasPeu) {
        // Format all PEU definitions
        defs.where((def) => def.bookName.contains("PEU")).forEach((def) {
          def.definition = formatPeuTable(def.word, def.definition);
        });
      } else if (word.length >= 9) {
        // Attempt to find and adjust definitions from the PEU dictionary
        String sql = '''
        SELECT *
        FROM dictionary
        WHERE dictionary.book_id = 8
        AND length(word) BETWEEN ${word.length - 4} and ${word.length}
        AND word LIKE '${word.substring(0, word.length - 4)}%'
        ORDER BY CASE 
          WHEN word LIKE '${word.substring(0, word.length - 1)}%' THEN 1
          WHEN word LIKE '${word.substring(0, word.length - 2)}%' THEN 2
          WHEN word LIKE '${word.substring(0, word.length - 3)}%' THEN 3
          ELSE 4                             
        END
        LIMIT 1;
      ''';

        List<Map> list = await db.rawQuery(sql);
        if (list.isNotEmpty) {
          debugPrint("found word in PEU: ${list[0].toString()}");
          var peuDefs = list.map((x) => Definition.fromJson(x)).toList();
          Definition def = peuDefs[0];
          def.bookName = "PEU Algo Used";
          def.definition = formatPeuTable(def.word, def.definition);
          debugPrint(def.definition);
          defs.add(def);
        }
      }
    }
    return defs;
  }

  String formatePeuAlgoDef(String fullWord, String foundWord, String def) {
    //"<p>PEU-Algo Activated: </p> ${def.definition}";

    // get word plus remainter.
    BeautifulSoup bs = BeautifulSoup(def);
    String newdef =
        "<p> [ $foundWord+${fullWord.substring(foundWord.length)} ] ${bs.text}";

    return newdef;
  }

  Future fixOtherDictionaries() async {
    List<Dictionary> dictionaries = await getOtherDictionaries();
    final db = await databaseHelper.database;
    int counter = 0;
    if (dictionaries.isNotEmpty) {
      for (Dictionary dict in dictionaries) {
        // modify the definition
        BeautifulSoup bs = BeautifulSoup(dict.definition);
        String newDef = '<p class="definition">${bs.text}</p>';
        String word = dict.word!.replaceAll(",", "");
        // change single quote into double single quote for sql req
        newDef = newDef.replaceAll('\'', '\'\'');
        word = word.replaceAll('\'', '\'\'');

        String sql = '''
                Update dictionary
                Set definition = '$newDef'
                Where word = '$word' AND book_id = ${dict.bookID}    
          ''';
        // definition = '${dict.definition}'  AND
        //debugPrint("${dict.word} ${dict.bookID}");
        await db.rawUpdate(sql);
        counter++;
        if ((counter % 50) == 1) {
          debugPrint(
              "working $counter of ${dictionaries.length}: $word with ${dict.bookID}");
        }
      }
    }
  }

  Future<List<Dictionary>> getOtherDictionaries() async {
    final db = await databaseHelper.database;
    const sql = '''
      SELECT word, definition, book_id from dictionary
      WHERE book_id > 69
    ''';

    List<Map> list = await db.rawQuery(sql);
    return list.map((dictionary) => Dictionary.fromJson(dictionary)).toList();
  }

  @override
  Future<int> insertOrReplace(DictionaryHistory dh) async {
    final db = await databaseHelper.database;
    final dt = DateTime.now();
    String now = dt.year.toString() +
        dt.month.toString() +
        dt.day.toString() +
        dt.hour.toString() +
        dt.minute.toString();

    var result = await db
        .rawDelete("DELETE FROM dictionary_history WHERE word = '${dh.word}';");
    result = await db.rawInsert(
        "INSERT INTO dictionary_history (word, date) VALUES('${dh.word}', '$now')");
    return result;
  }

  @override
  Future<int> delete(DictionaryHistory dh) async {
    final db = await databaseHelper.database;

    return await db
        .rawDelete("DELETE FROM dictionary_history WHERE word = '${dh.word}';");
  }

  @override
  Future<int> deleteAll() async {
    final db = await databaseHelper.database;
    return await db.rawDelete("DELETE FROM dictionary_history");
  }

  @override
  Future<List<DictionaryHistory>> getDictionaryHistory() async {
    final db = await databaseHelper.database;

    List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT word, context, date, book_id, page_number
      FROM dictionary_history ORDER BY date;
      ''');
    return maps.map((x) => DictionaryHistory.fromMap(x)).toList();
  }

  String formatPeuTable(String word, String definitionHtml) {
    // Parse the HTML using Beautiful Soup for Dart
    BeautifulSoup soup = BeautifulSoup(definitionHtml);

    // Extract text from the <p> tag
    String? definitionText = soup.text;

    // Define the patterns for confidence level
    RegExp clPattern = RegExp(r"CL=(\d+)");
    RegExp googleTranslatePattern = RegExp(r"Google Translate");

    String confidence;
    String breakup;
    String cleanedDefinition;

    if (googleTranslatePattern.hasMatch(definitionText)) {
      confidence = "Google Translation";
      // Split at "Google Translate" to separate breakup and definition
      List<String> parts = definitionText!.split("Google Translate");
      breakup = parts[0].trim();
      cleanedDefinition = parts.length > 1 ? parts[1].trim() : '';
    } else {
      // Handle regular "CL=" case
      RegExpMatch? clMatch = clPattern.firstMatch(definitionText ?? '');
      confidence = clMatch != null ? clMatch.group(1)! : 'Unknown';
      List<String> parts = definitionText!.split(clPattern);
      breakup = parts[0].trim();
      cleanedDefinition = parts.length > 1 ? parts[1].trim() : '';
    }

    // Format sub-definitions
    cleanedDefinition = formatDefinitions(cleanedDefinition);

    // Build the HTML table
    return buildHtmlTable(word, breakup, confidence, cleanedDefinition);
  }

  String formatDefinitions(String definitions) {
    // Handle sub-definitions formatting for both numbers and letters
    return definitions.replaceAllMapped(RegExp(r"\(([1-9]|[a-zA-Z])\)"),
        (Match match) {
      // Ensure we don't place <BR> before the very first definition
      if (match.start > 0) {
        return "<BR>${match.group(0)}";
      }
      return match.group(
          0)!; // Return without modification for the first sub-definition
    });
  }

  String buildHtmlTable(String word, String breakup, String confidence,
      String cleanedDefinition) {
    return '''
<table border="0" cellpadding="5" cellspacing="0">
  <tr>
    <th style="vertical-align: top;">Word</th>
    <td>$word</td>
  </tr>
  <tr>
    <th style="vertical-align: top;">Breakup</th>
    <td>$breakup</td>
  </tr>
  <tr>
    <th style="vertical-align: top;">Confidence</th>
    <td>$confidence</td>
  </tr>
  <tr>
    <th style="vertical-align: top;">Definition</th>
    <td>$cleanedDefinition</td>
  </tr>
</table>
''';
  }

  // Helper function to replace the last occurrence of a substring
  String replaceLast(String text, String from, String to) {
    int lastIndex = text.lastIndexOf(from);
    if (lastIndex == -1) return text;
    String before = text.substring(0, lastIndex);
    String after = text.substring(lastIndex + from.length);
    return before + to + after;
  }
}
