import 'package:flutter/material.dart';
import 'package:toggle_switch/toggle_switch.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';

enum GotoType { page, paragraph }

class GotoDialogResult {
  final int number;
  final GotoType type;
  GotoDialogResult(this.number, this.type);
}

class GotoDialog extends StatefulWidget {
  final int firstPage;
  final int lastPage;
  final int firstParagraph;
  final int lastParagraph;
  final double radius;

  const GotoDialog(
      {super.key,
      required this.firstPage,
      required this.lastPage,
      required this.firstParagraph,
      required this.lastParagraph,
      this.radius = 16.0});

  @override
  State<GotoDialog> createState() => _GotoDialogState();
}

class _GotoDialogState extends State<GotoDialog> {
  TextEditingController controller = TextEditingController();
  GotoType selectedType = GotoType.page;
  int? selectedTypeIndex;
  String? hintText;
  bool isValid = false;

  _GotoDialogState();

  @override
  void initState() {
    super.initState();
    hintText = 'page (${widget.firstPage}-${widget.lastPage})';
    selectedTypeIndex = 0;
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: SingleChildScrollView(
        child: Dialog(
          shape: RoundedRectangleBorder(
              side: BorderSide.none,
              borderRadius: BorderRadius.circular(widget.radius)),
          elevation: 10.0,
          child: dialogContent(),
        ),
      ),
    );
  }

  Widget dialogContent() {
    return SizedBox(
      width: 300,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _buildTitle(),
          const Divider(),
          _buildInputType(context),
          _buildInputField(),
          _buildActions(context)
        ],
      ),
    );
  }

  Padding _buildTitle() {
    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: Text(
        AppLocalizations.of(context)!.goto,
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
  }

  ToggleSwitch _buildInputType(BuildContext context) {
    return ToggleSwitch(
      totalSwitches: 2,
      labels: [
        AppLocalizations.of(context)!.page,
        AppLocalizations.of(context)!.paragraph
      ],
      initialLabelIndex: selectedTypeIndex!,
      onToggle: (index) {
        setState(() {
          selectedTypeIndex = index;
          if (index == 0) {
            selectedType = GotoType.page;
            hintText = 'page (${widget.firstPage}-${widget.lastPage})';
          } else {
            selectedType = GotoType.paragraph;
            hintText =
                'paragraph (${widget.firstParagraph}-${widget.lastParagraph})';
          }
        });
      },
      // activeBgColor: Theme.of(context).accentColor,
      minWidth: 100.0,
    );
  }

  Padding _buildInputField() {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, right: 16.0),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(hintText: hintText),
        onChanged: _validate,
        onSubmitted: (value) {
          if (_isValid(value)) {
            final result =
                GotoDialogResult(int.parse(controller.text), selectedType);
            Navigator.pop(context, result);
          }
        },
        keyboardType: TextInputType.number,
        autofocus: true,
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return ButtonBar(
      alignment: MainAxisAlignment.spaceEvenly,
      buttonTextTheme: ButtonTextTheme.accent,
      buttonMinWidth: 120.0,
      children: [
        TextButton(
          child: Text(
            AppLocalizations.of(context)!.cancel,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        TextButton(
            onPressed: !isValid
                ? null
                : () {
                    final result = GotoDialogResult(
                        int.parse(controller.text), selectedType);
                    Navigator.pop(context, result);
                  },
            child: Text(
              AppLocalizations.of(context)!.go,
            )),
      ],
    );
  }

  bool _isValid(String input) {
    if (input.isEmpty) return false;

    bool isValid = false;
    final inputNumber = int.parse(input);
    switch (selectedType) {
      case GotoType.page:
        isValid = _isPageNumberValid(inputNumber);
        break;
      case GotoType.paragraph:
        isValid = _isParagraphNumberValid(inputNumber);
        break;
    }
    return isValid;
  }

  void _validate(String input) {
    setState(() {
      isValid = _isValid(input);
    });
  }

  bool _isPageNumberValid(int pageNumber) {
    return widget.firstPage <= pageNumber && pageNumber <= widget.lastPage;
  }

  bool _isParagraphNumberValid(int paragraphNumber) {
    return widget.firstParagraph <= paragraphNumber &&
        paragraphNumber <= widget.lastParagraph;
  }
}
