import 'package:collection/collection.dart';
import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tipitaka_pali/services/repositories/sentence_paragraph_mapping_repo.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/app.dart';
import 'package:tipitaka_pali/business_logic/view_models/bookmark_page_view_model.dart';
import 'package:tipitaka_pali/services/provider/shown_languages_provider.dart';
import 'package:tipitaka_pali/services/repositories/bookmark_repo.dart';
import 'package:tipitaka_pali/services/tts/tts_service.dart';
import 'package:tipitaka_pali/utils/platform_info.dart';
import 'package:tipitaka_pali/utils/tts_highlight.dart';

import '../../../../business_logic/models/book.dart';
import '../../../../business_logic/models/bookmark.dart';
import '../../../../business_logic/models/found_info.dart';
import '../../../../business_logic/models/found_state.dart';
import '../../../../business_logic/models/page_content.dart';
import '../../../../business_logic/models/page_chunk.dart';
import '../../../../business_logic/models/paragraph_mapping.dart';
import '../../../../business_logic/models/recent.dart';
import '../../../../services/dao/recent_dao.dart';
import '../../../../services/database/database_helper.dart';
import '../../../../services/repositories/book_repo.dart';
import '../../../../services/repositories/page_content_repo.dart';
import '../../../../services/repositories/paragraph_mapping_repo.dart';
import '../../../../services/repositories/paragraph_repo.dart';
import '../../../../services/repositories/recent_repo.dart';
import '../../home/openning_books_provider.dart';
import '../../home/search_page/search_page.dart';

class ReaderViewController extends ChangeNotifier {
  final aiTranslationHtml = ValueNotifier<String?>(null);
  final ValueNotifier<bool> isTranslating = ValueNotifier(false);

