import 'package:flutter/material.dart';
import 'package:tipitaka_pali/ui/widgets/pali_text_view.dart';

import '../../../../business_logic/models/search_history.dart';

class SearchHistoryView extends StatelessWidget {
  const SearchHistoryView({
    super.key,
    required this.histories,
    this.onClick,
    this.onDelete,
  });

  final List<SearchHistory> histories;
  final ValueChanged<String>? onClick;
  final ValueChanged<String>? onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: histories.length,
      itemBuilder: (context, index) {
        return ListTile(
          dense: true,
          // The delete button's own 8 makes its icon 16 in from the right,
          // as the word is from the left.
          contentPadding: const EdgeInsets.only(left: 16, right: 8),
          title: PaliTextView(histories[index].word),
          onTap: () => onClick?.call(histories[index].word),
          trailing: IconButton(
            onPressed: () => onDelete?.call(histories[index].word),
            icon: const Icon(Icons.delete),
          ),
        );
      },
      separatorBuilder: (context, index) => const Divider(height: 1),
    );
  }
}
