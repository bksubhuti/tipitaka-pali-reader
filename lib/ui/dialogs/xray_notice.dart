import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/provider/shown_languages_provider.dart';
import 'package:tipitaka_pali/services/provider/theme_change_notifier.dart';

/// Tells the reader, once, that X-ray is on and where to turn it off.
///
/// It comes on by default, so the links under the Pāḷi appear without having
/// been asked for. The notice waits a while after a book opens, so the reader
/// has seen the links before being asked about them, and only comes while
/// the Pāḷi is on screen, since without it there are no links to see. Until
/// then it is not counted as shown, and each book opened tries again.
class XrayNotice {
  XrayNotice._();

  static const _delay = Duration(seconds: 7);
  static bool _waiting = false;

  /// Shows the notice [_delay] after a book opens, until it has been seen.
  /// [readerContext] is the open book's; [stillOpen] says whether it is.
  static void scheduleFor(
      BuildContext readerContext, bool Function() stillOpen) {
    if (Prefs.xrayNoticeShown || _waiting) return;
    _waiting = true;
    Future.delayed(_delay, () async {
      _waiting = false;
      // The book was closed in the meantime: wait for the next one.
      if (!stillOpen() || !readerContext.mounted) return;
      if (Prefs.xrayNoticeShown) return;
      // Turned off already: they have found the switch, nothing to tell.
      if (!Prefs.xray) {
        Prefs.xrayNoticeShown = true;
        return;
      }
      // No Pāḷi on screen, so no links either: wait for a book that has it.
      if (!_paliShown(readerContext)) return;
      Prefs.xrayNoticeShown = true;
      final turnOff = await showDialog<bool>(
        context: readerContext,
        builder: (context) => const XrayNoticeDialog(),
      );
      if (turnOff == true && readerContext.mounted) {
        readerContext.read<ThemeChangeNotifier>().onChangeXray(false);
      }
    });
  }

  static bool _paliShown(BuildContext context) {
    try {
      return context.read<ShownLanguagesProvider>().paliShown;
    } catch (_) {
      return Prefs.textDisplayMode != TextDisplayMode.translationOnly;
    }
  }
}

/// The notice itself. Pops true to turn X-ray off, false to keep it.
class XrayNoticeDialog extends StatelessWidget {
  const XrayNoticeDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l.xrayViewTitle),
      // Kept to a readable width; on a wide window it ran the full width.
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Text(l.xrayNoticeMessage),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.xrayKeepOn),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.xrayTurnOff),
        ),
      ],
    );
  }
}
