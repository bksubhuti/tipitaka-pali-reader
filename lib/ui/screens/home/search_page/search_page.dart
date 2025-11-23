import 'package:flutter/material.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/routes.dart';
import 'package:tipitaka_pali/providers/navigation_provider.dart';
import 'package:tipitaka_pali/ui/screens/search_result/search_result_page.dart';
import 'package:tipitaka_pali/ui/widgets/value_listenser.dart';

import '../../../../business_logic/view_models/search_page_view_model.dart';
import '../../../../services/database/database_helper.dart';
import '../../../../services/prefs.dart';
import '../../../../services/repositories/search_history_repo.dart';
import '../../../../utils/pali_script.dart';
import '../../../../utils/pali_script_converter.dart';
import '../../../../utils/script_detector.dart';
import '../../../../utils/platform_info.dart';
import 'package:flutter/services.dart';
import '../../../widgets/search_type_segmented_widget.dart';
import '../widgets/search_bar.dart';
import 'search_history_view.dart';
import 'search_suggestion_view.dart';

enum QueryMode { exact, prefix, distance, anywhere }

extension ParseToString on QueryMode {
  String toShortString() {
    print(toString());
    return toString().split('.').last;
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with AutomaticKeepAliveClientMixin {
  late final TextEditingController controller;
  late bool isShowingSearchModeView;
  late final FocusNode focusNode;

  @override
  void initState() {
    controller = TextEditingController();
    isShowingSearchModeView = false;
    focusNode = FocusNode();
    super.initState();
    // globalSearchWord.addListener(() {
    //   setState(() {});
    // });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestFocus();
      context.read<NavigationProvider>().addListener(_onNavigationChanged);
    });
  }

  void _onNavigationChanged() {
    if (mounted) {
      _requestFocus();
    }
  }

  void _requestFocus() {
    final currentNavigation =
        context.read<NavigationProvider>().currentNavigation;
    if (currentNavigation == 3) {
      focusNode.requestFocus();
      if (Mobile.isPhone(context) || Mobile.isTablet(context)) {
        SystemChannels.textInput.invokeMethod('TextInput.show');
      }
    } else if (currentNavigation != 4) {
      focusNode.unfocus();
    }
  }

