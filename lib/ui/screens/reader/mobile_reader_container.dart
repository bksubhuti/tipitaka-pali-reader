import 'dart:math';

import 'package:flutter/material.dart';
import 'package:tipitaka_pali/utils/font_utils.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/ui/screens/reader/reader.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';

import '../../../business_logic/models/book.dart';
import '../../../services/provider/script_language_provider.dart';
import '../../../utils/pali_script.dart';
import '../home/openning_books_provider.dart';
import '../home/dekstop_navigation_bar.dart';
import '../home/navigation_pane.dart';
import '../../../providers/navigation_provider.dart';
import '../home/search_page/search_page.dart';
import '../../widgets/paper_background.dart';
import 'widgets/home_shortcuts.dart';
import 'widgets/quote_of_day.dart';

enum BookViewMode {
  horizontal,
  vertical,
}

class MobileReaderContainer extends StatefulWidget {
  const MobileReaderContainer({super.key});

  static const routeName = '/mobile-reader';

  /// Up and down or side to side, chosen in the reader's text settings.
  static final bookViewMode =
      ValueNotifier(BookViewMode.values[Prefs.bookViewModeIndex]);

  /// The ☰ panel is open.
  static final _panelOpen = ValueNotifier(false);

  static void openPanel() => _panelOpen.value = true;
  static void closePanel() => _panelOpen.value = false;

  /// The welcome screen's tab is chosen, over the open books.
  static final _homeTab = ValueNotifier(false);

  /// The page the reader is on while it is shown: the phone's home screen.
  static Route? _route;

  /// Shows the reader on a phone, after a book has been added to the open
  /// books. When it is already there, the ☰ panel is shut and any page over
  /// it closed to show it, rather than a second reader being put on top.
  /// What the panel had open, such as search results, is kept for the next
  /// time it opens.
  static void show(BuildContext context) {
    _homeTab.value = false;
    final route = _route;
    // The app's own navigator: called from the ☰ panel, the nearest one is
    // the panel's, holding the search results to come back to.
    final navigator = Navigator.of(context, rootNavigator: true);
    if (route != null && route.isActive) {
      navigator.popUntil((r) => r == route);
      closePanel();
      return;
    }
    navigator.push(MaterialPageRoute(
        settings: const RouteSettings(name: routeName),
        builder: (_) => const MobileReaderContainer()));
  }

  @override
  State<MobileReaderContainer> createState() => _MobileReaderContainerState();
}

class _MobileReaderContainerState extends State<MobileReaderContainer> {
  late final PageController pageController;

  @override
  void initState() {
    super.initState();
    // On the selected book, which is not the first when new books open at
    // the end.
    pageController = PageController(
        initialPage: context.read<OpenningBooksProvider>().selectedBookIndex);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    MobileReaderContainer._route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    if (MobileReaderContainer._route == ModalRoute.of(context)) {
      MobileReaderContainer._route = null;
    }
    MobileReaderContainer.closePanel();
    pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final openningBooks = context.watch<OpenningBooksProvider>().books;
    final selectedBookIndex =
        context.watch<OpenningBooksProvider>().selectedBookIndex;
    // A book opened from within the reader, as by a link, is selected in
    // its new tab; the page follows.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (pageController.hasClients &&
          pageController.page?.round() != selectedBookIndex &&
          selectedBookIndex < openningBooks.length) {
        pageController.jumpToPage(selectedBookIndex);
      }
    });

    return ListenableBuilder(
        listenable: Listenable.merge([
          MobileReaderContainer.bookViewMode,
          MobileReaderContainer._homeTab
        ]),
        builder: (context, _) {
          final bookViewMode = MobileReaderContainer.bookViewMode.value;
          // The welcome screen, as a tab of its own before the books; and
          // always, with none open.
          final home =
              MobileReaderContainer._homeTab.value || openningBooks.isEmpty;
          // Held sideways, the screen is short: a lower top bar.
          final barHeight =
              MediaQuery.of(context).orientation == Orientation.landscape
                  ? 40.0
                  : kToolbarHeight;
          return SafeArea(
            top: false,
            bottom: true,
            child: Stack(children: [
              Scaffold(
                appBar: AppBar(
                  toolbarHeight: barHeight,
                  // ☰, and the open books as tabs that slide sideways.
                  leading: IconButton(
                    icon: const Icon(Icons.menu),
                    tooltip:
                        MaterialLocalizations.of(context).openAppDrawerTooltip,
                    onPressed: MobileReaderContainer.openPanel,
                  ),
                  titleSpacing: 0,
                  title: _BookTabStrip(
                    books: openningBooks,
                    height: barHeight,
                    homeSelected: home,
                    onHome: () => MobileReaderContainer._homeTab.value = true,
                    selectedIndex: home ? -1 : selectedBookIndex,
                    onSelected: (index) => _select(context, index),
                    onClosed: (index) => _close(context, index),
                  ),
                ),
                // The books stay open under the welcome screen, each on its
                // page.
                body: IndexedStack(
                  index: home ? 1 : 0,
                  children: [
                    PageView.builder(
                        controller: pageController,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: openningBooks.length,
                        itemBuilder: (context, index) {
                          final openedBook = openningBooks[index];
                          final book = openedBook['book'] as Book;
                          final pageNumber = openedBook['current_page'] as int?;
                          final textToHighlight =
                              openedBook['text_to_highlight'] as String?;
                          final queryMode =
                              openedBook['query_mode'] as QueryMode?;

                          return Reader(
                            key: Key(openedBook['uuid']),
                            book: book,
                            initialPage: pageNumber,
                            textToHighlight: textToHighlight,
                            queryMode: queryMode,
                            bookViewMode: bookViewMode,
                            bookUuid: openedBook['uuid'],
                          );
                        }),
                    const _HomeView(),
                  ],
                ),
              ),
              // Over the whole screen, so a tap beside the panel reaches the
              // dimmed reader behind it and closes the panel.
              const Positioned.fill(child: _NavigationPanel()),
            ]),
          );
        });
  }

  void _select(BuildContext context, int index) {
    MobileReaderContainer._homeTab.value = false;
    context
        .read<OpenningBooksProvider>()
        .updateSelectedBookIndex(index, forceNotify: true);
    pageController.jumpToPage(index);
  }

  /// Closes a book's tab. The one after it is shown, as in a browser; with
  /// the last one closed, the quote of the day.
  void _close(BuildContext context, int index) {
    final openBooks = context.read<OpenningBooksProvider>();
    openBooks.remove(index: index);
    if (openBooks.books.isEmpty) return;
    pageController.jumpToPage(openBooks.selectedBookIndex);
  }
}

