import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controller/dictionary_controller.dart';
import 'widget/dict_algo_selector.dart';
import 'widget/dict_content_view.dart';
import 'widget/dict_search_field.dart';

class DictionaryPage extends StatefulWidget {
  const DictionaryPage({Key? key}) : super(key: key);

  @override
  State<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends State<DictionaryPage>
    with AutomaticKeepAliveClientMixin {
  final List<String> _words = [];
  String _lastWord = "";

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dictionary'),
      ),
      body: ChangeNotifierProvider<DictionaryController>(
        create: (context) => DictionaryController(
          context: context,
        )..onLoad(),
        child: Consumer<DictionaryController>(builder: (context, dc, __) {
          if (dc.lookupWord != null) {
            if (dc.lookupWord != _lastWord) {
              _words.add(dc.lookupWord!);
              _lastWord = dc.lookupWord!;
              // debugPrint(" added words:  ${_words.toString()}");
            }
          } // if not null
          return Padding(
            padding: const EdgeInsets.all(8),
            child: Column(children: [
              Row(
                children: [
                  const Expanded(child: DictionarySearchField()),
                  const SizedBox(width: 8), // padding
                  IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.arrow_back, color: Colors.black),
                    onPressed: () {
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
                        //debugPrint("onpressed:  _words:  ${_words.toString()}");
                      }
                    },
                  ),
                  const DictionaryAlgorithmModeView(),
                ],
              ),
              const SizedBox(height: 4), // padding
              const Expanded(child: DictionaryContentView()),
            ]),
          );
        }),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
