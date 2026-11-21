import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/ui/screens/dictionary/controller/dictionary_controller.dart';
import 'package:tipitaka_pali/utils/platform_info.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:tipitaka_pali/utils/display_utils.dart';
import 'package:tipitaka_pali/utils/dpd_pali.dart';
import 'package:tipitaka_pali/business_logic/models/dictionary_book.dart';

import '../../../../business_logic/models/dpd_compound_family.dart';
import '../../../../services/prefs.dart';

showCompoundFamilyDialog(BuildContext context, int wordId,
    {int book = 11}) async {
  var dictionaryController = context.read<DictionaryController>();
  final pali = DpdPali(context, book);
  List<DpdCompoundFamily>? compoundFamilies = await dictionaryController
      .getDpdCompoundFamilies(wordId, lang: DictionaryBook.dpdLang(book) ?? '');

  // prevent using context across asynch gaps
  if (!context.mounted) return;

  if (compoundFamilies == null || compoundFamilies.isEmpty) {
    // TODO not all words have root family, so need to show a 'install' dialog
    //  only if the root family tables do not exist

    return;
  }

  debugPrint('Compound families count: ${compoundFamilies.length}');
  if (!context.mounted) return;

  List<dynamic> jsonData = [];
  for (final compoundFamily in compoundFamilies) {
    jsonData.addAll(json.decode(compoundFamily.data));
  }

  final DpdCompoundFamily first = compoundFamilies[0];
  final count = compoundFamilies.fold(0, (sum, cf) => sum + cf.count);
  final isMobile = Mobile.isPhone(context);
  const insetPadding = 10.0;
  final word = first.word.replaceAll(RegExp(r" \d.*\$"), '');
  final compoundFamily = first.compoundFamily;

  final content = isMobile
      ? SizedBox(
          width: MediaQuery.of(context).size.width - 2 * insetPadding,
          child: _getCompoundFamilyWidget(
              count, pali(word), jsonData, compoundFamily, pali),
        )
      : Container(
          constraints: const BoxConstraints(
            maxHeight: 400,
            maxWidth: 800,
          ),
          child: _getCompoundFamilyWidget(
              count, pali(word), jsonData, compoundFamily, pali));

  showDialog(
      context: context,
      builder: (context) => AlertDialog(
            title: Text(superscripterUni(pali(first.word))),
            contentPadding: isMobile ? EdgeInsets.zero : null,
            insetPadding: isMobile ? const EdgeInsets.all(insetPadding) : null,
            content: content,
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(AppLocalizations.of(context)!.ok))
            ],
          ));
}

Scrollbar _getCompoundFamilyWidget(
    count, word, jsonData, compoundFamily, DpdPali pali) {
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _getCompoundFamilyHeader(count, compoundFamily),
                _getCompoundFamilyTable(jsonData, pali)
              ],
            )),
      ),
    ),
  );
}

SelectableText _getCompoundFamilyHeader(count, compoundFamily) {
  return SelectableText.rich(
    TextSpan(children: [
      TextSpan(
          text: '$count', style: const TextStyle(fontWeight: FontWeight.bold)),
      const TextSpan(text: ' compounds which contain '),
      TextSpan(
          text: compoundFamily,
          style: TextStyle(
              fontSize: Prefs.dictionaryFontSize.toDouble(),
              fontWeight: FontWeight.bold)),
    ]),
    textAlign: TextAlign.left,
  );
}

Table _getCompoundFamilyTable(List<dynamic> jsonData, DpdPali pali) {
  return Table(
    border: TableBorder.all(),
    defaultColumnWidth: const IntrinsicColumnWidth(),
    children: jsonData.map((item) {
      return TableRow(
        children: [
          TableCell(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: SelectableText(
                pali(item[0]),
                style: TextStyle(
                    fontSize: Prefs.dictionaryFontSize.toDouble(),
                    color: getDpdHeaderColor(),
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
          TableCell(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: SelectableText(
                item[1],
                style: TextStyle(
                    fontSize: Prefs.dictionaryFontSize.toDouble(),
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
          TableCell(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: SelectableText('${item[2]} ${item[3]}',
                  style:
                      TextStyle(fontSize: Prefs.dictionaryFontSize.toDouble())),
            ),
          ),
        ],
      );
    }).toList(),
  );
}
