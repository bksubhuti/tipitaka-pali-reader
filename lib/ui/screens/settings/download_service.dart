import 'dart:convert';

import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:flutter/material.dart';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../../business_logic/models/download_list_item.dart';
import 'download_notifier.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:dio/dio.dart';
import 'package:tipitaka_pali/business_logic/models/page_content.dart';

class DatabaseUpdate {
  final insertLines = [];
  final updateLines = [];
  final deleteLines = [];

  var insertCount = 0;
  var updateCount = 0;
  var deleteCount = 0;
}

class DownloadService {
  DownloadNotifier downloadNotifier;
  DownloadListItem downloadListItem;
  int batchAmount = 500;

  String _dir = "";

  late final String _zipPath;
  late final String _localZipFileName;
  final dbService = DatabaseHelper();

  DownloadService(
      {required this.downloadNotifier, required this.downloadListItem}) {
    _zipPath = downloadListItem.url;

    _localZipFileName = downloadListItem.filename;
  }

  Future<String> get _localPath async {
    return Prefs.databaseDirPath;
  }

  Future<File> get _localFile async {
    final path = Prefs.databaseDirPath;
    return File('$path/$_localZipFileName');
  }

  Future<String> getSQL() async {
    await downloadZip();
    final file = await _localFile;

    // Read the file
    String s = await file.readAsString();
    return s;
  }

  Future<List<File>> getTestZip() async {
    var zippedFile = File('$_dir/$_localZipFileName');
    return await unarchiveAndSave(zippedFile);
  }

  Future<List<File>> downloadZip() async {
    final zippedFile = await downloadFile(_zipPath, _localZipFileName);
    return await unarchiveAndSave(zippedFile);
  }

  Future<void> installSqlZip() async {
    initDir();
    Database db = await dbService.database;
    downloadNotifier.connectionChecking = false;
    downloadNotifier.downloading = true;
    downloadNotifier.totalSteps = 3;
    downloadNotifier.stepsCompleted = 0;
    downloadNotifier.message =
        "\nNow downloading file.. ${downloadListItem.size}\nPlease wait.";

//////////////////////////////////////////////
    ///.  For testing with local file, comment out the above downloadZip()
    /// and uncomment the below getTestZip() to read from local file instead of downloading
    /// Place the zip in the applicationsupport dir and rename it as any one of the extensions with the same name.
//////////////////////////////////////////////
    final sqlFiles = await downloadZip();
    //final sqlFiles = await getTestZip();
//////////////////////////////////////////////

    downloadNotifier.stepsCompleted = 1;
    // ACCUMULATOR: Keep track of every book added across all files
    final Set<String> allNewBooks = {};
    // --- SPEED BOOST: Turn off foreign key checks during bulk import ---
    await db.execute("PRAGMA foreign_keys = OFF;");

    // 1. IMPORT LOOP
    for (final sqlFile in sqlFiles) {
      downloadNotifier.message = "Importing ${sqlFile.path.split('/').last}...";
      final booksInFile = await processLocalFile(sqlFile);
      allNewBooks.addAll(booksInFile);
    }

// --- Restore normal database safety rules ---
    await db.execute("PRAGMA foreign_keys = ON;");

    downloadNotifier.stepsCompleted = 2;
    // 2. INDEXING LOOP (Runs only once)
    if (downloadListItem.type.contains("index") && allNewBooks.isNotEmpty) {
      downloadNotifier.message = 'Building fts';
      Database db = await dbService.database;

      await doFts(db, allNewBooks);

      Stopwatch stopwatch = Stopwatch()..start();
      // Call our new targeted word builder
      await makeUniversalWordList(allNewBooks);
      debugPrint('Making English Word List took ${stopwatch.elapsed}.');
    }

    if (downloadListItem.type.contains("dpd_grammar")) {
      downloadNotifier.message = 'adding dpd grammar flag';
      Prefs.isDpdGrammarOn = true;
    }

    downloadNotifier.stepsCompleted = 3;
    downloadNotifier.message = "Rebuilding Index";
    await dbService.buildBothIndexes();
    downloadNotifier.message = "Reloading Extension List";
    downloadNotifier.downloading = false;
  }

