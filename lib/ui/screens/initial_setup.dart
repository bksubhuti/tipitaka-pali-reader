import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/business_logic/view_models/initial_setup_service.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:tipitaka_pali/providers/initial_setup_notifier.dart';
import 'package:tipitaka_pali/ui/widgets/colored_text.dart';
import 'package:tipitaka_pali/ui/widgets/select_language_widget.dart';
import 'package:tipitaka_pali/ui/screens/settings/select_script_language.dart';
import '../dialogs/reset_dialog.dart';

class InitialSetup extends StatelessWidget {
  final bool isUpdateMode;

  const InitialSetup({Key? key, this.isUpdateMode = false}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final initialSetupNotifier =
        Provider.of<InitialSetupNotifier>(context, listen: false);
    final initialSetupService =
        InitialSetupService(context, initialSetupNotifier, isUpdateMode);
    initialSetupService.setUp(isUpdateMode);

    return Material(
      child: ChangeNotifierProvider.value(
        value: initialSetupNotifier,
        child: Center(
          child: _buildHomeView(context, initialSetupNotifier),
        ),
      ),
    );
  }

  Widget _buildHomeView(BuildContext context, InitialSetupNotifier notifier) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          child: Text(AppLocalizations.of(context)!.resetData),
          onPressed: () {
            doResetDialog(context);
          },
        ),
        const SizedBox(height: 20),
        const Text(
          "Set Language \nသင်၏ဘာသာစကားကိုရွေးပါ\nඔබේ භාෂාව තෝරන්න\n选择你的语言\nChọn ngôn ngữ\nभाषा चयन करें\n",
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        SelectLanguageWidget(),
        const SizedBox(height: 20),
        const SelectScriptLanguageWidget(),
        const SizedBox(height: 20),
        const CircularProgressIndicator(),
        const SizedBox(height: 10),
        isUpdateMode
            ? Text(
                AppLocalizations.of(context)!.updatingStatus,
                textAlign: TextAlign.center,
              )
            : Text(
                AppLocalizations.of(context)!.copyingStatus,
                textAlign: TextAlign.center,
              ),
        const SizedBox(height: 10),
        Consumer<InitialSetupNotifier>(
          builder: (context, notifier, child) {
            return ColoredText(notifier.status);
          },
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
