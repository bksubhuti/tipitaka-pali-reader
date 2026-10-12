import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';

/// Puts the same passage on the clipboard in two forms at once, and the app
/// it is pasted into takes the one it reads: HTML, which a document, an
/// email or a word processor pastes with its formatting, and plain text,
/// which anything else pastes.
class RichClipboard {
  RichClipboard._();

  static Future<void> copy({required String html, required String text}) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard != null) {
      try {
        final item = DataWriterItem()
          ..add(Formats.htmlText(html))
          ..add(Formats.plainText(text));
        await clipboard.write([item]);
        return;
      } catch (_) {
        // Copied as plain text below.
      }
    }
    await Clipboard.setData(ClipboardData(text: text));
  }
}
