import 'package:flutter/material.dart';
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

class BookListPage extends StatelessWidget {
  BookListPage({super.key});

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
      child: Scaffold(
        appBar: Mobile.isPhone(context)
            ? AppBar(
                title: Text(AppLocalizations.of(context)!.tipitaka_pali_reader),
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
      ),
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
    return _buildCondensedBookListWithExpansionTiles(mainCategory);
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
