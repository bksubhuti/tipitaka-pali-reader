import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/business_logic/models/bookmark.dart';
import 'package:tipitaka_pali/business_logic/models/folder.dart';
import 'package:tipitaka_pali/business_logic/view_models/bookmark_page_view_model.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/repositories/bookmark_backup_repo.dart';
import 'package:tipitaka_pali/services/repositories/bookmark_fire_repo.dart';
import 'package:tipitaka_pali/services/repositories/bookmark_repo.dart';
import 'package:tipitaka_pali/services/repositories/folder_epository%20%7B.dart';
import 'package:tipitaka_pali/ui/widgets/colored_text.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';

class BookmarkCloudTransferDialog extends StatefulWidget {
  const BookmarkCloudTransferDialog({super.key});

  @override
  TransferDialogState createState() => TransferDialogState();
}

class TransferDialogState extends State<BookmarkCloudTransferDialog> {
  List<Bookmark> localBookmarks = [];
  List<Folder> localFolders = [];
  List<Bookmark> cloudBookmarks = [];
  List<Bookmark> backupBookmarks = [];
  List<Folder> backupFolders = [];
  String? backupError;
  ScrollController localListController = ScrollController();
  final backupRepo = BookmarkBackupRepository(DatabaseHelper());
  BookmarkBackupInfo? backupInfo;
  bool backupBusy = false;

  @override
  void initState() {
    super.initState();
    fetchBookmarks();
    fetchBackupInfo();
  }

  void fetchBackupInfo() async {
    try {
      backupInfo = await backupRepo.info();
    } catch (e) {
      debugPrint('Error reading backup info: $e');
    }
    if (mounted) setState(() {});
    await fetchBackupContents();
  }

  Future<void> fetchBackupContents() async {
    if (backupInfo == null) return;
    try {
      final (folders, bookmarks) = await backupRepo.contents();
      backupFolders = folders;
      backupBookmarks = bookmarks;
      backupError = null;
    } catch (e) {
      backupError = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() {});
  }

  String describe(int folders, int bookmarks) =>
      '$folders folder${folders == 1 ? '' : 's'}, '
      '$bookmarks bookmark${bookmarks == 1 ? '' : 's'}';

  void showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> runBackupTask(Future<void> Function() task) async {
    setState(() => backupBusy = true);
    try {
      await task();
    } catch (e) {
      if (mounted) showMessage(e.toString().replaceFirst('Exception: ', ''));
    }
    if (mounted) setState(() => backupBusy = false);
  }

  void backUpAll() => runBackupTask(() async {
        backupInfo = await backupRepo.backUp();
        await fetchBackupContents();
        if (mounted) {
          showMessage('Backed up '
              '${describe(backupInfo!.folderCount, backupInfo!.bookmarkCount)}.');
        }
      });

