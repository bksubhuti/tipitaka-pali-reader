import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/utils/pali_script.dart';

import '../../../../services/provider/theme_change_notifier.dart';
import '../../../../utils/pali_script_converter.dart';
import '../../../../utils/pali_tools.dart';
import '../../../../utils/script_detector.dart';
import '../../../widgets/labeled_checkbox.dart';
import '../controller/reader_view_controller.dart';

class SearchWidget extends StatefulWidget {
  const SearchWidget({super.key, this.word});
  final String? word;

  @override
  State<SearchWidget> createState() => _SearchWidgetState();
}

class _SearchWidgetState extends State<SearchWidget> {
  late final ReaderViewController readerViewController;
  late final double min;
  late final double max;
  late final int divisions;
  late int currentPage;
  late final TextEditingController _controller =
      TextEditingController(text: widget.word);

  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    readerViewController =
        Provider.of<ReaderViewController>(context, listen: false);

    readerViewController.searchResultCount.addListener(_onSearchCountChanged);
    readerViewController.currentSearchResult.addListener(_onSearchCountChanged);
    readerViewController.searchFocusRequests.addListener(_takeFocus);

    _controller.addListener(() {
      String text = _controller.value.text;
      final scriptLanguage = ScriptDetector.getLanguage(text);

      if (text.isNotEmpty &&
          scriptLanguage == Script.roman &&
          !Prefs.disableVelthuis) {
        final uniText = PaliTools.velthuisToUni(velthiusInput: text);
        if (uniText != text) {
          final pos = _controller.selection.start;
          final offset = pos + uniText.length - text.length;
          final sel = TextSelection.fromPosition(TextPosition(offset: offset));
          _controller.value = TextEditingValue(text: uniText, selection: sel);
          text = uniText;
        }
      } else if (text.isNotEmpty) {
        // convert to roman
        text =
            PaliScript.getRomanScriptFrom(script: scriptLanguage, text: text);
      }

      if (text.length > 2) {
        readerViewController.search(text);
      } else {
        readerViewController.search('');
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      //
      Focus.maybeOf(context)?.unfocus();
      _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant SearchWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    Future.microtask(() {
      _controller.text = widget.word ?? '';
    });
  }

  @override
  void dispose() {
    readerViewController.searchFocusRequests.removeListener(_takeFocus);
    super.dispose();
    _controller.dispose();
  }

  /// Ctrl+F while the box is already open, from another pane: bring the
  /// cursor back here with what was typed selected, ready to replace.
  void _takeFocus() {
    if (!mounted) return;
    _focusNode.requestFocus();
    _controller.selection =
        TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
  }

  void _onSearchCountChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final rvc = context.read<ReaderViewController>();
    final baseColor = context.read<ThemeChangeNotifier>().isDarkMode
        ? Colors.white
        : Colors.black;
    final textColor = _controller.value.text.length > 2
        ? baseColor
        : baseColor.withAlpha(100);

    return LayoutBuilder(
      builder: (_, BoxConstraints boxConstraints) {
        bool haveRoom = boxConstraints.maxWidth > 600;
        // debugPrint('width: ${boxConstraints.maxWidth}');
        return Container(
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey))),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        flex: 2,
                        child: TextField(
                          focusNode: _focusNode,
                          controller: _controller,
                          autofocus: true,
                          style: TextStyle(color: textColor),
                          decoration: InputDecoration(
                              suffixIcon: IconButton(
                                onPressed: () {
                                  _controller.clear();
                                },
                                icon: const Icon(
                                  Icons.clear,
                                  size: 18,
                                ),
                              ),
                              border: const OutlineInputBorder(),
                              contentPadding:
                                  const EdgeInsets.only(left: 8, right: 8)),
                        ),
                      ),
                      if (readerViewController.searchResultCount.value == 0)
                        const Padding(
                          padding: EdgeInsets.only(left: 10.0),
                          child: Text('0 results'),
                        ),
                      if (readerViewController.searchResultCount.value > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 10.0),
                          child: Text(
                              '${readerViewController.currentSearchResult.value} / ${readerViewController.searchResultCount.value}'),
                        ),
                      Padding(
                          padding: const EdgeInsets.all(2),
                          child: SizedBox(
                              height: 38.0,
                              width: 38.0,
                              child: IconButton(
                                padding: const EdgeInsets.all(0.0),
                                icon:
                                    const Icon(Icons.arrow_upward, size: 22.0),
                                onPressed: () {
                                  readerViewController.searchUpward();
                                },
                              ))),
                      Padding(
                          padding: const EdgeInsets.all(2),
                          child: SizedBox(
                              height: 38.0,
                              width: 38.0,
                              child: IconButton(
                                padding: const EdgeInsets.all(0.0),
                                icon: const Icon(Icons.arrow_downward,
                                    size: 22.0),
                                onPressed: () {
                                  readerViewController.searchDownward();
                                },
                              ))),
                      const VerticalDivider(
                        width: 20,
                        thickness: 1,
                        indent: 0,
                        endIndent: 0,
                        color: Colors.grey,
                      ),
                      // adding blank space to prohibit textfield from expanding to hight
                      if (boxConstraints.maxWidth > 800)
                        const Flexible(flex: 1, child: SizedBox.expand()),
                      if (haveRoom)
                        LabeledCheckbox(
                          value: readerViewController.highlightEveryMatch.value,
                          label: 'Highlight every match',
                          onChanged: (value) {
                            setState(() {
                              readerViewController
                                  .setHighlightEveryMatch(value);
                            });
                          },
                          padding: EdgeInsets.zero,
                        ),
                      // Expanded(child: Container()),
                      Padding(
                          padding: const EdgeInsets.all(2),
                          child: SizedBox(
                              height: 38.0,
                              width: 38.0,
                              child: IconButton(
                                padding: const EdgeInsets.all(0.0),
                                icon: const Icon(Icons.close, size: 22.0),
                                onPressed: () {
                                  rvc.showSearchWidget(false);
                                },
                              )))
                    ],
                  )),
              //
              if (!haveRoom)
                Row(
                  children: [
                    LabeledCheckbox(
                      value: readerViewController.highlightEveryMatch.value,
                      label: 'Highlight every match',
                      onChanged: (value) {
                        setState(() {
                          readerViewController.setHighlightEveryMatch(value);
                        });
                      },
                      padding: EdgeInsets.zero,
                    ),
                  ],
                )
            ],
          ),
        );
      },
    );
  }

  void _listenPageChange() {
    setState(() {
      currentPage = readerViewController.currentPage.value;
    });
  }
}
