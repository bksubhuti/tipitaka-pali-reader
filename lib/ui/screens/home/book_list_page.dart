import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tipitaka_pali/ui/screens/settings/language_settings.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/repositories/book_repo.dart';
import 'package:tipitaka_pali/services/repositories/category_repo.dart';
import 'package:tipitaka_pali/ui/screens/reader/mobile_reader_container.dart';
import 'package:tipitaka_pali/ui/widgets/pali_text_view.dart';
import 'package:tipitaka_pali/utils/font_utils.dart';

import '../../../business_logic/models/book.dart';
import '../../../business_logic/models/list_item.dart';
import '../../../business_logic/models/sutta.dart';
import '../../../business_logic/view_models/home_page_view_model.dart';
import '../../../routes.dart';
import '../../../services/database/database_helper.dart';
import '../../../services/provider/script_language_provider.dart';
import '../../../services/repositories/sutta_repository.dart';
import '../../../utils/platform_info.dart';
import '../../dialogs/about_tpr_dialog.dart';
import '../../dialogs/sutta_list_dialog.dart';
import '../../widgets/colored_text.dart';
import 'openning_books_provider.dart';
import 'widgets/book_toc_tree.dart';
import '../reader/controller/reader_view_controller.dart';

class BookListPage extends StatefulWidget {
  const BookListPage({super.key});

  @override
  State<BookListPage> createState() => _BookListPageState();
}

class _BookListPageState extends State<BookListPage> {
  /// Tree or cards, as the reader last chose.
  bool _tree = Prefs.bookListAsTree;

  // ---- The tree follows the reader -------------------------------------
  //
  // With a book open, the tree unfolds to it and marks the heading of the
  // page being read, and keeps up as the reading moves on.

  /// Where the reader is: the selected tab's book and page.
  final ValueNotifier<TreeFocus?> _focus = ValueNotifier(null);

  /// The tab's page, to follow as it changes.
  ValueListenable<int>? _pageSource;
  String? _focusBook;
  int? _fallbackPage;
  Timer? _settle;

  /// The books of each tab, read once rather than at every redraw.
  final Map<String, Future<List<CategoryWithBooks>>> _treeData = {};

  /// Each category's fold, so the tree can open the one holding the book.
  final Map<String, ExpansibleController> _folds = {};

