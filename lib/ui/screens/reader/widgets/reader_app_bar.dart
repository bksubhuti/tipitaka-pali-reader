import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/business_logic/models/book.dart';
import 'package:tipitaka_pali/ui/screens/home/book_list_page.dart';
import 'package:tipitaka_pali/services/prefs.dart';

import '../../../../app.dart';
import '../controller/reader_view_controller.dart';
import '../../../../services/provider/script_language_provider.dart';
import '../../../../utils/pali_script.dart';

class ReaderAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ReaderAppBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final vm = Provider.of<ReaderViewController>(context, listen: false);
    myLogger.i('Building Appbar');
    return AppBar(
      title: Text(PaliScript.getScriptOf(
          script: context.read<ScriptLanguageProvider>().currentScript,
          romanText: vm.book.name)),
      actions: [
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.looks_one_outlined),
        ),
        IconButton(
          onPressed: () => _openBookShelfDialog(context),
          icon: const Icon(Icons.add_box_outlined),
        ),
      ],
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(AppBar().preferredSize.height);

  void _openBookShelfDialog(BuildContext context) async {
    final book = await showGeneralDialog<Book>(
        context: context,
        transitionDuration:
            Duration(milliseconds: Prefs.animationSpeed.round()),
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: animation, child: child),
          );
        },
        pageBuilder: (context, animation, secondaryAnimation) => Material(
              child: BookListPage(),
            ));
  }
}
