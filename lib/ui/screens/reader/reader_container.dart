import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:ms_material_color/ms_material_color.dart';
import 'package:provider/provider.dart';
import 'package:tabbed_view/tabbed_view.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:tipitaka_pali/ui/screens/settings/download_view.dart';
import 'package:tipitaka_pali/ui/screens/reader/mobile_reader_container.dart';
import 'package:tipitaka_pali/utils/font_utils.dart';

import '../../../business_logic/models/book.dart';
import '../../../data/flex_theme_data.dart';
import '../../../services/provider/script_language_provider.dart';
import '../../../services/provider/theme_change_notifier.dart';
import '../../../utils/pali_script.dart';
import '../../../utils/platform_info.dart';
import '../home/openning_books_provider.dart';
import '../home/search_page/search_page.dart';
import 'reader.dart';
import 'package:tipitaka_pali/services/prefs.dart';

class ReaderContainer extends StatefulWidget {
  const ReaderContainer({super.key});

  @override
  State<ReaderContainer> createState() => _ReaderContainerState();
}

class _ReaderContainerState extends State<ReaderContainer> {
  final Map<String, bool> tabsVisibility = {};
  TabbedViewController? _tabController;
  final Map<String, TabData> _tabDataCache = {};

  Future<bool> _hasTranslationExtension() async {
    final hasEnglish =
        await File('${Prefs.databaseDirPath}/full_english.sql').exists();
    final hasVietnamese =
        await File('${Prefs.databaseDirPath}/full_vietnamese.sql').exists();
    return hasEnglish || hasVietnamese;
  }

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
    final queryMode = current['query_mode'] as QueryMode?;