/// The open books in a row that slides sideways, as in a browser on a phone.
/// The selected one is filled in and slid into view; each has a cross that
/// closes it.
class _BookTabStrip extends StatefulWidget {
  const _BookTabStrip({
    required this.books,
    required this.height,
    required this.homeSelected,
    required this.onHome,
    required this.selectedIndex,
    required this.onSelected,
    required this.onClosed,
  });

  final List<Map<String, dynamic>> books;
  final double height;
  final bool homeSelected;
  final VoidCallback onHome;

  /// The book whose tab is chosen; -1 for the welcome screen's.
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final ValueChanged<int> onClosed;

  @override
  State<_BookTabStrip> createState() => _BookTabStripState();
}

class _BookTabStripState extends State<_BookTabStrip> {
  final _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _showSelected();
  }

  @override
  void didUpdateWidget(_BookTabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex ||
        oldWidget.homeSelected != widget.homeSelected ||
        oldWidget.books.length != widget.books.length) {
      _showSelected();
    }
  }

  void _showSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tabContext = _selectedKey.currentContext;
      if (tabContext == null) return;
      Scrollable.ensureVisible(tabContext,
          alignment: 0.5,
          duration: Duration(milliseconds: Prefs.animationSpeed.round()));
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final script = context.watch<ScriptLanguageProvider>().currentScript;
    final fontName = FontUtils.getfontName(script: script);
    final closeTooltip = AppLocalizations.of(context)!.close;

    return SizedBox(
      height: widget.height,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            // The welcome screen: a small house, first and never closed.
            Padding(
              key: widget.homeSelected ? _selectedKey : null,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Material(
                color: widget.homeSelected
                    ? colors.primaryContainer
                    : colors.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(5),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: widget.homeSelected ? null : widget.onHome,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    child: SizedBox(
                      // As tall as the books' tabs, with their close buttons.
                      height: 22,
                      child: Icon(Icons.home,
                          size: 14,
                          color: widget.homeSelected
                              ? colors.onPrimaryContainer
                              : null),
                    ),
                  ),
                ),
              ),
            ),
            for (var index = 0; index < widget.books.length; index++)
              Builder(builder: (context) {
                final selected = index == widget.selectedIndex;
                final book = widget.books[index]['book'] as Book;
                final color = selected ? colors.onPrimaryContainer : null;
                return Padding(
                  key: selected ? _selectedKey : null,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Material(
                    color: selected
                        ? colors.primaryContainer
                        : colors.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(5),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: selected ? null : () => widget.onSelected(index),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 7),
                        child: Row(
                          children: [
                            ConstrainedBox(
                              // A long name is cut short, so that a few
                              // tabs still fit across.
                              constraints: const BoxConstraints(maxWidth: 90),
                              child: Text(
                                PaliScript.getScriptOf(
                                    script: script, romanText: book.name),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontFamily: fontName,
                                    fontSize: 9,
                                    color: color,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.normal),
                              ),
                            ),
                            IconButton(
                              tooltip: closeTooltip,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 22, minHeight: 22),
                              iconSize: 11,
                              icon: Icon(Icons.close, color: color),
                              onPressed: () => widget.onClosed(index),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

/// The ☰ panel over the reader: the rail, as on a computer, and beside it
/// the library, Recent, Bookmarks, Search, AI search, the dictionary or the
/// settings. A book chosen in it opens in a new tab, and the panel closes.
///
/// Kept, hidden, while it is closed, as the panel beside the reader is on a
/// computer: a Scaffold's drawer is thrown away when it closes, and the
/// search results in it went with it, so a search had to be made again
/// after every result looked at.
///
/// Opened by ☰ only: a swipe from the edge would be taken from the pages of
/// a book read side to side. Closed by ☰'s logo, the back button, a tap
/// beside it or a swipe to the left.
class _NavigationPanel extends StatefulWidget {
  const _NavigationPanel();

  @override
  State<_NavigationPanel> createState() => _NavigationPanelState();
}

class _NavigationPanelState extends State<_NavigationPanel> {
  static const _duration = Duration(milliseconds: 250);

  /// Shown: open, or sliding shut.
  bool _shown = MobileReaderContainer._panelOpen.value;

  @override
  void initState() {
    super.initState();
    MobileReaderContainer._panelOpen.addListener(_onOpen);
  }

  @override
  void dispose() {
    MobileReaderContainer._panelOpen.removeListener(_onOpen);
    super.dispose();
  }

  void _onOpen() {
    final open = MobileReaderContainer._panelOpen.value;
    if (open) {
      setState(() => _shown = true);
    } else {
      // Whatever was being typed in it is let go.
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = MobileReaderContainer._panelOpen.value;
    return PopScope(
      canPop: !open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) MobileReaderContainer.closePanel();
      },
      child: Offstage(
        offstage: !_shown,
        child: TickerMode(
          enabled: _shown,
          child: Stack(children: [
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !open,
                child: GestureDetector(
                  onTap: MobileReaderContainer.closePanel,
                  child: AnimatedOpacity(
                    opacity: open ? 1 : 0,
                    duration: _duration,
                    child: const ColoredBox(color: Colors.black54),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: AnimatedSlide(
                offset: open ? Offset.zero : const Offset(-1, 0),
                duration: _duration,
                curve: Curves.easeOutCubic,
                onEnd: () {
                  if (!MobileReaderContainer._panelOpen.value && mounted) {
                    setState(() => _shown = false);
                  }
                },
                child: GestureDetector(
                  onHorizontalDragEnd: (details) {
                    if ((details.primaryVelocity ?? 0) < -300) {
                      MobileReaderContainer.closePanel();
                    }
                  },
                  child: Drawer(
                    // Most of the screen upright; held sideways, no wider than
                    // it needs.
                    width: min(MediaQuery.of(context).size.width * 0.9, 480),
                    shape: const RoundedRectangleBorder(),
                    child: SafeArea(
                      child: Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                                border: Border(
                                    right: BorderSide(
                                        color:
                                            Theme.of(context).dividerColor))),
                            // Scrolls on a phone held sideways, too short for
                            // all of it.
                            child: LayoutBuilder(
                              builder: (context, constraints) =>
                                  SingleChildScrollView(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                      minHeight: constraints.maxHeight),
                                  child: const IntrinsicHeight(
                                    child: DeskTopNavigationBar(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const Expanded(
                              child: DetailNavigationPane(navigationCount: 7)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// What the phone shows with no book open: the quote of the day, and under
/// it where the reader last was, as beside the reader on a computer.
class _HomeView extends StatelessWidget {
  const _HomeView();

  @override
  Widget build(BuildContext context) {
    return PaperBackground(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The way in for a new reader: the library, in the ☰
                  // panel. A card like the quote and shortcuts under it.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Card(
                      margin: const EdgeInsets.fromLTRB(4, 16, 4, 12),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          context.read<NavigationProvider>().moveToBookList();
                          MobileReaderContainer.openPanel();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.menu_book,
                                  size: 32,
                                  color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 16),
                              Text(
                                AppLocalizations.of(context)!.openBook,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const QuoteOfDayCard(),
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: HomeShortcuts(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
