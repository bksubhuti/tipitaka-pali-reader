import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/business_logic/models/folder.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/repositories/bookmark_repo.dart';
import 'package:tipitaka_pali/services/repositories/folder_epository%20%7B.dart';

import '../../ui/screens/home/openning_books_provider.dart';
import '../../ui/screens/reader/mobile_reader_container.dart';
import '../../utils/platform_info.dart';
import '../models/book.dart';
import '../models/bookmark.dart';

class BookmarkPageViewModel extends ChangeNotifier {
  BookmarkPageViewModel() {
    _navigationPath.add(Folder(id: -1, name: 'Root', parentFolderId: null));
  }

  List<Folder> _navigationPath = [];
  List<Folder> get navigationPath => _navigationPath;

  int _currentFolderId = -1; // Default to root
  List<Bookmark> _bookmarks = [];
  List<Folder> _folders = [];
  List<dynamic> _items = []; // Combined list of folders and bookmarks

  final _bookmarkRepository = BookmarkDatabaseRepository(DatabaseHelper());
  final _folderRepository = FolderDatabaseRepository(DatabaseHelper());

  List<Bookmark> get bookmarks => _bookmarks;
  List<Folder> get folders => _folders;

  // Getter for clients to read the current state
  List<dynamic> get items => [..._folders, ..._bookmarks];
  int get currentFolderId => _currentFolderId;

  // Fetch bookmarks and folders by current folder ID
  Future<void> fetchItemsInCurrentFolder() async {
    _folders.clear();
    _bookmarks.clear();
    // Fetch folders and bookmarks within the specific folder
    _folders = await _folderRepository.fetchFoldersByParentId(_currentFolderId);
    _bookmarks =
        await _bookmarkRepository.fetchBookmarksByFolderId(_currentFolderId);
    _items = [..._folders, ..._bookmarks]; // Combine folders and bookmarks
    notifyListeners();
  }

  // Method to update current folder and fetch its contents
  Future<void> setCurrentFolderAndFetchItems(int folderId,
      {String folderName = 'Root'}) async {
    _currentFolderId = folderId;

    // Clear the navigation path and start fresh if navigating to root
    if (folderId == -1) {
      _navigationPath.clear();
      // Always add "Root" as the starting point of the navigation path
      _navigationPath.add(Folder(id: -1, name: 'Root', parentFolderId: -1));
    } else {
      // Check if we are navigating to a folder directly from root or a different folder
      if (_navigationPath.isEmpty || _navigationPath.last.id != folderId) {
        // This approach assumes direct navigation to the folder without rebuilding the entire path
        // If you're navigating deeper, consider reconstructing the path based on folder hierarchy
        _navigationPath
            .clear(); // Clear any previous path if directly navigating to a folder
        _navigationPath.add(Folder(
            id: -1,
            name: 'Root',
            parentFolderId: -1)); // Always start with Root
        _navigationPath.add(Folder(
            id: folderId,
            name: folderName,
            parentFolderId: null)); // Add the target folder
      }
    }

    await fetchItemsInCurrentFolder();
  }

  void goToFolderInPath(Folder folder) async {
    _currentFolderId = folder.id;
    // Find the index of the folder in the path to truncate the path correctly
    int index = _navigationPath.indexOf(folder);
    if (index != -1) {
      _navigationPath = _navigationPath.sublist(0, index + 1);
    }
    await fetchItemsInCurrentFolder();
  }

  Future<void> fetchBookmarksAndFolders() async {
    _items.clear();
    _bookmarks =
        await _bookmarkRepository.fetchBookmarksByFolderId(currentFolderId);
    _folders = await _folderRepository.fetchFoldersByParentId(currentFolderId);
    _items = [..._folders, ..._bookmarks];
    notifyListeners();
  }

  Future<void> fetchBookmarks() async {
    _bookmarks =
        await _bookmarkRepository.fetchBookmarksByFolderId(currentFolderId);
    notifyListeners();
  }

