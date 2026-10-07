import 'package:flutter/material.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import '../../utils/pali_script.dart';
import '../../utils/pali_script_converter.dart';

import '../../../../utils/pali_tools.dart';
import '../../../../utils/script_detector.dart';

class PaliSearchField extends StatefulWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onTextChanged;
  final String hint;
  final BorderRadius? borderRadius;
  const PaliSearchField({
    super.key,
    this.controller,
    this.onSubmitted,
    this.onTextChanged,
    this.hint = 'search',
    this.borderRadius,
  });

  @override
  State<PaliSearchField> createState() => _PaliSearchFieldState();
}

class _PaliSearchFieldState extends State<PaliSearchField> {
  _PaliSearchFieldState();

  Color borderColor = Colors.grey;
  Color textColor = Colors.grey[350] as Color;
  TextDecoration textDecoration = TextDecoration.lineThrough;
  late TextEditingController controller;
  ValueNotifier<String> inputText = ValueNotifier('');

  @override
  void initState() {
    super.initState();
    controller = widget.controller ?? TextEditingController();
    controller.addListener(() {
      inputText.value = controller.text;
    });
  }

  @override
  void dispose() {
    super.dispose();
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        autocorrect: false,
        controller: controller,
        textInputAction: TextInputAction.search,
        maxLines: 1,
        // this cause the keyboard to endlessly pop up
        // focusNode: FocusNode()..requestFocus(),
        onSubmitted: (text) {
          //if (scriptLanguage == Script.roman) text = _toUni(text);
          if (text.isEmpty) {
            return;
          }
          final script = ScriptDetector.getLanguage(text);
          if (script == Script.roman) {
            widget.onSubmitted?.call(text);
          } else {
            widget.onSubmitted?.call(
                PaliScript.getRomanScriptFrom(script: script, text: text));
          }
        },
        onChanged: (text) {
          if (text.isEmpty) {
            return widget.onTextChanged?.call('');
          }
          final script = ScriptDetector.getLanguage(text);

          if (script == Script.roman && !Prefs.disableVelthuis) {
            // text controller naturally pushes to the beginning
            // fixed to keep natural position

            // before conversion get cursor position and length
            int origTextLen = text.length;
            int pos = controller.selection.start;
            final uniText = PaliTools.velthuisToUni(velthiusInput: text);
            // after conversion get length and add the difference (if any)
            int uniTextlen = uniText.length;
            // Written back only when it changed: see TprSearchBar (#315).
            if (uniText != text) {
              controller.text = uniText;
              controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: pos + uniTextlen - origTextLen));
            }
            widget.onTextChanged?.call(uniText);
            return;
          }

          widget.onTextChanged?.call(
            PaliScript.getRomanScriptFrom(script: script, text: text),
          );
        },
        decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: widget.borderRadius ?? BorderRadius.circular(32),
              borderSide: const BorderSide(width: 1),
            ),
            prefixIcon: const Icon(Icons.search, color: Colors.grey),
            // clear button
            suffixIcon: ValueListenableBuilder(
                valueListenable: inputText,
                builder: (_, input, __) {
                  return input.isEmpty
                      ? const SizedBox(width: 0, height: 0)
                      : ClearButton(
                          onTap: () {
                            controller.clear();
                            widget.onTextChanged?.call('');
                          },
                        );
                }),
            hintStyle: const TextStyle(color: Colors.grey),
            hintText: widget.hint,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8.0)),
      ),
    );
  }
}

class ClearButton extends StatelessWidget {
  const ClearButton({super.key, this.onTap});
  final GestureTapCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: EdgeInsets.zero,
      splashRadius: 24,
      onPressed: onTap,
      icon: const Icon(Icons.clear),
    );
  }
}
