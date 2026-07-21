import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../business_logic/models/search_result.dart';

part 'search_result_state.freezed.dart';

@freezed
class SearchResultState with _$SearchResultState {
  const factory SearchResultState.loading() = SearchResultStateLoading;
  const factory SearchResultState.loaded(List<SearchResult> results, int bookCount) = SearchResultStateLoaded;
  const factory SearchResultState.noData() = SearchResultStateNoData;
}
