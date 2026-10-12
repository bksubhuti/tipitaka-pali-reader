import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';

/// Copy in the reader copies with formatting: from the menu of selected
/// text, and with Cmd+C or Ctrl+C. "Copy Plain Text" is beside it in the
/// menu for the text alone.

/// The menu's own buttons, with Copy copying formatted and "Copy Plain
/// Text" after it.
List<ContextMenuButtonItem> copyButtons(
  BuildContext context,
  SelectableRegionState region,
  String Function() selectedText,
  ValueChanged<String>? onCopyFormatted,
  ValueChanged<String>? onCopyPlain,
) {
  final items = <ContextMenuButtonItem>[];
  for (final item in region.contextMenuButtonItems) {
    if (item.type != ContextMenuButtonType.copy) {
      items.add(item);
      continue;
    }
    items.add(item.copyWith(onPressed: () {
      // Read before the menu closes, which can clear the selection.
      final text = selectedText();
      ContextMenuController.removeAny();
      onCopyFormatted?.call(text);
    }));
    items.add(ContextMenuButtonItem(
      label: AppLocalizations.of(context)!.copyPlainText,
      onPressed: () {
        final text = selectedText();
        ContextMenuController.removeAny();
        if (onCopyPlain != null) {
          onCopyPlain(text);
        } else {
          Clipboard.setData(ClipboardData(text: text));
        }
      },
    ));
  }
  return items;
}

class _CopyFormattedIntent extends Intent {
  const _CopyFormattedIntent();
}

/// Cmd+C and Ctrl+C in [child] copy the selected text formatted. Closer to
/// the selection than the app's own copy shortcut, so they are taken first.
class CopyFormattedShortcuts extends StatelessWidget {
  const CopyFormattedShortcuts(
      {super.key, required this.onCopy, required this.child});

  final VoidCallback onCopy;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyC, meta: true):
            _CopyFormattedIntent(),
        SingleActivator(LogicalKeyboardKey.keyC, control: true):
            _CopyFormattedIntent(),
      },
      child: Actions(
        actions: {
          _CopyFormattedIntent: CallbackAction<_CopyFormattedIntent>(
            onInvoke: (_) {
              onCopy();
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}
