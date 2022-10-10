import 'package:flutter/material.dart';
import 'package:tipitaka_pali/utils/pali_script_converter.dart';

import '../../../../utils/pali_tools.dart';
import '../../../../utils/script_detector.dart';

class SearchBar extends StatefulWidget {
  final TextEditingController controller;
  final void Function(String) onSubmitted;
  final void Function(String) onTextChanged;
  final String hint;
  const SearchBar({
    Key? key,
    required this.controller,
    required this.onSubmitted,
    required this.onTextChanged,
    this.hint = 'search',
  }) : super(key: key);

  @override
  State<SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<SearchBar> {
  _SearchBarState();

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
    return Container(
      margin: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32.0),
        border: Border.all(color: Colors.grey),
      ),
      height: 56.0,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              autocorrect: false,
              controller: widget.controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (text) => widget.onSubmitted(text),
              onChanged: (text) {
                final scriptLanguage = ScriptDetector.getLanguage(text);
                //if (scriptLanguage == Script.roman) text = _toUni(text);

                if (text.isNotEmpty && scriptLanguage == Script.roman) {
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
                border: InputBorder.none,
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
              ),
            ),
          ),
          const SizedBox(width: 4.0)
        ],
      ),
    );
  }

  String _toUni(String input) {
    input = PaliTools.velthuisToUni(velthiusInput: input);

    widget.controller.text = input;
    widget.controller.selection = TextSelection.fromPosition(
        TextPosition(offset: widget.controller.text.length));

    return input;
  }
}

class ClearButton extends StatelessWidget {
  const ClearButton({Key? key, this.onTap}) : super(key: key);
  final GestureTapCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: const Icon(Icons.clear, color: Colors.grey),
    );
  }
}
