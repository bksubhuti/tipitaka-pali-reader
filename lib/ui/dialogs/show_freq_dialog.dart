import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:tipitaka_pali/utils/dpd_pali.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/business_logic/models/freq.dart';
import 'package:tipitaka_pali/ui/screens/dictionary/controller/dictionary_controller.dart';
import 'package:tipitaka_pali/utils/display_utils.dart';
import 'package:tipitaka_pali/utils/pali_script_converter.dart';
import 'package:tipitaka_pali/utils/platform_info.dart';

import '../../utils/font_utils.dart';

double freqFontSize = 14.0;

// Define `expectedFrequencies` at the global level**
const List<Map<String, String>> expectedFrequencies = [
  {'section': 'Pārājika', 'book': 'Vinaya'},
  {'section': 'Pācittiya', 'book': 'Vinaya'},
  {'section': 'Mahāvagga', 'book': 'Vinaya'},
  {'section': 'Cūḷavagga', 'book': 'Vinaya'},
  {'section': 'Parivāra', 'book': 'Vinaya'},
  // ===========================================================================
  {'section': 'Dīgha Nikāya', 'book': 'Sutta'},
  {'section': 'Majjhima Nikāya', 'book': 'Sutta'},
  {'section': 'Saṃyutta Nikāya', 'book': 'Sutta'},
  {'section': 'Aṅguttara Nikāya', 'book': 'Sutta'},
  {'section': 'Khuddaka Nikāya 1', 'book': 'Sutta'},
  {'section': 'Khuddaka Nikāya 2', 'book': 'Sutta'},
  {'section': 'Khuddaka Nikāya 3', 'book': 'Sutta'},
  // ===========================================================================
  {'section': 'Dhammasaṅgaṇī', 'book': 'Abhidhamma'},
  {'section': 'Vibhaṅga', 'book': 'Abhidhamma'},
  {'section': 'Dhātukathā', 'book': 'Abhidhamma'},
  {'section': 'Puggalapaññatti', 'book': 'Abhidhamma'},
  {'section': 'Kathāvatthu', 'book': 'Abhidhamma'},
  {'section': 'Yamaka', 'book': 'Abhidhamma'},
  {'section': 'Paṭṭhāna', 'book': 'Abhidhamma'},
  // ===========================================================================
  {'section': 'Visuddhimagga', 'book': 'Aññā'},
  {'section': 'Leḍī Sayāḍo', 'book': 'Aññā'},
  {'section': 'Buddhavandanā', 'book': 'Aññā'},
  {'section': 'Vaṃsa', 'book': 'Aññā'},
  {'section': 'Byākaraṇa', 'book': 'Aññā'},
  {'section': 'Pucchavissajjanā', 'book': 'Aññā'},
  {'section': 'Nīti', 'book': 'Aññā'},
  {'section': 'Pakiṇṇaka', 'book': 'Aññā'},
  {'section': 'Sihaḷa', 'book': 'Aññā'},
];

void showFreqDialog(BuildContext context, int wordId, {int book = 11}) async {
  final pali = DpdPali(context, book);
  freqFontSize = 15 * 15 / MediaQuery.of(context).textScaler.scale(14);
  var dictionaryController = context.read<DictionaryController>();
  Freq? freq = await dictionaryController.getDpdFreq(wordId);

  if (!context.mounted) return;
  if (freq == null) return;

  // Parse freq_data to extract the CST frequency and grade
  List<dynamic> cstFreq = freq.freqData['CstFreq'];
  List<dynamic> cstGrad = freq.freqData['CstGrad'];

  // Adjust the data arrays using your `addDataPoints` and `makeMatRows` functions
  List<dynamic> adjustedFreq = addDataPoints(cstFreq, addSubscript: true);
  List<dynamic> adjustedGrad = addDataPoints(cstGrad);

  // Convert adjusted data to matrix rows
  List<List<dynamic>> freqMatrix = makeMatRows(adjustedFreq);
  List<List<dynamic>> gradMatrix = makeMatRows(adjustedGrad);

  final isMobile = Mobile.isPhone(context);
  const mobileScrollbarHeight = 7.0;
  double mobileWidth =
      MediaQuery.of(context).size.width - mobileScrollbarHeight;
  final freqWidget = _getFreqWidget(
      context, freqMatrix, gradMatrix, isMobile ? mobileWidth : null);

  final content = Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(
        child: isMobile
            ? Container(
                // width: mobileWidth,
                constraints: BoxConstraints(
                  minWidth: mobileWidth,
                ),
                child: freqWidget,
              )
            : Container(
                constraints: const BoxConstraints(
                  maxHeight: 400,
                  maxWidth: 800,
                ),
                child: freqWidget,
              ),
      ),
    ],
  );

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text("CST Data For ${superscripterUni(pali(freq.headword))}"),
      contentPadding: isMobile ? EdgeInsets.zero : null,
      insetPadding: isMobile ? const EdgeInsets.all(10) : null,
      content: content,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.ok),
        ),
      ],
    ),
  );
}

