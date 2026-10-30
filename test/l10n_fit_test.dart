import 'package:flutter/cupertino.dart'
    show CupertinoLocalizations, DefaultCupertinoLocalizations;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tipitaka_pali/business_logic/models/xray_link.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:tipitaka_pali/services/language_installer.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/provider/script_language_provider.dart';
import 'package:tipitaka_pali/ui/dialogs/bookmark_cloud_transfer_dialog.dart';
import 'package:tipitaka_pali/ui/dialogs/translation_terms_dialog.dart';
import 'package:tipitaka_pali/ui/dialogs/xray_notice.dart';
import 'package:tipitaka_pali/ui/screens/reader/widgets/xray_links_view.dart';
import 'package:tipitaka_pali/ui/screens/settings/general_settings_view.dart';
import 'package:tipitaka_pali/ui/screens/settings/language_settings.dart';
import 'package:tipitaka_pali/ui/widgets/language_steps.dart';
import 'package:tipitaka_pali/unsupported_language_classes/ccp_intl.dart';

/// Every new piece of translated text, in every language, laid out at phone
/// width. An overflow anywhere fails the test, with the language named.
///
/// The test font draws every character as a square, so widths are only
/// roughly those of the real fonts (wider, for scripts with combining
/// marks). Rows that do not wrap are what this catches.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    Prefs.instance = await SharedPreferences.getInstance();
  });

  const phone = Size(320, 640);

  Widget app(Locale locale, Widget home) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ScriptLanguageProvider()),
        ],
        child: MaterialApp(
          locale: locale,
          // As the app has them, except that Chakma, which Cupertino does
          // not cover, takes Cupertino's English rather than failing the
          // test with a warning about it.
          localizationsDelegates: [
            CcpMaterialLocalizations.delegate,
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            locale.languageCode == 'ccp'
                ? const _AnyCupertinoLocalizations()
                : GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      );

  /// Lays out [body] on a page, then fails on any exception, overflow
  /// included, naming [what] and the language.
  Future<void> fitsOnPage(WidgetTester tester, Locale locale, String what,
      Widget Function(BuildContext, AppLocalizations) body) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(
      locale,
      Scaffold(
        body: Builder(
          builder: (context) => body(context, AppLocalizations.of(context)!),
        ),
      ),
    ));
    // Not pumpAndSettle: the steps' progress bar never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull,
        reason: '$what overflows in ${locale.languageCode}');
  }

  /// Opens the dialog [builder] makes, as the app does, and fails on any
  /// exception, overflow included.
  Future<void> fitsInDialog(WidgetTester tester, Locale locale, String what,
      Widget Function(BuildContext, AppLocalizations) builder) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(
      locale,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) =>
                    builder(context, AppLocalizations.of(context)!),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: '$what overflows in ${locale.languageCode}');
  }

  String backupSummary(AppLocalizations l) =>
      l.cloudBackupSummary('2026-10-13 09:30', l.folderBookmarkCount(13, 128));

  for (final locale in AppLocalizations.supportedLocales) {
    group('${locale.languageCode} fits at 320 wide', () {
      setUp(() {
        final view =
            TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
        view.physicalSize = phone;
        view.devicePixelRatio = 1.0;
      });
      tearDown(() {
        final view =
            TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
        view.resetPhysicalSize();
        view.resetDevicePixelRatio();
      });

      testWidgets('X-ray notice', (tester) async {
        await fitsInDialog(tester, locale, 'X-ray notice',
            (_, __) => const XrayNoticeDialog());
      });

      testWidgets('X-ray links and the panel footer', (tester) async {
        await fitsOnPage(
          tester,
          locale,
          'X-ray links',
          (_, __) => Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const XrayLinksView(
                  fontSize: 18,
                  links: [
                    XrayLink(word: 'evaṃ', book: 'mūla', para: 1, line: 1),
                    XrayLink(
                        word: 'bhagavā sāvatthiyaṃ viharati',
                        book: 'mūla',
                        para: 1,
                        line: 2),
                    XrayLink(word: 'jetavane', book: 'mūla', para: 1, line: 3),
                  ],
                ),
                for (final book in const [
                  'sv-a',
                  'sv-pt',
                  'mūlapaṇṇāsa-aṭṭhakathā'
                ])
                  XrayCommentFooter(
                      book: book, fontSize: 18 * 0.7, onOpen: () {}),
              ],
            ),
          ),
        );
      });

      testWidgets('cloud backup section', (tester) async {
        for (final summary in [true, false]) {
          await fitsInDialog(
            tester,
            locale,
            'Cloud backup section',
            (context, l) => AlertDialog(
              title: Text(l.transferBookmarks),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: CloudBackupSection(
                    summary: summary ? backupSummary(l) : null,
                    busy: false,
                    onBackUp: () {},
                    onRestore: summary ? () {} : null,
                    onDownloadAll: () {},
                  ),
                ),
              ),
            ),
          );
        }
      });

      testWidgets('restore confirmation', (tester) async {
        await fitsInDialog(
          tester,
          locale,
          'Restore confirmation',
          (context, l) => RestoreConfirmDialog(
            localSummary: l.folderBookmarkCount(2, 5),
            date: '2026-10-13 09:30',
            backupSummary: l.folderBookmarkCount(13, 128),
          ),
        );
      });

      testWidgets('installed language row', (tester) async {
        await fitsOnPage(
          tester,
          locale,
          'Language row',
          (context, l) => _AllLaidOut(
            children: [
              for (final (status, current, canUpdate) in [
                (l.upToDate, true, false),
                (l.updateAvailableOn('13 Oct 2026'), false, true),
                (l.versionNotRecorded, false, true),
                (l.checkingForUpdates, false, false),
              ])
                Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: LanguageRowTile(
                    index: 0,
                    name: 'Myanmar',
                    status: status,
                    current: current,
                    canUpdate: canUpdate,
                    shown: true,
                    busy: false,
                    onShownChanged: (_) {},
                    onUpdate: () {},
                    onRemove: () {},
                  ),
                ),
            ],
          ),
        );
        expect(find.text('Myanmar'), findsNWidgets(4));
        expect(find.byType(Switch), findsNWidgets(4));
      });

      testWidgets('install and removal steps', (tester) async {
        await fitsOnPage(
          tester,
          locale,
          'Language steps',
          (context, l) => _AllLaidOut(
            children: [
              Text(l.installingLanguage('English')),
              LanguageSteps(
                state: LanguageStepState(LanguageStep.install)
                  ..update(
                      LanguageStep.download, 0.42, 'Downloading English… 42%'),
              ),
              Text(l.removingLanguage('English')),
              LanguageSteps(
                state: LanguageStepState(LanguageStep.removal)
                  ..update(LanguageStep.delete, null, 'Deleting English…'),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l.translationsSourceNote),
              ),
            ],
          ),
        );
      });

      testWidgets('leave while installing or removing', (tester) async {
        for (final removing in [false, true]) {
          await fitsInDialog(
            tester,
            locale,
            'Leave dialog (removing: $removing)',
            (context, l) => LeaveInProgressDialog(
              removing: removing,
              task: removing
                  ? l.removingLanguage('English')
                  : l.installingLanguage('English'),
            ),
          );
        }
      });

      testWidgets('ePitaka terms', (tester) async {
        await fitsInDialog(tester, locale, 'Translation terms',
            (_, __) => const TranslationTermsDialog());
      });
    });
  }
}

/// Cupertino's English for any language, for Chakma, which it lacks.
class _AnyCupertinoLocalizations
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _AnyCupertinoLocalizations();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      DefaultCupertinoLocalizations.load(locale);

  @override
  bool shouldReload(_AnyCupertinoLocalizations old) => false;
}

/// A scrolling column that lays out every child, where a ListView would
/// leave those below the screen unbuilt and so untested.
class _AllLaidOut extends StatelessWidget {
  final List<Widget> children;
  const _AllLaidOut({required this.children});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
}