  bool _mounted = true;
  bool get mounted => _mounted;

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _shownLanguages?.removeListener(_onShownLanguagesChanged);
    // Closing the book stops it being read, but not from in here. This runs
    // while the tab's widgets are being taken down and the tree is locked;
    // stopping tells the play buttons and the highlight to redraw, which is
    // not allowed then, and closing a tab mid-reading crashed. It stops
    // straight after, in the same frame, unless something else has started
    // reading in the meantime.
    final tts = _tts;
    final closing = bookUuid;
    if (tts != null && tts.bookUuid == closing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (tts.bookUuid == closing) tts.stop();
      });
    }
    super.dispose();
    _mounted = false;
  }

  /// Which translations are composed into the pages. When that changes the
  /// open book composes its pages again, rather than keeping the ones it
  /// opened with until the app restarts.
  ShownLanguagesProvider? _shownLanguages;
  TtsService? _tts;
  int _composedForVersion = 0;

  /// Moves each time the pages are reloaded, for the view to rebuild on.
  int get pagesVersion => _pagesVersion;
  int _pagesVersion = 0;

  void _onShownLanguagesChanged() {
    final version = _shownLanguages?.version ?? 0;
    if (version == _composedForVersion) return; // display mode only
    _composedForVersion = version;
    reloadPages();
  }

  /// Composes the book again with the current languages, keeping the place.
  ///
  /// A translation is added inside the paragraph it belongs to, so the number
  /// of blocks the list scrolls through does not change and the reader stays
  /// where it was.
  Future<void> reloadPages() async {
    if (!isloadingFinished) return;
    final reloaded = List<PageContent>.unmodifiable(await _loadPages(book.id));
    if (!_mounted) return;
    pages = reloaded;
    chunks = _parseChunks(pages);
    numberOfPage = pages.length;
    _pagesVersion++;
    notifyListeners();
  }

  final BuildContext context;
  final PageContentRepository pageContentRepository;
  final BookRepository bookRepository;
  final BookmarkRepository bookmarkRepository;
  final Book book;
  int? initialPage;
  String? textToHighlight;
  QueryMode? queryMode;
  String? selection;

  final ValueNotifier<FoundState> _foundState =
      ValueNotifier<FoundState>(FoundInitial());
  ValueListenable<FoundState> get foundState => _foundState;

  final ValueNotifier<String> _searchText = ValueNotifier('');
  ValueListenable<String> get searchText => _searchText;

  final ValueNotifier<bool> _highlightEveryMatch = ValueNotifier(true);
  ValueListenable<bool> get highlightEveryMatch => _highlightEveryMatch;

  /// Whether the goto/search word highlight is painted in the text.
  /// Tapping a word clears the highlight for the whole book, not only for the
  /// chunk that was tapped.
  final ValueNotifier<bool> _isHighlightShown = ValueNotifier(true);
  ValueListenable<bool> get isHighlightShown => _isHighlightShown;

  /// Removes the goto/search word highlight everywhere in this book.
  void clearHighlights() => _isHighlightShown.value = false;

  /// The sentence the reader last tapped, where reading aloud starts if it
  /// is still on screen.
  ({int page, String sentence})? _tappedSentence;

  /// The blocks of the list currently on screen, first and last, as the view
  /// reports them.
  int firstVisibleChunk = 0;
  int lastVisibleChunk = 0;

  void noteTappedSentence(int page, String? sentence) {
    if (sentence == null) return;
    _tappedSentence = (page: page, sentence: sentence);
  }

  /// The block of the list holding [sentence] on [page], or -1.
  int chunkIndexOfSentence(int page, String sentence) {
    final marker = '<a name="$sentence"></a>';
    final first = getChunkIndexForPage(page);
    if (first < 0) return -1;
    for (var i = first; i < chunks.length && chunks[i].pageNumber == page; i++) {
      if (chunks[i].htmlContent.contains(marker)) return i;
    }
    return -1;
  }

  /// Reads the book aloud from where the reader is.
  ///
  /// Starts at the sentence last tapped if it is on screen, otherwise at the
  /// first sentence of the topmost block showing, and carries on through the
  /// following pages, turning them as it goes. [page] and [sentence] start it
  /// somewhere else instead, as a restart after a change of languages does.
  ///
  /// Returns a message for the reader, or null.
  Future<String?> readAloud(
    TtsService tts, {
    required Set<String> languages,
    required double speed,
    int? page,
    String? sentence,
  }) async {
    if (page == null) {
      final tapped = _tappedSentence;
      final tappedChunk = tapped == null
          ? -1
          : chunkIndexOfSentence(tapped.page, tapped.sentence);
      if (tapped != null &&
          tappedChunk >= firstVisibleChunk &&
          tappedChunk <= lastVisibleChunk) {
        page = tapped.page;
        sentence = tapped.sentence;
      } else if (firstVisibleChunk < chunks.length) {
        final chunk = chunks[firstVisibleChunk];
        page = chunk.pageNumber;
        sentence = TtsHighlight.firstSentence(chunk.htmlContent);
      } else {
        page = _currentPage.value;
      }
    }
    final index = pages.indexWhere((p) => p.pageNumber == page);
    if (index < 0 || pages[index].sentences == null) {
      return 'This page cannot be read aloud.';
    }
    return tts.start(
      bookUuid: bookUuid,
      pages: pages,
      startIndex: index,
      fromSentence: sentence,
      chosen: languages,
      speed: speed,
      onPage: (pageNumber) {
        if (_mounted) gotoPage(pageNumber: pageNumber);
      },
    );
  }

  bool isloadingFinished = false;

  late ValueNotifier<int> _currentPage;
  ValueListenable<int> get currentPage => _currentPage;

  late int? _pageToHighlight;
  int? get pageToHighlight => _pageToHighlight;

  // will be use this for scroll to this
  String? tocHeader;
  late List<PageContent> pages;
  late List<PageChunk> chunks;
  late List<Bookmark> bookmarks;
  late int numberOfPage;

  bool _showSearch = false;

  bool get showSearch => _showSearch;

  String bookUuid;

  // // script features
  // late final bool _isShowAlternatePali;

  ReaderViewController({
    required this.context,
    required this.pageContentRepository,
    required this.bookRepository,
    required this.bookmarkRepository,
    required this.book,
    this.initialPage,
    this.textToHighlight,
    this.queryMode,
    required this.bookUuid,
  }) {
    try {
      _shownLanguages = context.read<ShownLanguagesProvider>();
      _composedForVersion = _shownLanguages!.version;
      _shownLanguages!.addListener(_onShownLanguagesChanged);
      _tts = context.read<TtsService>();
    } catch (_) {
      // Not provided, as in a test of the controller alone.
    }
    if (PlatformInfo.isDesktop) HardwareKeyboard.instance.addHandler(_onKey);
  }

  /// Ctrl+F (Cmd+F on macOS) from anywhere in the app searches the book in
  /// the selected tab.
  ///
  /// It used to be a shortcut on the reader itself, so it only worked once
  /// the reader had been clicked into: with the focus in the dictionary or
  /// the search pane, nothing happened. Nothing else in the app uses it, so
  /// it is taken globally. Every open reader listens; only the selected one
  /// answers.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyF) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    final modifier =
        Platform.isMacOS ? keyboard.isMetaPressed : keyboard.isControlPressed;
    if (!modifier || keyboard.isShiftPressed || keyboard.isAltPressed) {
      return false;
    }
    if (!_mounted || !isloadingFinished) return false;
    try {
      final tabs = context.read<OpenningBooksProvider>();
      final index = tabs.selectedBookIndex;
      if (index < 0 ||
          index >= tabs.books.length ||
          tabs.books[index]['uuid'] != bookUuid) {
        return false;
      }
    } catch (_) {
      return false;
    }
    openSearch();
    return true;
  }

  /// Asks the search box to take the keyboard, when it opens and when it is
  /// already open but the focus is elsewhere.
  ValueListenable<int> get searchFocusRequests => _searchFocusRequests;
  final ValueNotifier<int> _searchFocusRequests = ValueNotifier(0);

  /// Opens find-in-book, keeping what was typed if it is already open, and
  /// puts the cursor in it.
  void openSearch() {
    showSearchWidget(true, searchText: _showSearch ? null : '');
    _searchFocusRequests.value++;
  }

  void onSearchTermChanged(String text) {
    if (text.isEmpty || text.length < 2) {
      _foundState.value = FoundInitial();
      _searchText.value = text;
      _searchResultCount.value = 0;
      _currentSearchResult.value = 0;
      return;
    }

    _searchText.value = text;
    // Match literal text safely while allowing empty anchor tags between words.
    final String regexPattern = RegExp.escape(text)
        .replaceAll(' ', r'(?:\s*<a\s+name="[^"]*"></a>\s*|\s+)');
    final RegExp regex = RegExp(regexPattern, caseSensitive: false);

    int startIndex = 0;
    final List<FoundInfo> results = <FoundInfo>[];
    chunks.forEachIndexed((chunkIndex, chunk) {
      final chunkMatches = regex.allMatches(chunk.htmlContent).length;
      for (int i = 0; i < chunkMatches; i++) {
        results.add(FoundInfo(
          term: text,
          index: startIndex++,
          pageNumber: chunk.pageNumber,
          pageIndex: chunkIndex,
          occurrenceInPage: i + 1,
        ));
      }
    });
    if (results.isEmpty) {
      _foundState.value = FoundEmpty();
      _searchResultCount.value = 0;
      _currentSearchResult.value = 0;
    } else {
      _foundState.value = FoundData(founds: results, current: 0);
      _searchResultCount.value = results.length;
      _currentSearchResult.value = 1;
    }
  }

  void onSearchRequested(String term) {
    debugPrint('on search requested: $term');
    final currentState = _foundState.value;
    if (currentState is FoundEmpty || currentState is FoundInitial) {
      return;
    }
    var current = (currentState as FoundData).current;

    if (current == null) {
      _foundState.value = currentState.copyWith(current: _getNearestIndex());
      return;
    }
  }

  void onClickedNext() {
    final currentState = _foundState.value;
    if (currentState is FoundEmpty || currentState is FoundInitial) {
      return;
    }
    var current = (currentState as FoundData).current;

    if (current == null) {
      _foundState.value = currentState.copyWith(current: _getNearestIndex());
      return;
    }
    if (current == currentState.founds.length - 1) {
      return;
    }

    _foundState.value = currentState.copyWith(current: current + 1);
    _currentSearchResult.value =
        current + 2; // 1-based index for backward compat
  }

  void onClickedPrevious() {
    final currentState = _foundState.value;
    if (currentState is FoundEmpty || currentState is FoundInitial) {
      return;
    }
    var current = (currentState as FoundData).current;

    if (current == null) {
      _foundState.value = currentState.copyWith(current: _getNearestIndex());
      return;
    }
    if (current == 0) {
      return;
    }

    _foundState.value = currentState.copyWith(current: current - 1);
    _currentSearchResult.value = current; // 1-based index for backward compat
  }

  void onClosedSearch() {
    _foundState.value = FoundInitial();
  }

  int _getNearestIndex() {
    final currentState = _foundState.value;
    if (currentState is! FoundData) return 0;

    final totalPages = pages.length;
    int currentPage = _currentPage.value;
    final indexes = currentState.founds;

    if (indexes.length == 1) {
      return 0;
    }

    int index =
        indexes.indexWhere((element) => element.pageNumber == currentPage);
    if (index != -1) {
      return index;
    }

    // current page does not contain term
    for (int i = currentPage; i < totalPages + book.firstPage; i++) {
      index = indexes.indexWhere((element) => element.pageNumber == i);
      if (index != -1) {
        return index;
      }
    }
    for (int i = currentPage; i >= 0 + book.firstPage; i--) {
      index = indexes.indexWhere((element) => element.pageNumber == i);
      if (index != -1) {
        return index;
      }
    }
    return 0;
  }

  @Deprecated('Use onSearchTermChanged instead')
  void search(String text) {
    onSearchTermChanged(text);
  }

  @Deprecated('Use onClickedNext instead')
  void searchDownward() {
    onClickedNext();
  }

  @Deprecated('Use onClickedPrevious instead')
  void searchUpward() {
    onClickedPrevious();
  }

  // Backward compatibility for search_widget.dart
  @Deprecated('Use foundState instead')
  final ValueNotifier<int> _searchResultCount = ValueNotifier(0);
  @Deprecated('Use foundState instead')
  ValueListenable<int> get searchResultCount => _searchResultCount;

  @Deprecated('Use foundState instead')
  final ValueNotifier<int> _currentSearchResult = ValueNotifier(1);
  @Deprecated('Use foundState instead')
  ValueListenable<int> get currentSearchResult => _currentSearchResult;

  void showSearchWidget(bool show, {String? searchText}) {
    _showSearch = show;
    if (searchText != null) {
      onSearchTermChanged(searchText);
    }
    notifyListeners();
  }

  void setHighlightEveryMatch(bool highlight) {
    _highlightEveryMatch.value = highlight;
  }

  Future<void> loadDocument() async {
    pages = List.unmodifiable(await _loadPages(book.id));
    chunks = _parseChunks(pages);
    await _loadBookmarks(book.id);
    numberOfPage = pages.length;
    await _loadBookInfo(book.id);
    isloadingFinished = true;
    _pageToHighlight = initialPage;
    // The list already opens on the right page by itself; this only allows a
    // single fine adjustment onto the highlighted word.
    _armHighlightScroll(textToHighlight != null && textToHighlight!.isNotEmpty);
    myLogger.i('loading finished for: ${book.name}');

    if (!_mounted) {
      return;
    }

    notifyListeners();

    // update opened book list
    final openedBookController = context.read<OpenningBooksProvider>();
    openedBookController.update(
        newPageNumber: _currentPage.value, bookUuid: bookUuid);
    // save to recent table on load of the book.
    // from general book opening and also tapping a search result tile..
    await _saveToRecent();
  }

  Future<List<PageContent>> _loadPages(String bookID) async {
    // Timed because this is what the reader waits on before a book appears,
    // and it is the first thing to look at when opening one feels slow.
    final started = DateTime.now();
    final pages = await pageContentRepository.getPages(bookID);
    myLogger.i('loaded ${pages.length} pages of $bookID in '
        '${DateTime.now().difference(started).inMilliseconds} ms');
    return pages;
  }

  List<PageChunk> _parseChunks(List<PageContent> pagesList) {
    int chunkIndex = 0;
    final List<PageChunk> tempChunks = [];

    for (final page in pagesList) {
      bool isFirst = true;

      // A page that already knows how many blocks it holds does not have to
      // be built to be counted, and is not built until one of its blocks is
      // drawn. Parsing every page of a book took longer than composing them.
      final known = page.blockCount;
      if (known != null) {
        if (known == 0) {
          tempChunks.add(PageChunk(
            pageNumber: page.pageNumber!,
            chunkIndex: chunkIndex++,
            page: page,
            isFirstChunkOfPage: true,
          ));
          continue;
        }
        for (var i = 0; i < known; i++) {
          tempChunks.add(PageChunk(
            pageNumber: page.pageNumber!,
            chunkIndex: chunkIndex++,
            page: page,
            indexInPage: i,
            isFirstChunkOfPage: isFirst,
          ));
          isFirst = false;
        }
        continue;
      }

      // The page-shaped path: the HTML is already in hand, so it is parsed as
      // it always was.
      final soup = BeautifulSoup(page.content);
      final elements = soup.body?.children ?? [];
      if (elements.isEmpty) {
        tempChunks.add(PageChunk(
          pageNumber: page.pageNumber!,
          chunkIndex: chunkIndex++,
          htmlContent: page.content,
          isFirstChunkOfPage: isFirst,
        ));
        continue;
      }

      for (var element in elements) {
        tempChunks.add(PageChunk(
          pageNumber: page.pageNumber!,
          chunkIndex: chunkIndex++,
          htmlContent: element.outerHtml,
          isFirstChunkOfPage: isFirst,
        ));
        isFirst = false;
      }
    }
    return List.unmodifiable(tempChunks);
  }

  Future<void> _loadBookInfo(String bookID) async {
    book.firstPage = await bookRepository.getFirstPage(bookID);
    book.lastPage = await bookRepository.getLastPage(bookID);
    // The range comes from the pages actually loaded where it can. The books
    // table was written for the old pages and is a page short or long for a
    // few books in the sentence data (attha_vi_01_01 ends on 346, not 345;
    // tika_sa_05 has a page 32 before its first, 393). Scrolling onto such a
    // page put the scrollbar outside its own range, and moving it then
    // failed.
    if (pages.isNotEmpty) {
      final numbers = pages.map((page) => page.pageNumber!);
      book.firstPage = numbers.reduce(min);
      book.lastPage = numbers.reduce(max);
    }
    _currentPage = ValueNotifier(initialPage ?? book.firstPage);
    _pageToHighlight = initialPage;
  }

  Future<void> _loadBookmarks(String bookID) async {
    bookmarks = await bookmarkRepository.getBookmarks(bookID: bookID);
    debugPrint('bookmark count: ${bookmarks.length}');
  }

  List<Bookmark> getBookmarks(int pageNumber) {
    return bookmarks
        .where((element) => element.pageNumber == pageNumber)
        .toList();
  }

  Future<int> getFirstParagraph() async {
    final DatabaseHelper databaseProvider = DatabaseHelper();
    final ParagraphRepository repository =
        ParagraphDatabaseRepository(databaseProvider);
    return await repository.getFirstParagraph(book.id);
  }

  Future<int> getLastParagraph() async {
    final DatabaseHelper databaseProvider = DatabaseHelper();
    final ParagraphRepository repository =
        ParagraphDatabaseRepository(databaseProvider);
    return await repository.getLastParagraph(book.id);
  }

  Future<List<ParagraphMapping>> getParagraphs(int currentPage) async {
    final DatabaseHelper databaseProvider = DatabaseHelper();
    final ParagraphMappingRepository repository =
        DatabaseHelper.sentenceDataAvailable
            ? SentenceParagraphMappingRepository(databaseProvider)
            : ParagraphMappingDatabaseRepository(databaseProvider);

    return await repository.getParagraphMappings(book.id, currentPage);
  }

  Future<List<ParagraphMapping>> getBackWardParagraphs(int currentPage) async {
    final DatabaseHelper databaseProvider = DatabaseHelper();
    final ParagraphMappingRepository repository =
        DatabaseHelper.sentenceDataAvailable
            ? SentenceParagraphMappingRepository(databaseProvider)
            : ParagraphMappingDatabaseRepository(databaseProvider);

    return await repository.getBackWardParagraphMappings(book.id, currentPage);
  }

  Future<int> getPageNumber(int paragraphNumber) async {
    final DatabaseHelper databaseProvider = DatabaseHelper();
    final ParagraphRepository repository =
        ParagraphDatabaseRepository(databaseProvider);
    return await repository.getPageNumber(book.id, paragraphNumber);
  }

  String getCaller(StackTrace currentStack) {
    // Use like so *in* the function you want to find the caller of
    // String caller = getCaller(StackTrace.current);
    // debugPrint("Caller: $caller");
    var stack = currentStack.toString();
    var newLineNum = stack.indexOf("\n", 0);
    var secondLine = stack.substring(newLineNum + 9, newLineNum + 100);
    var endIndex = secondLine.indexOf(" ", 0);
    return secondLine.substring(0, endIndex);
  }

  void gotoPage({required int pageNumber}) {
    if (_currentPage.value == pageNumber) {
      // The page number is unchanged, so no listener will run. Drop any
      // pending permission here, otherwise the next page change - which would
      // come from plain scrolling - would inherit it and move the view.
      _pendingNavigation = false;
    }
    _currentPage.value = pageNumber;
    final openedBookController = context.read<OpenningBooksProvider>();
    openedBookController.update(
        newPageNumber: _currentPage.value, bookUuid: bookUuid);
  }

  int getChunkIndexForPage(int pageNumber) {
    int index = chunks.indexWhere((chunk) => chunk.pageNumber == pageNumber);
    if (index != -1) return index;
    // Some books skip page numbers. Going to a missing one, as the scrollbar
    // does while it is dragged, lands on the next page there is rather than
    // back at the start of the book.
    index = chunks.indexWhere((chunk) => chunk.pageNumber > pageNumber);
    if (index != -1) return index;
    return chunks.isEmpty ? 0 : chunks.length - 1;
  }

  int getPageNumberForChunk(int chunkIndex) {
    if (chunkIndex < 0 || chunkIndex >= chunks.length) {
      return book.firstPage!;
    }
    return chunks[chunkIndex].pageNumber;
  }

  /// A page change has two very different origins: an explicit navigation
  /// (goto page, table of contents, search result, slider, opening a book) and
  /// ordinary scrolling, which only reports which page has come into view.
  /// Only the first kind may move the scroll position, otherwise the text
  /// snaps back under the reader's finger while they are scrolling.
  bool _pendingNavigation = false;

  /// Takes the pending navigation. Returns true only once per request.
  bool takePendingNavigation() {
    if (!_pendingNavigation) return false;
    _pendingNavigation = false;
    return true;
  }

  /// One-shot permission to scroll to the highlighted word.
  /// A page is rendered as many chunk widgets and each of them is built afresh
  /// every time it scrolls back into view. Without this ticket every rebuilt
  /// chunk would pull the list towards its own highlight, so a page with
  /// several matches kept dragging the view back to the last one.
  bool _pendingHighlightScroll = false;
  DateTime? _highlightScrollArmedAt;

  /// How long a highlight scroll stays on offer. Long enough for the page to
  /// finish laying out, short enough that a chunk first built much later -
  /// while the reader is scrolling - can no longer move the view.
  static const Duration _highlightScrollLifetime = Duration(seconds: 2);

  void _armHighlightScroll(bool arm) {
    _pendingHighlightScroll = arm;
    _highlightScrollArmedAt = arm ? DateTime.now() : null;
  }

  /// Takes the pending highlight scroll. Returns true only once per request,
  /// and only while the request is still fresh.
  bool takePendingHighlightScroll() {
    if (!_pendingHighlightScroll) return false;
    final armedAt = _highlightScrollArmedAt;
    _armHighlightScroll(false);
    return armedAt != null &&
        DateTime.now().difference(armedAt) <= _highlightScrollLifetime;
  }

  Future<void> onGoto(
      {required int pageNumber,
      String? word,
      bool saveToRecent = true,
      String? bookUuid}) async {
    myLogger.i('current page number: $pageNumber');
    String caller = getCaller(StackTrace.current);
    debugPrint("Caller: $caller, pageNumber: $pageNumber, word: $word");
    _pageToHighlight = pageNumber;
    textToHighlight = word;
    // This page change was asked for, so it is allowed to move the view.
    _pendingNavigation = true;
    _armHighlightScroll(word != null && word.isNotEmpty);
    // A new destination restores highlights that a word tap had cleared.
    _isHighlightShown.value = true;
    // update current page
    gotoPage(pageNumber: pageNumber);
    // persit
    if (saveToRecent) {
      await _saveToRecent();
    }
  }

  // Future onPageChanged(int index) async {
  //   _currentPage.value = book.firstPage! + index;
  //   // notifyListeners();

  //   final openedBookController = context.read<OpenedBooksProvider>();
  //   openedBookController.update(newPageNumber: _currentPage.value);
  //   await _saveToRecent();
  // }

  // Future gotoPage(double value) async {
  //   _currentPage.value = value.toInt();
  //   final index = _currentPage.value - book.firstPage!;
  //   // pageController?.jumpToPage(index);
  //   // itemScrollController?.jumpTo(index: index);

  //   final openedBookController = context.read<OpenedBooksProvider>();
  //   openedBookController.update(newPageNumber: _currentPage.value);

  //   //await _saveToRecent();
  // }

  // Future gotoPageAndScroll(double value, String tocText) async {
  //   _currentPage = value.toInt();
  //   tocHeader = tocText;
  //   final index = _currentPage! - book.firstPage!;
  //   // pageController?.jumpToPage(index);
  //   // itemScrollController?.jumpTo(index: _currentPage! - book.firstPage!);
  //   //await _saveToRecent();
  // }

  void saveToBookmark(String note, String selectedText) async {
    BookmarkDatabaseRepository repository =
        BookmarkDatabaseRepository(DatabaseHelper());
    BookDatabaseRepository bookRepository =
        BookDatabaseRepository(DatabaseHelper());
    String name = await bookRepository.getName(book.id);

    repository.insert(Bookmark(
      bookID: book.id,
      pageNumber: _currentPage.value,
      note: note,
      name: name,
      selectedText: selectedText,
    ));
    if (context.mounted) {
      context.read<BookmarkPageViewModel>().refreshBookmarks();
    }
  }

  Future _saveToRecent() async {
    final RecentRepository recentRepository =
        RecentDatabaseRepository(DatabaseHelper(), RecentDao());
    recentRepository.insertOrReplace(Recent(book.id, _currentPage.value));
  }
}

class SearchIndex {
  int page;
  int index;
  SearchIndex(this.page, this.index);
}
