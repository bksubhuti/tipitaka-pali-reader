import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tipitaka_pali/utils/platform_info.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:tipitaka_pali/services/prefs.dart';

/// Copying in the reader: the menu of selected text has "Copy Plain Text"
/// and "Copy Formatted", and Cmd+C or Ctrl+C copies whichever the reader
/// has chosen with the switch in the bar that follows, formatted unless
/// they say otherwise.

/// The menu's own buttons, with Copy as "Copy Plain Text" and "Copy
/// Formatted" beside it, the way Cmd+C or Ctrl+C copies first.
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
    void copyPlain(String text) => onCopyPlain != null
        ? onCopyPlain(text)
        : Clipboard.setData(ClipboardData(text: text));
    // After either, the bar saying which it was, with the switch: on a phone,
    // with no Ctrl+C, the only place to choose which comes first.
    void copy(bool formatted) {
      // Read before the menu closes, which can clear the selection.
      final text = selectedText();
      final copyFormatted = onCopyFormatted;
      if (formatted && copyFormatted != null) {
        copyFormatted(text);
      } else {
        copyPlain(text);
      }
      if (copyFormatted != null) {
        showCopyModeBar(context,
            text: text,
            formatted: formatted,
            copyFormatted: copyFormatted,
            copyPlain: copyPlain);
      }
      ContextMenuController.removeAny();
    }

    final plain = item.copyWith(
        label: AppLocalizations.of(context)!.copyPlainText,
        onPressed: () => copy(false));
    final formatted = ContextMenuButtonItem(
      label: AppLocalizations.of(context)!.copyFormatted,
      onPressed: () => copy(true),
    );
    items.addAll(Prefs.copyFormatted ? [formatted, plain] : [plain, formatted]);
  }
  return items;
}

class _CopyFormattedIntent extends Intent {
  const _CopyFormattedIntent();
}

/// Cmd+C and Ctrl+C in [child] copy the selected text formatted, or as
/// plain text when the reader has turned [Prefs.copyFormatted] off. Closer
/// to the selection than the app's own copy shortcut, so they are taken
/// first.
class CopyFormattedShortcuts extends StatelessWidget {
  const CopyFormattedShortcuts(
      {super.key,
      required this.selectedText,
      required this.onCopy,
      this.onCopyPlain,
      this.onRightClick,
      required this.child});

  /// The text selected now. Read when the keys are pressed and kept, so it
  /// can be copied again from the bar after the selection has gone.
  final String Function() selectedText;
  final ValueChanged<String> onCopy;
  final ValueChanged<String>? onCopyPlain;

  /// Shows the menu at a right click, given while text is selected.
  ///
  /// Taken here, ahead of the selection area. On a right click it first
  /// selects the word under the pointer, going through every paragraph of
  /// the selection to find it, and with a long selection, part of it
  /// scrolled away, that went wrong and no menu came at all. Copying a long
  /// passage needed the menu. The selection is kept as it is, as the
  /// computer's own text does, and the menu shown for it.
  final ValueChanged<Offset>? onRightClick;
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
              final text = selectedText();
              // Nothing selected: nothing copied, and no bar saying it was.
              if (text.trim().isEmpty) return null;
              final plain = onCopyPlain;
              final formatted = plain == null || Prefs.copyFormatted;
              (formatted ? onCopy : plain)(text);
              if (plain != null) {
                showCopyModeBar(context,
                    text: text,
                    formatted: formatted,
                    copyFormatted: onCopy,
                    copyPlain: plain);
              }
              return null;
            },
          ),
        },
        child: onRightClick == null
            ? child
            : RawGestureDetector(
                gestures: {
                  _RightClickOnSelection: GestureRecognizerFactoryWithHandlers<
                      _RightClickOnSelection>(
                    _RightClickOnSelection.new,
                    (recognizer) => recognizer
                      ..claims = (() => selectedText().isNotEmpty)
                      ..onRightClick = onRightClick,
                  ),
                },
                child: child,
              ),
      ),
    );
  }
}

/// A right click while text is selected, claimed before the selection area
/// can take it; see [CopyFormattedShortcuts.onRightClick].
class _RightClickOnSelection extends OneSequenceGestureRecognizer {
  bool Function() claims = () => false;
  ValueChanged<Offset>? onRightClick;
  Offset? _at;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      event.buttons == kSecondaryMouseButton &&
      claims() &&
      super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _at = event.position;
    resolve(GestureDisposition.accepted);
  }

  @override
  void acceptGesture(int pointer) {
    super.acceptGesture(pointer);
    final at = _at;
    if (at != null) onRightClick?.call(at);
    _at = null;
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'right click on a selection';
}

/// After a copy, a bar saying which way [text] was copied, [formatted] or
/// plain, with a switch to change it. The switch is the one place the way
/// is set: it decides what Cmd+C or Ctrl+C copies and which comes first in
/// the menu. Changing it copies [text] again the new way, so what is on the
/// clipboard is what the bar says.
/// Where a message after a copy is shown. On a phone or tablet, at the
/// top, under the tabs: Android shows its own preview of what was copied,
/// with Share and the like, along the bottom, over the message. Swiped up
/// to go. On a computer, at the bottom as usual.
class AfterCopyPlacement {
  const AfterCopyPlacement._(this.behavior, this.dismissDirection, this.margin);

  final SnackBarBehavior? behavior;
  final DismissDirection? dismissDirection;
  final EdgeInsetsGeometry? margin;

  /// Room for a message of a line or two.
  static const double _height = 72;

  factory AfterCopyPlacement.of(BuildContext context) {
    if (PlatformInfo.isDesktop) {
      return const AfterCopyPlacement._(null, null, null);
    }
    final media = MediaQuery.of(context);
    final fromBottom =
        media.size.height - media.padding.top - kToolbarHeight - _height;
    return AfterCopyPlacement._(SnackBarBehavior.floating, DismissDirection.up,
        EdgeInsets.fromLTRB(12, 0, 12, max(12, fromBottom)));
  }
}

void showCopyModeBar(
  BuildContext context, {
  required String text,
  required bool formatted,
  required ValueChanged<String> copyFormatted,
  required ValueChanged<String> copyPlain,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = AppLocalizations.of(context);
  if (messenger == null || l10n == null) return;
  final colors = Theme.of(context).colorScheme;
  final afterCopy = AfterCopyPlacement.of(context);
  final onBar = TextStyle(color: colors.onPrimaryContainer);
  var on = formatted;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      // The theme's colours, so it reads in light and dark alike.
      backgroundColor: colors.primaryContainer,
      duration: const Duration(seconds: 6),
      behavior: afterCopy.behavior,
      dismissDirection: afterCopy.dismissDirection,
      margin: afterCopy.margin,
      content: StatefulBuilder(
        // The message, and the switch at the end where a button would be.
        builder: (context, setBarState) => Row(
          children: [
            Expanded(
              child: Text(on ? l10n.copiedFormatted : l10n.copiedPlain,
                  style: onBar),
            ),
            Text(l10n.copyFormatted, style: onBar),
            Switch(
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              value: on,
              onChanged: (value) {
                setBarState(() => on = Prefs.copyFormatted = value);
                (value ? copyFormatted : copyPlain)(text);
              },
            ),
          ],
        ),
      ),
    ));
}