  @override
  void dispose() {
    context.read<NavigationProvider>().removeListener(_onNavigationChanged);
    super.dispose();
    controller.dispose();
    focusNode.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ChangeNotifierProvider<SearchPageViewModel>(
        create: (_) => SearchPageViewModel(
              searchHistoryRepository:
                  SearchHistoryDatabaseRepository(dbh: DatabaseHelper()),
            )..init(),
        child: Builder(builder: (context) {
          final vm = context.watch<SearchPageViewModel>();
          return Scaffold(
              appBar: AppBar(
                // Disable because of conflict with mobile search
                // leading: getVelthuisHelp(context),

                // Rydmike: Consider not having implicit back, as it will give idea that
                //  user can go back, but back leads out of app in this case.
                automaticallyImplyLeading: false, // Mobile.isPhone(context),
                title: Text(AppLocalizations.of(context)!.search),
                // Rydmike info: Prefer consistent alignment on AppBar.
                //  if default, iOs is centered, Android start by default
                // centerTitle: true,

                // Rydmike proposal: Consider converting Drawer on Home screen
                //    to a Widget and add it also to other top level screens.
                // drawer: Mobile.isPhone(context) ? AppDrawer(context) : null,
                actions: [
                  FilterChip(
                      label: Text(
                        AppLocalizations.of(context)!.fuzzy,
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: Prefs.isFuzzy,
                      onSelected: (value) {
                        setState(() {
                          Prefs.isFuzzy = !Prefs.isFuzzy;
                          vm.isFuzzy = Prefs.isFuzzy;
                          vm.onTextChanged(controller.text);
                        });
                      }),
                  const SizedBox(
                    width: 8,
                  )
                ],
              ),
              body: ValueListenableListener(
                onValueChanged: (searchWord) {
                  if (searchWord != null) {
                    _onSubmitted(searchWord, vm);
                  }
                },
                valueListenable: globalSearchWord,
                child: Column(
                  children: [
                    SearchTypeSegmentedControl(
                      mode: vm.queryMode,
                      wordDistance: vm.wordDistance,
                      onModeChanged: (value) {
                        setState(() {
                          vm.onQueryModeChanged(value);
                        });
                      },
                      onDistanceChanged: (value) {
                        vm.onWordDistanceChanged(value);
                      },
                    ),
                    // search bar
                    Row(
                      children: [
                        Expanded(
                          child: TprSearchBar(
                            hint: _getHint(vm.queryMode),
                            controller: controller,
                            focusNode: focusNode,
                            onSubmitted: (value) {
                              _onSubmitted(value, vm);
                            },
                            onTextChanged: vm.onTextChanged,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                    _getMakeWordListButton(vm, context),
                    // search mode chooser view
                    AnimatedSize(
                      duration:
                          Duration(milliseconds: Prefs.animationSpeed.round()),
                      child: /* isShowingSearchModeView
                          ? SearchModeView(
                              mode: vm.queryMode,
                              wordDistance: vm.wordDistance,
                              onModeChanged: (value) {
                                vm.onQueryModeChanged(value);
                              },
                              onDistanceChanged: (value) {
                                vm.onWordDistanceChanged(value);
                              },
                            )
                          : */
                          const SizedBox.shrink(),
                    ),
                    // suggestion view

                    Expanded(
                      child: ValueListenableBuilder(
                          valueListenable: vm.isSearching,
                          builder: (context, isSearching, child) {
                            if (isSearching) {
                              return ValueListenableBuilder(
                                  valueListenable: vm.suggestions,
                                  builder: (_, suggestions, __) {
                                    return SearchSuggestionView(
                                      suggestions: suggestions,
                                      onClickedAddButton: (suggestion) {
                                        _updateInput(suggestion.word);
                                      },
                                      onClickedSuggestion: (suggestion) {
                                        _updateInput(suggestion.word);
                                        _onSubmitted(controller.text, vm);
                                      },
                                    );
                                  });
                            }
                            return ValueListenableBuilder(
                                valueListenable: vm.histories,
                                builder: (_, histories, __) {
                                  return SearchHistoryView(
                                      histories: histories,
                                      onClick: (value) {
                                        _onSubmitted(value, vm);
                                      },
                                      onDelete: vm.onDeleteButtonClicked);
                                });
                          }),
                    ),
                  ],
                ),
              ));
        }));
  }

  void _updateInput(String suggestion) {
    String inputText = controller.text;
    final inputScript = ScriptDetector.getLanguage(inputText);
    final words = inputText.split(' ');
    if (inputScript == Script.roman) {
      words.last = suggestion;
    } else {
      words.last =
          PaliScript.getScriptOf(script: inputScript, romanText: suggestion);
    }
    inputText = words.join(' ');
    controller.text = inputText;
    controller.selection = TextSelection.fromPosition(
        TextPosition(offset: controller.text.length));
  }



  String _getHint(QueryMode queryMode) {
    if (queryMode == QueryMode.exact) {
      return AppLocalizations.of(context)!.exact;
    } else if (queryMode == QueryMode.distance) {
      return AppLocalizations.of(context)!.distance;
    } else if (queryMode == QueryMode.prefix) {
      return AppLocalizations.of(context)!.prefix;
    } else {
      return AppLocalizations.of(context)!.anywhere;
    }
  }

  // _showSearchTypeSelectDialog(QueryMode queryMode) {
  //   return showBottomSheet<void>(
  //       context: context,
  //       builder: (BuildContext bc) {
  //         return SearchModeView(mode: queryMode);
  //       });
  // }

  void _onSubmitted(String searchWord, SearchPageViewModel vm) {
    searchWord = searchWord.trimRight();
    final inputScriptLanguage = ScriptDetector.getLanguage(searchWord);
    if (inputScriptLanguage != Script.roman) {
      searchWord = PaliScript.getRomanScriptFrom(
          script: inputScriptLanguage, text: searchWord);
    }
    vm.onSubmmited(searchWord);

    var route = MaterialPageRoute(
        builder: (_) => SearchResultPage(
            searchWord: searchWord,
            queryMode: vm.queryMode,
            wordDistance: vm.wordDistance));

    NestedNavigationHelper.goto(
        context: context, route: route, navkey: searchNavigationKey);

    // if (PlatformInfo.isDesktop || Mobile.isTablet(context)) {
    //   searchNavigationKey.currentState?.push(route);
    // } else {
    //   Navigator.push(context, route);
    // }

    // // open search results
    // Navigator.pushNamed(context, searchResultRoute, arguments: {
    //   'searchWord': searchWord,
    //   'queryMode': vm.queryMode,
    //   'wordDistance': vm.wordDistance,
    // });
  }

  @override
  bool get wantKeepAlive => true;

  Widget _getMakeWordListButton(SearchPageViewModel vm, context) {
    bool isTaskCompleted = false; // Track if the task is completed
    String message = ""; // Store the message from the database helper

    if (vm.count > 800000) {
      return const SizedBox.shrink();
    } else {
      return TextButton(
        onPressed: () async {
          // Show a loading dialog

          StateSetter? _ss;
          showDialog(
            context: context,
            barrierDismissible: false, // Prevent users from closing the dialog
            builder: (BuildContext context) {
              return StatefulBuilder(
                  builder: (BuildContext context, StateSetter ss) {
                _ss = ss;
                return AlertDialog(
                  title: Text(AppLocalizations.of(context)!.processing),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                          message), // Display the message from the database helper
                      if (!isTaskCompleted) const CircularProgressIndicator(),
                    ],
                  ),
                  actions: <Widget>[
                    if (isTaskCompleted) // Show the close button when the task is completed
                      TextButton(
                        onPressed: () {
                          vm.init();
                          Navigator.of(context).pop(); // Close the dialog
                        },
                        child: Text(AppLocalizations.of(context)!.close),
                      ),
                  ],
                );
              });
            },
          );

          try {
            // Perform your time-consuming task here
            final DatabaseHelper databaseHelper = DatabaseHelper();
            await databaseHelper.buildWordList((String incomingMessage) {
              _ss?.call(() {
                // Update the message when the database helper provides it
                message = incomingMessage;
              });
            });

            // Set isTaskCompleted to true when the task is finished
            _ss?.call(() {
              isTaskCompleted = true;
            });
          } catch (error) {
            // Handle any errors that may occur during the task
            _ss?.call(() {
              message =
                  "Error: $error"; // Update the message in case of an error
              isTaskCompleted =
                  true; // Set isTaskCompleted to true to enable the close button
            });
          }
        },
        style: ButtonStyle(
          backgroundColor: MaterialStateProperty.all<Color>(Colors.red),
        ),
        child: Text(AppLocalizations.of(context)!.fixWordlist,
            style: const TextStyle(color: Colors.white)),
      );
    }
  }
}
