import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tipitaka_pali/ui/widgets/copy_formatted_menu.dart';

void main() {
  for (final (name, key) in [
    ('Cmd+C', LogicalKeyboardKey.metaLeft),
    ('Ctrl+C', LogicalKeyboardKey.controlLeft),
  ]) {
    testWidgets('$name copies formatted, not as Flutter would', (tester) async {
      var formatted = 0;
      String? plain;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          plain = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CopyFormattedShortcuts(
            onCopy: () => formatted++,
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

      await tester.sendKeyDownEvent(key);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(key);
      await tester.pump();

      expect(formatted, 1);
      expect(plain, isNull);
    });
  }
}
