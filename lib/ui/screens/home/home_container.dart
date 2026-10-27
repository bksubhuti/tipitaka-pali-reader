import 'dart:async';
import 'dart:io';

import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../providers/font_provider.dart';
import '../../../services/database/database_helper.dart';
import '../../../services/prefs.dart';
import '../../../utils/platform_info.dart';
import '../language_choice.dart';
import 'desktop_home_view.dart';
import '../reader/mobile_reader_container.dart';
import '../reader/reader.dart';
import 'openning_books_provider.dart';

// enum Screen { Home, Bookmark, Recent, Search }

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  @override
  void initState() {
    super.initState();
    // Offer a translation once, on the first start that has the sentence data
    // to use one. First-run setup covers a fresh install; this covers an
    // existing one, which never runs that.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _offerTranslation();
      await _offerRestoreTabs();
    });
    HardwareKeyboard.instance.addHandler(_onFontSizeKey);
  }

  Orientation? _orientation;

  /// A dictionary open as the device is turned is shown again the way it
  /// is now held. Watched here, above both layouts, as a tablet turned
  /// changes from one to the other.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.orientationOf(context);
    if (_orientation != null && orientation != _orientation) {
      DictionaryPopup.onTurned(context);
    }
    _orientation = orientation;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onFontSizeKey);
    super.dispose();
  }

  /// Ctrl and + or - (Cmd on macOS) makes the reader's text larger or
  /// smaller from anywhere in the app, while a book is open.
  ///
  /// They were shortcuts on the reader itself, so they only worked once the
  /// reader had been clicked into, and on macOS they wanted Ctrl, not Cmd.
  /// Like Ctrl+F, they are taken before the focus is asked: with the focus
  /// in the dictionary, the search pane or the book list, they still go to
  /// the reader. With no book open they are left alone.
  bool _onFontSizeKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final keyboard = HardwareKeyboard.instance;
    final modifier =
        Platform.isMacOS ? keyboard.isMetaPressed : keyboard.isControlPressed;
    if (!modifier || keyboard.isAltPressed) return false;
    final key = event.logicalKey;
    final larger = key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd;
    final smaller = key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract;
    if (!larger && !smaller) return false;
    if (!mounted || context.read<OpenningBooksProvider>().books.isEmpty) {
      return false;
    }
    final fonts = context.read<ReaderFontProvider>();
    larger ? fonts.onIncreaseFontSize() : fonts.onDecreaseFontSize();
    return true;
  }

  Future<void> _offerTranslation() async {
    // The database is opened first. On a normal start the home screen is
    // built before anything has opened it, and the sentence data, attached as
    // it opens, read as missing, so the offer never came.
    await DatabaseHelper().database;
    if (!DatabaseHelper.sentenceDataAvailable) return;
    // Not skipped when a language is already on the device: a reset keeps
    // the files, and the reader is still asked, and shown which are there.
    if (Prefs.languageChoiceMade) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LanguageChoiceScreen()),
    );
  }

  /// When the reader has turned on restoring in Settings › General, and books
  /// were open when TPR last closed, asks whether to open them again, each on
  /// the page that was at the top. Not when a book is already open, as from
  /// a link that started the app.
  Future<void> _offerRestoreTabs() async {
    if (!Prefs.restoreTabs || !mounted) return;
    final saved = OpenningBooksProvider.savedTabs();
    if (saved.books.isEmpty) return;
    final openBooks = context.read<OpenningBooksProvider>();
    if (openBooks.books.isNotEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    var turnOff = false;
    final restore = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        // A switch that turns it off in the settings, for those who would
        // rather not be asked.
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            final text = Theme.of(context).textTheme;
            // A third larger than the theme's own sizes, which read too small
            // here.
            TextStyle? larger(TextStyle? style) =>
                style?.copyWith(fontSize: (style.fontSize ?? 14) * 1.3);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The question a third larger again than the switch under it.
                Text(l10n.restoreTabsQuestion(saved.books.length),
                    style: larger(larger(text.bodySmall))),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.turnOffInSettings,
                      style: larger(text.bodySmall)),
                  value: turnOff,
                  onChanged: (value) => setDialogState(() => turnOff = value),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.no)),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.open)),
        ],
      ),
    );
    if (turnOff) {
      Prefs.restoreTabs = false;
      Prefs.savedTabs = null;
    }
    if (restore != true) {
      // Declined: forget them, or the next start would ask again about the
      // same books, nothing having been opened since to replace them.
      Prefs.savedTabs = null;
      return;
    }
    if (!mounted) return;
    openBooks.restore(saved.books, saved.selected);
    if (Mobile.isPhone(context)) {
      MobileReaderContainer.show(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyW,
                meta: Platform.isMacOS ? true : false,
                control: Platform.isWindows || Platform.isLinux ? true : false):
            () => context.read<OpenningBooksProvider>().remove(),
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: FlexColorScheme.themedSystemNavigationBar(
          context,
          systemNavBarStyle: FlexSystemNavBarStyle.transparent,
          useDivider: false,
        ),
        child: Focus(
          autofocus: true,
          child: SafeArea(
            top: PlatformInfo.isDesktop || Mobile.isTablet(context),
            bottom: PlatformInfo.isDesktop || Mobile.isTablet(context),
            child: WillPopScope(
              onWillPop: () async {
                return await _onWillPop(context);
              },
              child: Builder(builder: (context) {
                return Scaffold(
                    // On a phone, the reader is the home screen: the quote
                    // of the day until a book is opened, and the rest from
                    // its ☰ panel.
                    body: PlatformInfo.isDesktop || Mobile.isTablet(context)
                        ? const DesktopHomeView()
                        : const MobileReaderContainer());
              }),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _onWillPop(BuildContext context) async {
    // 1. Detect and close the keyboard if it is open
    final currentFocus = FocusScope.of(context);
    if (!currentFocus.hasPrimaryFocus && currentFocus.focusedChild != null) {
      currentFocus.unfocus();
    }

    return (await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.confirmation),
            content: Text(AppLocalizations.of(context)!.doYouWantToLeave),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(AppLocalizations.of(context)!.no),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(AppLocalizations.of(context)!.yes),
              ),
            ],
          ),
        )) ??
        false;
  }
}
