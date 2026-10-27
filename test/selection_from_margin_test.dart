import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:tipitaka_pali/ui/widgets/selection_from_margin.dart';

/// A selection begun in the margin beside a line of a paragraph took the
/// whole paragraph above the line with it.
void main() {
  const html = '<p>atha kho bhagavā ātumāyaṃ viharitvā<br>'
      'Then the Blessed One stayed in Ātumā<br>'
      'tena kho pana samayena sāvatthiyaṃ<br>'
      'Now at that time, a great quantity of fruit</p>';

  Future<String> dragFromMargin(WidgetTester tester, bool fixed) async {
    SelectedContent? selected;
    Widget block = const HtmlWidget(html);
    if (fixed) block = SelectionFromMargin(child: block);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SelectionArea(
          onSelectionChanged: (c) => selected = c,
          child: Padding(
            // The margin beside the text.
            padding: const EdgeInsets.only(left: 120, right: 120),
            child: block,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final paragraph = tester
        .renderObjectList<RenderParagraph>(find.byType(RichText))
        .firstWhere((p) => p.text.toPlainText().contains('tena kho'));
    final text = paragraph.text.toPlainText();
    Offset at(int index) => paragraph.localToGlobal(
        paragraph.getOffsetForCaret(TextPosition(offset: index), Rect.zero) +
            Offset(1, paragraph.preferredLineHeight / 2));
    final line = at(text.indexOf('tena kho'));
    final margin = Offset(40, line.dy);

    final gesture =
        await tester.startGesture(margin, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await gesture.moveTo(at(text.indexOf('pana')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    return selected?.plainText ?? '';
  }

  testWidgets('without the fix, the paragraph above is taken too',
      (tester) async {
    final text = await dragFromMargin(tester, false);
    expect(text.startsWith('atha kho'), isTrue, reason: text);
  });

  testWidgets('begun in the margin, the selection starts at the line',
      (tester) async {
    final text = await dragFromMargin(tester, true);
    expect(text.startsWith('tena kho'), isTrue, reason: text);
  });
}