  Future processEntries(DatabaseUpdate dbUpdate, Database db, int limit) async {
    if (dbUpdate.insertLines.length >= limit) {
      await execSQL(db, dbUpdate.insertLines, 'insert');
      dbUpdate.insertLines.clear();
      notifyProcessed('Inserted', dbUpdate.insertCount);
    }

    if (dbUpdate.updateLines.length >= limit) {
      await execSQL(db, dbUpdate.updateLines, 'update');
      dbUpdate.updateLines.clear();
      notifyProcessed('Updated', dbUpdate.updateCount);
    }

    if (dbUpdate.deleteLines.isNotEmpty) {
      await execSQL(db, dbUpdate.deleteLines, 'delete');
      dbUpdate.deleteLines.clear();
      notifyProcessed('Deleted', dbUpdate.deleteCount);
    }
  }

  notifyProcessed(String operation, int counter) {
    downloadNotifier.message = "$operation $counter lines";
  }

  Future<Set<String>> doDeletes(Database db, String sql) async {
    Set<String> newBooks = <String>{};
    RegExp reBookId = RegExp("'.+'");
    sql = sql.toLowerCase();
    List<String> lines = sql.split("\n");
    //StringBuffer sb = StringBuffer("");

    //String deleteSql = sb.toString();
    downloadNotifier.message = "Deleting Records";

    if (lines.isNotEmpty) {
      var batch = db.batch();
      for (String line in lines) {
        if (line.contains("delete")) {
          if (line.contains('delete from books')) {
            final match = reBookId.firstMatch(line)!;
            newBooks.add(match[0]!);
          }
          batch.rawDelete(line);
        }
      }
      await batch.commit();
    }
    return newBooks;
  }