  /// The context inside the tabs, to switch to the book's tab.
  BuildContext? _tabsContext;
  OpenningBooksProvider? _books;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _books = context.read<OpenningBooksProvider>()..addListener(_bindFocus);
      _books!.selectionChanges.addListener(_bindFocus);
      _bindFocus();
    });
  }

  @override
  void dispose() {
    _books?.removeListener(_bindFocus);
    _books?.selectionChanges.removeListener(_bindFocus);
    _pageSource?.removeListener(_onPage);
    _settle?.cancel();
    _focus.dispose();
    for (final f in _folds.values) {
      f.dispose();
    }
    super.dispose();
  }

  /// Follows the book in the selected tab, and its page.
  void _bindFocus({bool retried = false}) {
    final books = _books;
    if (!mounted || books == null) return;
    if (books.books.isEmpty) {
      _pageSource?.removeListener(_onPage);
      _pageSource = null;
      _focusBook = null;
      _focus.value = null;
      return;
    }
    final entry =
        books.books[books.selectedBookIndex.clamp(0, books.books.length - 1)];
    final book = entry['book'] as Book;
    final reader = ReaderViewController.open[entry['uuid']];
    ValueListenable<int>? source;
    try {
      source = reader?.currentPage;
      source?.value;
    } catch (_) {
      source = null; // not loaded yet
    }
    if (source == null && !retried) {
      // A book just opened has no reader yet; it is there a moment later.
      Future.delayed(
          const Duration(milliseconds: 300), () => _bindFocus(retried: true));
    }
    if (!identical(source, _pageSource)) {
      _pageSource?.removeListener(_onPage);
      _pageSource = source?..addListener(_onPage);
    }
    final newBook = book.id != _focusBook;
    _focusBook = book.id;
    _fallbackPage = entry['current_page'] as int?;
    if (newBook) _showTabOf(book.id);
    _onPage(now: newBook);
  }

  /// The page has moved. Followed once it pauses, so scrolling through a
  /// book does not set the tree flickering.
  void _onPage({bool now = false}) {
    _settle?.cancel();
    void apply() {
      final book = _focusBook;
      int? page;
      try {
        page = _pageSource?.value;
      } catch (_) {}
      page ??= _fallbackPage;
      _focus.value =
          book == null || page == null ? null : TreeFocus(book, page);
    }

    if (now) {
      apply();
    } else {
      _settle = Timer(const Duration(milliseconds: 500), apply);
    }
  }

  /// Opens the category holding the book, in a tree that is showing.
  Future<void> _onFocus() async {
    final f = _focus.value;
    if (f == null || !_tree) return;
    final data = _treeData[_tabOf(f.bookId)];
    if (data == null) return;
    for (final c in await data) {
      if (c.books.any((b) => b.book.id == f.bookId)) {
        final fold = _folds[c.category.category.id];
        if (fold != null && !fold.isExpanded) fold.expand();
      }
    }
  }

  /// The tab a book is listed under, from its id: mula_…, attha_…, tika_…,
  /// annya_….
  String _tabOf(String bookId) {
    final prefix = bookId.split('_').first;
    return _mainCategories.containsKey(prefix) ? prefix : 'mula';
  }

  void _showTabOf(String bookId) {
    if (!_tree) return;
    final tabs = _tabsContext;
    if (tabs == null || !tabs.mounted) return;
    final index = _mainCategories.keys.toList().indexOf(_tabOf(bookId));
    final controller = DefaultTabController.maybeOf(tabs);
    if (controller != null && index >= 0 && controller.index != index) {
      controller.animateTo(index);
    }
  }

  // key will be use for load book list from database
  // value will be use for TabBar Title

  final Map<String, String> _mainCategories = {
    'mula': 'Pāḷi',
    'attha': 'Aṭṭhakathā',
    'tika': 'Ṭīkā',
    'annya': 'Añña'
  };

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Builder(builder: (context) {
        _tabsContext = context;
        return Scaffold(
          appBar: Mobile.isPhone(context)
              ? AppBar(
                  title:
                      Text(AppLocalizations.of(context)!.tipitaka_pali_reader),
                  actions: [
                    IconButton(
                      padding: const EdgeInsets.all(4.0),
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.settings),
                      onPressed: () async {
                        await Navigator.pushNamed(context, settingRoute);
                      },
                    ),
                  ],
                  bottom: _buildTabBar(context),
                )
              : null,
          // Rydmike proposal: Consider converting the Drawer on this Home screen
          //    to a Widget and then add it also to other top level screens.
          // drawer: Mobile.isPhone(context) ? AppDrawer(context) : null,
          drawer: Mobile.isPhone(context) ? _buildDrawer(context) : null,
          body: Column(
            children: [
              if (!Mobile.isPhone(context))
                Material(
                  color: Theme.of(context).appBarTheme.backgroundColor,
                  child: _buildTabBar(context),
                ),
              // Its own row under the tabs, so the tabs keep their full width.
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                child: _viewToggle(context),
              ),
              Expanded(
                child: TabBarView(
                    children: _mainCategories.entries
                        .map((mainCategory) => _buildBookList(mainCategory.key))
                        .toList()),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () async {
              final sutta = await _openSuttaDialog(context);
              if (sutta != null) {
                final Book book = Book(id: sutta.bookID, name: sutta.bookName);
                final openningBookProvider =
                    context.read<OpenningBooksProvider>();
                openningBookProvider.add(
                  book: book,
                  currentPage: sutta.pageNumber,
                  textToHighlight: sutta.name,
                );
                if (Mobile.isPhone(context)) {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const MobileReaderContainer()));
                }
              }
            },
            child: const PaliTextView("Sutta"),
          ),
        );
      }),
    );
  }

  TabBar _buildTabBar(BuildContext context) {
    final theme = Theme.of(context);
    return TabBar(
      tabs: _mainCategories.entries.map((mainCategory) {
        String text = mainCategory.value;
        // Truncate the text to 5 characters and add '...' if it's longer
        String truncatedText =
            (text.length > 5) ? '${text.substring(0, 5)}..' : text;
        return Tab(child: PaliTextView(truncatedText));
      }).toList(),
      indicator: BoxDecoration(
        color: theme.useMaterial3
            ? theme.focusColor
            : Colors.white.withOpacity(0.1),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(15),
          topRight: Radius.circular(15),
        ),
        // shape: BoxShape()
      ),
      splashBorderRadius: const BorderRadius.only(
        topLeft: Radius.circular(15),
        topRight: Radius.circular(15),
      ),
      labelStyle: TextStyle(
          fontFamily: FontUtils.getfontName(
              script: context.read<ScriptLanguageProvider>().currentScript)),
      unselectedLabelStyle: TextStyle(
          fontFamily: FontUtils.getfontName(
              script: context.read<ScriptLanguageProvider>().currentScript)),
    );
  }

  Drawer _buildDrawer(BuildContext context) {
    return Drawer(
      // Add a ListView to the drawer. This ensures the user can scroll
      // through the options in the drawer if there isn't enough vertical
      // space to fit everything.
      child: ListView(
        // Important: Remove any padding from the ListView.
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: 250,
            child: DrawerHeader(
              duration: Duration(
                milliseconds: Prefs.animationSpeed.round(),
              ),
              decoration: const BoxDecoration(),
              child: Column(
                children: [
                  ColoredText(
                    AppLocalizations.of(context)!.tipitaka_pali_reader,
                  ),
                  const SizedBox(height: 25.0),
                  Image.asset(
                    "assets/icon/icon.png",
                    height: 90,
                    width: 90,
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            title: ColoredText(AppLocalizations.of(context)!.dictionary,
                style: const TextStyle()),
            onTap: () => _openDictionaryPage(context),
          ),
          ListTile(
            title: ColoredText(AppLocalizations.of(context)!.translations,
                style: const TextStyle()),
            onTap: () => _openTranslationsPage(context),
          ),
          ListTile(
            title: ColoredText(AppLocalizations.of(context)!.settings,
                style: const TextStyle()),
            onTap: () => _openSettingPage(context),
          ),
          ListTile(
            title: ColoredText(AppLocalizations.of(context)!.about,
                style: const TextStyle()),
            onTap: () => showAboutTprDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _buildBookList(String mainCategory) {
    return _tree
        ? _buildTree(mainCategory)
        : _buildCondensedBookListWithExpansionTiles(mainCategory);
  }

  /// Cards or tree, as two labelled choices across the row; the one in use
  /// is filled. The choice is kept for the next start.
  Widget _viewToggle(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<bool>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [
          ButtonSegment(
              value: false,
              icon: const Icon(Icons.view_agenda_outlined, size: 18),
              label: Text(l10n.cardView)),
          ButtonSegment(
              value: true,
              icon: const Icon(Icons.account_tree_outlined, size: 18),
              label: Text(l10n.treeView)),
        ],
        selected: {_tree},
        onSelectionChanged: (choice) {
          Prefs.bookListAsTree = choice.first;
          setState(() => _tree = choice.first);
          if (_tree) {
            // Shown now: go to the open book's place in it.
            final book = _focusBook;
            if (book != null) _showTabOf(book);
            WidgetsBinding.instance.addPostFrameCallback((_) => _onFocus());
          }
        },
      ),
    );
  }

  /// The books as a compact tree: a line per category with its arrow on the
  /// left, the books indented under it along a thin guide line, and under
  /// each book its contents. No cards, so far more fits on the screen.
  Widget _buildTree(String mainCategory) {
    return FutureBuilder(
        future: _treeData.putIfAbsent(
            mainCategory, () => _loadSubCategoriesAndBooks(mainCategory)),
        builder: (context, AsyncSnapshot<List<CategoryWithBooks>> snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final guide = Theme.of(context).dividerColor;
          // A fifth smaller than the cards: a tree is for seeing much at once.
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
                textScaler: TextScaler.linear(media.textScaler.scale(1) * 0.8)),
            child: SingleChildScrollView(
              // Built in full, not lazily: the tree must be able to open and
              // scroll to the book being read wherever it is in the list.
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final categoryWithBooks in snapshot.data!)
                    ExpansionTile(
                      controller: _folds.putIfAbsent(
                          categoryWithBooks.category.category.id,
                          ExpansibleController.new),
                      initiallyExpanded: Prefs.expandedBookList ||
                          categoryWithBooks.books
                              .any((b) => b.book.id == _focus.value?.bookId),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      shape: const Border(),
                      collapsedShape: const Border(),
                      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                      title: categoryWithBooks.category.build(context),
                      children: [
                        Container(
                          margin: const EdgeInsets.only(left: 19, bottom: 4),
                          decoration: BoxDecoration(
                              border: Border(left: BorderSide(color: guide))),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final bookItem in categoryWithBooks.books)
                                  BookTocNode(
                                    item: bookItem,
                                    focus: _focus,
                                    open: (book, page, highlight) =>
                                        _openBookAt(
                                            context, book, page, highlight),
                                  ),
                              ]),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
        });
  }

  Widget _buildExpandedBookList(String mainCategory) {
    return FutureBuilder(
        future: _loadBooks(mainCategory),
        builder: (context, AsyncSnapshot<List<ListItem>> snapshot) {
          if (snapshot.hasData) {
            final listItems = snapshot.data!;
            return ListView.separated(
                controller: ScrollController(),
                itemCount: listItems.length,
                itemBuilder: (context, index) => ListTile(
                      title: listItems[index].build(context),
                      onTap: () => _openBook(context, listItems[index]),
                      minVerticalPadding: 4,
                    ),
                separatorBuilder: (context, index) {
                  return Divider(
                    color: Colors.grey.shade400,
                    height: 1,
                    thickness: 0,
                  );
                });
          }
          return const Center(
            child: CircularProgressIndicator(),
          );
        });
  }

  Widget _buildCondensedBookListWithExpansionTiles(String mainCategory) {
    final ScrollController scrollController = ScrollController();
    return FutureBuilder(
        future: _loadSubCategoriesAndBooks(mainCategory),
        builder: (context, AsyncSnapshot<List<CategoryWithBooks>> snapshot) {
          if (snapshot.hasData) {
            final categoriesWithBooks = snapshot.data!;
            return ListView.builder(
              controller: scrollController,
              itemCount: categoriesWithBooks.length,
              itemBuilder: (context, index) {
                final GlobalKey expansionTileKey = GlobalKey();
                final categoryWithBooks = categoriesWithBooks[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: ExpansionTile(
                    key: expansionTileKey, // Assigning key here
                    onExpansionChanged: (isExpanding) {
                      if (isExpanding) {
                        // Delay scrolling a bit to allow for the expansion animation to start.
                        Future.delayed(const Duration(milliseconds: 200))
                            .then((value) {
                          RenderObject? renderObject = expansionTileKey
                              .currentContext
                              ?.findRenderObject();
                          renderObject?.showOnScreen(
                            rect: renderObject.semanticBounds,
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.ease,
                          );
                        });
                      }
                    },
                    initiallyExpanded: Prefs.expandedBookList,
                    title: categoryWithBooks.category.build(context),
                    tilePadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    childrenPadding: const EdgeInsets.only(left: 0, bottom: 8),
                    children: categoryWithBooks.books.map<Widget>((bookItem) {
                      return ListTile(
                        title: bookItem.build(context),
                        onTap: () => _openBook(context, bookItem),
                        minVerticalPadding: 4,
                      );
                    }).toList(),
                  ),
                );
              },
            );
          }
          return const Center(
            child: CircularProgressIndicator(),
          );
        });
  }

  Future<List<ListItem>> _loadBooks(String category) async {
    // await Future.delayed(Duration(seconds: 2));
    return await HomePageViewModel().fecthItems(category);
  }

  _openSettingPage(BuildContext context) async {
    await Navigator.pushNamed(context, settingRoute);
  }

  /// Opens [book] at [page] with [highlight] marked, as the contents panel
  /// does, or at its first page when [page] is null.
  Future<void> _openBookAt(
      BuildContext context, Book book, int? page, String? highlight) async {
    final books = context.read<OpenningBooksProvider>();
    // Already open: go there in its own tab, gliding as the contents panel
    // does. Opening it again reloaded the book and lost the glide.
    if (page != null) {
      final at = books.books.indexWhere((b) =>
          (b['book'] as Book).id == book.id &&
          ReaderViewController.open.containsKey(b['uuid']));
      if (at != -1) {
        final uuid = books.books[at]['uuid'] as String;
        books.updateSelectedBookIndex(at, forceNotify: true);
        if (Mobile.isPhone(context)) {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const MobileReaderContainer()));
        }
        // After the tab has come to the front and its list can move.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ReaderViewController.open[uuid]
              ?.onGoto(pageNumber: page, word: highlight, bookUuid: uuid);
        });
        return;
      }
    }
    final firstPage = page ??
        await BookDatabaseRepository(DatabaseHelper()).getFirstPage(book.id);
    if (!context.mounted) return;
    books.add(
      book: book,
      currentPage: firstPage,
      textToHighlight: highlight,
    );
    if (Mobile.isPhone(context)) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const MobileReaderContainer()));
    }
  }

  _openBook(BuildContext context, ListItem listItem) async {
    if (listItem.runtimeType == BookItem) {
      BookItem bookItem = listItem as BookItem;
      debugPrint('book name: ${bookItem.book.name}');

      final databaseProvider = DatabaseHelper();
      final firstPage = await BookDatabaseRepository(databaseProvider)
          .getFirstPage(bookItem.book.id);
      debugPrint('first page: $firstPage');
      final openningBookProvider = context.read<OpenningBooksProvider>();
      openningBookProvider.add(
        book: bookItem.book,
        currentPage: firstPage,
      );

      if (Mobile.isPhone(context)) {
        // Navigator.pushNamed(context, readerRoute,
        //     arguments: {'book': bookItem.book});
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const MobileReaderContainer()));
      }
    }
  }

  _openDictionaryPage(BuildContext context) {
    Navigator.pushNamed(context, dictionaryRoute);
  }

  /// Translations install as language files now, not as the old English
  /// extension, so the drawer goes to where they are chosen.
  _openTranslationsPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LanguageSettings()),
    );
  }

  Future<Sutta?> _openSuttaDialog(BuildContext context) async {
    const sideSheetWidth = 350.0;
    return showGeneralDialog<Sutta>(
      context: context,
      barrierLabel: 'TOC',
      barrierDismissible: true,
      transitionDuration: const Duration(milliseconds: 150),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position:
              Tween(begin: const Offset(0, 1), end: const Offset(0, 0)).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeIn),
          ),
          child: child,
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        return Padding(
          padding: const EdgeInsets.only(left: 50.0, top: 16.0),
          child: Align(
            alignment: PlatformInfo.isDesktop
                ? Alignment.bottomLeft
                : Alignment.bottomCenter,
            child: SafeArea(
              child: Dialog.fullscreen(
                //shape: const RoundedRectangleBorder(
                //  borderRadius: BorderRadius.all(Radius.circular(16.0))),
                child: Material(
                  type: MaterialType.transparency,
                  child: Container(
                    padding: const EdgeInsets.all(8.0),
                    width: PlatformInfo.isDesktop ? sideSheetWidth : 500,
                    // decoration: BoxDecoration(
                    //     color: Theme.of(context).colorScheme.background,
                    //     borderRadius: const BorderRadius.only(
                    //       topLeft: Radius.circular(16),
                    //       topRight: Radius.circular(16),
                    //     )),
                    child: SuttaListDialog(
                      suttaRepository:
                          SuttaRepositoryDatabase(DatabaseHelper()),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<List<CategoryWithBooks>> _loadSubCategoriesAndBooks(
      String mainCategory) async {
    final databaseProvider = DatabaseHelper();
    List<CategoryWithBooks> categoriesWithBooks = [];

    final subCategories = await CategoryDatabaseRepository(databaseProvider)
        .getCategories(mainCategory);

    for (var subCategory in subCategories) {
      final books = await BookDatabaseRepository(databaseProvider)
          .getBooks(mainCategory, subCategory.id);
      final bookListItems = books.map((book) => BookItem(book)).toList();
      categoriesWithBooks.add(CategoryWithBooks(
          category: CategoryItem(subCategory), books: bookListItems));
    }

    return categoriesWithBooks;
  }
}

class CategoryWithBooks {
  final CategoryItem category;
  final List<BookItem> books;

  CategoryWithBooks({required this.category, required this.books});
}
