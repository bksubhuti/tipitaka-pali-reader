import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/providers/font_provider.dart';
import 'package:tipitaka_pali/services/prefs.dart';

import '../../../../data/constants.dart';
import '../../../../services/provider/theme_change_notifier.dart';
import '../../../../utils/pali_script_converter.dart';

class PaliPageWidget extends StatefulWidget {
  final int pageNumber;
  final String htmlContent;
  final Script script;
  final String? highlightedWord;
  final Function(String clickedWord)? onClick;
  const PaliPageWidget({
    Key? key,
    required this.pageNumber,
    required this.htmlContent,
    required this.script,
    this.highlightedWord,
    this.onClick,
  }) : super(key: key);

  @override
  State<PaliPageWidget> createState() => _PaliPageWidgetState();
}

class _PaliPageWidgetState extends State<PaliPageWidget> {
  final _myFactory = _MyFactory();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _myFactory.onTapUrl('#goto');
    });
  }

  @override
  Widget build(BuildContext context) {
    int fontSize = context.watch<FontProvider>().fontSize;
    String html = _formatContent(widget.htmlContent, widget.script);

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SelectionArea(
        selectionControls: CupertinoTextSelectionControls(),
        child: HtmlWidget(
          html,
          factoryBuilder: () => _myFactory,
          textStyle: TextStyle(fontSize: fontSize.toDouble(), inherit: false),
          customStylesBuilder: (element) {
            // if (element.className == 'title' ||
            //     element.className == 'book' ||
            //     element.className == 'chapter' ||
            //     element.className == 'subhead' ||
            //     element.className == 'nikaya') {
            //   return {
            //     'text-align': 'center',
            //     // 'text-decoration': 'none',
            //   };
            // }
            if (element.localName == 'a') {
              // print('found a tag: ${element.outerHtml}');
              if (context.read<ThemeChangeNotifier>().isDarkMode) {
                return {
                  'color': 'white',
                  'text-decoration': 'none',
                };
              } else {
                return {
                  'color': 'black',
                  'text-decoration': 'none',
                };
              }
            }
            // no style
            return {'text-decoration': 'none'};
          },
          onTapUrl: (word) {
            if (widget.onClick != null) {
              // #goto is used for scrolling to selected text
              if (word != '#goto') {
                widget.onClick!(word);
              }
            }
            return false;
          },
        ),
      ),
    );
  }

  String _formatContent(String content, Script script) {
    if (widget.highlightedWord != null) {
      content = _addHighlight(content, widget.highlightedWord!);
    }

    content = _makeClickable(content, script);
    content = _changeToInlineStyle(content);
    content = _formatWithUserSetting(content);
    return content;
  }

  String _makeClickable(String content, Script script) {
    // pali word not inside html tag
    // final regexPaliWord = RegExp(r'[a-zA-ZāīūṅñṭḍṇḷṃĀĪŪṄÑṬḌHṆḶṂ]+(?![^<>]*>)');
    final regexPaliWord = _getPaliWordRegexp(script);
    return content.replaceAllMapped(regexPaliWord,
        (match) => '<a href="${match.group(0)}">${match.group(0)}</a>');
    /*
    final regexHtmlTag = RegExp(r'<[^>]+>');
    final regexPaliWord = RegExp(r'([a-zA-ZāīūṅñṭḍṇḷṃĀĪŪṄÑṬḌHṆḶṂ]+)');
    final matches = regexHtmlTag.allMatches(content);

    var formattedContent = '';
    for (var i = 0, length = matches.length; i < length - 1; i++) {
      final curretTag = matches.elementAt(i);
      final nextTag = matches.elementAt(i + 1);
      // add current tag to formatted content
      formattedContent += content.substring(curretTag.start, curretTag.end);
      if (curretTag.end == nextTag.start) continue; // no text data
      // extract text data
      var text = content.substring(curretTag.end, nextTag.start);
      // add a tag to every word to make clickable
      text = text.replaceAllMapped(regexPaliWord, (match) {
        String word = match.group(0)!;
        return '<a href="$word">$word</a>';
      });
      // add text to formatted context
      formattedContent += text;
    }
    // add last tag to formatted content
    formattedContent += content.substring(matches.last.start);

    return formattedContent;
    */
  }

  String _changeToInlineStyle(String content) {
    final styleMaps = <String, String>{
      r'class="bld"': r'style="font-weight:bold;"',
      r'class="centered"': r'style="text-align:center;"',
      r'class="paranum"': r'style="font-weight: bold;"',
      r'class="indent"': r'style="text-indent:1.3em;margin-left:2em;"',
      r'class="bodytext"': r'style="text-indent:1.3em;"',
      r'class="unindented"': r'style=""',
      r'class="noindentbodytext"': r'style=""',
      r'class="book"':
          r'style="font-size: 1.9em; text-align:center; font-weight: bold;"',
      r'class="chapter"':
          r'style="font-size: 1.7em; text-align:center; font-weight: bold;"',
      r'class="nikaya"':
          r'style="font-size: 1.6em; text-align:center; font-weight: bold;"',
      r'class="title"':
          r'style="font-size: 1.3em; text-align:center; font-weight: bold;"',
      r'class="subhead"':
          r'style="font-size: 1.6em; text-align:center; font-weight: bold;"',
      r'class="subsubhead"':
          r'style="font-size: 1.6em; text-align:center; font-weight: bold;"',
      r'class="gatha1"': r'style="margin-bottom: 0em; margin-left: 5em;"',
      r'class="gatha2"': r'style="margin-bottom: 0em; margin-left: 5em;"',
      r'class="gatha3"': r'style="margin-bottom: 0em; margin-left: 5em;"',
      r'class="gathalast"': r'style="margin-bottom: 1.3em; margin-left: 5em;"',
      r'class="pageheader"': r'style="font-size: 0.9em; color: deeppink;"',
      r'class="highlighted"':
          r'style="background: rgb(255, 114, 20); color: white;"',
    };

    styleMaps.forEach((key, value) {
      content = content.replaceAll(key, value);
    });

    return content;
  }

  RegExp _getPaliWordRegexp(Script script) {
    // only alphabets used for pali
    // no digit , no puntutation
    switch (script) {
      case Script.myanmar:
        return RegExp('[\u1000-\u103F]+(?![^<>]*>)');
      case Script.roman:
        return RegExp(r'[a-zA-ZāīūṅñṭḍṇḷṃĀĪŪṄÑṬḌHṆḶṂ]+(?![^<>]*>)');
      case Script.sinhala:
        return RegExp('[\u0D80-\u0DDF\u0DF2\u0DF3]+(?![^<>]*>)');
      case Script.devanagari:
        return RegExp('[\u0900-\u097F]+(?![^<>]*>)');
      case Script.thai:
        return RegExp('[\u0E00-\u0E7F\uF700-\uF70F]+(?![^<>]*>)');
      case Script.laos:
        return RegExp('[\u0E80-\u0EFF]+(?![^<>]*>)');
      case Script.khmer:
        return RegExp('\u1780-\u17FF]+(?![^<>]*>)');
      case Script.bengali:
        return RegExp('[\u0980-\u09FF]+(?![^<>]*>)');
      case Script.gurmukhi:
        return RegExp('[\u0A00-\u0A7F]+(?![^<>]*>)');
      case Script.taitham:
        return RegExp('[\u1A20-\u1AAF]+(?![^<>]*>)');
      case Script.gujarati:
        return RegExp('[\u0A80-\u0AFF]+(?![^<>]*>)');
      case Script.telugu:
        return RegExp('[\u0C00-\u0C7F]+(?![^<>]*>)');
      case Script.kannada:
        return RegExp('[\u0C80-\u0CFF]+(?![^<>]*>)');
      case Script.malayalam:
        return RegExp('[\u0D00-\u0D7F]+(?![^<>]*>)');
// actual code block [0x11000, 0x1107F]
// need check
      case Script.brahmi:
        return RegExp('[\uD804\uDC00-\uDC7F]+(?![^<>]*>)');
      case Script.tibetan:
        return RegExp('[\u0F00-\u0FFF]+(?![^<>]*>)');
// actual code block [0x11000, 0x1107F]
//need check
      case Script.cyrillic:
        return RegExp('[\u0400-\u04FF\u0300-\u036F]+(?![^<>]*>)');

      default:
        return RegExp(r'[a-zA-ZāīūṅñṭḍṇḷṃĀĪŪṄÑṬḌHṆḶṂ]+(?![^<>]*>)');
    }
  }

  String _formatWithUserSetting(String pageContent) {
    // return pages[index].content;

    // if (tocHeader != null) {
    //   pageContent = addIDforScroll(pageContent, tocHeader!);
    // }

    // showing page number based on user settings
    var publicationKeys = <String>['P', 'T', 'V'];
    if (!Prefs.isShowPtsNumber) publicationKeys.remove('P');
    if (!Prefs.isShowThaiNumber) publicationKeys.remove('T');
    if (!Prefs.isShowVriNumber) publicationKeys.remove('V');

    if (publicationKeys.isNotEmpty) {
      for (var publicationKey in publicationKeys) {
        final publicationFormat =
            RegExp('(<a name="$publicationKey(\\d+)\\.(\\d+)">)');
        pageContent = pageContent.replaceAllMapped(publicationFormat, (match) {
          final volume = match.group(2)!;
          // remove leading zero from page number
          final pageNumber = int.parse(match.group(3)!).toString();
          return '${match.group(1)}[$publicationKey $volume.$pageNumber]';
        });
      }
    }

    return '''
            <p style="color:brown;text-align:right;">${widget.pageNumber}</p>
            <div id="page_content">
              $pageContent
            </div>
    ''';
  }

  String _addHighlight(String content, String textToHighlight) {
    // TODO - optimize highlight for some query text

    //
    if (content.contains(textToHighlight)) {
      final replace = '<span class = "highlighted">$textToHighlight</span>';
      content = content.replaceAll(textToHighlight, replace);
      // adding id to scroll
      content = content.replaceFirst('<span class = "highlighted">',
          '<span id="$kGotoID" class="highlighted">');

      return content;
    }

    final words = textToHighlight.trim().split(' ');
    for (final word in words) {
      if (content.contains(word)) {
        final String replace = '<span class = "highlighted">$word</span>';
        content = content.replaceAll(word, replace);
      } else {
        // bolded word case
        // Log.d("if not found highlight", "yes");
        // removing ti (တိ) at end
        String trimmedWord = word.replaceAll(RegExp(r'(nti|ti)$'), '');
        // print('trimmedWord: $trimmedWord');
        final replace = '<span class = "highlighted">$trimmedWord</span>';

        content = content.replaceAll(trimmedWord, replace);
      }
      //
    }
    // adding id to scroll
    content = content.replaceFirst('<span class = "highlighted">',
        '<span id="$kGotoID" class="highlighted">');

    return content;
  }

  String addIDforScroll(String content, String tocHeader) {
    String tocHeaderWithID = '<span id="$kGotoID">$tocHeader</span>';
    content = content.replaceAll(tocHeader, tocHeaderWithID);

    return content;
  }
}

class _MyFactory extends WidgetFactory {
  /// Controls whether text is rendered with [SelectableText] or [RichText].
  ///
  /// Default: `true`.
  bool get selectableText => false;

  /// The callback when user changes the selection of text.
  ///
  /// See [SelectableText.onSelectionChanged].
  SelectionChangedCallback? get selectableTextOnChanged => null;

  @override
  Widget? buildText(BuildMetadata meta, TextStyleHtml tsh, InlineSpan text) {
    if (meta.overflow == TextOverflow.clip && text is TextSpan) {
      return Text.rich(
        text,
        maxLines: meta.maxLines > 0 ? meta.maxLines : null,
        textAlign: tsh.textAlign ?? TextAlign.start,
        textDirection: tsh.textDirection,
      );
    }
    return super.buildText(meta, tsh, text);
  }
}
