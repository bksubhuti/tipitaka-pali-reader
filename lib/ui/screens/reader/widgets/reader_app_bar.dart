import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:provider/provider.dart';
import 'package:tipitaka_pali/utils/tts_helpers.dart';
import '../../../../app.dart';
import '../controller/reader_view_controller.dart';
import '../../../../services/provider/script_language_provider.dart';
import '../../../../utils/pali_script.dart';

class ReaderAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ReaderAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = Provider.of<ReaderViewController>(context, listen: false);
    myLogger.i('Building Appbar');
    return AppBar(
      title: Text(PaliScript.getScriptOf(
          script: context.read<ScriptLanguageProvider>().currentScript,
          romanText: vm.book.name)),
      actions: [
        FutureBuilder<bool>(
          future: TtsHelpers.isTtsSupported(),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data == true) {
              return IconButton(
                onPressed: () {
                  vm.startTtsForCurrentPage();
                },
                icon: const Icon(Icons.volume_up),
              );
            }
            return const SizedBox.shrink();
          },
        ),
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

  void _openBookShelfDialog(BuildContext context) async {}
}
