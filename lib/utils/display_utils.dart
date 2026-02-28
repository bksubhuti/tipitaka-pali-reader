import 'package:flutter/material.dart';
import 'package:tipitaka_pali/services/prefs.dart';


String superscripterUni(String text) {
  // Superscript using unicode characters.
  text = text.replaceAllMapped(
    RegExp(r'( )(\d)'),
    (Match match) => '\u200A${match.group(2)}',
  );
  text = text.replaceAll('0', '⁰');
  text = text.replaceAll('1', '¹');
  text = text.replaceAll('2', '²');
  text = text.replaceAll('3', '³');
  text = text.replaceAll('4', '⁴');
  text = text.replaceAll('5', '⁵');
  text = text.replaceAll('6', '⁶');
  text = text.replaceAll('7', '⁷');
  text = text.replaceAll('8', '⁸');
  text = text.replaceAll('9', '⁹');
  text = text.replaceAll('.', '·');
  return text;
}

Color getDpdHeaderColor() {
  if (Prefs.darkThemeOn) {
    // Return a bright orange color for dark mode
    return Colors.orange[300]!; // Lighter orange for better visibility
  } else {
    // Return a darker orange color for light mode
    return const Color.fromARGB(255, 183, 86, 29)!; // Darker orange for light mode
  }
}

double paintedWidth(BuildContext context, String text, TextStyle textStyle) {
  final textPainter = TextPainter(
      text: TextSpan(
          text: text,
          style: textStyle),
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr);
  textPainter.layout();
  return MediaQuery.of(context).textScaler.scale(textPainter.width);
}

double paintedHeight(BuildContext context, TextSpan text) {
  TextPainter textPainter = TextPainter(
      text: text, textAlign: TextAlign.left, textDirection: TextDirection.ltr);
  textPainter.layout();
  return MediaQuery.of(context).textScaler.scale(textPainter.height);
}