  void restoreAll() async {
    final info = backupInfo;
    if (info == null) return;
    final (folders, bookmarks) = await backupRepo.localCounts();
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore from the cloud?'),
        content: Text('This replaces everything in Bookmarks on this device '
            '(${describe(folders, bookmarks)}) with the cloud backup of '
            '${formatDate(info.created)} '
            '(${describe(info.folderCount, info.bookmarkCount)}).\n\n'
            'This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await runBackupTask(() async {
      await backupRepo.restore();
      if (!mounted) return;
      await Provider.of<BookmarkPageViewModel>(context, listen: false)
          .setCurrentFolderAndFetchItems(-1);
      fetchBookmarks();
      if (mounted) {
        showMessage('Restored '
            '${describe(info.folderCount, info.bookmarkCount)}.');
      }
    });
  }

  String formatDate(DateTime date) {
    final local = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  void fetchBookmarks() async {
    localBookmarks =
        await BookmarkDatabaseRepository(DatabaseHelper()).getAllBookmark();
    localFolders =
        (await FolderDatabaseRepository(DatabaseHelper()).fetchFolders())
            .where((f) => f.id != -1)
            .toList();
    cloudBookmarks = await BookmarkFireRepository().getBookmarks();
    setState(() {});
  }

  void downloadBookmark(Bookmark bookmark) async {
    final bookmarkViewModel =
        Provider.of<BookmarkPageViewModel>(context, listen: false);
    bookmarkViewModel.insertBookmark(bookmark);
    fetchBookmarks();
    scrollToBottom();
  }

  /// Adds every cloud bookmark (uploaded one at a time, by this or an older
  /// version, without its folder) to the top level, skipping any already on
  /// this device.
  void downloadAllBookmarks() => runBackupTask(() async {
        final repo = BookmarkDatabaseRepository(DatabaseHelper());
        String key(Bookmark b) =>
            '${b.bookID}|${b.pageNumber}|${b.note}|${b.selectedText}';
        final present = (await repo.getAllBookmark()).map(key).toSet();
        var added = 0;
        for (final bookmark in cloudBookmarks) {
          if (!present.add(key(bookmark))) continue;
          await repo.insert(bookmark);
          added++;
        }
        if (!mounted) return;
        await Provider.of<BookmarkPageViewModel>(context, listen: false)
            .fetchBookmarksAndFolders();
        fetchBookmarks();
        final skipped = cloudBookmarks.length - added;
        if (mounted) {
          showMessage('Added $added bookmark${added == 1 ? '' : 's'}'
              '${skipped > 0 ? ', $skipped already here' : ''}.');
        }
      });

  void scrollToBottom() {
    if (localListController.hasClients) {
      localListController.animateTo(
        localListController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
      );
    }
  }

  void deleteFromCloud(Bookmark bookmark) async {
    await BookmarkFireRepository().delete(bookmark);
    fetchBookmarks();
  }

  void transferToCloud(Bookmark bookmark) async {
    await BookmarkFireRepository().insert(bookmark);
    fetchBookmarks();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.transferBookmarks),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          children: [
            buildBackupSection(),
            const Divider(height: 24),
            ColoredText(
              AppLocalizations.of(context)!.localBookmarks,
              style: const TextStyle(fontWeight: FontWeight.bold),
              fontSize: Prefs.uiFontSize + 3,
            ),
            Expanded(
              child: buildLocalBookmarksList(),
            ),
            const SizedBox(
              height: 20,
            ),
            ColoredText(
              AppLocalizations.of(context)!.cloudBookmarks,
              style: const TextStyle(fontWeight: FontWeight.bold),
              fontSize: Prefs.uiFontSize + 3,
            ),
            Expanded(
              child: buildCloudBookmarksList(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: Text(AppLocalizations.of(context)!.close),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  Widget buildBackupSection() {
    final info = backupInfo;
    return Column(
      children: [
        Text(
          info == null
              ? 'No backup in the cloud yet.'
              : 'Cloud backup: ${formatDate(info.created)}, '
                  '${describe(info.folderCount, info.bookmarkCount)}',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        if (backupBusy)
          const Padding(
            padding: EdgeInsets.all(6),
            child: CircularProgressIndicator(),
          )
        else
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.cloud_upload),
                label: const Text('Back up all'),
                onPressed: backUpAll,
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.cloud_download),
                label: const Text('Restore'),
                onPressed: info == null ? null : restoreAll,
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.download_for_offline),
                label: const Text('Download all'),
                onPressed: cloudBookmarks.isEmpty ? null : downloadAllBookmarks,
              ),
            ],
          ),
        const SizedBox(height: 4),
        Text(
          'Folders included. Restore replaces what is on this device. '
          'A backup made before a password change cannot be read.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  String titleOf(Bookmark bookmark) =>
      bookmark.note.trim().isEmpty ? bookmark.name : bookmark.note;

  Widget buildLocalBookmarksList() {
    return Card(
      child: ListView(
        controller: localListController,
        children: buildTree(
          localFolders,
          localBookmarks,
          (bookmark) => IconButton(
            icon: const Icon(Icons.cloud_upload),
            onPressed: () => transferToCloud(bookmark),
          ),
        ),
      ),
    );
  }

  Widget buildCloudBookmarksList() {
    return Card(
      child: ListView(
        children: [
          if (backupError != null)
            ListTile(title: Text(backupError!))
          else
            ...buildTree(backupFolders, backupBookmarks, null),
          if (cloudBookmarks.isNotEmpty) ...[
            ListTile(
              dense: true,
              title: Text(
                'Single uploads (no folders)',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            for (final bookmark in cloudBookmarks)
              ListTile(
                leading: const Icon(Icons.bookmark_border),
                title: Text(titleOf(bookmark)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.cloud_download),
                      onPressed: () => downloadBookmark(bookmark),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => deleteFromCloud(bookmark),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// The folders under [parentId] as collapsible rows, each holding its own
  /// subfolders and bookmarks, followed by the bookmarks directly in it. A
  /// folder or bookmark whose parent is missing is shown at the top level.
  List<Widget> buildTree(List<Folder> folders, List<Bookmark> bookmarks,
      Widget? Function(Bookmark)? trailing,
      {int parentId = -1}) {
    final folderIds = {for (final f in folders) f.id};
    int parentOf(Folder f) =>
        folderIds.contains(f.parentFolderId) ? f.parentFolderId! : -1;
    int folderOf(Bookmark b) =>
        folderIds.contains(b.folderId) ? b.folderId : -1;

    int countIn(int folderId) =>
        bookmarks.where((b) => folderOf(b) == folderId).length +
        folders
            .where((f) => parentOf(f) == folderId && f.id != folderId)
            .fold(0, (n, f) => n + countIn(f.id));

    final children = folders
        .where((f) => parentOf(f) == parentId && f.id != parentId)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final here = bookmarks.where((b) => folderOf(b) == parentId).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return [
      for (final folder in children)
        ExpansionTile(
          leading: const Icon(Icons.folder),
          title: Text('${folder.name} (${countIn(folder.id)})'),
          childrenPadding: const EdgeInsets.only(left: 24),
          children:
              buildTree(folders, bookmarks, trailing, parentId: folder.id),
        ),
      for (final bookmark in here)
        ListTile(
          leading: const Icon(Icons.bookmark_border),
          title: Text(titleOf(bookmark)),
          trailing: trailing?.call(bookmark),
        ),
    ];
  }
}
