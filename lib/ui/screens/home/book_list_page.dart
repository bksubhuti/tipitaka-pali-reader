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
import '../../../business_logic/models/category.dart' as models;
import '../../../business_logic/models/list_item.dart';
import '../../../business_logic/models/sutta.dart';
import '../../../business_logic/view_models/home_page_view_model.dart';
import '../../../routes.dart';
import '../../../services/database/database_helper.dart';
import '../../../services/provider/script_language_provider.dart';
import '../../../services/repositories/sutta_repository.dart';
import '../../../services/repositories/volume_parts.dart';
import '../../../utils/platform_info.dart';
import '../../dialogs/about_tpr_dialog.dart';
import '../../dialogs/sutta_list_dialog.dart';
import '../../widgets/basket_icon.dart';
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
  /// Cards, tree, or the tree by basket, as the reader last chose; see
  /// [Prefs.bookListView].
  String _view = Prefs.bookListView;
  bool get _tree => _view == 'tree';

  /// The basket view and the Mūla view, the two trees without tabs.
  bool get _baskets => _view == 'baskets' || _view == 'layers';

  /// Their books, read once for each.
  final Map<String, Future<List<_Basket>>> _basketTrees = {};
  Future<List<_Basket>>? get _basketData => _basketTrees[_view];

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
  void _bindFocus({int tries = 0}) {
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
    if (source == null && tries < 20) {
      // A book just opened has no reader yet; it is there a moment later.
      // Asked again for up to six seconds, not once: a book that took longer
      // than 300 ms to open, as in a debug run, was never followed at all,
      // and the tree stayed where it was however far the reader went.
      final uuid = entry['uuid'];
      Future.delayed(const Duration(milliseconds: 300), () {
        // Only while that tab is still the one shown.
        final now = _books?.books;
        final at = _books?.selectedBookIndex ?? -1;
        if (now == null || at < 0 || at >= now.length) return;
        if (now[at]['uuid'] != uuid) return;
        _bindFocus(tries: tries + 1);
      });
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
    if (f == null) return;
    if (_baskets) {
      // Each fold on the way to the book: Mūla, its piṭaka, the nikāya. A
      // fold not built yet opens by itself when it is, since it holds the
      // book; see [_buildBasketTree].
      final baskets = _basketData;
      if (baskets == null) return;
      for (final basket in await baskets) {
        for (final key in basket.keysTo(f.bookId)) {
          final fold = _folds[key];
          if (fold != null && !fold.isExpanded) fold.expand();
        }
      }
      return;
    }
    if (!_tree) return;
    final tab = _tabOf(f.bookId);
    final data = _treeData[tab];
    if (data == null) return;
    for (final c in await data) {
      if (c.books.any((b) => b.book.id == f.bookId)) {
        final fold = _folds[_tabFoldKey(tab, c.category.category.id)];
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

  /// The key of a category's fold in the tabbed tree. Each tab has its own:
  /// the tabs share category ids, Majjhima being `ma` in all four, and one
  /// controller shared by two folds tied them together, and to whichever
  /// tab the tree had just switched to while following the reader.
  static String _tabFoldKey(String tab, String category) =>
      'tab:$tab:$category';

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
                  // The view choice on top, then the tabs, which the basket
                  // tree does without.
                  bottom: PreferredSize(
                    preferredSize: Size.fromHeight(
                        _viewToggleHeight + (_baskets ? 0 : kTextTabBarHeight)),
                    child: Column(children: [
                      _viewToggleRow(context),
                      if (!_baskets) _buildTabBar(context),
                    ]),
                  ),
                )
              : null,
          // Rydmike proposal: Consider converting the Drawer on this Home screen
          //    to a Widget and then add it also to other top level screens.
          // drawer: Mobile.isPhone(context) ? AppDrawer(context) : null,
          drawer: Mobile.isPhone(context) ? _buildDrawer(context) : null,
          body: Column(
            children: [
              // The view choice at the very top, in its own row so the tabs
              // under it keep their full width.
              if (!Mobile.isPhone(context)) ...[
                _viewToggleRow(context),
                if (!_baskets)
                  Material(
                    color: Theme.of(context).appBarTheme.backgroundColor,
                    child: _buildTabBar(context),
                  ),
              ],
              Expanded(
                child: _baskets
                    ? _buildBasketTree()
                    : TabBarView(
                        children: _mainCategories.entries
                            .map((mainCategory) =>
                                _buildBookList(mainCategory.key))
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

  static const double _viewToggleHeight = 48;

  Widget _viewToggleRow(BuildContext context) => SizedBox(
        height: _viewToggleHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          child: _viewToggle(context),
        ),
      );

  /// Cards, tree, baskets or Mūla, as four icons across the row, each
  /// named in its tooltip: four labels did not fit the panel. The one in
  /// use is filled. The choice is kept for the next start.
  Widget _viewToggle(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    ButtonSegment<String> segment(String value, Object icon, String name) =>
        ButtonSegment(
            value: value,
            icon: icon is IconData
                ? Icon(icon, size: 20, semanticLabel: name)
                : BasketIcon(size: 20, semanticLabel: name),
            tooltip: name);
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<String>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [
          segment('cards', Icons.view_agenda_outlined, l10n.cardView),
          segment('tree', Icons.account_tree_outlined, l10n.treeView),
          segment('baskets', const BasketIcon(), l10n.basketView),
          segment('layers', Icons.layers_outlined, l10n.mulaView),
        ],
        selected: {_view},
        onSelectionChanged: (choice) {
          Prefs.bookListView = choice.first;
          setState(() => _view = choice.first);
          if (_view != 'cards') {
            // Shown now: go to the open book's place in it.
            final book = _focusBook;
            if (book != null) _showTabOf(book);
            WidgetsBinding.instance.addPostFrameCallback((_) => _onFocus());
          }
        },
      ),
    );
  }

  /// A fold of the tree: its arrow on the left, its rows indented under it
  /// along a thin guide line.
  Widget _fold({
    required String key,
    required Widget title,
    required bool open,
    required List<Widget> children,
  }) {
    return ExpansionTile(
      controller: _folds.putIfAbsent(key, ExpansibleController.new),
      initiallyExpanded: Prefs.expandedBookList || open,
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      visualDensity: VisualDensity.compact,
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      title: title,
      children: [
        Container(
          margin: const EdgeInsets.only(left: 19, bottom: 4),
          decoration: BoxDecoration(
              border: Border(
                  left: BorderSide(color: Theme.of(context).dividerColor))),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children),
        ),
      ],
    );
  }

  /// The basket view or the Mūla view, trees with no tabs; see
  /// [_loadBaskets] for how each is laid out. A basket with one nikāya
  /// lists its books directly.
  Widget _buildBasketTree() {
    return FutureBuilder(
        future: _basketTrees.putIfAbsent(_view, () => _loadBaskets(_view)),
        builder: (context, AsyncSnapshot<List<_Basket>> snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final focusBook = _focus.value?.bookId;
          Widget book(BookItem item) => BookTocNode(
                item: item,
                focus: _focus,
                open: (book, page, highlight) =>
                    _openBookAt(context, book, page, highlight),
              );
          Widget fold(_Basket basket) => _fold(
                key: basket.key,
                title: CategoryItem(models.Category(basket.id, basket.name))
                    .build(context),
                open: focusBook != null && basket.holds(focusBook),
                children: [
                  for (final inner in basket.children) fold(inner),
                  if (basket.children.isEmpty && basket.groups.length == 1)
                    for (final b in basket.groups.single.books) book(b)
                  else
                    for (final group in basket.groups)
                      _fold(
                        key: basket.groupKey(group),
                        title: group.category.build(context),
                        open: group.books.any((b) => b.book.id == focusBook),
                        children: [for (final b in group.books) book(b)],
                      ),
                ],
              );
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
                textScaler: TextScaler.linear(media.textScaler.scale(1) * 0.8)),
            child: SingleChildScrollView(
              // Built in full, as the tree is, to open at the book being read.
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final basket in snapshot.data!) fold(basket)],
              ),
            ),
          );
        });
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
                          _tabFoldKey(mainCategory,
                              categoryWithBooks.category.category.id),
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
                    children: [
                      for (final bookItem in categoryWithBooks.books)
                        ListTile(
                          title: bookItem.build(context),
                          onTap: () => _openBookAt(context, bookItem.book,
                              bookItem.fromPage, null),
                          minVerticalPadding: 4,
                        ),
                    ],
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
    // does. Opening it again reloaded the book and lost the glide. The
    // book's own line, which asks for no page, opens it anew in a tab of its
    // own, so the same book can be open twice.
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
      final bookListItems = await VolumeParts.split(
          books.map((book) => BookItem(book)).toList());
      categoriesWithBooks.add(CategoryWithBooks(
          category: CategoryItem(subCategory), books: bookListItems));
    }

    return categoriesWithBooks;
  }
}

