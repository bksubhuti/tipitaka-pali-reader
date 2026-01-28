import 'dart:io';

import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flash_card/flash_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:path/path.dart' as path;
import 'package:tipitaka_pali/ui/screens/dictionary/controller/dictionary_controller.dart';

import '../../../business_logic/models/dictionary_history.dart';

class FlashCardsView extends StatelessWidget {
  final List<DictionaryHistory> cards;
  final DictionaryController dictionaryController;
  final ValueNotifier<bool> isExporting = ValueNotifier<bool>(false);

  FlashCardsView(
      {super.key, required this.cards, required this.dictionaryController});

  String _highlightOccurrences(String source, String context) {
    if (context.isEmpty || !source.contains(context)) {
      return source;
    }
    return source.replaceAll(context, '<b>$context</b>');
  }

  String _highlightMDOccurrences(String source, String word) {
    if (word.isEmpty || !source.contains(word)) {
      return source;
    }
    return source.replaceAll(word, '**$word**');
  }

  void _exportToAnki(BuildContext context, bool note3) async {
    isExporting.value = true;
    List<List<dynamic>> rows = [];

    // Add flashcards data
    for (var card in cards) {
      String def = await dictionaryController.loadDefinition(card.word);
      if (note3) {
        rows.add([
          '<p><h3>${card.word}</h3></p>',
          '<p>${_highlightOccurrences(card.context, card.word)}</p>',
          def
        ]);
      } else {
        rows.add([
          '<p><h3>${card.word}</h3>\n${_highlightOccurrences(card.context, card.word)}</p>',
          def
        ]);
      }
    }

    String csv = const ListToCsvConverter(
      fieldDelimiter: ';',
      textEndDelimiter: '"',
    ).convert(rows);

    // Pick directory
    String? dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null) {
      // Create file in the chosen directory
      final file = File(path.join(dir, "anki_flashcards.csv"));

      // Write CSV to the file
      try {
        await file.writeAsString(csv);
      } catch (e) {
        debugPrint('Error writing file: $e');
      }

      isExporting.value = false;
      // File is saved. You can show a success message if you want.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 2),
          content: Text('Flashcards exported successfully!'),
        ),
      );
    }
  }

  _exportToRemNote(BuildContext context, {required bool writeFile}) async {
    isExporting.value = true;
    StringBuffer sb = StringBuffer();

    // Add flashcards data
    for (var card in cards) {
      String def = await dictionaryController.loadDefinition(card.word);
      debugPrint(def);
      BeautifulSoup bs = BeautifulSoup(def);
      String defCard = "\n";

      // Separate by h3 and p.definition
      List<Bs4Element> pdefs = bs.findAll("h3, div, p.definition");

      for (Bs4Element pdef in pdefs) {
        if (pdef.name == "h3") {
          defCard += "\t\t- **${pdef.getText()}**\n";
        } else {
          if (pdef.hasAttr('class') &&
              pdef.getAttrValue('class') == 'dpd_grammar') {
            List<Bs4Element> trs = pdef.findAll('tr');
            for (Bs4Element tr in trs) {
              defCard += "\t\t\t\t";
              List<Bs4Element> tds = tr.findAll('td');
              for (Bs4Element td in tds) {
                defCard += td.getText() + " ";
              }
              defCard += "\n";
            }
            continue; // Skip the rest and go to the next pdef
          } else {
            Bs4Element? summary = pdef.find('summary');
            if (summary != null) {
              // Process summary tag
              defCard += "\t\t\t- ";
              defCard += summary.getText();
              defCard += "\n";
            } else {
              // If no summary tag found, get the entire pdef
              defCard += "\t\t\t- ";
              defCard += pdef.getText();
              defCard += "\n";
            }
          }
        }
      }

      String front =
          "**${card.word}** \n\t-${_highlightMDOccurrences(card.context, card.word)}";
      sb.write(front);
      sb.write(defCard);
    }

    if (writeFile) {
      // Pick directory
      String? dir = await FilePicker.platform.getDirectoryPath();
      if (dir != null) {
        // Create file in the chosen directory
        final file = File(path.join(dir, "tpr_export.md"));

        // Write CSV to the file
        try {
          await file.writeAsString(sb.toString().replaceAll("•", ""));
        } catch (e) {
          debugPrint('Error writing file: $e');
        }

        isExporting.value = false;
        // File is saved. You can show a success message if you want.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 2),
            content: Text('MD Files exported'),
          ),
        );
      }
    } else {
      await Clipboard.setData(
          ClipboardData(text: sb.toString().replaceAll("•", "")));
      // File is saved. You can show a success message if you want.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 2),
          content: Text('Remnotes copied to paste buffer'),
        ),
      );
    }

    isExporting.value = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('Flashcards'),
        ),
        body: ListView.builder(
          itemCount: cards.length,
          itemBuilder: (context, index) {
            return FlashCard(
              backWidget: () => Container(
                padding: EdgeInsets.all(10), // Add padding for better spacing
                constraints: BoxConstraints(
                  maxHeight: 400, // Set a maximum height
                ),
                child: SingleChildScrollView(
                  // Allows scrolling within the card
                  child: Column(
                    children: [
                      Text(
                        cards[index].word, // Display the word
                        style: const TextStyle(fontSize: 30),
                        overflow: TextOverflow.ellipsis, // Prevents overflow
                      ),
                      HtmlWidget(
                        _highlightOccurrences(
                            cards[index].context,
                            cards[index]
                                .word), // Highlight the word in the context
                      ),
                    ],
                  ),
                ),
              ),
              frontWidget: () => FutureBuilder<String>(
                future: dictionaryController
                    .loadDefinition(cards[index].word), // your future operation
                builder:
                    (BuildContext context, AsyncSnapshot<String> snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const CircularProgressIndicator(); // or some kind of loading widget
                  } else {
                    if (snapshot.hasError) {
                      return const Text('Error: loading definition');
                    } else {
                      return SingleChildScrollView(
                        child: HtmlWidget(
                          (snapshot.data!).isEmpty
                              ? "<p><h2>No Definition Found</h2></p>"
                              : snapshot.data!,
                        ),
                      );
                    }
                  }
                },
              ),
              width: 300,
              height: 400,
            );
          },
        ),
        floatingActionButton: buildSpeedDial(context));
  }

  SpeedDial buildSpeedDial(BuildContext context) {
    return SpeedDial(
      icon: Icons.download,
      label: Text(AppLocalizations.of(context)!.export),
      activeIcon: Icons.close,
      //buttonSize: 56.0,
      visible: true,
      closeManually: false,
      renderOverlay: false,
      curve: Curves.bounceIn,
      overlayColor: Colors.black,
      overlayOpacity: 0.5,
      tooltip: 'Export',
      heroTag: 'speed-dial-hero-tag',
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 8.0,
      shape: const CircleBorder(),
      children: [
        SpeedDialChild(
          child: Image.asset(
            'assets/images/anki.png',
            width: 34.0,
            height: 34.0,
            fit: BoxFit.cover,
          ),
          backgroundColor: Colors.white,
          label: 'Anki',
          labelStyle: const TextStyle(fontSize: 18.0),
          onTap: () => _exportToAnki(context, false),
        ),
        SpeedDialChild(
          child: Image.asset(
            'assets/images/anki.png',
            width: 34.0,
            height: 34.0,
            fit: BoxFit.cover,
          ),
          backgroundColor: const Color.fromARGB(255, 61, 61, 59),
          label: 'Anki 3 Field Note',
          labelStyle: const TextStyle(fontSize: 18.0),
          onTap: () => _exportToAnki(context, true),
        ),
        SpeedDialChild(
          child: Image.asset(
            'assets/images/remnote.jpg',
            width: 34.0,
            height: 34.0,
            fit: BoxFit.cover,
          ),
          backgroundColor: Colors.white,
          label: 'Remnote',
          labelStyle: const TextStyle(fontSize: 18.0),
          onTap: () => _exportToRemNote(context, writeFile: false),
        ),
        SpeedDialChild(
          child: Image.asset(
            'assets/images/remnote.jpg',
            width: 34.0,
            height: 34.0,
            fit: BoxFit.cover,
          ),
          backgroundColor: Colors.white,
          label: 'Remnote Simple',
          labelStyle: const TextStyle(fontSize: 18.0),
          onTap: () => _exportToRemNoteSimple(
            context,
          ),
        ),
        SpeedDialChild(
          child: Image.asset(
            'assets/images/vecteezy_md.jpg',
            width: 34.0,
            height: 34.0,
            fit: BoxFit.cover,
          ),
          backgroundColor: Colors.white,
          label: 'MD File',
          labelStyle: const TextStyle(fontSize: 18.0),
          onTap: () => _exportToRemNote(context, writeFile: true),
        ),
      ],
    );
  }

  _exportToRemNoteSimple(
    BuildContext context,
  ) async {
    isExporting.value = true;
    StringBuffer sb = StringBuffer();

    // Add flashcards data
    for (var card in cards) {
      String def = await dictionaryController.loadDefinition(card.word);
      debugPrint(def);
      BeautifulSoup bs = BeautifulSoup(def);
      String defCard = "\n";

      // Find all summary tags for definitions
      List<Bs4Element> summaries = bs.findAll('summary');
      if (summaries.isNotEmpty) {
        defCard += "\t\t- Basic Definitions:\n";
        for (Bs4Element summary in summaries) {
          defCard += "\t\t\t- ${summary.getText()}\n";
        }
      }

      String front =
          "**${card.word}** \n\t-${_highlightMDOccurrences(card.context, card.word)}";
      sb.write(front);
      sb.write(defCard);
    }

    // Logic to write to file or copy to clipboard
    await Clipboard.setData(
        ClipboardData(text: sb.toString().replaceAll("•", "")));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 2),
        content: Text('Remnotes copied to paste buffer'),
      ),
    );

    isExporting.value = false;
  }
}