  Future<void> deleteBookmark(int bookmarkId) async {
    // Assuming each bookmark has a unique identifier
    _bookmarks.removeWhere((bookmark) => bookmark.id == bookmarkId);
    await _bookmarkRepository
        .deleteBookmark(bookmarkId); // Adjust based on your repository method
    notifyListeners();
  }

  Future<void> deleteFolder(int folderId) async {
    // Assuming folders are managed in a similar way and have a unique identifier
    _folders.removeWhere((folder) => folder.id == folderId);
    await _folderRepository
        .deleteFolder(folderId); // Adjust based on your repository method
    notifyListeners();
  }

  Future<void> deleteAll() async {
    _bookmarks.clear();
    await _bookmarkRepository.deleteAll();
    notifyListeners();
  }

  /// The words of a bookmark's saved passage worth highlighting, or null.
  ///
  /// Null, not empty, when nothing is left. An empty string reached the
  /// highlighter as a search for "", which matches between every character:
  /// a span went in between each letter of the page, tags included, and the
  /// page showed its own HTML. Old bookmarks, saved without a passage or with
  /// only short words, opened that way.
  static String? highlightTextOf(String? selectedText) {
    final words = (selectedText ?? '')
        .split(RegExp(r'\s+'))
        .where((word) => word.length >= 4 && !word.contains(RegExp(r'\d')))
        .join(' ');
    return words.isEmpty ? null : words;
  }

  void openBook(Bookmark bookmark, BuildContext context) async {
    final book = Book(id: bookmark.bookID, name: bookmark.name);
    final openningBookProvider = context.read<OpenningBooksProvider>();

    // BUG FIX HACK  issue 217 https://github.com/bksubhuti/tipitaka-pali-reader/issues/217
    // highlighting words with numbers and small words interferes with the
    // html code.  So this is a hack until we can do system based highlights
    final textToHighlight = highlightTextOf(bookmark.selectedText);

    openningBookProvider.add(
        book: book,
        currentPage: bookmark.pageNumber,
        textToHighlight: textToHighlight);

    if (Mobile.isPhone(context)) {
      // Navigator.pushNamed(context, readerRoute,
      //     arguments: {'book': bookItem.book});
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const MobileReaderContainer()));
    }
    // update bookmarks
    _bookmarks =
        await _bookmarkRepository.fetchBookmarksByFolderId(currentFolderId);
    notifyListeners();
  }

  void refreshBookmarks() async {
    await fetchBookmarks();
    notifyListeners();
  }

  Future<void> addAndNavigateToFolder(String folderName, int parentId) async {
    int newFolderId =
        await _folderRepository.insertFolder(folderName, parentId);
    fetchBookmarksAndFolders();
  }

  Future<void> insertBookmark(Bookmark bookmark) async {
    await _bookmarkRepository.insert(bookmark);
    fetchBookmarksAndFolders();
  }

  Future<void> updateFolderName(Folder folder) async {
    // Update the folder name in the database
    // Refresh the UI or navigation path as needed
    await _folderRepository.updateFolder(folder);
    notifyListeners();
  }

  Future<void> updateBookmarkNote(Bookmark bookmark) async {
    // Update the bookmark note in the database
    // Refresh the UI as needed
    await _bookmarkRepository.updateBookmarkName(bookmark);
    notifyListeners();
  }

  Future<void> deleteFolderAndSubfolders(int folderId) async {
    // First, fetch all direct subfolders of the folder
    final db = FolderDatabaseRepository(DatabaseHelper());
    List<Folder> subfolders = await db.fetchAllSubFolders(folderId);

    // Recursively delete each subfolder
    for (var subfolder in subfolders) {
      await deleteFolderAndSubfolders(subfolder.id);
    }

    // After all subfolders are deleted, delete the folder itself
    // This will also cascade delete all bookmarks in this folder due to the foreign key constraint
    await deleteFolder(folderId);
    await fetchItemsInCurrentFolder();
    notifyListeners();
  }

  Future<List<Bookmark>> fetchAllBookmarks() async {
    return await _bookmarkRepository.getAllBookmark();
  }
}
