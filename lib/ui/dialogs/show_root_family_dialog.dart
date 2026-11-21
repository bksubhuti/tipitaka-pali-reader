import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/business_logic/models/dpd_root_family.dart';
import 'package:tipitaka_pali/ui/screens/dictionary/controller/dictionary_controller.dart';
import 'package:tipitaka_pali/utils/platform_info.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:tipitaka_pali/utils/display_utils.dart';
import 'package:tipitaka_pali/utils/dpd_pali.dart';
import 'package:tipitaka_pali/business_logic/models/dictionary_book.dart';

import '../../../../services/prefs.dart';

showRootFamilyDialog(BuildContext context, int wordId, {int book = 11}) async {
  var dictionaryController = context.read<DictionaryController>();
  final pali = DpdPali(context, book);
  DpdRootFamily? rootFamily = await dictionaryController
      .getDpdRootFamily(wordId, lang: DictionaryBook.dpdLang(book) ?? '');

  // Prevent using context across async gaps
  if (!context.mounted) return;

  // Handle case where no root family data is found
  if (rootFamily == null) {
    // Optionally, you can add a dialog to handle cases where root family is not found
    return;
  }

  debugPrint('Root family: $rootFamily');

  List<dynamic> jsonData = json.decode(rootFamily.data);

  final isMobile = Mobile.isPhone(context);
  const insetPadding = 10.0;

  // Prepare the content widget with scrollbars
  final content = isMobile
      ? SizedBox(
          width: MediaQuery.of(context).size.width - 2 * insetPadding,
          child: _getRootFamilyWidget(rootFamily, jsonData, pali),
        )
      : Container(
          constraints: const BoxConstraints(
            maxHeight: 400,
            maxWidth: 800,
          ),
          child: _getRootFamilyWidget(rootFamily, jsonData, pali),
        );

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(superscripterUni(pali(rootFamily.word))),
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

Scrollbar _getRootFamilyWidget(
    DpdRootFamily rootFamily, List<dynamic> jsonData, DpdPali pali) {
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
              _getRootFamilyHeader(rootFamily, pali),
              _getRootFamilyTable(jsonData, pali),
            ],
          ),
        ),
      ),
    ),
  );
}

SelectableText _getRootFamilyHeader(DpdRootFamily rootFamily, DpdPali pali) {
  return SelectableText.rich(
    TextSpan(children: [
      TextSpan(
          text: '${rootFamily.count}',
          style: const TextStyle(fontWeight: FontWeight.bold)),
      const TextSpan(text: ' words belong to the root family '),
      TextSpan(
          text: pali(rootFamily.rootFamily),
          style: TextStyle(
              fontSize: Prefs.dictionaryFontSize.toDouble(),
              fontWeight: FontWeight.bold)),
      TextSpan(
        text: ' (${rootFamily.rootMeaning})',
      )
    ]),
    textAlign: TextAlign.left,
  );
}

Table _getRootFamilyTable(List<dynamic> jsonData, DpdPali pali) {
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
