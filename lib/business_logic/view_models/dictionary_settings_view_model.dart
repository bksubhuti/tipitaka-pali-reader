import 'package:flutter/material.dart';
import 'package:tipitaka_pali/business_logic/models/book.dart';
import 'package:tipitaka_pali/business_logic/models/recent.dart';
import 'package:tipitaka_pali/business_logic/models/dictionary.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/repositories/dictionary_book_repo.dart';

import '../../routes.dart';

class DictionarySettingController extends ChangeNotifier {
  List<Dictionary> userDicts = [];
  final UserDictRepository _repository =
      UserDictDatabaseRepository(DatabaseHelper());

  Future<void> fetchUserDicts() async {
    userDicts = await _repository.getUserDicts();
    notifyListeners();
  }

  Future<void> changeOrder(int oldIndex, int newIndex) async {
    final index = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final dictionary = userDicts.removeAt(oldIndex);
    userDicts.insert(index, dictionary);
    final length = userDicts.length;
    for (int i = 0; i < length; i++) {
      userDicts[i] = userDicts[i].copyWith(order: i);
    }
    _repository.updateDall(userDicts);
    notifyListeners();
  }

  Future<void> onCheckedChange(int index, bool value) async {
    userDicts[index] = userDicts[index].copyWith(userChoice: value);
    _repository.update(userDicts[index]);
    notifyListeners();
  }

/*
  Future<void> delete(int index) async {
    final Recent recent = recents[index];
    recents.removeAt(index);
    notifyListeners();
    await _repository.delete(recent);
  }

  Future<void> deleteAll() async {
    recents.clear();
    notifyListeners();
    await _repository.deleteAll();
  }

*/
  void openBook(Recent recent, BuildContext context) {
    final book = Book(id: recent.bookID, name: recent.bookName!);
    Navigator.pushNamed(context, readerRoute, arguments: {
      'book': book,
      'currentPage': recent.pageNumber,
    });
  }
}