/// One basket of the basket tree: the nikāyas in it, or, for Mūla, the
/// piṭakas.
class _Basket {
  final String id;
  final String name;
  final List<CategoryWithBooks> groups;
  final List<_Basket> children;

  /// Where it sits, as the key of its fold: `basket:mula:sutta`. Apart from
  /// the tabbed tree's folds, whose categories share these ids.
  final String key;

  _Basket(this.id, this.name, this.groups,
      {this.children = const [], String? parent})
      : key = '${parent ?? 'basket'}:$id';

  /// The same, placed inside [parent].
  _Basket inside(_Basket parent) => _within(parent.key);

  _Basket _within(String parentKey) {
    final placed = _Basket(id, name, groups, parent: parentKey);
    return _Basket(id, name, groups,
        children: [for (final c in children) c._within(placed.key)],
        parent: parentKey);
  }

  String groupKey(CategoryWithBooks group) =>
      '$key:${group.category.category.id}';

  bool holds(String bookId) =>
      children.any((c) => c.holds(bookId)) ||
      groups.any((g) => g.books.any((b) => b.book.id == bookId));

  /// The keys of the folds to open, outermost first, to show [bookId].
  List<String> keysTo(String bookId) {
    if (!holds(bookId)) return const [];
    for (final c in children) {
      if (c.holds(bookId)) return [key, ...c.keysTo(bookId)];
    }
    return [
      key,
      for (final g in groups)
        if (g.books.any((b) => b.book.id == bookId)) groupKey(g),
    ];
  }
}

