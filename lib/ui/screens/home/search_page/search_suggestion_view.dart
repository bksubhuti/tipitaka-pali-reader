import 'package:flutter/material.dart';
import '../../../../business_logic/models/search_suggestion.dart';
import 'suggestion_list_tile.dart';

class SearchSuggestionView extends StatelessWidget {
  const SearchSuggestionView({
    super.key,
    required this.suggestions,
    this.onClickedAddButton,
    this.onClickedSuggestion,
    this.isFistWord = true,
  });

  final List<SearchSuggestion> suggestions;
  final ValueChanged<SearchSuggestion>? onClickedAddButton;
  final ValueChanged<SearchSuggestion>? onClickedSuggestion;
  final bool isFistWord;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: suggestions.length,
      itemBuilder: (context, index) => SuggestionListTile(
        suggestedWord: suggestions[index].word,
        frequency: suggestions[index].count,
        asTyped: suggestions[index].asTyped,
        isFirstWord: isFistWord,
        onClickedAddButton: () => onClickedAddButton?.call(suggestions[index]),
        onClickedSuggestion: () =>
            onClickedSuggestion?.call(suggestions[index]),
      ),
      separatorBuilder: (context, index) => const Divider(height: 1),
    );
  }
}
