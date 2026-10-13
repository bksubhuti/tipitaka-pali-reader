import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../services/provider/script_language_provider.dart';
import '../../../../utils/font_utils.dart';
import '../../../../utils/pali_script.dart';

class SuggestionListTile extends StatelessWidget {
  const SuggestionListTile({
    super.key,
    required this.suggestedWord,
    required this.frequency,
    this.isFirstWord = true,
    this.asTyped = false,
    this.onClickedSubmitButton,
    this.onClickedSuggestion,
    this.onClickedAddButton,
  });

  final String suggestedWord;
  final int frequency;
  final bool isFirstWord;

  /// Shown as it is rather than in the reader's Pali script.
  final bool asTyped;
  final VoidCallback? onClickedSubmitButton;
  final VoidCallback? onClickedSuggestion;
  final VoidCallback? onClickedAddButton;

  @override
  Widget build(BuildContext context) {
    String scriptWord = asTyped
        ? suggestedWord
        : PaliScript.getScriptOf(
            script: context.read<ScriptLanguageProvider>().currentScript,
            romanText: suggestedWord);
    if (!isFirstWord) {
      scriptWord = '... $scriptWord';
    }
    return ListTile(
      dense: true,
      minVerticalPadding: 0,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      // suggested word
      // A Pāḷi word in the Pāḷi font; a translation's word as it is.
      title: Text(scriptWord,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontFamily: asTyped
                  ? null
                  : FontUtils.getfontName(
                      script: context
                          .read<ScriptLanguageProvider>()
                          .currentScript))),
      leading: IconButton(
        onPressed: onClickedAddButton,
        icon: const Icon(Icons.library_add),
      ),
      //subtitle: const Icon(Icons.library_add),
      // word frequency
      trailing: Text(
          asTyped
              ? frequency.toString()
              : PaliScript.getScriptOf(
                  script: context.read<ScriptLanguageProvider>().currentScript,
                  romanText: (frequency == -1) ? " " : frequency.toString()),
          style: Theme.of(context).textTheme.bodyLarge),
      onTap: onClickedSuggestion,
    );
  }
}
