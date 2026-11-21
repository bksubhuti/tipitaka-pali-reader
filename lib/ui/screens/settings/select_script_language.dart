import 'package:tipitaka_pali/ui/dialogs/dpd_language_offer.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/utils/pali_script_converter.dart';

import '../../../services/provider/script_language_provider.dart';
import '../../widgets/colored_text.dart';

class SelectScriptLanguageWidget extends StatelessWidget {
  const SelectScriptLanguageWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final scriptLanguageProvider = context.watch<ScriptLanguageProvider>();
    return DropdownButton<ScriptInfo>(
        value: scriptLanguageProvider.currentScriptInfo,
        // style: TextStyle(color: Theme.of(context).primaryColor),
        onChanged: (value) {
          scriptLanguageProvider.onLanguageChage(value);
          // DPD in this script's language, if there is one (not during the
          // first setup: the database is not there yet)
          if (Prefs.isDatabaseSaved) DpdLanguageOffer.offerIfWanted(context);
        },
        items:
            scriptLanguageProvider.languages.map<DropdownMenuItem<ScriptInfo>>(
          (ScriptInfo value) {
            return DropdownMenuItem<ScriptInfo>(
              value: value,
              child: ColoredText(
                value.nameInLocale,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Theme.of(context).primaryColor,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            );
          },
        ).toList());
  }
}