// based on the data for araha1.  The issue is the data has holes or is designed for
// merged cells.. we need to fill the wholes and then we can flip the array better.
// it is a crude function but it works.
List<dynamic> addDataPoints(List<dynamic> data, {bool addSubscript = false}) {
  List<dynamic> result = [];
  int dataCounter = 0;

  // First loop for Mūla (first 19 rows)
  for (int i = 1; i <= 19; i++) {
    result.add(dataCounter < data.length ? data[dataCounter++] : 'i');
  }

  // Insert 9 "i" placeholders for Mūla after the first 19 elements
  for (int i = 1; i <= 9; i++) {
    result.add('i');
  }

  // Second loop for Aṭṭhakathā (12 rows)
  for (int i = 1; i <= 12; i++) {
    result.add(dataCounter < data.length ? data[dataCounter++] : 'i');
  }

  // Add 3 "i" placeholders before 113
  for (int i = 1; i <= 3; i++) {
    result.add('i');
  }

  // Add 113 and handle addStar logic
  result.add(dataCounter < data.length
      ? (addSubscript ? '${data[dataCounter++]}¹' : data[dataCounter++])
      : 'i');

  // Add 3 "i" placeholders after 113
  for (int i = 1; i <= 3; i++) {
    result.add('i');
  }

  // Add 28 and then 8 "i" placeholders after it
  result
      .add(dataCounter < data.length ? data[dataCounter++] : 'i'); // Adding 28
  for (int i = 1; i <= 8; i++) {
    result.add('i');
  }

  // Now start Ṭīkā section
  result.add('i');
  result.add('i'); // Add two "i" placeholders

  result.add(dataCounter < data.length
      ? (addSubscript ? '${data[dataCounter++]}¹' : data[dataCounter++])
      : 'i');

  result.add('i');
  result.add('i'); // Add two "i" placeholders

  result.add(dataCounter < data.length ? data[dataCounter++] : 'i'); // Add 66
  result.add(dataCounter < data.length ? data[dataCounter++] : 'i'); // Add 37
  result.add(dataCounter < data.length ? data[dataCounter++] : 'i'); // Add 20
  result.add(dataCounter < data.length ? data[dataCounter++] : 'i'); // Add 41

  result.add('i');
  result.add('i'); // Add two "i" placeholders

  result.add(dataCounter < data.length
      ? (addSubscript ? '${data[dataCounter++]}' : data[dataCounter++])
      : 'i');

  result.add('i');
  result.add('i');
  result.add('i'); // Add three "i"s

  result.add(dataCounter < data.length
      ? (addSubscript ? '${data[dataCounter++]}¹' : data[dataCounter++])
      : 'i');

  result.add('i');
  result.add('i');
  result.add('i'); // Add three "i"s

  // Add the rest of the data
  while (dataCounter < data.length) {
    result.add(data[dataCounter++]);
  }

  return result;
}

// ** `makeMatRows` function to flip the vertical to horizontal 3x3 rows**
List<List<dynamic>> makeMatRows(List<dynamic> adjustedData) {
  List<List<dynamic>> matrix = [];

  for (int i = 0; i < 28; i++) {
    matrix.add([
      adjustedData[i] == 'i' ? null : adjustedData[i], // M
      adjustedData[i + 28] == 'i' ? null : adjustedData[i + 28], // A
      adjustedData[i + 56] == 'i' ? null : adjustedData[i + 56], // Ṭ
    ]);
  }

  return matrix;
}

// ** Function to build the frequency widget**
Widget _getFreqWidget(BuildContext context, List<List<dynamic>> freqMatrix,
    List<List<dynamic>> gradMatrix,
    [double? width]) {
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
          child: _getFreqTable(context, freqMatrix, gradMatrix, width),
        ),
      ),
    ),
  );
}

