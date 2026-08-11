import 'package:tipitaka_pali/ui/screens/home/search_page/search_page.dart';

import '../business_logic/models/search_result.dart';
import '../business_logic/models/search_suggestion.dart';
import 'database/database_helper.dart';
import 'repositories/fts_repo.dart';
import 'repositories/search_suggetion_repo.dart';

class SearchService {
  static Future<List<SearchSuggestion>> getSuggestions(
      String filterWord, bool isFuzzy) async {
    final databaseProvider = DatabaseHelper();
    final SearchSuggestionRepository repository =
        SearchSuggestionDatabaseRepository(databaseProvider);
    final suggestions = await repository.getSuggestions(filterWord, isFuzzy);
    return suggestions;
  }

  static Future<List<SearchResult>> getResultsByFTS(
      String searchWord, QueryMode queryMode, int wordDistance,
      {bool isTranslationSearch = false, bool joinEnglish = true}) async {
    final DatabaseHelper databaseHelper = DatabaseHelper();
    final FtsRespository respository = FtsDatabaseRepository(databaseHelper);
    return await respository.getResults(searchWord, queryMode, wordDistance,
        isTranslationSearch: isTranslationSearch, joinEnglish: joinEnglish);
  }

  ///
  ///
  ///

/*
  static Future<List<Index>> getResults(String searchWord) async {
    List<List<Index>> results = [];
    final DatabaseHelper databaseProvider = DatabaseHelper();
    final IndexRepository repository =
        IndexDatabaseRepository(databaseProvider);
    List<String> queryWords = searchWord.trim().split(' ');
    // final beforeTime = DateTime.now();
    for (String word in queryWords) {
      //print('searching for $word');
      var temp = await repository.getIndexes(word);
      if (temp.isEmpty) {
        return <Index>[];
      }
      results.add(temp);
    }
    //print('load time ${DateTime.now().difference(beforeTime)}');

    if (results.length == 1) {
      // one word case
      //
      await _addBookIdtoIndex(results.first);
      //print(results.first.first.bookID);
      return results.first;
    }

    // multiple words case

    final matches = _getMatch(results);
    await _addBookIdtoIndex(matches);

    return matches;
  }

  static List<Index> _getMatch(List<List<Index>> results) {
    // Comparator<Index> indexComparator = (a, b) => a.page.compareTo(b.page);
    List<Index> matches = <Index>[];
    for (int i = 1, length = results.length; i < length; i++) {
      var current = results[i - 1];
      var next = results[i];
      if (i != 1) {
        current = matches;
      }
      if (current.length < next.length) {
        matches = _findAdjacents(smallList: current, largeList: next);
        // if not found , doesn't need anymore to find for next word
        if (matches.isEmpty) return matches;
      } else {
        matches = _findAdjacents(
            smallList: next, largeList: current, reverseSearchMode: true);
        // if not found , doesn't need anymore to find for next word
        if (matches.isEmpty) return matches;
      }
    }
    return matches;
  }

  static List<Index> _findAdjacents(
      {required List<Index> smallList,
      required List<Index> largeList,
      bool reverseSearchMode = false}) {
    // Comparator<Index> indexComparator = (a, b) => a.pageID.compareTo(b.pageID);
    List<Index> adjacentItems = [];

    for (Index item in smallList) {
      int index = binarySearch<Index>(largeList, item,
          compare: (a, b) => a.pageID.compareTo(b.pageID));
      if (index != -1) {
        int leftMostMatch = _findLeftMostMatch(largeList, index, item.pageID);
        int rightMostMatch = _findRightMostMatch(largeList, index, item.pageID);
        while (leftMostMatch <= rightMostMatch) {
          int position;
          reverseSearchMode
              ? position = largeList[leftMostMatch].position + 1
              : position = largeList[leftMostMatch].position - 1;
          if (position == item.position) {
            adjacentItems.add(item);
          }
          leftMostMatch++;
        }
      }
    }
    return adjacentItems;
  }

  static int _findLeftMostMatch(List<Index> list, int index, int page) {
    int left = index;
    while (left - 1 >= 0 && list[left - 1].pageID == page) {
      left--;
    }

    return left;
  }

  static int _findRightMostMatch(List<Index> list, int index, int page) {
    int right = index;
    int length = list.length;
    while (right + 1 < length && list[right + 1].pageID == page) {
      right++;
    }
    return right;
  }

  static Future<void> _addBookIdtoIndex(List<Index> indexes) async {
    final DatabaseHelper databaseProvider = DatabaseHelper();
    final IndexRepository repository =
        IndexDatabaseRepository(databaseProvider);
    for (Index index in indexes) {
      index.bookID = await repository.getBookId(index.pageID);
    }
  }

  static Future<SearchResult> getDetail(String query, Index index) async {
    final databaseProvider = DatabaseHelper();
    final searchSuggestionRepository =
        SearchResultDatabaseRepository(databaseProvider);
    final pageContent =
        await searchSuggestionRepository.getPageContent(index.pageID);

    final bookRepository = BookDatabaseRepository(databaseProvider);
    final bookName = await bookRepository.getName(pageContent.bookID!);
    final book = Book(id: pageContent.bookID!, name: bookName);

    final description =
        _extractDescription(pageContent.content, query, index.position);

    var result = SearchResult(
        textToHighlight: query,
        description: description,
        book: book,
        pageNumber: pageContent.pageNumber!);

    return result;
  }

  static String _removeAllHtmlTags(String htmlText) {
    RegExp exp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);

    return htmlText.replaceAll(exp, ' ');
  }

  static String _extractDescription(
      String content, String query, int wordPosition) {
    // remmove HTML tag from source
    content = content.replaceAllMapped(
        RegExp(r'</span>(န္တိ|တိ)'), (match) => match.group(1)!);
    // content = content.replaceAll(new RegExp(r'<.*?>'), " ");
    content = _removeAllHtmlTags(content);
    content = content.replaceAll(RegExp(r' +'), ' ');
    // split word
    List<String> wordList = content.trim().split(' ');
    int wordsCount = wordList.length;

    int wordIndex = wordPosition;
    //checking word or phrase
    // String word = query;
    // int len = word.split(" ").length;

    String wordsBeforeQuery = "";
    String wordsAfterQuery = "";

    // get 17 words before query word if available
    int countTofindWords = 12;
    for (int i = countTofindWords; i > 0; i--) {
      if (wordIndex - i >= 0) {
        int ii = 0;
        while (ii < i) {
          wordsBeforeQuery += (wordList[(wordIndex - i) + ii] + " ");
          ii++;
        }
        break;
      }
    }

    //fix some formatting
    wordsBeforeQuery = wordsBeforeQuery.replaceAllMapped(
        "([\u1040-\u1049]+။)\n", (match) => match.group(1)!);

    // get 20 words after query word if available
    for (int i = 20; i >= 0; i--) {
      if (wordIndex + i < wordsCount - 1) {
        int ii = 1;
        while (ii < i) {
          wordsAfterQuery += (" " + wordList[wordIndex + ii]);
          ii++;
        }
        break;
      }
    }

    //fix some formatting
    wordsAfterQuery = wordsAfterQuery.replaceAllMapped(
        "([\u1040-\u1049]+။)\n", (match) => match.group(1)!);

    String description =
        wordsBeforeQuery + wordList[wordIndex] + wordsAfterQuery;

    return description;
  }

  */
}
