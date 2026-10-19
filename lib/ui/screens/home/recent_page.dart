import 'package:flutter/material.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/utils/font_utils.dart';
import 'package:tipitaka_pali/utils/pali_script_converter.dart';

import '../../../../services/provider/script_language_provider.dart';
import '../../../../utils/pali_script.dart';
import '../../../business_logic/view_models/recent_page_view_model.dart';
import '../../../services/dao/recent_dao.dart';
import '../../../services/database/database_helper.dart';
import '../../../services/prefs.dart';
import '../../../services/repositories/recent_repo.dart';
import '../../../services/repositories/heading_trail_repo.dart';
import '../../dialogs/confirm_dialog.dart';

class RecentPage extends StatelessWidget {
  const RecentPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RecentPageViewModel>(
      create: (_) => RecentPageViewModel(
          RecentDatabaseRepository(DatabaseHelper(), RecentDao()))
        ..fetchRecents(),
      child: Scaffold(
        appBar: const RecentAppBar(),
        // Rydmike proposal: Consider converting the Drawer on Home screen
        //    to a Widget and add it also to other top level screens.
        // drawer: Mobile.isPhone(context) ? AppDrawer(context) : null,
        body: Consumer<RecentPageViewModel>(builder: (context, vm, child) {
          final recents = vm.recents;
          Script script = context.read<ScriptLanguageProvider>().currentScript;

          return recents.isEmpty
              ? Center(child: Text(AppLocalizations.of(context)!.recent))
              : ListView.separated(
                  itemCount: recents.length,
                  itemBuilder: (context, index) {
                    final recent = recents[index];
                    return ListTile(
                      dense: true,
                      // The text 16 in from the left, as the title above it
                      // is; the trash button's own 8 makes its icon 16 in
                      // from the right.
                      contentPadding: const EdgeInsets.only(left: 16, right: 8),
                      visualDensity:
                          const VisualDensity(horizontal: 0, vertical: -4),
                      title: Text(localScript(context, "${recent.bookName}"),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: Prefs.uiFontSize - 1,
                            fontFamily: FontUtils.getfontName(script: script),
                          )),
                      // "Page" is a word of the app's, so in the UI font;
                      // the heading it is under is Pāḷi, in the Pāḷi font.
                      subtitle: FutureBuilder<String?>(
                        future: HeadingTrailRepository(DatabaseHelper())
                            .lineAtPage(recent.bookID, recent.pageNumber),
                        builder: (context, heading) => Text.rich(
                          TextSpan(children: [
                            TextSpan(
                                text:
                                    "${AppLocalizations.of(context)!.page}: ${localScript(context, recent.pageNumber.toString())}"),
                            if (heading.data != null)
                              TextSpan(
                                  text:
                                      ' · ${localScript(context, heading.data!)}',
                                  style: TextStyle(
                                      fontFamily: FontUtils.getfontName(
                                          script: script))),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: Prefs.uiFontSize - 3),
                        ),
                      ),
                      onTap: () => vm.openBook(recent, context),
                      trailing: IconButton(
                        onPressed: () => vm.delete(recent),
                        icon: const Icon(Icons.delete),
                      ),
                    );
                  },
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                );
        }),
      ),
    );
  }

  String localScript(BuildContext context, String s) {
    return PaliScript.getScriptOf(
        script: context.read<ScriptLanguageProvider>().currentScript,
        romanText: s);
  }
}

class RecentAppBar extends StatelessWidget implements PreferredSizeWidget {
  const RecentAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(AppLocalizations.of(context)!.recent),
      // Rydmike: Consider not having implicit back, as it will give idea that
      //  user can go back, but back leads out of app in this case.
      automaticallyImplyLeading: false,
      // The clear-all trash in line with the trash on each row below.
      actionsPadding: const EdgeInsets.only(right: 4),
      actions: [
        IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              final action = await _getConfirmataion(context);
              if (action == OkCancelAction.ok) {
                context.read<RecentPageViewModel>().deleteAll();
              }
            })
      ],
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(AppBar().preferredSize.height);

  Future<OkCancelAction?> _getConfirmataion(BuildContext context) async {
    return await showDialog<OkCancelAction>(
        context: context,
        builder: (context) {
          return ConfirmDialog(
            title: AppLocalizations.of(context)!.confirmation,
            message: AppLocalizations.of(context)!.areSureDelete,
            okLabel: AppLocalizations.of(context)!.delete,
            cancelLabel: AppLocalizations.of(context)!.cancel,
          );
        });
  }
}
