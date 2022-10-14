import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/ui/widgets/colored_text.dart';

import '../../../business_logic/view_models/script_settings_view_model.dart';
import 'select_script_language.dart';

class ScriptSettingView extends StatelessWidget {
  const ScriptSettingView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ScriptSettingController>(
        create: (_) => ScriptSettingController(),
        child: Consumer<ScriptSettingController>(
          builder: (context, controller, child) {
            return Card(
              elevation: 8,
              child: ExpansionTile(
                leading: const Icon(Icons.font_download_outlined),
                title: Text(AppLocalizations.of(context)!.paliScript,
                    style: Theme.of(context).textTheme.headline6),
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 32.0),
                    child: ListTile(
                      title: Text(AppLocalizations.of(context)!.scriptLanguage),
                      trailing: SelectScriptLanguageWidget(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 32.0),
                    child: ListTile(
                      title:
                          Text(AppLocalizations.of(context)!.showAlternatePali),
                      trailing: Switch(
                        onChanged: (value) => context
                            .read<ScriptSettingController>()
                            .onToggleShowAlternatePali(value),
                        value: context
                            .read<ScriptSettingController>()
                            .isShowAlternatePali,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 32.0),
                    child: ListTile(
                      title:
                          Text(AppLocalizations.of(context)!.showPTSPageNumber),
                      trailing: Switch(
                        onChanged: (value) => context
                            .read<ScriptSettingController>()
                            .onToggleShowPtsNumber(value),
                        value: context
                            .read<ScriptSettingController>()
                            .isShowPtsNumber,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 32.0),
                    child: ListTile(
                      title: Text(
                          AppLocalizations.of(context)!.showThaiPageNumber),
                      trailing: Switch(
                        onChanged: (value) => context
                            .read<ScriptSettingController>()
                            .onToggleShowThaiNumber(value),
                        value: context
                            .read<ScriptSettingController>()
                            .isShowThaiNumber,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 32.0),
                    child: ListTile(
                      title:
                          Text(AppLocalizations.of(context)!.showVRIPageNumber),
                      trailing: Switch(
                        onChanged: (value) => context
                            .read<ScriptSettingController>()
                            .onToggleShowVriNumber(value),
                        value: context
                            .read<ScriptSettingController>()
                            .isShowVriNumber,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ));
  }
}