/// The basket a book goes in, from its layer (`books.basket`: mula, attha,
/// tika, annya) and its category. The Pāḷi of the canon by piṭaka; the
/// commentaries, the sub-commentaries and Añña each in a basket of their
/// own, as Añña already was. Any category an extension adds, under Añña.
String _basketOf(String layer, String category) {
  if (category.startsWith('annya') || layer == 'annya') return 'annya';
  if (layer == 'attha') return 'attha';
  if (layer == 'tika') return 'tika';
  return switch (category) {
    'vi' => 'vinaya',
    'di' || 'ma' || 'sa' || 'an' || 'ku' => 'sutta',
    'bi' => 'abhidhamma',
    _ => 'annya',
  };
}

/// The piṭakas, gathered under Mūla in the tree.
const _mulaBaskets = {'vinaya', 'sutta', 'abhidhamma'};

const _basketNames = {
  'vinaya': 'Vinayapiṭaka',
  'sutta': 'Suttantapiṭaka',
  'abhidhamma': 'Abhidhammapiṭaka',
  'attha': 'Aṭṭhakathā',
  'tika': 'Ṭīkā',
  'annya': 'Añña',
};

/// A category's name inside a basket. "suttantapiṭaka (dīghanikāya)" is
/// "dīghanikāya"; Vinaya and Abhidhamma, whose names carry "khuddakanikāya"
/// in the same place, by their piṭaka.
String _groupName(String id, String name) => switch (id) {
      'vi' => 'vinayapiṭaka',
      'bi' => 'abhidhammapiṭaka',
      _ when id.startsWith('annya') => name,
      _ => RegExp(r'\(([^)]+)\)\s*$').firstMatch(name)?[1] ?? name,
    };

