import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/ui/widgets/copy_formatted_menu.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    Prefs.instance = await SharedPreferences.getInstance();
  });

  Future<(int, int)> pressCopy(WidgetTester tester) async {
    var formatted = 0;
    var plain = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CopyFormattedShortcuts(
          selectedText: () => 'evaṃ me sutaṃ',
          onCopy: (_) => formatted++,
          onCopyPlain: (_) => plain++,
          child: const SelectionArea(child: Text('evaṃ me sutaṃ')),
        ),
      ),
    ));
    final text = find.byType(Text);
    final drag = await tester.startGesture(
        tester.getTopLeft(text) + const Offset(1, 5),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    await drag.moveTo(tester.getTopRight(text) + const Offset(-1, 5));
    await drag.up();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    return (formatted, plain);
  }

  testWidgets('the copy shortcut copies formatted by default', (tester) async {
    expect(Prefs.copyFormatted, isTrue);
    expect(await pressCopy(tester), (1, 0));
  });

  testWidgets('and plain text when the reader chose that', (tester) async {
    Prefs.copyFormatted = false;
    addTearDown(() => Prefs.copyFormatted = true);
    expect(await pressCopy(tester), (0, 1));
  });
}
