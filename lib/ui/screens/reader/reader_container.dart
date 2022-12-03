import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabbed_view/tabbed_view.dart';

import '../../../business_logic/models/book.dart';
import '../../../services/provider/script_language_provider.dart';
import '../../../services/provider/theme_change_notifier.dart';
import '../../../utils/pali_script.dart';
import '../../../utils/platform_info.dart';
import '../home/openning_books_provider.dart';
import 'reader.dart';

class ReaderContainer extends StatefulWidget {
  const ReaderContainer({Key? key}) : super(key: key);

  @override
  State<ReaderContainer> createState() => _ReaderContainerState();
}

class TargetIconProvider implements IconProvider {
  TargetIconProvider(this.iconData, this.onTap);

  final Function(int index) onTap;

  @override
  final IconData? iconData;

  @override
  Widget buildIcon(Color color, double size) {
    return DragTarget(
      builder: (
        BuildContext context,
        List<dynamic> accepted,
        List<dynamic> rejected,
      ) {
        return Icon(iconData, color: color, size: size);
      },
      onAccept: (int index) {
        debugPrint('accepted $index');
        onTap(index);
      },
    );
  }

  @override
  IconPath? get iconPath => null;
}

class _ReaderContainerState extends State<ReaderContainer> {
  var tabsVisibility = {};

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Widget readerAt(int i, List<Map<String, dynamic>> books) {
    final current = books[i];
    final book = current['book'] as Book;
    final currentPage = current['current_page'] as int?;
    final textToHighlight = current['text_to_highlight'] as String?;
    var reader = Reader(
      book: book,
      initialPage: currentPage,
      textToHighlight: textToHighlight,
    );
    return reader;
  }

  @override
  Widget build(BuildContext context) {
    // TODO: There are two states, empty state and data state
    // only rebuild when states are not equal.
    // when previous and new state is same,
    // add new books to tabbed view by TabbedViewController
    final openedBookProvider = context.watch<OpenningBooksProvider>();
    final books = openedBookProvider.books;

    final tabs = books.asMap().entries.map((entry) {
      final book = entry.value['book'] as Book;
      final index = entry.key;
      // Newly opened tab always becomes visible and hides the last visible book
      if (index == 0 && !tabsVisibility.containsKey(book.id)) {
        tabsVisibility[book.id] = true;

        if (books.length > 3) {
          for (var i = books.length - 1; i > 1; i--) {
            final revBook = books[i]['book'] as Book;
            if (tabsVisibility.containsKey(revBook.id) &&
                tabsVisibility[revBook.id] == true) {
              tabsVisibility[revBook.id] = false;
              break;
            }
          }
        }
      }
      final isVisible = (tabsVisibility[book.id] ?? false) == true;
      return TabData(
          text: PaliScript.getScriptOf(
              script: context.watch<ScriptLanguageProvider>().currentScript,
              romanText: book.name),
          buttons: [
            TabButton(
                icon: TargetIconProvider(
                    isVisible ? Icons.visibility : Icons.visibility_off,
                    (int sourceIndex) {
                  debugPrint('Will move $sourceIndex to $index');
                  final openedBookProvider =
                  context.read<OpenningBooksProvider>().swap(
                      sourceIndex,
                      index);
                }),
                onPressed: () => {
                      setState(() {
                        tabsVisibility[book.id] = !isVisible;
                      })
                    })
          ],
          keepAlive: false);
    }).toList();

    if (books.isEmpty) {
      return Container(
        color: const Color(0xfffbf0da),
        child: Center(
          child: Text(
            PaliScript.getScriptOf(
              script: context.watch<ScriptLanguageProvider>().currentScript,
              romanText: ('''
Sabbapāpassa akaraṇaṃ
Kusalassa upasampadā
Sacittapa⁠riyodāpanaṃ
Etaṃ buddhānasāsanaṃ
'''),
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              color: Colors.brown,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    // cannot watch two notifiers simultaneity in a single widget
    // so warp in consumer for watching theme change
    return Stack(
      children: [
        Consumer<ThemeChangeNotifier>(
          builder: ((context, themeChangeNotifier, child) {
            // tabbed view uses custom theme and provide TabbedViewTheme.
            // need to watch theme change and rebuild TabbedViewTheme with new one

            return TabbedViewTheme(
              data: themeChangeNotifier.isDarkMode
                  ? TabbedViewThemeData.dark()
                  : TabbedViewThemeData.mobile(
                      accentColor:
                          Theme.of(context).appBarTheme.backgroundColor ??
                              Colors.blue,
                    ),
              // data: TabbedViewThemeData.minimalist(),
              child: TabbedView(
                  controller: TabbedViewController(tabs),
                  contentBuilder: (_, index) {
                    if (Mobile.isPhone(context)) {
                      return readerAt(index, books);
                    } else {
                      return Container();
                    }
                  },
                  onTabClose: (index, tabData) {
                    tabsVisibility.remove(books[index]['book'].id);
                    context.read<OpenningBooksProvider>().remove(index: index);
                  },
                  onTabSelection: (selectedIndex) {
                    if (selectedIndex != null) {
                      context
                          .read<OpenningBooksProvider>()
                          .updateSelectedBookIndex(selectedIndex);
                    }
                  },
                  draggableTabBuilder:
                      (int tabIndex, TabData tab, Widget tabWidget) {
                    return Draggable<int>(
                        feedback: Material(
                            child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(border: Border.all()),
                                child: Text(tab.text))),
                        data: tabIndex,
                        dragAnchorStrategy: (Draggable<Object> draggable,
                            BuildContext context, Offset position) {
                          return Offset.zero;
                        },
                        child: tabWidget);
                  }),
            );
          }),
        ),
        if (!Mobile.isPhone(context)) getColumns(books)
      ],
    );
  }

  Widget getColumns(List<Map<String, dynamic>> books) {
    return Container(
      padding: const EdgeInsets.fromLTRB(1, 30, 1, 1),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: Iterable.generate(books.length)
              .map((i) {
                final isVisible = tabsVisibility[books[i]['book'].id] ?? false;
                if (isVisible) {
                  return Expanded(child: readerAt(i, books));
                } else {
                  return null;
                }
              })
              .where((element) => element != null)
              .cast<Widget>()
              .toList()),
    );
  }
}
