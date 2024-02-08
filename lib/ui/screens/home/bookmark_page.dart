import 'dart:io';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tipitaka_pali/business_logic/models/folder.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/provider/bookmark_provider.dart';
import 'package:tipitaka_pali/services/repositories/bookmark_repo.dart';
import 'package:tipitaka_pali/services/repositories/folder_epository%20%7B.dart';
import 'package:tipitaka_pali/ui/screens/home/bookmark_app_bar.dart';
import 'package:tipitaka_pali/ui/screens/home/widgets/folder_path_navigator.dart';

import '../../../../services/provider/script_language_provider.dart';
import '../../../../utils/pali_script.dart';
import '../../../business_logic/models/bookmark.dart';
import '../../../business_logic/view_models/bookmark_page_view_model.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';

class BookmarkPage extends StatefulWidget {
  const BookmarkPage({super.key});

  @override
  State<BookmarkPage> createState() => _BookmarkPageState();
}

class _BookmarkPageState extends State<BookmarkPage>
    with WidgetsBindingObserver {
  bool _isCurrentlyMounted = true; // New variable to track mounted state
  List<dynamic> items = []; // This will hold both Bookmarks and Folders

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkInternetConnectivity();
    _isCurrentlyMounted = true;
    Provider.of<BookmarkPageViewModel>(context, listen: false)
        .fetchItemsInCurrentFolder(); // Fetch root items
  }

  @override
  void dispose() {
    _isCurrentlyMounted = false; // Update mounted state
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleDialogClose() {
    if (mounted) {
      // Check if BookmarkPage is still mounted
      context.read<BookmarkPageViewModel>().refreshBookmarks();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkInternetConnectivity();
    }
  }

  void _checkInternetConnectivity() async {
    bool hasInternet = await InternetConnection().hasInternetAccess;
    if (!hasInternet) {
      setState(() {
        Prefs.isSignedIn = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Note: Assuming _createNewFolder and _buildItem are defined in this class.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => BookmarkPageViewModel()..fetchItemsInCurrentFolder(),
        ),
        // Include other providers as needed
        ChangeNotifierProvider(
          create: (_) => BookmarkNotifier(),
        ),
      ],
      child: Scaffold(
        appBar: BookmarkAppBar(onDialogClose: () {
          // Assuming this is correctly defined to handle dialog closure
        }),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _createNewFolder(context),
          tooltip: 'Create New Folder',
          child: const Icon(Icons.create_new_folder),
        ),
        body: Consumer<BookmarkPageViewModel>(
          builder: (context, viewModel, child) {
            final items =
                viewModel.items; // This includes both bookmarks and folders

            return Column(
              children: [
                // Navigation path widget
                FolderPathNavigator(
                  path: viewModel.navigationPath,
                  onFolderTap: (Folder folder) {
                    if (folder.id == -1) {
                      // Assuming -1 is your ID for "Root"
                      viewModel.setCurrentFolderAndFetchItems(-1);
                    } else {
                      viewModel.goToFolderInPath(folder);
                    }
                  },
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: viewModel.items.length,
                    itemBuilder: (context, index) => _buildItem(
                        context, viewModel.items[index], viewModel, index),
                    separatorBuilder: (context, index) => const Divider(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, dynamic item,
      BookmarkPageViewModel viewModel, index) {
    bool isFolder = item is Folder;
    IconData icon = isFolder ? Icons.folder : Icons.bookmark;
    Color folderColor = Theme.of(context).primaryColor; // Example color coding
    String titlePrefix = isFolder ? '[Folder]\n' : '';
    String title = titlePrefix + (isFolder ? item.name : item.name + item.note);
    String subtitle = isFolder ? "" : "Page ${item.pageNumber}";

    return ListTile(
        dense: true,
        leading: Icon(icon,
            color:
                isFolder ? folderColor : null), // Apply color to icon as well
        title:
            Text(title, style: TextStyle(color: isFolder ? folderColor : null)),
        subtitle: Text(subtitle),
        onTap: () {
          if (isFolder) {
            viewModel.setCurrentFolderAndFetchItems(item.id,
                folderName: item.name);
            // Handle folder tap, e.g., navigate to a folder detail view or expand
          } else {
            // Handle bookmark tap, e.g., open the bookmarked content
            viewModel.openBook(item, context);
          }
        },
        trailing: _buildSpeedDial(context, item, viewModel, index));
  }

  void _deleteItem(BuildContext context, dynamic item,
      BookmarkPageViewModel viewModel) async {
    bool confirm = await _showDeleteConfirmationDialog(context);
    if (confirm) {
      if (item is Bookmark) {
        viewModel.deleteBookmark(item.id);
      } else if (item is Folder) {
        viewModel.deleteFolderAndSubfolders(item.id);
      }
      // Refresh your ViewModel data
      viewModel.fetchItemsInCurrentFolder();
    }
  }

  void _edit(context, item, viewModel) {
    if (item is Folder) {
      _editFolder(context, item, viewModel);
    } else {
      _editBookmark(context, item, viewModel);
    }
  }

  Future<bool> _showDeleteConfirmationDialog(BuildContext context) async {
    return (await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm Delete'),
            content: const Text('Are you sure you want to delete this item?'),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              TextButton(
                child: const Text('Delete'),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        )) ??
        false;
  }

  void _createNewFolder(BuildContext context) async {
    String? folderName = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        TextEditingController folderNameController = TextEditingController();
        return AlertDialog(
          title: const Text('New Folder'),
          content: TextField(
            controller: folderNameController,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Folder Name'),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: const Text('Create'),
              onPressed: () {
                Navigator.pop(context, folderNameController.text);
              },
            ),
          ],
        );
      },
    );

    if (folderName != null && folderName.isNotEmpty) {
      var viewModel =
          Provider.of<BookmarkPageViewModel>(context, listen: false);
      viewModel.addAndNavigateToFolder(folderName,
          viewModel.currentFolderId); // or any other method as required
    }
  }

  void _moveToFolderDialog(
      BuildContext context, BookmarkPageViewModel viewModel, item) async {
    // Fetch list of folders from the database
    final FolderDatabaseRepository folderRepository =
        FolderDatabaseRepository(DatabaseHelper());
    int? exclusionId = item is Folder ? item.id : null;

    List<Folder> folders =
        await folderRepository.fetchAllFolders(exclusionId: exclusionId);

    String? selectedFolderIdStr = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Move to Folder'),
          content: SingleChildScrollView(
            child: ListBody(
              children: folders
                  .map((folder) => ListTile(
                        title: Text(folder.name),
                        onTap: () => Navigator.pop(context,
                            folder.id.toString()), // Convert id to String
                      ))
                  .toList(),
            ),
          ),
        );
      },
    );

    if (selectedFolderIdStr != null) {
      int? selectedFolderId =
          int.tryParse(selectedFolderIdStr); // Convert back to int
      if (selectedFolderId != null) {
        // Assuming both Bookmark and Folder have a 'folderId' field
        if (item is Bookmark) {
          // Update the bookmark with the new folderId
          final BookmarkDatabaseRepository bookmarkDatabaseRepository =
              BookmarkDatabaseRepository(DatabaseHelper());
          await bookmarkDatabaseRepository.updateBookmarkFolder(
              item.id, selectedFolderId);
        } else if (item is Folder) {
          // Update the folder with the new parent folderId
          await folderRepository.updateFolderParentId(
              item.id, selectedFolderId);
        }
        viewModel.fetchItemsInCurrentFolder();
        // Refresh the UI accordingly, possibly by calling setState or using a state management solution
      }
    }
  }

  String localScript(BuildContext context, String s) {
    return PaliScript.getScriptOf(
        script: context.read<ScriptLanguageProvider>().currentScript,
        romanText: s);
  }

  Future<void> _editFolder(BuildContext context, Folder folder,
      BookmarkPageViewModel viewModel) async {
    String? newName = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        TextEditingController _controller =
            TextEditingController(text: folder.name);
        return AlertDialog(
          title: const Text('Edit Folder Name'),
          content: TextField(
            controller: _controller,
            decoration: const InputDecoration(
              hintText: 'Enter new folder name',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(_controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (newName != null && newName.isNotEmpty && newName != folder.name) {
      folder.name = newName;
      await viewModel.updateFolderName(folder);
    }
  }

// Function to show an edit dialog and update the bookmark note
  Future<void> _editBookmark(BuildContext context, Bookmark bookmark,
      BookmarkPageViewModel viewModel) async {
    String? newNote = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        TextEditingController _controller =
            TextEditingController(text: bookmark.note);
        return AlertDialog(
          title: const Text('Edit Bookmark Note'),
          content: TextField(
            controller: _controller,
            decoration: const InputDecoration(
              hintText: 'Enter new note',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(_controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (newNote != null && newNote.isNotEmpty && newNote != bookmark.note) {
      bookmark.note = newNote;
      await viewModel.updateBookmarkNote(bookmark);
    }
  }

  Future<void> shareBookmarksAsFile(List<Bookmark> bookmarks) async {
    final String bookmarkJson = bookmarkToJson(bookmarks);
    final Directory tempDir = await getTemporaryDirectory();
    final File file = File('${tempDir.path}/bookmarks.tprbmk');

    await file.writeAsString(bookmarkJson);

    // Create an XFile object from the saved file
    final XFile xfile = XFile(file.path);

    // Use shareXFiles to share the XFile
    await Share.shareXFiles([xfile], text: 'Here are my bookmarks!');
  }

  Widget _buildSpeedDial(BuildContext context, dynamic item,
      BookmarkPageViewModel viewModel, int index) {
    // Set the direction of the speed dial
    SpeedDialDirection direction =
        (index <= 1) ? SpeedDialDirection.down : SpeedDialDirection.up;

    return SpeedDial(
      direction: direction,
      animatedIcon: AnimatedIcons
          .menu_close, // This icon will animate when the speed dial is opened or closed
      spaceBetweenChildren: 4, // Adjust the spacing as needed
      children: [
        // Only add this SpeedDialChild if item is a Bookmark
        if (item is Bookmark)
          SpeedDialChild(
            child: const Icon(Icons.share),
            label: 'Share',
            onTap: () => Share.share(
              item.toString(),
              subject:
                  'Share Bookmark', // Replace with your localization or custom text
            ),
          ),
        SpeedDialChild(
          child: const Icon(Icons.edit),
          label: 'Edit',
          onTap: () => _edit(context, item, viewModel), // Your edit logic
        ),
        SpeedDialChild(
          child: const Icon(Icons.drive_file_move),
          label: 'Move To Folder',
          onTap: () =>
              _moveToFolderDialog(context, viewModel, item), // Your move logic
        ),
        SpeedDialChild(
          child: const Icon(Icons.delete),
          label: 'Delete',
          onTap: () =>
              _deleteItem(context, item, viewModel), // Your delete logic
        ),
      ],
    );
  }
}
