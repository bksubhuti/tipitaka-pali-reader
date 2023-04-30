import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/services/provider/theme_change_notifier.dart';
import 'package:tipitaka_pali/ui/screens/dictionary/widget/dictionary_history_view.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../services/prefs.dart';
import '../controller/dictionary_controller.dart';
import '../controller/dictionary_state.dart';

class DictionaryContentView extends StatelessWidget {
  const DictionaryContentView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final state = context.select<DictionaryController, DictionaryState>(
        (controller) => controller.dictionaryState);

    return state.when(
        initial: () => ValueListenableBuilder(
            valueListenable: context.read<DictionaryController>().histories,
            builder: (_, histories, __) {
              return DictionaryHistoryView(
                histories: histories,
                onClick: (word) =>
                    context.read<DictionaryController>().onWordClicked(word),
                onDelete: (word) =>
                    context.read<DictionaryController>().onDelete(word),
              );
            }),
        loading: () => const SizedBox(
            height: 100, child: Center(child: CircularProgressIndicator())),
        data: (content) => SingleChildScrollView(
            child: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: SelectionArea(
                  child: HtmlWidget(
                    content,
                    customStylesBuilder: (element) {
                      if (element.classes.contains('dpdheader')) {
                        return {'font-weight:': 'bold'};
                      }
                      return null;
                    },
                    customWidgetBuilder: (element) {
                      /*             if (element.localName == "button") {
                        final value = element.attributes['value'];
                        if (value != null) {
                          debugPrint("found button: $value");
                          return TextButton(
                              onPressed: showDeclension(context),
                              child: const Text("Declension"));
                        }
                      }
                      */
                      final href = element.attributes['href'];
                      if (href != null) {
                        String linkText = href.contains("wikipedia")
                            ? "Wikipedia"
                            : "Submit a correction";

                        return InkWell(
                          onTap: () {
                            launchUrl(Uri.parse(href),
                                mode: LaunchMode.externalApplication);

                            debugPrint('will launch $href.');
                          },
                          child: Text(
                            linkText,
                            style: const TextStyle(
                                decoration: TextDecoration.underline,
                                color: Colors.blue,
                                fontSize: 10),
                          ),
                        );
                      }
                      return null;
                    },
                    textStyle: TextStyle(
                        fontSize: Prefs.dictionaryFontSize.toDouble(),
                        color: context.watch<ThemeChangeNotifier>().isDarkMode
                            ? Colors.white
                            : Colors.black,
                        inherit: false),
                    factoryBuilder: () => ClickableFactory(
                      onClicked: (word) {
                        debugPrint(word);
                        context
                            .read<DictionaryController>()
                            .onWordClicked(word);
                      },
                    ),
                  ),
                ))),
        noData: () => const SizedBox(
              height: 100,
              child: Center(child: Text('Not found')),
            ));
  }

  showDeclension(BuildContext context) {
    const String declension = '''Hellow world
''';

    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Oh No'),
              content: const HtmlWidget(declension),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('OK'))
              ],
            ));
  }
}

typedef WordChanged = void Function(String word);

class ClickableFactory extends WidgetFactory {
  final WordChanged? onClicked;
  ClickableFactory({this.onClicked});

  @override
  Widget? buildText(BuildMetadata meta, TextStyleHtml tsh, InlineSpan text) {
    if (meta.overflow == TextOverflow.clip && text is TextSpan) {
      if (text.text?.isNotEmpty == true) {
        String inlineText = text.text!;
        // inlineText = inlineText.replaceAll('+', ' + '); // add space between +
        // add space before + if not exist
        inlineText =
            inlineText.replaceAllMapped(RegExp(r'(?<!\s)\+'), (match) => ' +');
        // add space after + if not exist
        inlineText =
            inlineText.replaceAllMapped(RegExp(r'\+(?!\s)'), (match) => '+ ');
        // add space after . if not exist
        inlineText =
            inlineText.replaceAllMapped(RegExp(r'\.(?!\s)'), (match) => '. ');

        return CliakableWordTextView(
          text: inlineText,
          style: tsh.style,
          maxLines: meta.maxLines > 0 ? meta.maxLines : null,
          textAlign: tsh.textAlign ?? TextAlign.start,
          textDirection: tsh.textDirection,
          onWordTapped: (word, index) {
            onClicked?.call(word);
          },
        );
      }
    }

    return super.buildText(meta, tsh, text);
  }
}

class CliakableWordTextView extends StatefulWidget {
  final String text;
  final Function(String word, int? index)? onWordTapped;
  final bool highlight;
  final Color? highlightColor;
  final String alphabets;
  final TextStyle? style;
  final int? maxLines;
  final TextAlign textAlign;
  final TextDirection textDirection;
  const CliakableWordTextView(
      {Key? key,
      required this.text,
      this.onWordTapped,
      this.highlight = true,
      this.highlightColor,
      this.alphabets = '[a-zA-Z]',
      this.style,
      this.maxLines,
      this.textAlign = TextAlign.start,
      this.textDirection = TextDirection.ltr})
      : super(key: key);

  @override
  State<CliakableWordTextView> createState() => _CliakableWordTextViewState();
}

class _CliakableWordTextViewState extends State<CliakableWordTextView> {
  int? selectedWordIndex;
  Color? highlightColor;

  @override
  void initState() {
    selectedWordIndex = -1;
    if (widget.highlightColor == null) {
      highlightColor = Colors.pink.withOpacity(0.3);
    } else {
      highlightColor = widget.highlightColor;
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    List<String> wordList = widget.text
        .replaceAll(RegExp(r'(\n)+'), "#")
        .trim()
        .split(RegExp(r'\s|(?<=#)'));

    return Text.rich(
      TextSpan(
        children: [
          for (int i = 0; i < wordList.length; i++)
            TextSpan(
              children: [
                TextSpan(
                    text: wordList[i].replaceAll("#", ""),
                    style: TextStyle(
                        backgroundColor:
                            selectedWordIndex == i && widget.highlight
                                ? highlightColor
                                : Colors.transparent),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        setState(() {
                          selectedWordIndex = i;
                        });
                        if (widget.onWordTapped != null) {
                          widget.onWordTapped!(
                              wordList[i]
                                  .trim()
                                  .replaceAll(
                                      RegExp(r'${widget.alphabets}'), "")
                                  .trim(),
                              selectedWordIndex);
                        }
                      }),
                wordList[i].contains("#")
                    ? const TextSpan(text: "\n\n")
                    : const TextSpan(text: " "),
              ],
            )
          // generateSpans()
        ],
      ),
      style: widget.style,
      maxLines: widget.maxLines,
      textAlign: widget.textAlign,
      textDirection: widget.textDirection,
    );
  }
}
