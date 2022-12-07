import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/services/prefs.dart';

import '../../../../business_logic/view_models/search_page_view_model.dart';
import '../widgets/search_bar.dart';
import 'search_mode_view.dart';
import 'suggestion_list_tile.dart';

enum QueryMode { exact, prefix, distance, anywhere }

class SearchPage extends StatefulWidget {
  const SearchPage({Key? key}) : super(key: key);

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final TextEditingController controller;
  late bool isShowingSearchModeView;

  @override
  void initState() {
    controller = TextEditingController();
    isShowingSearchModeView = false;
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SearchPageViewModel>(
        create: (_) => SearchPageViewModel()..init(),
        child: Consumer<SearchPageViewModel>(builder: (context, vm, child) {
          return Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                title: Text(AppLocalizations.of(context)!.search),
                centerTitle: true,
              ),
              body: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SearchBar(
                          controller: controller,
                          onSubmitted: (searchWord) {
                            // checking input
                            int wordCount = searchWord.split(' ').length;
                            if (wordCount == 1 &&
                                vm.queryMode == QueryMode.distance) {
                              // showing alert dialog
                              showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                        title: const Text('Oh No'),
                                        content: const Text(
                                            'Not aviable for a single word.\nPhrase Only'),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                              child: const Text('OK'))
                                        ],
                                      ));
                            } else {
                              vm.onSubmmited(context, searchWord, vm.queryMode,
                                  vm.wordDistance);
                            }
                          },
                          onTextChanged: vm.onTextChanged,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.filter_list),
                        onPressed: () {
                          setState(() {
                            isShowingSearchModeView = !isShowingSearchModeView;
                          });
                        },
                      ),
                    ],
                  ),
                  AnimatedSize(
                    duration:
                        Duration(milliseconds: Prefs.animationSpeed.round()),
                    child: isShowingSearchModeView
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
                        : const SizedBox(height: 0),
                  ),
                  // suggestion view
                  Expanded(
                      child: vm.suggestions.isEmpty
                          ? _buildEmptyView(context)
                          : ListView.separated(
                              itemCount: vm.suggestions.length,
                              itemBuilder: (_, index) => SuggestionListTile(
                                suggestedWord: vm.suggestions[index].word,
                                frequency: vm.suggestions[index].count,
                                isFirstWord: vm.isFirstWord,
                                onTap: () {
                                  //
                                  final inputText = controller.text;
                                  final selectedWord =
                                      vm.suggestions[index].word;

                                  final words = inputText.split(' ');
                                  words.last = selectedWord;
                                  vm.onSubmmited(context, words.join(' '),
                                      vm.queryMode, vm.wordDistance);
                                },
                              ),
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                            )),
                ],
              ));
        }));
  }

  Widget _buildEmptyView(BuildContext context) {
    return GestureDetector(
      child: Container(color: Colors.transparent),
      // in android, keyboard can be hide by pressing back button
      // ios doesn't have back button
      // so to hide keyboard, provide this
      onTap: () => FocusScope.of(context).unfocus(),
    );
  }

  // _showSearchTypeSelectDialog(QueryMode queryMode) {
  //   return showBottomSheet<void>(
  //       context: context,
  //       builder: (BuildContext bc) {
  //         return SearchModeView(mode: queryMode);
  //       });
  // }
}
