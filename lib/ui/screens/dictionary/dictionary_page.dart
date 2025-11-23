import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/repositories/dictionary_repo.dart';
import 'package:tipitaka_pali/ui/widgets/get_velthuis_help_widget.dart';
import 'package:tipitaka_pali/providers/navigation_provider.dart';
import 'package:tipitaka_pali/utils/platform_info.dart';

import '../../../business_logic/models/dictionary_history.dart';
import '../../../services/repositories/dictionary_history_repo.dart';
import '../../widgets/colored_text.dart';
import 'controller/dictionary_controller.dart';
import 'widget/dict_algo_selector.dart';
import 'widget/dict_content_view.dart';
import 'widget/dict_search_field.dart';

class DictionaryPage extends StatefulWidget {
  const DictionaryPage({super.key});

  @override
  State<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends State<DictionaryPage>
    with AutomaticKeepAliveClientMixin {
  late final FocusNode focusNode;

  @override
  void initState() {
    super.initState();
    focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestFocus();
      context.read<NavigationProvider>().addListener(_onNavigationChanged);
    });
  }

  @override
  void dispose() {
    context.read<NavigationProvider>().removeListener(_onNavigationChanged);
    focusNode.dispose();
    super.dispose();
  }

  void _onNavigationChanged() {
    if (mounted) {
      _requestFocus();
    }
  }

  void _requestFocus() {
    final currentNavigation =
        context.read<NavigationProvider>().currentNavigation;
    if (currentNavigation == 4) {
      focusNode.requestFocus();
      if (Mobile.isPhone(context) || Mobile.isTablet(context)) {
        SystemChannels.textInput.invokeMethod('TextInput.show');
      }
    } else if (currentNavigation != 3) {
      focusNode.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return ChangeNotifierProvider<DictionaryController>(
      create: (context) => DictionaryController(
        context: context,
        dictionaryRepository: DictionaryDatabaseRepository(DatabaseHelper()),
        dictionaryHistoryRepository: DictionaryHistoryDatabaseRepository(
          dbh: DatabaseHelper(),
        ),
      )..onLoad(),
      child: Consumer<DictionaryController>(builder: (context, dc, __) {
        return RawKeyboardListener(
          focusNode: FocusNode(), // Ensure the widget has focus
          onKey: (event) => _handleKeyboardEvent(event, context, dc),

          child: Scaffold(
            extendBody: true,
            appBar: AppBar(
              leading: getVelthuisHelp(context),
              title: Text(AppLocalizations.of(context)!.dictionary),
              actions: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios),
                  tooltip: AppLocalizations.of(context)!.dictionaryPrevious,
                  onPressed: () => dc.onClickedPrevious(),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios),
                  tooltip: AppLocalizations.of(context)!.dictionaryNext,
                  onPressed: () => dc.onClickedNext(),
                ),
                IconButton(
                  icon: const Icon(Icons.history),
                  onPressed: dc.onClickedHistoryButton,
                ),
              ],
            ),
            body: Padding(
              padding: EdgeInsets.all(8),
              child: Column(children: [
                Row(
                  children: [
                    Expanded(
                        child: DictionarySearchField(
                      focusNode: focusNode,
                    )),
                    SizedBox(width: 8), // padding
                    DictionaryAlgorithmModeView(),
                  ],
                ),
                SizedBox(height: 4), // padding
                Expanded(child: DictionaryContentView()),
              ]),
            ),
          ),
        );
      }),
    );
  }

  @override
  bool get wantKeepAlive => true;
  Future<void> _showDictionaryHistoryDlg(BuildContext context) async {
    final dbService = DatabaseHelper();
    final dbDHR = DictionaryDatabaseRepository(dbService);

    return showDialog<void>(
      context: context,
      //barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: ColoredText(AppLocalizations.of(context)!.dictionaryHistory),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              physics: const ScrollPhysics(),
              child: FutureBuilder<List<DictionaryHistory>>(
                  future: dbDHR.getDictionaryHistory(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }
                    return ListView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        scrollDirection: Axis.vertical,
                        shrinkWrap: true,
                        itemCount: snapshot.data!.length,
                        itemBuilder: (context, index) {
                          final dictHistory = snapshot.data![index];
                          // String s = dictHistory.date;
                          // String sFormattedDate =
                          //     "${s.substring(6, 8)}/${s.substring(4, 6)}/${s.substring(0, 4)}";

                          return Card(
                            child: ListTile(
                              leading: ColoredText(
                                  '${index + 1}) ${dictHistory.word}'),
                              //title: ColoredText(" $sFormattedDate"),
                              onTap: () {
                                // cause a lookup
                                globalLookupWord.value =
                                    snapshot.data![index].word;
                                Navigator.of(context).pop();
                              },
                            ),
                          );
                        });
                  }),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _handleKeyboardEvent(
      RawKeyEvent event, BuildContext context, DictionaryController dc) {
    // does not seem to work for LogicalKeyboardKey.escape
    debugPrint(event.toString());
    if (event is RawKeyUpEvent && event.isAltPressed) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        dc.onClickedPrevious();
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        dc.onClickedNext();
      }
    }
  }
}