  Future<void> execSQL(Database db, List lines, String operation) async {
    var batch = db.batch();
    for (final line in lines) {
      if (operation == 'insert') {
        batch.rawInsert(line);
      } else if (operation == 'update') {
        batch.rawUpdate(line);
      } else if (operation == 'delete') {
        batch.rawDelete(line);
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> doInserts(Database db, String sql) async {
    sql = sql.toLowerCase();
    List<String> lines = sql.split("\n");
    var batch = db.batch();

    int counter = 0;
    for (String line in lines) {
      if (line.contains("insert")) {
        batch.rawInsert(line);
        counter++;
        if (batchAmount % counter == 1) {
          await batch.commit(noResult: true);
          downloadNotifier.message =
              "inserted $counter of ${lines.length}: ${(counter / lines.length * 100).toStringAsFixed(0)}%";
          batch = db.batch();
        }
      }
    }
    await batch.commit(noResult: true);

    downloadNotifier.message = "Insert Complete";
  }

  Future<void> doUpdates(Database db, String sql) async {
    sql = sql.toLowerCase();
    List<String> lines = sql.split("\n");
    var batch = db.batch();

    int counter = 0;
    for (String line in lines) {
      if (line.contains("update")) {
        batch.rawUpdate(line);
        counter++;
        if (counter % batchAmount == 1) {
          await batch.commit(noResult: true);
          downloadNotifier.message =
              "updated $counter of ${lines.length}: ${(counter / lines.length * 100).toStringAsFixed(0)}%";
          batch = db.batch();
        }
      }
    }
    await batch.commit(noResult: true);

    downloadNotifier.message = "Update Complete";
  }

  Future<void> doFts(Database db, Set<String> newBooks) async {
    // Ensure virtual FTS tables exist
    await db.execute('''CREATE VIRTUAL TABLE IF NOT EXISTS fts_pages USING FTS5(
    id UNINDEXED, 
    bookid UNINDEXED, 
    page UNINDEXED, 
    content, 
    paranum UNINDEXED, 
    sutta_name,
    tokenize = 'porter' 
);''');

    // Drop and recreate fts_translation_pages for clean installation
    await db.execute('DROP TABLE IF EXISTS fts_translation_pages;');
    await db.execute('''CREATE VIRTUAL TABLE fts_translation_pages USING FTS5(
    id UNINDEXED, 
    bookid UNINDEXED, 
    page UNINDEXED, 
    content, 
    paranum UNINDEXED, 
    sutta_name,
    tokenize = 'porter' 
);''');

    int maxWrites = 200;
    var batch = db.batch();
    int counter = 0;

    for (final bookId in newBooks) {
      // 1. SAFEGUARD: Delete old FTS records for this book to prevent ID collisions
      await db.rawDelete("DELETE FROM fts_pages WHERE bookid = ?", [bookId]);
      await db.rawDelete(
          "DELETE FROM fts_translation_pages WHERE bookid = ?", [bookId]);

      // Parameterized query to safely handle IDs like 'vin01m.mul'
      final querySql =
          'SELECT id, bookid, page, content, paranum FROM pages WHERE bookid = ?';

      final maps = await db.rawQuery(querySql, [bookId]);

      for (var element in maps) {
        final rawContent = element['content'] as String;

        // 1. Extract pure Pali content for fts_pages
        final paliText = _extractPaliText(rawContent);
        final paliValue = <String, Object?>{
          'rowid': element['id'] as int,
          'id': element['id'] as int,
          'bookid': element['bookid'] as String,
          'page': element['page'] as int,
          'content': paliText,
          'paranum': element['paranum'] as String,
        };
        batch.insert('fts_pages', paliValue,
            conflictAlgorithm: ConflictAlgorithm.replace);

        // 2. Extract translation content for fts_translation_pages (if present)
        final translationText = _extractTranslationText(rawContent);
        if (translationText.isNotEmpty) {
          final transValue = <String, Object?>{
            'rowid': element['id'] as int,
            'id': element['id'] as int,
            'bookid': element['bookid'] as String,
            'page': element['page'] as int,
            'content': translationText,
            'paranum': element['paranum'] as String,
          };
          batch.insert('fts_translation_pages', transValue,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }

        counter++;

        // Commit every 500 records and yield to event loop for smooth UI rendering
        if (counter % maxWrites == 0) {
          await batch.commit(noResult: true);
          batch = db.batch();
          downloadNotifier.message = "Indexing... $counter FTS pages";
          await Future.delayed(Duration.zero);
        }
      }
    }

    // 2. CRITICAL FIX: The final commit MUST be outside the bookId loop!
    // This catches the remainder of the pages after all books are processed.
    await batch.commit(noResult: true);

    downloadNotifier.message = "FTS is complete";
  }

  String _extractPaliText(String html) {
    if (html.contains('palitext')) {
      final palitextRegex = RegExp(r'<span class="palitext"[^>]*>(.*?)</span>',
          dotAll: true, caseSensitive: false);
      final matches = palitextRegex.allMatches(html);
      final paliParts = matches.map((m) => m.group(1) ?? '').join(' ');
      return _cleanText(paliParts);
    }
    return _cleanText(html);
  }

  String _extractTranslationText(String html) {
    if (html.contains('translation_text')) {
      final translationRegex = RegExp(
          r'<span class="translation_text[^"]*"[^>]*>(.*?)</span>',
          dotAll: true,
          caseSensitive: false);
      final matches = translationRegex.allMatches(html);
      final transParts = matches.map((m) => m.group(1) ?? '').join(' ');
      return _cleanText(transParts);
    }
    return '';
  }

  void showDownloadProgress(received, total) {
    if (total != -1) {
      String percent = (received / total * 100).toStringAsFixed(0);
      downloadNotifier.message = "Downloading: $percent %\n";
    }
  }

  Future<File> downloadFile(String url, String fileName) async {
    var req = await Dio().get(
      url,
      onReceiveProgress: showDownloadProgress,
      options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (status) {
            return status! < 500;
          }),
    );
    if (req.statusCode == 200) {
      var file = File('$_dir/$fileName');
      debugPrint("file.path ${file.path}");
      return file.writeAsBytes(req.data);
    } else {
      throw Exception('Failed to load zip file');
    }
  }

  initDir() async {
    _dir = Prefs.databaseDirPath;
  }

  Future<List<File>> unarchiveAndSave(File zippedFile) async {
    var bytes = zippedFile.readAsBytesSync();
    var archive = ZipDecoder().decodeBytes(bytes);
    List<File> extractedSqlFiles = [];

    for (var file in archive) {
      final outPath = '$_dir/${file.name}';
      if (!file.isFile || outPath.contains('__MACOSX')) continue;

      final outFile = File(outPath);
      await outFile.create(recursive: true);
      await outFile.writeAsBytes(file.content);

      if (outFile.path.endsWith('.sql')) {
        extractedSqlFiles.add(outFile);
      }
    }

    downloadNotifier.message =
        "\nDownloaded ${extractedSqlFiles.length} .sql files.\nPlease wait for further processing";

    return extractedSqlFiles;
  }

  String _cleanText(String text) {
    final regexHtmlTags = RegExp(r'<[^>]*>');
    return text.replaceAll(regexHtmlTags, '');
  }

  Future<void> makeEnglishWordList() async {
    // select * from pages where bookid like "annya_pe%"
    // build Stringbuffer from  bs t1 which is english
    // add unique words to list
    //
    // delete words table which have -1 count
    // insert the words to the word table with count -1
    //  final pageContentRepository =
    //    PageContentDatabaseRepository(DatabaseHelper());
    downloadNotifier.message = "Creating unique wordlist\n";
    Database db = await dbService.database;
    List<String> uniqueWords = [];

    List<String> categories = [
      "annya_pe_vinaya",
      "annya_pe_dn",
      "annya_pe_mn",
      "annya_pe_sn",
      "annya_pe_an",
      "annya_pe_kn"
    ];

    for (String x in categories) {
      downloadNotifier.message += "\nprocesseing wordlist for $x";
      debugPrint(downloadNotifier.message);
      List<Map> list = await db.rawQuery(
          '''SELECT pages.id, pages.bookid, pages.page, pages.content, pages.paranum from pages,books,category 
          WHERE category.id ='$x'
              AND books.category = category.id
              AND books.id = pages.bookid;''');

      var pages = list.map((x) => PageContent.fromJson(x)).toList();
      int lines = 0;

      var englishPagesBuffer = StringBuffer();
      // build massive 17k pages of text into string buffer.
      for (PageContent page in pages) {
        BeautifulSoup bs = BeautifulSoup(page.content);
        List<Bs4Element> englishLines = bs.findAll("p");
        for (Bs4Element bsEnglishLine in englishLines) {
          if (bsEnglishLine.toString().contains("t1")) {
            englishPagesBuffer.write("${bsEnglishLine.text.toLowerCase()} ");
            lines++;
          }
          if (x == "annya_pe_kn") {
            // hack fix for dhpA
            //TODO fix the import file so that it is t1 for english
            englishPagesBuffer.write("${bsEnglishLine.text.toLowerCase()} ");
            lines++;
          }
        }
      }

      String englishPagesString = englishPagesBuffer.toString();

      List<String> words = englishPagesString.split(RegExp(r"[\s—]+"));
      // Iterate through the words and add them to the wordlist with frequency

      for (var word in words) {
        String w = word.trim().toLowerCase().toString();
        w = w.replaceAll(RegExp('[^A-Za-zāīūṃṅñṭṭḍṇḷ-]'), '');
        if (!uniqueWords.contains(w)) {
          uniqueWords.add(w);
        }
      }
    }
    downloadNotifier.message = "Adding word list";

    // now delete all words from the table with -1 count
    await db.rawDelete("Delete from words where frequency = -1");
    var batch = db.batch();
    int counter = 0;
    for (String s in uniqueWords) {
      // keep plain duplicate so works with fuzzy if turned on
      batch.rawInsert(
          '''INSERT INTO words (word, plain, frequency) SELECT '$s','$s', -1  
                          WHERE NOT EXISTS 
                          (SELECT word from words where word ='$s');''');
      counter++;
      if (counter % 100 == 1) {
        await batch.commit();
        batch = db.batch();
        downloadNotifier.message = "$counter of ${uniqueWords.length}";
      }
    }
    await batch.commit();
    downloadNotifier.message = "English word list is complete";
  }

  Future<void> makeEnglishWordList2() async {
    downloadNotifier.message = "Creating unique wordlist";
    final Database db = await dbService.database;
    final uniqueWords = <String>{};

    // 1. DYNAMIC CATEGORY SEARCH
    // Instead of hardcoding, we find all categories that start with 'annya_pe'
    final List<Map<String, dynamic>> categoryMaps =
        await db.rawQuery("SELECT id FROM category WHERE id LIKE 'annya_pe%'");
    final List<String> categories =
        categoryMaps.map((m) => m['id'] as String).toList();

    if (categories.isEmpty) {
      debugPrint("No English categories found to process.");
      return;
    }

    final commas = List.filled(categories.length, '?').join(', ');
    var startId = 0;
    var batchesCount = 0;

    while (true) {
      final QueryCursor cursor = await db.rawQueryCursor('''
      SELECT 
        pages.id, pages.content, books.category as category
      FROM 
        pages
      JOIN 
        books on books.id = pages.bookid
      WHERE 
        pages.id > ? AND
        books.category IN ($commas)
      ORDER BY pages.id ASC
      LIMIT 5000
      ''', [startId, ...categories]);

      final hasFirst = await cursor.moveNext();
      if (!hasFirst) break;
      batchesCount++;

      // REGEX: Matches anything that IS NOT a letter or specific diacritic
      final nonWordChars = RegExp('[^a-zāīūṃṅñṭṭḍṇḷ-]+');
      final wordSplitter = RegExp(r"[\s—]+");

      while (true) {
        final content = cursor.current['content'] as String;
        final category = cursor.current['category'] as String;
        startId = cursor.current['id'] as int;

        // Handle the specific tags used for English text
        final startTag =
            category == 'annya_pe_kn' ? '<p>' : '<span class="t1">';
        final endTag = category == 'annya_pe_kn' ? '</p>' : '</span>';

        var startFrom = 0;
        while (true) {
          final start = content.indexOf(startTag, startFrom);
          if (start == -1) break;

          final end = content.indexOf(endTag, start + startTag.length);
          if (end == -1) break;

          final rawText = content.substring(start + startTag.length, end);
          startFrom = end + endTag.length;

          // 2. IMPROVED CLEANING
          // Clean the text and split into words
          final words = rawText
              .toLowerCase()
              .replaceAll(nonWordChars, ' ') // Replace junk with space
              .split(wordSplitter);

          for (var word in words) {
            final trimmed = word.trim();
            // Only add if it's not empty and isn't just a dash
            if (trimmed.isNotEmpty && trimmed != '-') {
              uniqueWords.add(trimmed);
            }
          }
        }

        final hasNext = await cursor.moveNext();
        if (!hasNext) break;
      }
    }

    // 3. DATABASE UPDATE
    downloadNotifier.message = "Adding ${uniqueWords.length} words";
    await db.rawDelete("DELETE FROM words WHERE frequency = -1");

    var batch = db.batch();
    int counter = 0;
    for (final String word in uniqueWords) {
      batch.rawInsert('''
        INSERT OR IGNORE INTO 
        words (word, plain, frequency) 
        VALUES(?, ?, -1)
        ''', [word, word]);

      counter++;
      if (counter % 500 == 0) {
        await batch.commit(noResult: true);
        batch = db.batch();
        downloadNotifier.message = "$counter of ${uniqueWords.length}";
      }
    }
    await batch.commit(noResult: true);
    downloadNotifier.message = "English word list is complete";
  }

  Future<List<File>> getExtensionFiles() async {
    final directory = Directory(Prefs.databaseDirPath);
    final files = directory.listSync().whereType<File>().toList();
    List<File> extensions = [];

    for (final file in files) {
      if (file.path.endsWith('.sql')) {
        //await processLocalFile(file);
        extensions.add(file);
      }
    }
    return extensions;
  }

  Future<Set<String>> processLocalFile(File downloadedFile) async {
    final dbUpdate = DatabaseUpdate();

    final lineStream = downloadedFile
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    final reBookId = RegExp("'.+'");
    final newBooks = <String>{};

    Database db = await dbService.database;
    await for (final rawLine in lineStream) {
      final line = rawLine.toLowerCase();

      // do these first
      if (line.startsWith("drop")) {
        await db.database.execute(line);
      } else if (line.startsWith("create")) {
        await db.database.execute(line);
      }

      if (line.startsWith("insert")) {
        dbUpdate.insertLines.add(rawLine);
        dbUpdate.insertCount++;
      } else if (line.startsWith("update")) {
        dbUpdate.updateLines.add(rawLine);
        dbUpdate.updateCount++;
      } else if (line.startsWith("delete")) {
        dbUpdate.deleteLines.add(rawLine);
        dbUpdate.deleteCount++;

        if (line.contains('delete from books')) {
          final match = reBookId.firstMatch(rawLine)!;
          // Clean the quotes off the ID before adding it
          newBooks.add(match[0]!.replaceAll("'", ""));
        }
      }
      await processEntries(dbUpdate, db, batchAmount);
    }

    await processEntries(dbUpdate, db, 1);

    // Simply return the books we found back to the main install loop
    return newBooks;
  }

  Future<void> makeUniversalWordList(Set<String> newBooks) async {
    if (newBooks.isEmpty) return;

    downloadNotifier.message = "Creating wordlist (All Words)";
    final Database db = await dbService.database;
    final uniqueWords = <String>{};

    // Regex to strip ALL HTML tags to catch both Pali and English
    final htmlTagRegex = RegExp(r'<[^>]*>');
    // Matches anything that IS NOT a letter or specific diacritic
    final nonWordChars = RegExp('[^a-zāīūṃṅñṭṭḍṇḷ-]+');
    final wordSplitter = RegExp(r"[\s—]+");

    int counter = 0;

    // 1. EXTRACT WORDS ONLY FROM NEW BOOKS
    for (final bookId in newBooks) {
      final querySql = "SELECT content FROM pages WHERE bookid = '$bookId'";
      final maps = await db.rawQuery(querySql);

      for (var element in maps) {
        final content = element['content'] as String;

        // Strip tags completely
        String plainText = content.replaceAll(htmlTagRegex, ' ');

        if (plainText.isNotEmpty) {
          final words = plainText
              .toLowerCase()
              .replaceAll(nonWordChars, ' ') // Replace junk with space
              .split(wordSplitter);

          for (var word in words) {
            final trimmed = word.trim();
            if (trimmed.length >= 2 && trimmed != '-') {
              uniqueWords.add(trimmed);
            }
          }
        }
      }
    }

    debugPrint('Total unique words found: ${uniqueWords.length}');
    downloadNotifier.message = "Saving ${uniqueWords.length} words...";

    // 2. INSERT SAFELY (NO DELETIONS)
    // By using INSERT OR IGNORE, we don't need to delete frequency = -1.
    // This protects words imported from other extension files.
    await db.transaction((txn) async {
      var batch = txn.batch();

      for (final String word in uniqueWords) {
        batch.rawInsert('''
            INSERT OR IGNORE INTO 
            words (word, plain, frequency) 
            VALUES(?, ?, -1)
            ''', [word, word]);

        counter++;
        if (counter % 200 == 0) {
          batch.commit(noResult: true);
          batch = txn.batch();
          downloadNotifier.message =
              "Saved $counter of ${uniqueWords.length} words";
        }
      }
      batch.commit(noResult: true);
    });

    downloadNotifier.message = "Word list complete";
  }

  Future<void> installLocalSqlZip() async {
    await initDir();
    Database db = await dbService.database;
    downloadNotifier.connectionChecking = false;
    downloadNotifier.downloading = true;
    downloadNotifier.totalSteps = 3;
    downloadNotifier.stepsCompleted = 0;
    downloadNotifier.message =
        "\nExtracting local file.. ${downloadListItem.size}\nPlease wait.";

    // 1. Grab the local file using the path we stored in the 'url' property
    final localZipFile = File(downloadListItem.url);

    if (!await localZipFile.exists()) {
      downloadNotifier.message = "Error: Local zip file not found.";
      downloadNotifier.downloading = false;
      return;
    }

    // 2. Unarchive directly without downloading
    final sqlFiles = await unarchiveAndSave(localZipFile);

    downloadNotifier.stepsCompleted = 1;
    // ACCUMULATOR: Keep track of every book added across all files
    final Set<String> allNewBooks = {};

    // --- SPEED BOOST: Turn off foreign key checks during bulk import ---
    await db.execute("PRAGMA foreign_keys = OFF;");

    // 3. IMPORT LOOP
    for (final sqlFile in sqlFiles) {
      downloadNotifier.message = "Importing ${sqlFile.path.split('/').last}...";
      final booksInFile = await processLocalFile(sqlFile);
      allNewBooks.addAll(booksInFile);
    }

    // --- Restore normal database safety rules ---
    await db.execute("PRAGMA foreign_keys = ON;");

    downloadNotifier.stepsCompleted = 2;
    // 4. INDEXING LOOP (Runs only once)
    // Thanks to the JSON mapping, this correctly triggers for ePitaka and other 'books index' types
    if (downloadListItem.type.contains("index") && allNewBooks.isNotEmpty) {
      downloadNotifier.message = 'Building fts';

      await doFts(db, allNewBooks);

      Stopwatch stopwatch = Stopwatch()..start();
      await makeUniversalWordList(allNewBooks);
      debugPrint('Making Word List took ${stopwatch.elapsed}.');
    }

    if (downloadListItem.type.contains("dpd_grammar")) {
      downloadNotifier.message = 'adding dpd grammar flag';
      Prefs.isDpdGrammarOn = true;
    }

    downloadNotifier.stepsCompleted = 3;
    downloadNotifier.message = "Rebuilding Index";
    await dbService.buildBothIndexes();
    downloadNotifier.message = "Local Restore Complete";
    downloadNotifier.downloading = false;
  }

  bool isDbZip(File zipFile) {
    try {
      final bytes = zipFile.readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      return archive.any((f) => f.name.toLowerCase().endsWith('.db'));
    } catch (e) {
      return false;
    }
  }

  File? findLocalZipFile() {
    // 1. Check App Database directory first for zip containing a .db file or testing.db/testingdb/full_en
    try {
      final dbDir = Directory(Prefs.databaseDirPath);
      if (dbDir.existsSync()) {
        final files = dbDir.listSync().whereType<File>().toList();
        for (final f in files) {
          final pathLower = f.path.toLowerCase();
          if (pathLower.endsWith('.zip') &&
              (pathLower.contains('testing') ||
                  pathLower.contains('full_en') ||
                  isDbZip(f))) {
            return f;
          }
        }
      }
    } catch (e) {
      debugPrint('Error searching app DB dir: $e');
    }

    // 2. Try un-sandboxed user home Desktop path
    try {
      final realDesktopDir = Directory('/Users/bhantesubhuti/Desktop/test_db');
      if (realDesktopDir.existsSync()) {
        final files = realDesktopDir.listSync().whereType<File>().toList();
        for (final f in files) {
          final pathLower = f.path.toLowerCase();
          if (pathLower.endsWith('.zip') &&
              (pathLower.contains('testing') ||
                  pathLower.contains('full_en') ||
                  isDbZip(f))) {
            return f;
          }
        }
      }
    } catch (e) {
      debugPrint('Could not read /Users/bhantesubhuti/Desktop/test_db: $e');
    }

    // 3. Fallback check for sandboxed $HOME/Desktop/test_db/
    try {
      final home = Platform.environment['HOME'] ?? '';
      if (home.isNotEmpty) {
        final testDbDir = Directory('$home/Desktop/test_db');
        if (testDbDir.existsSync()) {
          final files = testDbDir.listSync().whereType<File>().toList();
          for (final f in files) {
            final pathLower = f.path.toLowerCase();
            if (pathLower.endsWith('.zip') &&
                (pathLower.contains('testing') ||
                    pathLower.contains('full_en') ||
                    isDbZip(f))) {
              return f;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Could not read sandboxed Desktop dir: $e');
    }

    return null;
  }

  Future<List<File>> unarchiveAndSaveExtractedDbFiles(File zippedFile) async {
    var bytes = zippedFile.readAsBytesSync();
    var archive = ZipDecoder().decodeBytes(bytes);
    List<File> extractedFiles = [];

    for (var file in archive) {
      final outPath = '$_dir/${file.name}';
      if (!file.isFile || outPath.contains('__MACOSX')) continue;

      final outFile = File(outPath);
      await outFile.create(recursive: true);
      await outFile.writeAsBytes(file.content);
      extractedFiles.add(outFile);
    }
    return extractedFiles;
  }

  Future<void> installDbExtensionFromDesktopZip() async {
    await initDir();
    Database db = await dbService.database;
    downloadNotifier.connectionChecking = false;
    downloadNotifier.downloading = true;
    downloadNotifier.totalSteps = 4;
    downloadNotifier.stepsCompleted = 0;

    downloadNotifier.message =
        "Locating DB extension zip in working DB directory...";

    debugPrint(
        'installDbExtensionFromDesktopZip: searching in ${Prefs.databaseDirPath}');
    File? zipFile = findLocalZipFile();
    debugPrint(
        'installDbExtensionFromDesktopZip: findDesktopZipFile returned: ${zipFile?.path}');

    if (zipFile == null || !await zipFile.exists()) {
      if (downloadListItem.url.startsWith('http')) {
        downloadNotifier.message = "Downloading ${downloadListItem.name}...";
        try {
          zipFile = await downloadFile(
              downloadListItem.url, downloadListItem.filename);
        } catch (e) {
          downloadNotifier.message = "Download Failed: $e";
          downloadNotifier.downloading = false;
          return;
        }
      } else {
        downloadNotifier.message =
            "Error: No DB extension zip (testing.db.zip) found in:\n${Prefs.databaseDirPath}";
        downloadNotifier.downloading = false;
        return;
      }
    }

    downloadNotifier.message =
        "Found ${zipFile.path.split('/').last}. Extracting...";

    // 1. Copy desktop zip into app database dir if not already there
    final localZipFile =
        File('${Prefs.databaseDirPath}/${zipFile.path.split('/').last}');
    if (zipFile.path != localZipFile.path) {
      await zipFile.copy(localZipFile.path);
    }

    // 2. Unarchive zip to get extracted .db file
    final extractedFiles = await unarchiveAndSaveExtractedDbFiles(localZipFile);

    File? extractedDbFile;
    for (final f in extractedFiles) {
      if (f.path.endsWith('.db')) {
        extractedDbFile = f;
        break;
      }
    }

    if (extractedDbFile == null || !await extractedDbFile.exists()) {
      downloadNotifier.message =
          "Error: No .db file found inside ${zipFile.path.split('/').last}";
      downloadNotifier.downloading = false;
      return;
    }

    // Step 1 Complete (Downloading & Extracting done -> Move to Step 2: Copying Tables)
    downloadNotifier.stepsCompleted = 1;
    final extPath = extractedDbFile.path;
    downloadNotifier.message = "Attaching & copying tables...";

    await db.execute("ATTACH DATABASE ? AS ext;", [extPath]);

    // Find all new books in ext database
    final bookRows = await db.rawQuery("SELECT id FROM ext.books;");
    final Set<String> allNewBooks =
        bookRows.map((r) => r['id'] as String).toSet();

    downloadNotifier.message =
        "Found ${allNewBooks.length} books. Copying tables...";

    await db.execute("PRAGMA foreign_keys = OFF;");

    // Fetch existing table names in ext
    final extTables = await db
        .rawQuery("SELECT name FROM ext.sqlite_master WHERE type='table';");
    final extTableNames = extTables.map((r) => r['name'] as String).toSet();

    Stopwatch copyStopwatch = Stopwatch()..start();
    await db.transaction((txn) async {
      final targetTables = [
        'books',
        'category',
        'pages',
        'paragraph_mapping',
        'paragraphs',
        'special_books',
        'sutta_page_shortcut',
        'suttas',
        'tocs'
      ];

      for (String table in targetTables) {
        if (extTableNames.contains(table)) {
          downloadNotifier.message = "Copying table '$table'...";
          if (table == 'books') {
            await txn.execute(
                "DELETE FROM main.books WHERE id IN (SELECT id FROM ext.books);");
          } else if (table == 'pages') {
            await txn.execute(
                "DELETE FROM main.pages WHERE bookid IN (SELECT id FROM ext.books);");
          } else if (table == 'tocs' ||
              table == 'suttas' ||
              table == 'sutta_page_shortcut' ||
              table == 'paragraphs') {
            await txn.execute(
                "DELETE FROM main.$table WHERE book_id IN (SELECT id FROM ext.books);");
          } else if (table == 'paragraph_mapping') {
            await txn.execute(
                "DELETE FROM main.paragraph_mapping WHERE base_book_id IN (SELECT id FROM ext.books);");
          }

          // Column matching for safe bulk insert
          final mainColsRes =
              await txn.rawQuery("PRAGMA main.table_info($table);");
          final extColsRes =
              await txn.rawQuery("PRAGMA ext.table_info($table);");

          final mainCols = mainColsRes.map((r) => r['name'] as String).toSet();
          final extCols = extColsRes.map((r) => r['name'] as String).toSet();

          final commonCols = mainCols.intersection(extCols).toList();
          if (commonCols.isNotEmpty) {
            final colList = commonCols.map((c) => '"$c"').join(', ');
            await txn.execute(
                'INSERT OR REPLACE INTO main."$table" ($colList) SELECT $colList FROM ext."$table";');
          }
        }
      }
    });

    debugPrint('ATTACH DB table copy took ${copyStopwatch.elapsed}.');

    await db.execute("PRAGMA foreign_keys = ON;");
    await db.execute("DETACH DATABASE ext;");

    // Delete temp extracted files
    for (final f in extractedFiles) {
      if (await f.exists()) await f.delete();
    }
    if (await localZipFile.exists()) await localZipFile.delete();

    // Step 2 Complete (Tables copied -> Move to Step 3: Indexing FTS Pages)
    downloadNotifier.stepsCompleted = 2;

    if (allNewBooks.isNotEmpty) {
      downloadNotifier.message = 'Building FTS index...';
      await doFts(db, allNewBooks);
    }

    // Step 3 Complete (FTS done -> Move to Step 4: Rebuilding Indexes)
    downloadNotifier.stepsCompleted = 3;

    if (allNewBooks.isNotEmpty) {
      Stopwatch stopwatch = Stopwatch()..start();
      downloadNotifier.message = 'Building word list index...';
      await makeUniversalWordList(allNewBooks);
      debugPrint('Making Word List took ${stopwatch.elapsed}.');
    }

    downloadNotifier.message = "Rebuilding Book Indexes...";
    await dbService.buildBothIndexes();

    // Step 4 Complete (Finished!)
    downloadNotifier.stepsCompleted = 4;
    downloadNotifier.message = "ePitaka DB Extension Import Complete!";
    downloadNotifier.downloading = false;
  }
}
