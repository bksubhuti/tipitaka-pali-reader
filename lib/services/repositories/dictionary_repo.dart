import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:flutter/material.dart';
import 'package:tipitaka_pali/business_logic/models/definition.dart';
import 'package:tipitaka_pali/business_logic/models/dictionary.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/prefs.dart';

abstract class DictionaryRepository {
  Future<List<Definition>> getDefinition(String id);
  Future<Definition> getDpdDefinition(String headwords);
  Future<List<String>> getSuggestions(String word);
  Future<String> getDprBreakup(String word);
  Future<String> getDprStem(String word);
  Future<String> getDpdHeadwords(String word);
}

class DictionaryDatabaseRepository implements DictionaryRepository {
  final DatabaseHelper databaseHelper;
  DictionaryDatabaseRepository(this.databaseHelper);

  @override
  Future<List<Definition>> getDefinition(String word) async {
    final db = await databaseHelper.database;
    String sql = '''
      SELECT word, definition, dictionary_books.name,user_order from dictionary, dictionary_books 
      WHERE word = '$word' AND dictionary.book_id = dictionary_books.id
      AND dictionary_books.user_choice = 1
      ORDER BY dictionary_books.user_order
    ''';
    List<Map<String, dynamic>> maps = await db.rawQuery(sql);
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
      SELECT word, definition, user_order, name from dpd, dictionary_books 
      WHERE word = '$word' AND user_choice =1  AND dictionary_books.id = dpd.book_id
    ''';
      List<Map<String, dynamic>> maps = await db.rawQuery(sql);
      List<Definition> defs = maps.map((x) => Definition.fromJson(x)).toList();
      if (defs.isNotEmpty) {
        htmlDefs = defs[0].definition;

        if (htmlDefs.isNotEmpty) {
          BeautifulSoup bs = BeautifulSoup(htmlDefs);
          // need to remove summary contents with bs
          // extract div classs dpd should be good.
          Bs4Element? bs4 = bs.find("div", class_: 'dpd');
          if (bs4 != null) {
            stripDefs += '<P>'; // style="font-weight: normal;"> [ $word ] : ';
            stripDefs += bs4.toString(); //bs.text;
          } else {
            stripDefs += '<P>'; // style="font-weight: normal;"> [ $word ] : ';
            stripDefs += htmlDefs; //bs.text;
          }
        }
        stripDefs += '</P>';
        stripDefs = stripDefs.replaceAll("✎", "");
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
  Future<List<String>> getSuggestions(String word) async {
    final db = await databaseHelper.database;
    final sql = '''
      SELECT word from dictionary, dictionary_books 
      WHERE word LIKE '$word%' AND dictionary.book_id = dictionary_books.id
      AND dictionary_books.user_choice = 1
      ORDER BY dictionary_books.user_order LIMIT 200
    ''';
    List<Map<String, dynamic>> maps = await db.rawQuery(sql);
    return maps.map((e) => e['word'] as String).toList();
  }

  @override
  Future<String> getDprBreakup(String word) async {
    final db = await databaseHelper.database;
    final List<Map<String, dynamic>> maps = await db.query('dpr_breakup',
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

  Future<List<Definition>> _adjustPEU(
      String word, List<Definition> defs) async {
    // before giving the list of definitions.. check to see if peu was selected.
    // if selected, reduce the search item up to 5 char.
    // result should not be bigger than original and not less than 5 chars (assuming we have all of these)
    //if (defs.contains(element.)
    final db = await databaseHelper.database;

    if (Prefs.isPeuOn) {
      bool hasPeu = false;
      for (int x = 0; x < defs.length; x++) {
        if (defs[x].bookName.contains("PEU")) {
          hasPeu = true;
          return defs; // there is a definition found with normal query
        }
      }

      // the peu is selected
      // the PEU does not have a definition
      // We now need to adjust this.
      // see if we can get a hit.
      if (!hasPeu && word.length >= 14) {
        // reduce one by one up to 4 times to see if the word exists
        // add those words to the list.
        for (int reduce = 1; reduce < 5; reduce++) {
          String sql = '''
      SELECT word, definition, "PEU Algo Used" as "name" from dictionary 
             WHERE
                dictionary.book_id = 8
                AND dictionary.word LIKE '${word.substring(0, word.length - reduce)}%' 
                AND  length(dictionary.word) <= ${word.length}
                  ''';

// TODO manually remove the word if bigger than original.

          List<Map> list = await db.rawQuery(sql);
          if (list.isNotEmpty) {
            // we found the word.. now need to add it.
            debugPrint("found word in peu ${list[0].toString()}");

            var peuDefs = list.map((x) => Definition.fromJson(x)).toList();

            Definition def = peuDefs[0];
            def.definition = formatePeuAlgoDef(word, def.word!, def.definition);
            debugPrint(def.definition);
            defs.add(def);
            return defs;
          }
        }
      }
    } // peu is selected

/*
  Future<List<InterviewDetails>> getAllInterviewDetails() async {
    //await initDatabase();
    final _db = await _dbHelper.database;

    String dbQuery =
        '''Select residentDetails.id_code, residentDetails.dhamma_name, residentDetails.passport_name,residentDetails.kuti, residentDetails.country, interviews.stime, interviews.teacher, interviews.pk
          FROM residentDetails, interviews
          WHERE residentDetails.id_code = interviews.id_code
          ORDER BY interviews.stime DESC''';

    List<Map> list = await _db.rawQuery(dbQuery);
    return list
        .map((interviewdetails) => InterviewDetails.fromJson(interviewdetails))
        .toList();

    //return list.map((trail) => Trail.fromJson(trail)).toList();
  }
*/

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
}
