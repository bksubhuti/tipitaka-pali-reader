import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/data/page_papers.dart';
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

  /// The X-ray notice was shown since the app started: the paper offer
  /// waits for the next start rather than following straight after it.
  static bool _xrayShownNow = false;

  /// The paper offer was shown since the app started: the font notice
  /// waits for the next start in turn.
  static bool _paperShownNow = false;

  /// Shows the notice [_delay] after a book opens, until it has been seen.
  /// [readerContext] is the open book's; [stillOpen] says whether it is.
  static void scheduleFor(
      BuildContext readerContext, bool Function() stillOpen) {
    if (Prefs.xrayNoticeShown) {
      _schedulePaperOffer(readerContext, stillOpen);
      return;
    }
    if (_waiting) return;
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
      _xrayShownNow = true;
      final turnOff = await showDialog<bool>(
        context: readerContext,
        builder: (context) => const XrayNoticeDialog(),
      );
      if (turnOff == true && readerContext.mounted) {
        readerContext.read<ThemeChangeNotifier>().onChangeXray(false);
      }
    });
  }

  /// Once the X-ray notice has been seen, at a later start, the paper pages
  /// are offered once: few find them, under the middle of the three page
  /// colours. Yes puts the page on aged parchment.
  static void _schedulePaperOffer(
      BuildContext readerContext, bool Function() stillOpen) {
    if (Prefs.paperOfferShown) {
      _scheduleFontNotice(readerContext, stillOpen);
      return;
    }
    if (_xrayShownNow || _waiting) return;
    _waiting = true;
    Future.delayed(_delay, () async {
      _waiting = false;
      if (!stillOpen() || !readerContext.mounted) return;
      if (Prefs.paperOfferShown) return;
      Prefs.paperOfferShown = true;
      // On a paper already: they have found them.
      if (Prefs.selectedPageTheme == PageTheme.medium &&
          Prefs.pagePaper != 0) {
        return;
      }
      _paperShownNow = true;
      final tryIt = await showDialog<bool>(
        context: readerContext,
        builder: (context) => const PaperOfferDialog(),
      );
      if (tryIt == true && readerContext.mounted) {
        final theme = readerContext.read<ThemeChangeNotifier>();
        theme.onChangePagePaper(pagePapers.indexOf(agedParchment));
        theme.toggleTheme(PageTheme.medium);
      }
    });
  }

  /// After the paper offer, at a later start, the two TPR Indic Roman
  /// fonts are made known once. Only to a reader of Roman script, as the
  /// fonts are only for it, and not to one using either already. Nothing
  /// is changed: the notice only says where they are.
  static void _scheduleFontNotice(
      BuildContext readerContext, bool Function() stillOpen) {
    if (Prefs.fontNoticeShown || _xrayShownNow || _paperShownNow || _waiting) {
      return;
    }
    if (Prefs.currentScriptLanguage != defaultScriptLanguage) return;
    _waiting = true;
    Future.delayed(_delay, () async {
      _waiting = false;
      if (!stillOpen() || !readerContext.mounted) return;
      if (Prefs.fontNoticeShown) return;
      Prefs.fontNoticeShown = true;
      if (FontNoticeDialog.fonts.contains(Prefs.romanFontName)) return;
      await showDialog<void>(
        context: readerContext,
        builder: (context) => const FontNoticeDialog(),
      );
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

/// The offer of a paper page. Pops true to try aged parchment.
class PaperOfferDialog extends StatelessWidget {
  const PaperOfferDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l.paperOfferTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.paperOfferMessage),
              const SizedBox(height: 16),
              // Where the buttons are, as Settings › Theme shows them.
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset('assets/images/paper_settings.png'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.paperOfferNo),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.paperOfferTry),
        ),
      ],
    );
  }
}

/// Where the TPR Indic Roman fonts are, each name drawn in its own font.
class FontNoticeDialog extends StatelessWidget {
  const FontNoticeDialog({super.key});

  static const fonts = ['TPR Indic Roman', 'TPR Indic Roman Noline'];
  static const _sample = 'evaṃ me sutaṃ — ekaṃ samayaṃ bhagavā';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final style = Theme.of(context).textTheme.bodyMedium;
    return AlertDialog(
      title: Text(l.fontNoticeTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.fontNoticeMessage(l.settings, l.theme, l.font)),
              for (final font in fonts) ...[
                const SizedBox(height: 16),
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text: font,
                      style: style?.copyWith(fontFamily: font, fontSize: 22)),
                  TextSpan(
                      text: '\n$_sample',
                      style: style?.copyWith(fontFamily: font, fontSize: 18)),
                ])),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.ok),
        ),
      ],
    );
  }
}