/// The layers of a piṭaka in the piṭaka view.
const _layerNames = {'mula': 'Mūla', 'attha': 'Aṭṭhakathā', 'tika': 'Ṭīkā'};

/// Every book, by basket and then by nikāya, in the books' own order.
///
/// For [view] `baskets`, the basket view: each piṭaka holding its own Mūla,
/// Aṭṭhakathā and Ṭīkā, then Añña on its own. For `layers`, the Mūla view:
/// Mūla (holding the three piṭakas), Aṭṭhakathā, Ṭīkā and Añña.
Future<List<_Basket>> _loadBaskets(String view) async {
  final db = await DatabaseHelper().database;
  final categories =
      await db.rawQuery('SELECT id, name FROM category ORDER BY sort_order');
  final books = await db.rawQuery(
      'SELECT id, name, basket, category FROM books ORDER BY sort_order');

  final order = [for (final row in categories) row['id'] as String];
  final names = {
    for (final row in categories)
      row['id'] as String: row['name'] as String? ?? row['id'] as String
  };

  // Each book under a path of baskets, then its category.
  final byPath = <String, Map<String, List<BookItem>>>{};
  for (final row in books) {
    final category = row['category'] as String? ?? '';
    final layer = row['basket'] as String? ?? '';
    final basket = _basketOf(layer, category);
    final String path;
    if (view == 'baskets') {
      // The piṭaka a commentary belongs to is its category's.
      final pitaka = basket == 'annya' ? 'annya' : _basketOf('mula', category);
      path = pitaka == 'annya' || !_layerNames.containsKey(layer)
          ? 'annya'
          : '$pitaka/$layer';
    } else {
      path = basket;
    }
    byPath.putIfAbsent(path, () => {}).putIfAbsent(category, () => []).add(
        BookItem(
            Book(id: row['id'] as String, name: row['name'] as String? ?? '')));
  }
  for (final groups in byPath.values) {
    for (final category in groups.keys.toList()) {
      groups[category] = await VolumeParts.split(groups[category]!);
    }
  }

  // A path's categories, in the categories' order, then any the list does
  // not name, as an extension may leave.
  List<CategoryWithBooks> groupsOf(String path) {
    final groups = byPath[path] ?? const {};
    return [
      for (final category in [
        ...order.where(groups.containsKey),
        ...groups.keys.where((c) => !order.contains(c)),
      ])
        CategoryWithBooks(
            category: CategoryItem(models.Category(
                category, _groupName(category, names[category] ?? category))),
            books: groups[category]!),
    ];
  }

  if (view == 'baskets') {
    _Basket pitaka(String id) {
      final placed = _Basket(id, _basketNames[id]!, const [], parent: 'pitaka');
      return _Basket(id, _basketNames[id]!, const [],
          parent: 'pitaka',
          children: [
            for (final MapEntry(key: layer, value: name) in _layerNames.entries)
              if (byPath.containsKey('$id/$layer'))
                _Basket(layer, name, groupsOf('$id/$layer')).inside(placed)
          ]);
    }

    return [
      for (final id in _mulaBaskets)
        if (_layerNames.keys.any((l) => byPath.containsKey('$id/$l')))
          pitaka(id),
      if (byPath.containsKey('annya'))
        _Basket('annya', _basketNames['annya']!, groupsOf('annya'),
            parent: 'pitaka'),
    ];
  }

  final baskets = [
    for (final id in _basketNames.keys)
      if (byPath.containsKey(id)) _Basket(id, _basketNames[id]!, groupsOf(id))
  ];
  // The three piṭakas' Pāḷi under one Mūla, beside the commentaries.
  final mula = _Basket('mula', 'Mūla', const []);
  final pitakas = baskets.where((b) => _mulaBaskets.contains(b.id)).toList();
  return [
    if (pitakas.isNotEmpty)
      _Basket(mula.id, mula.name, const [],
          children: [for (final p in pitakas) p.inside(mula)]),
    ...baskets.where((b) => !_mulaBaskets.contains(b.id)),
  ];
}

class CategoryWithBooks {
  final CategoryItem category;
  final List<BookItem> books;

  CategoryWithBooks({required this.category, required this.books});
}
