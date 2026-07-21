import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../widgets/loading_view.dart';
import '../home/search_page/search_page.dart';
import 'controller/search_filter_provider.dart';
import 'controller/search_result_provider.dart';
import 'widgets/empty_result_view.dart';
import 'widgets/result_list_view.dart';
import 'controller/search_result_state.dart';

class SearchResultPage extends StatelessWidget {
  final String searchWord;
  final QueryMode queryMode;
  final int wordDistance;
  //  final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();

  const SearchResultPage(
      {super.key,
      required this.searchWord,
      required this.queryMode,
      required this.wordDistance});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
        providers: [
          ChangeNotifierProvider<SearchFilterController>(
              create: (context) => SearchFilterController(context: context)),
          ChangeNotifierProxyProvider<SearchFilterController,
                  SearchResultController>(
              create: (ctx) => SearchResultController(
                  searchWord: searchWord,
                  queryMode: queryMode,
                  wordDistance: wordDistance,
                  filterController: ctx.read<SearchFilterController>())
                ..init(),
              update: (_, filterController, resultConroller) {
                resultConroller!.onChangeFilter(filterController);
                return resultConroller;
              }),
        ],
        builder: (context, _) {
          // final notifier = context.watch<SearchResultNotifier>();
          final state = context.watch<SearchResultController>().state;

          return switch (state) {
            SearchResultStateLoading() => const Material(child: LoadingView()),
            SearchResultStateNoData() => EmptyResultView(searchWord: searchWord),
            SearchResultStateLoaded(results: var results, bookCount: var bookCount) => ResultListView(
              searchWord: searchWord,
              results: results,
              bookCount: bookCount,
            ),
            _ => const SizedBox.shrink(),
          };
        });
  }
}
