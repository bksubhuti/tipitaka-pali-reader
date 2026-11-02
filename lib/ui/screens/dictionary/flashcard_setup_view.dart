import 'package:flutter/material.dart';
import 'package:tipitaka_pali/services/repositories/dictionary_repo.dart';
import 'package:tipitaka_pali/ui/screens/dictionary/flashcards_view.dart';
import '../../../business_logic/models/dictionary_history.dart';
import '../../../services/repositories/dictionary_history_repo.dart';
import '../../../services/database/database_helper.dart';
import 'package:tipitaka_pali/ui/screens/dictionary/controller/dictionary_controller.dart';
import 'package:tipitaka_pali/l10n/app_localizations.dart';
import 'package:tipitaka_pali/ui/widgets/pali_text_view.dart';

class FlashCardSetupView extends StatefulWidget {
  const FlashCardSetupView({super.key});

  @override
  _FlashCardSetupViewState createState() => _FlashCardSetupViewState();
}

class _FlashCardSetupViewState extends State<FlashCardSetupView> {
  late Future<List<DictionaryHistory>> _dictionaryHistoryFuture;
  final DictionaryHistoryRepository _repo =
      DictionaryHistoryDatabaseRepository(dbh: DatabaseHelper());

  // Tracks the selected items
  final Map<DictionaryHistory, bool> _selectedItems = {};

  @override
  void initState() {
    super.initState();
    // Initialize _dictionaryHistoryFuture
    _dictionaryHistoryFuture = _repo.getAll().then((value) {
      // A word tapped in Thai was once kept empty (#340): nothing to learn.
      value.removeWhere((item) => item.word.isEmpty);
      value.sort((a, b) =>
          b.dateTime.compareTo(a.dateTime)); // sort in descending order
      return value; // return sorted list
    });
  }

  DatabaseHelper getDatabaseHelper() {
    // Replace this with your actual implementation
    return DatabaseHelper();
  }

  @override
  Widget build(BuildContext context) {
    DictionaryController dc = DictionaryController(
        context: context,
        dictionaryHistoryRepository:
            DictionaryHistoryDatabaseRepository(dbh: DatabaseHelper()),
        dictionaryRepository: DictionaryDatabaseRepository(DatabaseHelper()));

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.flashcardSetup),
      ),
      body: FutureBuilder<List<DictionaryHistory>>(
        future: _dictionaryHistoryFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else {
            final items = snapshot.data ?? [];
            for (var item in items) {
              if (!_selectedItems.containsKey(item)) {
                _selectedItems[item] = true; // Default selected state is true
              }
            }

            return ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return CheckboxListTile(
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _selectedItems[item] ?? false,
                  onChanged: (bool? newValue) {
                    setState(() {
                      _selectedItems[item] = newValue!;
                    });
                  },
                  title: PaliTextView(item.word), // Display word for each item
                );
              },
            );
          }
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final selectedItems = _selectedItems.entries
              .where((entry) => entry.value == true)
              .map((entry) => entry.key)
              .toList();
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => FlashCardsView(
                      cards: selectedItems, dictionaryController: dc)));
        },
        label: Text(AppLocalizations.of(context)!.practiceNow),
        icon: const Icon(Icons.play_arrow),
      ),
    );
  }
}
