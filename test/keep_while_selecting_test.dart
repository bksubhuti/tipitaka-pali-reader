import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:tipitaka_pali/ui/widgets/keep_while_selecting.dart';

/// Drags a selection from the top of a list of blocks to below its bottom
/// edge and holds it there while the list scrolls, as a reader does to select
/// a long passage, and gives the text selected.
Future<String> _selectByDragging(WidgetTester tester,
    {required bool keep}) async {
  tester.view.physicalSize = const Size(700, 500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  var selected = '';
  final selecting = ValueNotifier(false);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SelectionArea(
        onSelectionChanged: (content) {
          selected = content?.plainText ?? '';
          selecting.value = keep && selected.isNotEmpty;
        },
        child: ScrollablePositionedList.builder(
          addAutomaticKeepAlives: keep,
          itemCount: 6,
          itemBuilder: (_, block) => KeepWhileSelecting(
            selecting: selecting,
            child: Column(children: [
              for (var line = 0; line < 30; line++)
                Text('B${block}L$line evaṃ me sutaṃ'),
            ]),
          ),
        ),
      ),
    ),
  ));

  final drag = await tester.startGesture(
      tester.getTopLeft(find.byType(RichText).first) + const Offset(2, 5),
      kind: PointerDeviceKind.mouse);
  await tester.pump();
  await drag.moveTo(const Offset(300, 200));
  for (var frame = 0; frame < 1500; frame++) {
    await drag.moveTo(Offset(300, 560 + (frame % 2).toDouble()));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await drag.up();
  await tester.pump();
  return selected;
}

void main() {
  testWidgets('a long selection keeps the blocks it was dragged through',
      (tester) async {
    final selected = await _selectByDragging(tester, keep: true);
    expect(selected, contains('B5L29'), reason: 'dragged to the end');
    for (var block = 0; block < 6; block++) {
      for (var line = 0; line < 30; line++) {
        expect(selected, contains('B${block}L$line '));
      }
    }
  });

  testWidgets('without it, the blocks between are lost', (tester) async {
    final selected = await _selectByDragging(tester, keep: false);
    expect(selected, contains('B0L0 '));
    expect(selected, contains('B5L29'));
    expect(selected, isNot(contains('B2L0 ')));
  });
}
