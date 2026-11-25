import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For clipboard copy
import 'package:tipitaka_pali/utils/pali_script.dart';
import 'package:tipitaka_pali/utils/pali_script_converter.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:tipitaka_pali/utils/script_detector.dart';
import 'package:tipitaka_pali/ui/dialogs/claude_extension_dialog.dart';
import 'package:tipitaka_pali/ui/dialogs/codex_extension_dialog.dart';

class TextConverterView extends StatefulWidget {
  const TextConverterView({super.key});

  @override
  TextConverterViewState createState() => TextConverterViewState();
}

class TextConverterViewState extends State<TextConverterView> {
  final TextEditingController inputController = TextEditingController();
  final TextEditingController outputController = TextEditingController();

  ScriptInfo? selectedInputScript = listOfScripts[0];
  ScriptInfo? selectedOutputScript =
      listOfScripts[2]; // Default to Roman script

  @override
  void dispose() {
    inputController.dispose();
    outputController.dispose();
    super.dispose();
  }

  void updateOutputText() {
    String? inputText = inputController.text;
    if (ClaudeExtensionDialog.available &&
        inputText.trim().toLowerCase() == ClaudeExtensionDialog.trigger) {
      inputController.clear();
      outputController.clear();
      ClaudeExtensionDialog.show(context);
      return;
    }
    if (CodexExtensionDialog.available &&
        CodexExtensionDialog.triggers
            .contains(inputText.trim().toLowerCase())) {
      inputController.clear();
      outputController.clear();
      CodexExtensionDialog.show(context);
      return;
    }
    Script inputScript = ScriptDetector.getLanguage(inputText);

    if (inputText.isNotEmpty && inputText.isNotEmpty) {
      // Convert the input text to Roman script first
      String romanScript = PaliScript.getRomanScriptFrom(
        script: inputScript,
        text: inputText,
      );

      // Then convert to the selected output script
      String convertedText = PaliScript.getScriptOf(
        script: selectedOutputScript!.script,
        romanText: romanScript,
      );

      setState(() {
        outputController.text = convertedText;
      });
    }
  }

  void copyToClipboard() {
    Clipboard.setData(ClipboardData(text: outputController.text));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.scriptConverter),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16.0),
              TextField(
                controller: inputController,
                maxLines: 5,
                onChanged: (_) => updateOutputText(),
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.inputScript,
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(AppLocalizations.of(context)!.outputScript),
                  const SizedBox(width: 16.0),
                  DropdownButton<ScriptInfo>(
                    value: selectedOutputScript,
                    onChanged: (ScriptInfo? newValue) {
                      setState(() {
                        selectedOutputScript = newValue;
                      });
                      updateOutputText();
                    },
                    items: listOfScripts.map<DropdownMenuItem<ScriptInfo>>(
                        (ScriptInfo scriptInfo) {
                      return DropdownMenuItem<ScriptInfo>(
                        value: scriptInfo,
                        child: Text(scriptInfo.nameInLocale),
                      );
                    }).toList(),
                  ),
                  const SizedBox(width: 16.0),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      copyToClipboard();
                    },
                    tooltip: AppLocalizations.of(context)!.copy,
                  ),
                ],
              ),
              const SizedBox(height: 16.0),
              TextField(
                controller: outputController,
                maxLines: 5,
                readOnly: true,
/*                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.outputScript,
                  alignLabelWithHint: true,
                ),*/
              ),
            ],
          ),
        ),
      ),
    );
  }
}
