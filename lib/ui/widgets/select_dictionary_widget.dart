import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tipitaka_pali/business_logic/view_models/dictionary_settings_view_model.dart';

class SelectDictionaryWidget extends StatelessWidget {
  const SelectDictionaryWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DictionarySettingController>(
      create: (context) {
        var vm = DictionarySettingController();
        vm.fetchUserDicts();
        return vm;
      },
      child:
          Consumer<DictionarySettingController>(builder: (context, vm, child) {
        final dictionaries = vm.userDicts;
        // print(userDicts);
        return ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // Our own handle, on the right. The default one added a second
          // handle beside it on desktop.
          buildDefaultDragHandles: false,
          padding: const EdgeInsets.only(bottom: 8),
          itemCount: dictionaries.length,
          itemBuilder: (context, index) {
            // Each dictionary as its own card, so the rows stand apart. They
            // sit inside the settings card, so an outline marks them where a
            // second fill of the same colour would not show. A long press
            // anywhere picks one up, as before.
            return ReorderableDelayedDragStartListener(
              key: Key('${dictionaries[index].bookID}'),
              index: index,
              child: Card.outlined(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ListTile(
                  leading: Checkbox(
                    value: dictionaries[index].userChoice,
                    onChanged: (value) => vm.onCheckedChange(
                        index, value!, dictionaries[index].bookID),
                  ),
                  title: Text(dictionaries[index].name),
                  // subtitle: Text('${vm.userDicts[index].userOrder}'),
                  trailing: ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle),
                  ),
                ),
              ),
            );
          },
          onReorder: (oldIndex, newIndex) => vm.changeOrder(oldIndex, newIndex),
        );
      }),
    );
  }
}
