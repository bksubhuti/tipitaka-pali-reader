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
      if (!mounted) return;
      backupError = errorText(e);
    }
    if (mounted) setState(() {});
  }

  String describe(int folders, int bookmarks) =>
      AppLocalizations.of(context)!.folderBookmarkCount(folders, bookmarks);

  /// What went wrong, for the reader: the backup's own failures in their
  /// language, anything else (such as a network error) as it came.
  String errorText(Object e) {
    final l = AppLocalizations.of(context)!;
    if (e is BookmarkBackupException) {
      return switch (e.failure) {
        BookmarkBackupFailure.encrypt => l.backupEncryptFailed,
        BookmarkBackupFailure.read => l.backupReadFailed,
      };
    }
    return e.toString().replaceFirst('Exception: ', '');
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> runBackupTask(Future<void> Function() task) async {
    setState(() => backupBusy = true);
    try {
      await task();
    } catch (e) {
      if (mounted) showMessage(errorText(e));
    }
    if (mounted) setState(() => backupBusy = false);
  }

  void backUpAll() => runBackupTask(() async {
        backupInfo = await backupRepo.backUp();
        await fetchBackupContents();
        if (mounted) {
          showMessage(AppLocalizations.of(context)!.backedUpSummary(
              describe(backupInfo!.folderCount, backupInfo!.bookmarkCount)));
        }
      });

  void restoreAll() async {
    final info = backupInfo;
    if (info == null) return;
    final (folders, bookmarks) = await backupRepo.localCounts();
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => RestoreConfirmDialog(
        localSummary: describe(folders, bookmarks),
        date: formatDate(info.created),
        backupSummary: describe(info.folderCount, info.bookmarkCount),
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
        showMessage(AppLocalizations.of(context)!
            .restoredSummary(describe(info.folderCount, info.bookmarkCount)));
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
          final l = AppLocalizations.of(context)!;
          showMessage(skipped > 0
              ? l.bookmarksAddedSkipped(added, skipped)
              : l.bookmarksAdded(added));
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
    return CloudBackupSection(
      summary: info == null
          ? null
          : AppLocalizations.of(context)!.cloudBackupSummary(
              formatDate(info.created),
              describe(info.folderCount, info.bookmarkCount)),
      busy: backupBusy,
      onBackUp: backUpAll,
      onRestore: info == null ? null : restoreAll,
      onDownloadAll: cloudBookmarks.isEmpty ? null : downloadAllBookmarks,
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
                AppLocalizations.of(context)!.singleUploadsNoFolders,
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

/// The cloud backup at the top of the transfer dialog: what the backup holds
/// ([summary], or null when there is none), its buttons, and a note.
///
/// A null callback disables its button. While [busy], a spinner stands in
/// for the buttons.
class CloudBackupSection extends StatelessWidget {
  final String? summary;
  final bool busy;
  final VoidCallback onBackUp;
  final VoidCallback? onRestore;
  final VoidCallback? onDownloadAll;

  const CloudBackupSection({
    super.key,
    required this.summary,
    required this.busy,
    required this.onBackUp,
    required this.onRestore,
    required this.onDownloadAll,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      children: [
        Text(
          summary ?? l.noCloudBackupYet,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        if (busy)
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
                label: Text(l.backUpAll),
                onPressed: onBackUp,
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.cloud_download),
                label: Text(l.restore),
                onPressed: onRestore,
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.download_for_offline),
                label: Text(l.downloadAll),
                onPressed: onDownloadAll,
              ),
            ],
          ),
        const SizedBox(height: 4),
        Text(
          l.cloudBackupNote,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Asks before a restore replaces the bookmarks on this device. Pops true
/// to replace them.
class RestoreConfirmDialog extends StatelessWidget {
  final String localSummary;
  final String date;
  final String backupSummary;

  const RestoreConfirmDialog({
    super.key,
    required this.localSummary,
    required this.date,
    required this.backupSummary,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l.restoreFromCloudTitle),
      content:
          Text(l.restoreFromCloudMessage(localSummary, date, backupSummary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.replace),
        ),
      ],
    );
  }
}