// ** Function to build the frequency table**
Widget _getFreqTable(BuildContext context, List<List<dynamic>> freqMatrix,
    List<List<dynamic>> gradMatrix,
    [double? width]) {
  List<TableRow> rows = [];

  // STYLES ====================================================================
  final headerStyle = TextStyle(
    fontFamily: FontUtils.getfontName(script: Script.roman),
    fontSize: freqFontSize,
    fontWeight: FontWeight.w800,
    color: getDpdHeaderColor(),
    height: 1,
  );

  final sectionStyle = TextStyle(
      fontFamily: FontUtils.getfontName(script: Script.roman),
      fontSize: freqFontSize,
      fontWeight: FontWeight.bold,
      color: getDpdHeaderColor(),
      height: 1);
  // END STYLES ================================================================

  getHeader(String title, [TextAlign? textAlign]) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        title,
        style: headerStyle,
        textAlign: textAlign ?? TextAlign.left,
      ),
    );
  }

  // Add the header row
  rows.add(
    TableRow(
      children: [
        getHeader('Section'),
        getHeader('M', TextAlign.center),
        getHeader('A', TextAlign.center),
        getHeader('Ṭ', TextAlign.center),
      ],
    ),
  );

  double cellHeight =
      paintedHeight(context, TextSpan(text: 'Majjhima', style: sectionStyle)) +
          2 * 8;
  double largestSectionWidth =
      paintedWidth(context, 'Khuddaka Nikāya 3', sectionStyle);
  double headerHeight = paintedHeight(
      context,
      TextSpan(
        text: 'Section MAṬ',
        style: headerStyle,
      ));
  debugPrint('cellHeight: $cellHeight, header height: $headerHeight');

  // FIND the largest frequency cell width =====================================
  final largestFreqCellWidth = freqMatrix
      .expand((row) => row)
      .whereNotNull()
      .map((element) => paintedWidth(
          context,
          element.toString(),
          TextStyle(
            // really important to have the same font used in measurements
            fontFamily: FontUtils.getfontName(script: Script.roman),
            fontSize: freqFontSize,
            height: 1,
          )).ceil().toDouble())
      .max;

  // Offsets, sizes etc magic numbers ==========================================
  const padding = 8.0;
  const doublePadding = 2.0 * padding;
  const bookLegendGap = 5.0;
  const bookLegendWidth = 30.0;
  const borderWidth = 0.5;
  const scrollbarDesktopWidth = 15.0;
  const cellLeeway = 2.0;
  final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
  final topOffset = headerHeight + doublePadding;
  final projectedTableWidth = bookLegendWidth +
      bookLegendGap +
      (largestSectionWidth + doublePadding + borderWidth * 2) +
      3 * (largestFreqCellWidth + doublePadding + cellLeeway + borderWidth * 2);
  // End Offsets ===============================================================

  debugPrint(
      '\nprojectedTableWidth: $projectedTableWidth -- \nmobileWidth: $width -- \ndevicePixelRatio: $devicePixelRatio, \nlargestFreqCellWidth: $largestFreqCellWidth, \nlargestSectionWidth: $largestSectionWidth');

  const borderDecoration = BoxDecoration(
      border: Border.fromBorderSide(
          BorderSide(color: Colors.black, width: borderWidth)));

  for (int i = 0; i < freqMatrix.length; i++) {
    var freqRow = freqMatrix[i];
    var gradRow = gradMatrix[i];

    String section = expectedFrequencies[i]['section']!;
    final book = expectedFrequencies[i]['book'];

    // gets the indices of the items of a specific book, e.g. for 'Vinaya' that
    // would be [0..4] and for 'Sutta' that'd be [5..11]
    final bookIndices = expectedFrequencies
        .mapIndexed((index, item) => item['book'] == book ? index : null)
        .whereType<int>()
        .toList();

    isTotal(int index) {
      return bookIndices
              .map((i) => freqMatrix[i][index])
              .whereNotNull()
              .firstWhereOrNull((el) => '$el'.contains('¹')) !=
          null;
    }

    getTotalGrade(index) {
      return bookIndices
          .map((i) => gradMatrix[i][index])
          .whereNotNull()
          .firstWhereOrNull((el) => el != 0);
    }

    final freqData = ['M', 'A', 'T'].mapIndexed((index, type) {
      return {
        'type': type,
        'freq': freqRow[index],
        'grad': gradRow[index],
        'isTotal': isTotal(index),
        'totalGrad': getTotalGrade(index)
      };
    });

    final isFirst = i == bookIndices.first;
    final isLast = i == bookIndices.last;

    // Build the table row
    rows.add(
      TableRow(
        children: [
          Container(
              decoration: borderDecoration,
              child: Padding(
                padding: const EdgeInsets.all(padding),
                child: Text(section, style: sectionStyle),
              )),
          ...freqData.map((e) => _buildFrequencyCell(context, e['freq'],
              e['grad'], e['isTotal'], isFirst, isLast, e['totalGrad']))
        ],
      ),
    );
  }

  final weights = [5, 7, 7, 9];
  final titles = ['Vinaya', 'Sutta', 'Abhidhamma', 'Aññā'];

  debugPrint('topOffset: $topOffset, cellHeight=$cellHeight');

  return Row(
    mainAxisAlignment: MainAxisAlignment.start,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: EdgeInsets.only(right: bookLegendGap, top: topOffset),
        child: Table(
          children: weights.mapIndexed((index, weight) {
            final title = titles[index].split('').join('\n');
            double bookHeight =
                weight * (cellHeight.floor() + borderWidth * 2) -
                    borderWidth * 2;
            return TableRow(
              children: [
                Container(
                    // constraints: BoxConstraints(
                    //   minHeight: bookHeight,
                    // ),
                    decoration: borderDecoration,
                    child: SizedBox(
                      height: bookHeight,
                      child: Center(
                          child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontFamily:
                                FontUtils.getfontName(script: Script.roman),
                            fontSize: freqFontSize * 0.9,
                            height: 1),
                      )),
                    )),
              ],
            );
          }).toList(),
          defaultColumnWidth: const FixedColumnWidth(bookLegendWidth),
        ),
      ),
      width == null
          ? Padding(
              padding: const EdgeInsets.only(right: scrollbarDesktopWidth),
              child: Table(
                defaultColumnWidth: FixedColumnWidth(
                    largestFreqCellWidth + doublePadding + cellLeeway),
                columnWidths: const {
                  0: IntrinsicColumnWidth(),
                },
                children: rows,
              ))
          : projectedTableWidth > width
              ? Container(
                  constraints: BoxConstraints(
                    minWidth: width -
                        bookLegendGap -
                        bookLegendWidth -
                        doublePadding -
                        cellLeeway,
                    maxWidth: double.infinity,
                  ),
                  // width: ,
                  child: Table(
                    defaultColumnWidth: FixedColumnWidth(
                        largestFreqCellWidth + doublePadding + cellLeeway),
                    columnWidths: const {
                      0: IntrinsicColumnWidth(),
                    },
                    children: rows,
                  ))
              : SizedBox(
                  width: width -
                      bookLegendGap -
                      bookLegendWidth -
                      doublePadding -
                      cellLeeway,
                  child: Table(
                    defaultColumnWidth: FixedColumnWidth(
                        largestFreqCellWidth + doublePadding + cellLeeway),
                    columnWidths: const {
                      0: FlexColumnWidth(),
                    },
                    children: rows,
                  )),
    ],
  );
}

