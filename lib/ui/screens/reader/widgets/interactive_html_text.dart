import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/providers/font_provider.dart';
import 'package:tipitaka_pali/data/page_papers.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/provider/theme_change_notifier.dart';

class InteractiveHtmlText extends StatelessWidget {
  final String html;
  final void Function(String word)? onWordTap;

  const InteractiveHtmlText({
    super.key,
    required this.html,
    this.onWordTap,
  });

  @override
  Widget build(BuildContext context) {
    final GlobalKey _htmlKey = GlobalKey();

    final themeNotifier = context.watch<ThemeChangeNotifier>();
    final mediumTheme = themeNotifier.themeData.colorScheme.surfaceVariant;
    final backgroundColor = switch (Prefs.selectedPageTheme) {
      PageTheme.light => Colors.white,
      PageTheme.medium => pagePapers[Prefs.pagePaper].color ?? mediumTheme,
      PageTheme.dark => Colors.black,
      _ => Colors.white,
    };

    // Get system-wide font and theme info
    final fontSize = context.watch<ReaderFontProvider>().fontSize;
    final isDark = context.watch<ThemeChangeNotifier>().isDarkMode;
    final fontColor = isDark ? Colors.white : Colors.black;

    return SelectionArea(
      child: GestureDetector(
        onTapUp: (details) {
          final renderBox =
              _htmlKey.currentContext?.findRenderObject() as RenderBox?;
          if (renderBox == null) return;

          final result = BoxHitTestResult();
          final localPosition = renderBox.globalToLocal(details.globalPosition);
          if (!renderBox.hitTest(result, position: localPosition)) return;

          for (final entry in result.path) {
            if (entry is! BoxHitTestEntry || entry.target is! RenderParagraph) {
              continue;
            }

            final paragraph = entry.target as RenderParagraph;
            final pos = paragraph.getPositionForOffset(entry.localPosition);
            final text = paragraph.text.toPlainText();

            if (pos.offset >= text.length) return;

            final tappedChar = text[pos.offset];
            final left = _getLeftWord(text, pos.offset);
            final right = _getRightWord(text, pos.offset);
            final word = left + tappedChar + right;

            if (word.trim().isNotEmpty) {
              onWordTap?.call(word.trim());
            }
            return;
          }
        },
        child: Container(
          color: backgroundColor,
          child: HtmlWidget(
            html,
            key: _htmlKey,
            textStyle: TextStyle(
              fontSize: fontSize.toDouble(),
              color: fontColor,
            ),
          ),
        ),
      ),
    );
  }

  String _getLeftWord(String text, int offset) {
    final buffer = StringBuffer();
    for (int i = offset - 1; i >= 0; i--) {
      final c = text[i];
      if (_isBoundary(c)) break;
      buffer.write(c);
    }
    return buffer.toString().split('').reversed.join();
  }

  String _getRightWord(String text, int offset) {
    final buffer = StringBuffer();
    for (int i = offset + 1; i < text.length; i++) {
      final c = text[i];
      if (_isBoundary(c)) break;
      buffer.write(c);
    }
    return buffer.toString();
  }

  bool _isBoundary(String c) =>
      RegExp(r'[^\wāīūṅñṭḍṇḷṃĀĪŪṄÑṬḌṆḶṂ]').hasMatch(c);
}
