import 'package:flutter/material.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/utils/pali_script_converter.dart';

import '../../../../utils/pali_tools.dart';
import '../../../../utils/script_detector.dart';

class TprSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final void Function(String) onSubmitted;
  final void Function(String) onTextChanged;
  final String hint;
  final bool autofocus;
  const TprSearchBar({
    super.key,
    required this.controller,
    required this.onSubmitted,
    required this.onTextChanged,
    this.hint = 'search',
    this.autofocus = false,
  });

  @override
  State<TprSearchBar> createState() => _TprSearchBarState();
}

class _TprSearchBarState extends State<TprSearchBar> {
  _TprSearchBarState();

  Color borderColor = Colors.grey;
  Color textColor = Colors.grey[350] as Color;
  TextDecoration textDecoration = TextDecoration.lineThrough;
  // TextEditingController controller = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    // controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        autofocus: widget.autofocus,
        autocorrect: false,
        controller: widget.controller,
        textInputAction: TextInputAction.search,
        maxLines: 1,
        // this cause the keyboard to endlessly pop up
        // focusNode: FocusNode()..requestFocus(),
        onSubmitted: (text) => widget.onSubmitted(text),
        onChanged: (text) {
          final scriptLanguage = ScriptDetector.getLanguage(text);
          //if (scriptLanguage == Script.roman) text = _toUni(text);

          if (text.isNotEmpty &&
              scriptLanguage == Script.roman &&
              !Prefs.disableVelthuis) {
            // text controller naturally pushes to the beginning
            // fixed to keep natural position

            // before conversion get cursor position and length
            int origTextLen = text.length;
            int pos = widget.controller.selection.start;
            final uniText = PaliTools.velthuisToUni(velthiusInput: text);
            // after conversion get length and add the difference (if any)
            int uniTextlen = uniText.length;
            widget.controller.text = uniText;
            widget.controller.selection = TextSelection.fromPosition(
                TextPosition(offset: pos + uniTextlen - origTextLen));
            text = uniText;
          }

          widget.onTextChanged(text);
        },
        decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(32),
              borderSide: const BorderSide(
                width: 1,
              ),
            ),
            prefixIcon: const Icon(Icons.search, color: Colors.grey),
            // clear button
            suffixIcon: widget.controller.text.isEmpty
                ? const SizedBox(width: 0, height: 0)
                : ClearButton(
                    onTap: () {
                      widget.controller.clear();
                      widget.onTextChanged('');
                    },
                  ),
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
      onPressed: onTap,
      icon: const Icon(Icons.clear, color: Colors.grey),
    );
  }
}
