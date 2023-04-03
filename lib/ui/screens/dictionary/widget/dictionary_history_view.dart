import 'package:flutter/material.dart';
import 'package:tipitaka_pali/business_logic/models/dictionary_history.dart';

enum DictionaryHistoryOrder { time, alphabetically }

class DictionaryHistoryView extends StatefulWidget {
  final List<DictionaryHistory> histories;
  final ValueChanged<String>? onClick;
  final ValueChanged<String>? onDelete;

  const DictionaryHistoryView({
    super.key,
    required this.histories,
    this.onClick,
    this.onDelete,
  });

  @override
  State<DictionaryHistoryView> createState() => _DictionaryHistoryViewState();
}

class _DictionaryHistoryViewState extends State<DictionaryHistoryView> {
  DictionaryHistoryOrder order = DictionaryHistoryOrder.time;
  late List<DictionaryHistory> histories;

  @override
  void initState() {
    super.initState();
    histories = widget.histories;
  }

@override
  void didUpdateWidget(covariant DictionaryHistoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    histories = widget.histories;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.histories.isEmpty) {
      return const Center(child: Text('no history'));
    }
    if (order == DictionaryHistoryOrder.time) {
      widget.histories.sort((a, b) => a.word.compareTo(b.word));
    } else {
      widget.histories.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    }
    return Column(
      children: [
        _buildOrderSelector(),
        Expanded(
          child: ListView.separated(
            itemCount: widget.histories.length,
            itemBuilder: (context, index) {
              return ListTile(
                dense: true,
                title: Text(widget.histories[index].word),
                onTap: () => widget.onClick?.call(widget.histories[index].word),
                trailing: IconButton(
                  onPressed: () =>
                      widget.onDelete?.call(widget.histories[index].word),
                  icon: const Icon(Icons.delete),
                ),
              );
            },
            separatorBuilder: (context, index) => const Divider(height: 1),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderSelector() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          const Text('sort by: '),
          const Spacer(),
          SegmentedButton<DictionaryHistoryOrder>(
            segments: const [
              ButtonSegment<DictionaryHistoryOrder>(
                  value: DictionaryHistoryOrder.time,
                  label: Text(
                    'Time',
                  )),
              ButtonSegment<DictionaryHistoryOrder>(
                  value: DictionaryHistoryOrder.alphabetically,
                  label: Text(
                    'Alphabetically',
                  )),
            ],
            showSelectedIcon: false,
            selected: <DictionaryHistoryOrder>{order},
            onSelectionChanged: (value) {
              setState(() {
                order = value.first;
              });
            },
          ),
        ],
      ),
    );
  }
}