    var reader = Reader(
      book: book,
      initialPage: currentPage,
      textToHighlight: textToHighlight,
      queryMode: queryMode,
      bookViewMode: BookViewMode.horizontal, // horizontal for desktop
      bookUuid: current['uuid'],
    );
    return reader;
  }

  @override
  Widget build(BuildContext context) {
    final multiWindowMode = Prefs.multiTabMode &&
        (PlatformInfo.isDesktop || Mobile.isTablet(context));

    // TODO: There are two states, empty state and data state
    // only rebuild when states are not equal.
    // when previous and new state is same,
    // add new books to tabbed view by TabbedViewController
    final openedBookProvider = context.watch<OpenningBooksProvider>();
    final books = openedBookProvider.books;

    books.asMap().forEach((index, entry) {
      final uuid = entry['uuid'];
      // Newly opened tab always becomes visible and hides the last visible book
      final isActiveTab =
          Prefs.isNewTabAtEnd ? index == books.length - 1 : index == 0;

      if (isActiveTab && !tabsVisibility.containsKey(uuid)) {
        tabsVisibility[uuid] = true;

        if (books.length > Prefs.tabsVisible) {
          final booksArr =
              Prefs.isNewTabAtEnd ? books.reversed.toList() : books;
          for (var i = books.length - 1; i > 1; i--) {
            final revUuid = booksArr[i]['uuid'];
            if (tabsVisibility.containsKey(revUuid) &&
                tabsVisibility[revUuid] == true) {
              tabsVisibility[revUuid] = false;
              break;
            }
          }
        }
      }
    });

    final tabs = books.asMap().entries.map((entry) {
      final index = entry.key;
      final book = entry.value['book'] as Book;
      final uuid = entry.value['uuid'];

      final isVisible = (tabsVisibility[uuid] ?? false) == true;
      final titleText = PaliScript.getScriptOf(
          script: context.watch<ScriptLanguageProvider>().currentScript,
          romanText: book.name);

      if (_tabDataCache.containsKey(uuid)) {
        final existingTab = _tabDataCache[uuid]!;
        existingTab.text = titleText;
        existingTab.content =
            multiWindowMode ? Container() : readerAt(index, books);
        existingTab.buttons = [
          if (multiWindowMode)
            TabButton(
                icon: IconProvider.data(
                    isVisible ? Icons.visibility : Icons.visibility_off),
                onPressed: () => {
                      setState(() {
                        tabsVisibility[uuid] = !isVisible;
                      })
                    }),
        ];
        return existingTab;
      }

      final newTab = TabData(
          text: titleText,
          content: multiWindowMode ? Container() : readerAt(index, books),
          buttons: [
            if (multiWindowMode)
              TabButton(
                  icon: IconProvider.data(
                      isVisible ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => {
                        setState(() {
                          tabsVisibility[uuid] = !isVisible;
                        })
                      }),
          ],
          keepAlive: true);
      _tabDataCache[uuid] = newTab;
      return newTab;
    }).toList();

    if (books.isEmpty) {
      final script = context.watch<ScriptLanguageProvider>().currentScript;
      final fontName = FontUtils.getfontName(script: script);

      final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

      return Container(
        color: Prefs.getChosenColor(context),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                PaliScript.getScriptOf(
                    script:
                        context.watch<ScriptLanguageProvider>().currentScript,
                    romanText:
                        "Sabbapāpassa akaraṇaṃ\nKusalassa upasampadā\nSacittapariyodāpanaṃ\nEtaṃ buddhānasāsanaṃ"),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontFamily: fontName,
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              FutureBuilder<bool>(
                future: _hasTranslationExtension(),
                builder: (context, snapshot) {
                  if (snapshot.hasData && !snapshot.data! && !Prefs.hideTranslationNag) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 24.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.g_translate),
                            label: Text(AppLocalizations.of(context)!
                                .installEnglishTranslations),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (BuildContext dialogContext) {
                                  return AlertDialog(
                                    title: Text(AppLocalizations.of(context)!
                                        .installEnglishTranslations),
                                    content: Text(AppLocalizations.of(context)!
                                        .installTranslationInstructions),
                                    actions: [
                                      TextButton(
                                        onPressed: () {
                                          Navigator.of(dialogContext).pop();
                                          Navigator.of(context)
                                              .push(
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  const DownloadView(),
                                            ),
                                          )
                                              .then((_) {
                                            if (mounted) {
                                              setState(() {});
                                            }
                                          });
                                        },
                                        child:
                                            Text(AppLocalizations.of(context)!.ok),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Dismiss',
                            onPressed: () {
                              setState(() {
                                Prefs.hideTranslationNag = true;
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              if (Prefs.geminiDirectApiKey.isEmpty && !Prefs.hideAiSearchNag)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.video_library),
                        label:
                            Text(AppLocalizations.of(context)!.learnAboutAiSearch),
                        onPressed: () {
                          launchUrl(
                            Uri.parse(
                                'https://www.youtube.com/watch?v=tJXhPFZO6Xs'),
                            mode: LaunchMode.externalApplication,
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Dismiss',
                        onPressed: () {
                          setState(() {
                            Prefs.hideAiSearchNag = true;
                          });
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final isOrange2 = Prefs.themeName == MyThemes.orange2Name;

    final primaryColor = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surfaceTint;
    final materialColor = MsMaterialColor(primaryColor.value);
    final TabbedViewThemeData themeData =
        TabbedViewThemeData.minimalist(colorSet: materialColor);
    Radius radius = const Radius.circular(8.0);
    BorderRadiusGeometry? borderRadius =
        BorderRadius.only(topLeft: radius, topRight: radius);
    themeData.tabsArea
      ..border = const Border(bottom: BorderSide(color: Colors.grey))
      ..initialGap = 0
      ..buttonsAreaDecoration = null
      ..hoverButtonBackground =
          BoxDecoration(color: primaryColor.withValues(alpha: 0.2))
      ..normalButtonColor = Theme.of(context).colorScheme.onSurface
      ..hoverButtonColor = primaryColor;

    themeData.tab
      ..margin = const EdgeInsets.only(top: 2)
      ..textStyle = TextStyle(color: Theme.of(context).colorScheme.onBackground)
      ..padding = const EdgeInsets.fromLTRB(10, 4, 4, 4)
      ..buttonsOffset = 18
      ..normalButtonColor = Theme.of(context).colorScheme.onSurface
      ..hoverButtonColor = primaryColor
      ..decoration = BoxDecoration(
          shape: BoxShape.rectangle,
          color: Theme.of(context).colorScheme.background,
          border: Border.all(color: Colors.grey),
          borderRadius: borderRadius)
      ..selectedStatus.normalButtonColor = primaryColor
      ..selectedStatus.decoration = BoxDecoration(
          shape: BoxShape.rectangle,
          color: primaryColor.withValues(alpha: 0.6),
          border: Border.all(color: Colors.transparent),
          borderRadius: borderRadius)
      ..highlightedStatus.decoration = BoxDecoration(
          color: surface.withValues(alpha: 0.3),
          border: Border.all(color: Colors.transparent),
          borderRadius: borderRadius);

    if (!Prefs.darkThemeOn) {
      themeData.tabsArea
        ..border = null
        ..color = const Color(0xFFf4f4f4)
        ..middleGap = isOrange2 ? 3 : 0
        ..initialGap = isOrange2 ? 5 : 0
        ..gapBottomBorder = const BorderSide(color: Colors.grey);

      themeData.tab
        ..margin = EdgeInsets.zero
        ..padding = const EdgeInsets.fromLTRB(8, 4, 8, 4)
        ..buttonsOffset = 4
        ..disabledButtonColor = Colors.grey
        ..normalButtonColor = Theme.of(context).colorScheme.onSurface
        ..hoverButtonColor = primaryColor
        ..decoration = const BoxDecoration(
            shape: BoxShape.rectangle,
            border: Border(
              left: BorderSide(color: Colors.transparent),
              right: BorderSide(color: Colors.transparent),
              top: BorderSide(color: Colors.transparent),
              bottom: BorderSide(color: Colors.grey),
            ))
        ..selectedStatus.normalButtonColor = primaryColor
        ..selectedStatus.decoration = BoxDecoration(
          shape: BoxShape.rectangle,
          color: Prefs.getChosenColor(context),
          border: const Border(
            left: BorderSide(color: Colors.grey),
            right: BorderSide(color: Colors.grey),
            top: BorderSide(color: Colors.grey),
            bottom: BorderSide(color: Colors.transparent),
          ),
        )
        ..selectedStatus.fontColor = primaryColor
        ..highlightedStatus.decoration = const BoxDecoration(
          color: Color(0xFFdadada),
          border: Border(
            left: BorderSide(color: Colors.transparent),
            right: BorderSide(color: Colors.transparent),
            top: BorderSide(color: Colors.transparent),
            bottom: BorderSide(color: Colors.grey),
          ),
        );

      themeData.contentArea.decoration = const BoxDecoration(
          shape: BoxShape.rectangle,
          border: Border(
              left: BorderSide(color: Colors.grey),
              bottom: BorderSide(color: Colors.transparent),
              right: BorderSide(color: Colors.transparent),
              top: BorderSide(color: Colors.transparent)));
    }

    // cannot watch two notifiers simultaneity in a single widget
    // so warp in consumer for watching theme change
    final tabsArea = getTabArea(themeData, multiWindowMode, tabs, books);
    if (multiWindowMode) {
      return Stack(
        children: [tabsArea, getColumns(books)],
      );
    } else {
      return tabsArea;
    }
  }

  void _closeAllTabs() {
    setState(() {
      tabsVisibility.clear();
      _tabDataCache.clear();
    });
    context.read<OpenningBooksProvider>().removeAll();
  }

  closeTab(int tabIndex, TabbedViewController controller) {
    int toSelect = 0;
    int selected = controller.selectedIndex ?? 0;

    if (tabIndex <= selected) {
      toSelect =
          min(controller.tabs.length - 2, (controller.selectedIndex ?? 1));
    } else {
      toSelect = selected;
    }

    if (!Prefs.isNewTabAtEnd) {
      toSelect = 0;
    }

    controller.removeTab(tabIndex, selectedIndex: toSelect);

    final openedBookProvider = context.read<OpenningBooksProvider>();
    final books = openedBookProvider.books;
    if (tabIndex < books.length) {
      final uuid = books[tabIndex]['uuid'];
      tabsVisibility.remove(uuid);
      _tabDataCache.remove(uuid);
    }

    openedBookProvider.remove(index: tabIndex);
  }

  Widget getTabArea(themeData, multiWindowMode, tabs, books) {
    if (_tabController == null) {
      _tabController = TabbedViewController(tabs);
    } else {
      _tabController!.setTabs(tabs);
    }
    _tabController!.selectedIndex =
        context.read<OpenningBooksProvider>().selectedBookIndex;
    return Consumer<ThemeChangeNotifier>(
      builder: ((context, themeChangeNotifier, child) {
        // tabbed view uses custom theme and provide TabbedViewTheme.
        // need to watch theme change and rebuild TabbedViewTheme with new one

        return TabbedViewTheme(
          data: themeData,
          child: TabbedView(
              selectToEnableButtons: false,
              controller: _tabController!,
              tabsAreaButtonsBuilder: (context, tabsCount) {
                if (tabsCount == 0) return [];
                return [
                  TabButton(
                    icon: IconProvider.data(Icons.delete_sweep),
                    iconSize: 22.0,
                    color: Theme.of(context).colorScheme.onSurface,
                    hoverColor: Theme.of(context).colorScheme.primary,
                    toolTip: AppLocalizations.of(context)!.closeAll,
                    onPressed: _closeAllTabs,
                  ),
                ];
              },
              onTabSelection: (selectedIndex) {
                if (selectedIndex != null) {
                  context
                      .read<OpenningBooksProvider>()
                      .updateSelectedBookIndex(selectedIndex);
                }
              },
              tabCloseInterceptor: (int tabIndex) {
                closeTab(tabIndex, _tabController!);
                return false;
              },
              draggableTabBuilder:
                  (int tabIndex, TabData tab, Widget tabWidget) {
                // tabWidget actually is a MouseRegion in the tabbed_view
                // library. The following code is only used to make tabs
                // selectable on "tap down" instead of "on tap" (which is
                // "on tap down" + "on tap up").
                //
                final mr = tabWidget as MouseRegion;
                final gd = mr.child as GestureDetector;

                GestureDetector gestureDetector = GestureDetector(
                    onTertiaryTapUp: (details) {
                      closeTab(tabIndex, _tabController!);
                    },
                    onTap: () => gd.onTap?.call(),
                    child: gd.child);

                MouseRegion mouseRegion = MouseRegion(
                    cursor: mr.cursor,
                    onHover: mr.onHover,
                    onExit: mr.onExit,
                    child: gestureDetector);

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
                    child: DragTarget(
                      builder: (
                        BuildContext context,
                        List<dynamic> accepted,
                        List<dynamic> rejected,
                      ) {
                        return mouseRegion;
                      },
                      onAccept: (int index) {
                        debugPrint('Will move $tabIndex to $index');
                        context
                            .read<OpenningBooksProvider>()
                            .swap(tabIndex, index, selected: tabIndex);
                      },
                    ));
              }),
        );
      }),
    );
  }

  Widget getColumns(List<Map<String, dynamic>> books) {
    return Container(
      padding: const EdgeInsets.fromLTRB(1, 31, 1, 1),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: Iterable.generate(books.length)
              .map((i) {
                final isVisible = tabsVisibility[books[i]['uuid']] ?? false;
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