// ** Helper function to build frequency cell with grade color**
Widget _buildFrequencyCell(
    BuildContext context,
    dynamic frequency,
    dynamic grade,
    bool hideBorder,
    bool isFirst,
    bool isLast,
    dynamic gradeAll) {
  int gradeInt =
      (grade is int) ? grade : (int.tryParse(grade?.toString() ?? '0') ?? 0);
  final text = frequency != null
      ? frequency.toString().replaceAll('¹', '')
      : hideBorder
          ? ''
          : '-';
  final gradeColor = _getGradeColor(context, hideBorder ? gradeAll : grade);

  BoxBorder boxBorder;
  if (hideBorder) {
    boxBorder = Border(
      left: const BorderSide(width: 0.5, color: Colors.black),
      top: BorderSide(width: 0.5, color: isFirst ? Colors.black : gradeColor),
      right: const BorderSide(width: 0.5, color: Colors.black),
      bottom: BorderSide(width: 0.5, color: isLast ? Colors.black : gradeColor),
    );
  } else {
    boxBorder = const Border.fromBorderSide(
        BorderSide(color: Colors.black, width: 0.5));
  }
  return Container(
    decoration: BoxDecoration(
      border: boxBorder,
      color: gradeColor,
    ),
    child: Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          // really important to have the same font used in measurements
          fontFamily: FontUtils.getfontName(script: Script.roman),
          fontSize: freqFontSize,
          height: 1,
          color: gradeInt > 4
              ? Colors.white
              : Theme.of(context).textTheme.bodyMedium?.color,
        ),
      ),
    ),
  );
}

// ** Helper function to map grade to color**
Color _getGradeColor(BuildContext context, dynamic grade) {
  bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

  if (grade == null || grade == 0) {
    return isDarkMode ? Colors.grey[850]! : Colors.white;
  }

  if (isDarkMode) {
    // Define colors suitable for dark mode
    switch (grade) {
      case 1:
        return Colors.blueGrey[800]!;
      case 2:
        return Colors.blueGrey[700]!;
      case 3:
        return Colors.blueGrey[600]!;
      case 4:
        return Colors.blueGrey[500]!;
      case 5:
        return Colors.blueGrey[400]!;
      case 9:
        return Colors.blueGrey[300]!;
      case 10:
        return Colors.blueGrey[200]!;
      default:
        return Colors.blueGrey[500]!;
    }
  } else {
    // Colors for light mode
    switch (grade) {
      case 1:
        return Colors.lightBlue[50]!;
      case 2:
        return Colors.lightBlue[100]!;
      case 3:
        return Colors.lightBlue[200]!;
      case 4:
        return Colors.lightBlue[300]!;
      case 5:
        return Colors.lightBlue[400]!;
      case 9:
        return Colors.lightBlue[700]!;
      case 10:
        return Colors.lightBlue[800]!;
      default:
        return Colors.lightBlue[500]!;
    }
  }
}
