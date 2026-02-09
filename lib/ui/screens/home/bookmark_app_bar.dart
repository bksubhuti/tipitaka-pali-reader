import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tipitaka_pali/business_logic/models/bookmark.dart';
import 'package:tipitaka_pali/business_logic/view_models/bookmark_page_view_model.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/repositories/bookmark_repo.dart';
import 'package:tipitaka_pali/ui/dialogs/bookmark_cloud_transfer_dialog.dart';
import 'package:tipitaka_pali/ui/dialogs/confirm_dialog.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:tipitaka_pali/ui/widgets/colored_text.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class BookmarkAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onDialogClose;

  const BookmarkAppBar({super.key, required this.onDialogClose});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      // Rydmike: Consider not having implicit back, as it will give idea that
      //  user can go back, but back leads out of app in this case.
      automaticallyImplyLeading: false,
      title: Text(AppLocalizations.of(context)!.bookmark),
      actions: [
        buildDropdownButton(context),
        getCloudButton(context),
/*       //TODO need to make this work with folders and bookmarks
            IconButton(
            tooltip: AppLocalizations.of(context)!.shareAllNotes,
            icon: const Icon(Icons.share),
            onPressed: () async {
              String bookMarkText = "";
              final List<Bookmark> bookmarks =
                  context.read<BookmarkPageViewModel>().bookmarks;
              for (var book in bookmarks) {
                bookMarkText += book.toString();
              }
              Share.share(bookMarkText,
                  subject: AppLocalizations.of(context)!.shareAllNotes);
            }),
            */
/*        IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              final result = await _getConfirmataion(context);
              if (result == OkCancelAction.ok) {
                context.read<BookmarkPageViewModel>().deleteAll();
              }
            }),*/
      ],
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(AppBar().preferredSize.height);

  Future<OkCancelAction?> _getConfirmataion(BuildContext context) async {
    return await showDialog<OkCancelAction>(
        context: context,
        builder: (context) {
          return ConfirmDialog(
            title: AppLocalizations.of(context)!.confirmation,
            message: AppLocalizations.of(context)!.areSureDelete,
            okLabel: AppLocalizations.of(context)!.delete,
            cancelLabel: AppLocalizations.of(context)!.cancel,
          );
        });
  }

  Widget buildDropdownButton(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (value) async {
        if (value == 'import') {
          doImport(context);
        } else if (value == 'export') {
          doExport(context);
        }
      },
      itemBuilder: (BuildContext context) => [
        PopupMenuItem(
          value: 'import',
          child: Row(
            children: [
              Icon(
                Icons.upload,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(width: 8.0),
              ColoredText(AppLocalizations.of(context)!.importBookmarks),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'export',
          child: Row(
            children: [
              Icon(
                Icons.download,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(width: 8.0),
              ColoredText(AppLocalizations.of(context)!.exportBookmarks),
            ],
          ),
        ),
      ],
      icon:
          const Icon(Icons.sd_storage_outlined), // Change to your desired icon
    );
  }

  doImport(BuildContext context) async {
    FilePickerResult? filename = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      lockParentWindow: true,
    );

    if (filename != null) {
      final DatabaseHelper databaseHelper = DatabaseHelper();
      final BookmarkDatabaseRepository db =
          BookmarkDatabaseRepository(databaseHelper);

      File file = File(filename.files.single.path.toString());
      String content = await file.readAsString();
      List<Bookmark> importedBookmarks = bookmarkFromJson(content);

      // Optionally, determine the default folderId or retrieve it based on your app's logic
      // For example, int defaultFolderId = await getDefaultFolderId();

      for (Bookmark bm in importedBookmarks) {
        // If you need to assign all imported bookmarks to a specific folder, set folderId here
        bm.folderId = -1; // root folder is always -1

        db.insert(bm);
      }
      // Refresh the bookmarks to reflect the imported bookmarks
      context.read<BookmarkPageViewModel>().refreshBookmarks();
    } else {
      // User canceled the picker
    }
  }

  doExport(BuildContext context) async {
    final List<Bookmark> bookmarks =
        await BookmarkDatabaseRepository(DatabaseHelper()).getAllBookmark();

    final modifiedBookmarks = bookmarks.map((bookmark) {
      return Bookmark(
        id: bookmark.id,
        bookID: bookmark.bookID,
        pageNumber: bookmark.pageNumber,
        note: bookmark.note,
        name: bookmark.name,
        selectedText: bookmark.selectedText,
        folderId: -1,
        bmkSort: bookmark.bmkSort,
      );
    }).toList();

    String bookmarksJson = bookmarkToJson(modifiedBookmarks);

    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      // ... your existing Mobile/Web share code ...
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/bookmarks_export.json');
      await file.writeAsString(bookmarksJson);
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles([XFile(file.path)],
          subject: 'Exported Bookmarks');
    }
    // ADD THIS FOR MAC/WINDOWS/LINUX
    else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Bookmarks',
        fileName: 'bookmarks_export.json', // Ensure the extension is here
        // Sometimes leaving 'type' as any or omitting it
        // helps bypass strict sandbox check on certain macOS versions
      );

      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsString(bookmarksJson);

        // Optional: Show a little snackbar to confirm success
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bookmarks exported successfully!')),
          );
        }
      }
    }
  }

  Widget getCloudButton(BuildContext context) {
    InternetConnection().hasInternetAccess.then((bInternet) {
      if (!bInternet) {
        Prefs.isSignedIn = false;
        // You can also add more code here to handle the scenario when there is no internet.
      } else {
        // Handle the scenario when there is internet.
      }
    });

    return (Prefs.isSignedIn)
        ? IconButton(
            icon: const Icon(Icons.cloud),
            onPressed: () {
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return const BookmarkCloudTransferDialog();
                },
              ).then((_) => onDialogClose()); // Use the callback here
            })
        : const SizedBox.shrink();
  }
}
