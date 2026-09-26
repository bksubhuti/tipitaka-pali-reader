import 'dart:async';
import 'dart:io';

import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../services/database/database_helper.dart';
import '../../../services/prefs.dart';
import '../../../utils/platform_info.dart';
import '../language_choice.dart';
import 'desktop_home_view.dart';
import 'mobile_navigation_bar.dart';
import 'navigation_pane.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerTranslation());
  }

  Future<void> _offerTranslation() async {
    if (!DatabaseHelper.sentenceDataAvailable) return;
    if (DatabaseHelper.installedLanguages.isNotEmpty) return;
    if (Prefs.languageChoiceMade) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LanguageChoiceScreen()),
    );
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
                    body: PlatformInfo.isDesktop || Mobile.isTablet(context)
                        ? const DesktopHomeView()
                        : const DetailNavigationPane(
                            navigationCount: 5,
                          ),
                    bottomNavigationBar:
                        !(PlatformInfo.isDesktop || Mobile.isTablet(context))
                            ? const MobileNavigationBar()
                            : null);
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
