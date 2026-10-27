/*
import 'package:flutter/material.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'package:tipitaka_pali/services/database/database_helper.dart';

import '../../../business_logic/models/book.dart';
import '../../../services/repositories/sutta_repository.dart';
import '../../../utils/platform_info.dart';
import '../../widgets/colored_text.dart';
import '../reader/mobile_reader_container.dart';
import 'openning_books_provider.dart';
//import 'package:provider/provider.dart';
//import 'package:tipitaka_pali/data/constants.dart';

//import '../settings/download_view.dart';

class QuickJumpPage extends StatefulWidget {
  const QuickJumpPage({super.key});

  @override
  State<QuickJumpPage> createState() => _QuickJumpPageState();
}

class _QuickJumpPageState extends State<QuickJumpPage> {
  late TextEditingController _controller;
  late bool _isValid;

  late SuttaRepositoryDatabase srd;

  @override
  void initState() {
    _controller = TextEditingController();
    _isValid = false;
    super.initState();
    srd = SuttaRepositoryDatabase(DatabaseHelper());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.quickjump),
          actions: const [],
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 150,
                      margin: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(32.0),
                        border: Border.all(color: Colors.grey),
                      ),
                      child: TextField(
                          decoration:
                              const InputDecoration(border: InputBorder.none),
                          maxLines: 1,
                          controller: _controller,
                          onSubmitted: (text) {
                            quickJump(context, text);
                          }),
                    ),
                    const SizedBox(width: 50),
                    FloatingActionButton(
                        onPressed: () {
                          quickJump(context, _controller.text);
                        },
                        child: const Text("go")),
                  ],
                ),
                const ColoredText(
                    "You may use shortcut \nnotation to jump to a sutta:\n\nExample:\n\nmn118\nMajjhima Sutta 118\n\ndn10\nDīgha sutta 10\n\nsn5.20 \nsaṃyutta 5 sutta 20\n\nan4.50 \nbook 4 and sutta 50"),
              ],
            ),
          ),
        ));
  }

  quickJump(BuildContext context, String qj) async {
    //await makeSNQuickjumpTable();
    Book book = Book(id: "mula_di_01", name: "dn");

    if (qj.toLowerCase().contains("dn")) {
      book = srd.getDnBookDetails(qj, book); // get the number
    }
    if (qj.toLowerCase().contains("mn")) {
      book = srd.getMnBookDetails(qj, book); // get the number
    }
    if (qj.toLowerCase().contains("sn")) {
      final snFormat = RegExp(r'^sn\d+\.\d+$');
      if (snFormat.hasMatch(qj)) {
        book = await srd.getSnBookDetails(qj, book);
      } // get the number
    }
    if (qj.toLowerCase().contains("an")) {
      final anFormat = RegExp(r'^an\d+\.\d+$');
      if (anFormat.hasMatch(qj)) {
        book = await srd.getAnBookDetails(qj, book); // get the number
      }
    }

    if (book.name.isNotEmpty) {
      final openningBookProvider = context.read<OpenningBooksProvider>();
      openningBookProvider.add(
        book: book,
        currentPage: book.firstPage,
        textToHighlight: book.paraNum.toString(),
      );

      // quick jump page and reader page are different routes in mobile
      // so need to open reader route for moble
      // ignore: use_build_context_synchronously
      if (Mobile.isPhone(context)) {
        // ignore: use_build_context_synchronously
        MobileReaderContainer.show(context);
      }
    }
  }
}
*/
