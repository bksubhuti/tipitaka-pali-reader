import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/dictionary/controller/dictionary_controller.dart';
import '../screens/dictionary/widget/dict_algo_selector.dart';
import '../screens/dictionary/widget/dict_content_view.dart';
import '../screens/dictionary/widget/dict_search_field.dart';

class DictionaryDialog extends StatelessWidget {
  final String? word;

  DictionaryDialog({Key? key, this.word}) : super(key: key);
  final List<String> _words = [];
  String _lastWord = "";

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DictionaryController>(
      create: (context) =>
          DictionaryController(context: context, lookupWord: word)..onLoad(),
      child: Consumer<DictionaryController>(
        builder: (context, dc, __) {
          if (dc.lookupWord != null) {
            if (dc.lookupWord != _lastWord) {
              _words.add(dc.lookupWord!);
              _lastWord = dc.lookupWord!;
              //debugPrint(" added words:  ${_words.toString()}");
            }
          } // if not null

          return Material(
            child: Stack(
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 56.0),
                  child: DictionaryContentView(),
                ),
                Row(
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.close, color: Colors.black),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(child: DictionarySearchField()),
                    IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.arrow_back, color: Colors.black),
                      onPressed: () async {
                        if (_words.isNotEmpty) {
                          // i think this should be handled by the state, but I'm
                          // sure the notifier is always the same object, so I
                          // handle here in the ui.

                          //the last -1 item is shown.. so need to go -2
                          int index = _words.length - 2;
                          // don't go beyond
                          index = (index < 0) ? 0 : index;
                          // save that word
                          _lastWord = _words[index];
                          _words.removeLast(); // remove from list
                          dc.onWordClicked(_lastWord);
                          debugPrint(
                              "onpressed:  _words:  ${_words.toString()}");
                        }
                      },
                    ),
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: DictionaryAlgorithmModeView(),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
