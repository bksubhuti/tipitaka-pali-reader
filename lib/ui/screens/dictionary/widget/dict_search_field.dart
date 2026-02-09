import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/repositories/dictionary_history_repo.dart';
import 'package:tipitaka_pali/utils/pali_script_converter.dart';

import '../../../../services/provider/script_language_provider.dart';
import '../../../../utils/pali_script.dart';
import '../../../../utils/pali_tools.dart';
import '../../../../utils/script_detector.dart';
import '../controller/dictionary_controller.dart';

class DictionarySearchField extends StatefulWidget {
  final FocusNode? focusNode;
  const DictionarySearchField({
    super.key,
    this.focusNode,
  });

  @override
  State<DictionarySearchField> createState() => _DictionarySearchFieldState();
}

class _DictionarySearchFieldState extends State<DictionarySearchField> {
  late final TextEditingController textEditingController;
  late final DictionaryController dictionaryController;
  ValueNotifier<bool> showClearButton = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();

    dictionaryController = context.read<DictionaryController>();
    textEditingController = TextEditingController();

    final lookupWord = dictionaryController.lookupWord;
    if (lookupWord.isNotEmpty) {
      textEditingController.text = PaliScript.getScriptOf(
          script: context.read<ScriptLanguageProvider>().currentScript,
          romanText: lookupWord);
    } else {
      textEditingController.text = '';
    }
    dictionaryController.addListener(_lookUpWordListener);
    textEditingController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    showClearButton.value = textEditingController.text.isNotEmpty;
  }

  @override
  void dispose() {
    textEditingController.dispose();
    super.dispose();
  }

  void _lookUpWordListener() {
    final lookupWord = dictionaryController.lookupWord;
    if (lookupWord.isNotEmpty) {
      textEditingController.text = PaliScript.getScriptOf(
          script: context.read<ScriptLanguageProvider>().currentScript,
          romanText: lookupWord);
    } else {
      textEditingController.text = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return TypeAheadField<String>(
      controller: textEditingController,
      suggestionsCallback: (text) async {
        if (text.isEmpty) return <String>[];
        final inputLanguage = ScriptDetector.getLanguage(text);
        final romanText = PaliScript.getRomanScriptFrom(
          script: inputLanguage,
          text: text,
        );
        return await context
            .read<DictionaryController>()
            .getSuggestions(romanText);
      },
      itemBuilder: (context, String suggestion) {
        return ListTile(
          title: Text(PaliScript.getScriptOf(
            script: context.read<ScriptLanguageProvider>().currentScript,
            romanText: suggestion,
          )),
        );
      },
      onSelected: (String suggestion) async {
        final inputLanguage =
            ScriptDetector.getLanguage(textEditingController.text);
        textEditingController.text = PaliScript.getScriptOf(
          script: inputLanguage,
          romanText: suggestion,
        );
        await insertHistory(suggestion);
        context.read<DictionaryController>().onLookup(suggestion);
      },
      builder: (context, controller, focusNode) {
        return TextField(
          controller: controller,
          focusNode: widget.focusNode ?? focusNode,
          autocorrect: false,
          decoration: InputDecoration(
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            suffixIcon: ValueListenableBuilder(
              valueListenable: showClearButton,
              builder: (context, isVisible, _) {
                return Visibility(
                  visible: isVisible,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: IconButton(
                      onPressed: () {
                        controller.clear();
                      },
                      icon: const Icon(Icons.clear),
                    ),
                  ),
                );
              },
            ),
          ),
          onChanged: (text) {
            showClearButton.value = text.isNotEmpty;
            String inputText = text;
            final inputScript = ScriptDetector.getLanguage(inputText);

            if (text.isNotEmpty) {
              int origTextLen = text.length;
              int pos = controller.selection.start;

              if (!Prefs.disableVelthuis && inputScript == Script.roman) {
                final uniText = PaliTools.velthuisToUni(velthiusInput: text);
                int uniTextlen = uniText.length;
                controller.text = uniText;
                controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: pos + uniTextlen - origTextLen),
                );
              }
            } else {
              context.read<DictionaryController>().onInputIsEmpty();
            }
          },
          onSubmitted: (word) async {
            await insertHistory(word);
            context.read<DictionaryController>().onLookup(word);
          },
        );
      },
    );
  }

  insertHistory(word) async {
    final DictionaryHistoryDatabaseRepository dictionaryHistoryRepository =
        DictionaryHistoryDatabaseRepository(dbh: DatabaseHelper());

    await dictionaryHistoryRepository.insert(word, "", 1, "");
  }
}
