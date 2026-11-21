import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:tipitaka_pali/utils/dpd_pali.dart';
import 'package:tipitaka_pali/utils/pali_script_converter.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/business_logic/models/dpd_inflection.dart';
import 'package:tipitaka_pali/routes.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/ui/screens/dictionary/controller/dictionary_controller.dart';
import 'package:tipitaka_pali/ui/screens/settings/download_view.dart';
import 'package:tipitaka_pali/utils/platform_info.dart';
import 'package:tipitaka_pali/utils/display_utils.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';

showDeclensionDialog(BuildContext context, int wordId, {int book = 11}) async {
  final pali = DpdPali(context, book);
  var dictionaryController = context.read<DictionaryController>();
  DpdInflection? inflection =
      await dictionaryController.getDpdInflection(wordId);

  // Prevent using context across async gaps
  if (!context.mounted) return;

  // Handle case where no inflection data is found
  if (inflection == null) {
    bool? shouldNavigate = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.inflectionNoDataTitle),
        content: Text(AppLocalizations.of(context)!.inflectionNoDataMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocalizations.of(context)!.close),
          ),
        ],
      ),
    );

    if (shouldNavigate == true) {
      if (!context.mounted) return;
      final route =
          MaterialPageRoute(builder: (context) => const DownloadView());
      NestedNavigationHelper.goto(
          context: context, route: route, navkey: dictionaryNavigationKey);
    }

    return;
  }

  debugPrint('Inflection: $inflection');

  String data = await DefaultAssetBundle.of(context)
      .loadString("assets/inflectionTemplates.json");
  List inflectionTemplates = jsonDecode(data);
  final template = inflectionTemplates
      .firstWhereOrNull((map) => map['pattern'] == inflection.pattern);

  if (template == null) {
    debugPrint('Could not find template...');
    return;
  }

  debugPrint('Template: $template');

  // Prepare the table rows from the template data
  List<TableRow> rows =
      template['data'].asMap().entries.map<TableRow>((rowEntry) {
    int rowIndex = rowEntry.key;
    List<List<String>> row = (rowEntry.value as List)
        .map((e) => (e as List).map((item) => item as String).toList())
        .toList();

    final stem = inflection.stem.replaceAll(RegExp(r'[!*]'), '');
    return TableRow(
      children: row
          .asMap()
          .entries
          .map<Padding?>((entry) {
            int colIndex = entry.key;
            List<String> cell = entry.value;
            if (colIndex == 0) {
              return Padding(
                padding: EdgeInsets.all(8.0),
                child: SelectableText(cell[0],
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: getDpdHeaderColor())),
              );
            }
            if (colIndex % 2 != 1) {
              return null;
            }
            List<InlineSpan> spans = [];

            cell.asMap().forEach((index, value) {
              if (index > 0) {
                spans.add(const TextSpan(text: '\n'));
              }
              if (rowIndex == 0) {
                spans.add(TextSpan(
                    text: value,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: getDpdHeaderColor())));
              } else if (value.isNotEmpty && pali.script != Script.roman) {
                // In another script the stem and ending are converted as one
                // word: apart, a letter split between them came out wrong.
                spans.add(TextSpan(
                    text: pali(stem + value),
                    style: TextStyle(
                        fontSize: Prefs.dictionaryFontSize.toDouble(),
                        fontWeight: FontWeight.bold)));
              } else if (value.isNotEmpty) {
                spans.add(TextSpan(
                    text: stem,
                    style: TextStyle(
                        fontSize: Prefs.dictionaryFontSize.toDouble())));
                spans.add(TextSpan(
                    text: value,
                    style: TextStyle(
                        fontSize: Prefs.dictionaryFontSize.toDouble(),
                        fontWeight: FontWeight.bold)));
              }
            });

            return Padding(
              padding: const EdgeInsets.all(8.0),
              child: SelectableText.rich(TextSpan(children: spans)),
            );
          })
          .where((cell) => cell != null)
          .cast<Padding>()
          .toList(),
    );
  }).toList();

  if (!context.mounted) return;

  final isMobile = Mobile.isPhone(context);
  const insetPadding = 10.0;

  final content = isMobile
      ? SizedBox(
          width: MediaQuery.of(context).size.width - 2 * insetPadding,
          child: _getInflectionWidget(rows),
        )
      : Container(
          constraints: const BoxConstraints(
            maxHeight: 400,
            maxWidth: 800,
          ),
          child: _getInflectionWidget(rows),
        );

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(superscripterUni(pali(inflection.word))),
      contentPadding: isMobile ? EdgeInsets.zero : null,
      insetPadding: isMobile ? const EdgeInsets.all(insetPadding) : null,
      content: content,
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.ok)),
      ],
    ),
  );
}

Scrollbar _getInflectionWidget(List<TableRow> rows) {
  final horizontal = ScrollController();
  final vertical = ScrollController();

  return Scrollbar(
    controller: vertical,
    thumbVisibility: true,
    trackVisibility: true,
    child: Scrollbar(
      controller: horizontal,
      thumbVisibility: true,
      trackVisibility: true,
      notificationPredicate: (notification) => notification.depth == 1,
      child: SingleChildScrollView(
        controller: vertical,
        child: SingleChildScrollView(
          controller: horizontal,
          scrollDirection: Axis.horizontal,
          child: Table(
            border: TableBorder.all(),
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: rows,
          ),
        ),
      ),
    ),
  );
}
