import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:tipitaka_pali/services/ai_search_service.dart';
import 'package:tipitaka_pali/services/ai_search_history_manager.dart';
import 'package:tipitaka_pali/ui/screens/home/openning_books_provider.dart';
import 'package:tipitaka_pali/ui/screens/home/search_page/search_page.dart';
import 'package:tipitaka_pali/ui/screens/reader/mobile_reader_container.dart';
import 'package:tipitaka_pali/ui/screens/home/widgets/search_result_list_tile.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/ui/screens/settings/settings.dart';
import 'package:tipitaka_pali/ui/widgets/ai_help_dialog.dart';
import 'package:tipitaka_pali/utils/platform_info.dart';
import 'package:url_launcher/url_launcher.dart';

class AiSearchPage extends StatefulWidget {
  final String query;

  const AiSearchPage({super.key, required this.query});

  @override
  State<AiSearchPage> createState() => _AiSearchPageState();
}

class _AiSearchPageState extends State<AiSearchPage> {
  late final TextEditingController _queryController;
  final List<String> _logs = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  List<AiMatchedResult> _results = [];
  String _summary = '';
  late double _maxResults = Prefs.aiMaxResults.toDouble();
  final AiSearchHistoryManager _historyManager = AiSearchHistoryManager();

  AiSearchService? _aiSearchService;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.query);
    _initHistory();
  }
  
  Future<void> _initHistory() async {
    await _historyManager.init();
    if (mounted) {
      setState(() {});
      if (widget.query.trim().isNotEmpty && Prefs.geminiDirectApiKey.isNotEmpty) {
        _runAiSearch();
      }
    }
  }

  Future<void> _runAiSearch() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _hasSearched = true;
      _logs.clear();
      _logs.add('Starting AI search for "$query"...');
      _results.clear();
      _summary = '';
    });

    _aiSearchService = AiSearchService(
      onStatusUpdate: (message) {
        if (mounted) {
          setState(() {
            _logs.add(message);
          });
        }
      },
    );

    final result = await _aiSearchService!.search(query, maxResults: _maxResults.toInt());

    if (mounted) {
      setState(() {
        _isSearching = false;
        _results = result.results;
        _summary = result.summary;
        _logs.add('Search complete');
      });
      
      // Save to history after successful search
      if (result.results.isNotEmpty || result.summary.isNotEmpty) {
        await _historyManager.add(query, result);
        setState(() {});
      }
    }
  }

  void _loadFromHistory(AiSearchHistoryItem item) {
    _queryController.text = item.query;
    FocusScope.of(context).unfocus();
    setState(() {
      _isSearching = false;
      _hasSearched = true;
      _results = item.result.results;
      _summary = item.result.summary;
      _logs.clear();
      _logs.add('Loaded from history');
    });
  }

  void _openBook(AiMatchedResult match) {
    final openningBookProvider = context.read<OpenningBooksProvider>();
    openningBookProvider.add(
      book: match.searchResult.book,
      currentPage: match.searchResult.pageNumber,
      textToHighlight: match.term,
      queryMode: match.queryMode == QueryMode.prefix
          ? QueryMode.anywhere
          : match.queryMode,
    );

    if (Mobile.isPhone(context)) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const MobileReaderContainer()));
    }
  }

  Future<void> _copyToClipboard() async {
    final buffer = StringBuffer();
    buffer.writeln('AI Search Query: "${_queryController.text}"');
    buffer.writeln('\n--- AI Thinking ---');
    buffer.writeln(_summary);
    buffer.writeln('--- Results ---');

    if (_results.isEmpty) {
      buffer.writeln('No results found.');
    } else {
      for (int i = 0; i < _results.length; i++) {
        final r = _results[i].searchResult;
        final cleanDesc = r.description
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

        buffer.writeln('${i + 1}. Book: ${r.book.name}');
        if (r.suttaName.isNotEmpty) {
          buffer.writeln('   Sutta: ${r.suttaName}');
        }
        buffer.writeln('   Page: ${r.pageNumber}');
        buffer.writeln('   "$cleanDesc"');
        buffer.writeln('');
      }
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Copied thinking and results to clipboard')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Search'),
        actions: [
          if (_isSearching)
            TextButton.icon(
              icon: const Icon(Icons.stop, size: 20),
              label: const Text('Cancel'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: () {
                _aiSearchService?.cancel();
                setState(() {
                  _logs.add('Cancelling search...');
                });
              },
            ),
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.speed),
              tooltip: 'Check API Rate Limit',
              onPressed: () async {
                final url = Uri.parse('https://aistudio.google.com/rate-limit/');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
            ),
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy thinking and results',
              onPressed: _copyToClipboard,
            ),
          if (!_isSearching && !_hasSearched && _historyManager.history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear History',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Clear AI History?'),
                    content: const Text('Are you sure you want to delete all saved AI searches?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _historyManager.deleteAll();
                  setState(() {});
                }
              },
            ),
        ],
      ),
      body: Column(
        children: [
          if (Prefs.geminiDirectApiKey.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.vpn_key_off, size: 48, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        'You need to get a free key and put it in the AI settings to use AI Search.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.key),
                        label: const Text('Get Key'),
                        onPressed: () => showAiHelpDialog(context),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.settings),
                        label: const Text('TPR AI Settings'),
                        onPressed: () {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const SettingPage()));
                        },
                      ),
                    ],
                  ),
                ),
              ),
            )
          else ...[
            // Search Input
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Slider for results count
                  Row(
                    children: [
                      Text(
                        'Results to analyze:',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Expanded(
                        child: Slider(
                          value: _maxResults,
                          min: 10,
                          max: 100,
                          divisions: 9,
                          label: _maxResults.round().toString(),
                          onChanged: _isSearching
                              ? null
                              : (value) {
                                  setState(() {
                                    _maxResults = value;
                                  });
                                },
                          onChangeEnd: (value) {
                            Prefs.aiMaxResults = value.toInt();
                          },
                        ),
                      ),
                      Text(
                        _maxResults.round().toString(),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _queryController,
                          maxLines: 4,
                          minLines: 1,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText:
                                'Ask in English (e.g. When did the Buddha teach dullabho?)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                          onSubmitted: (_) {
                            if (!_isSearching) _runAiSearch();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        icon: const Icon(Icons.send),
                        onPressed: _isSearching
                            ? null
                            : () {
                                FocusScope.of(context).unfocus();
                                _runAiSearch();
                              },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Status / Progress
            if (_isSearching)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .dividerColor
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context)
                              .dividerColor
                              .withValues(alpha: 0.2),
                        ),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: ListView.builder(
                        reverse: true,
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          final logText = _logs[_logs.length - 1 - index];
                          final isError = logText.contains('Error') ||
                              logText.contains('failed');
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              logText,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    fontFamily: 'monospace',
                                    color: isError ? Colors.red : null,
                                  ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),

            // Summary and Results
            if (!_isSearching && _hasSearched)
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    if (_summary.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: Card(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.1),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.lightbulb_outline,
                                    size: 20,
                                    color:
                                        Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: SelectableText(
                                    _summary,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${_results.length} results found',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                        ),
                      ),
                    ),
                    if (_results.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'No results found.\nTry rephrasing your question.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                      )
                    else
                      ..._results.map((match) => SearchResultListTile(
                            result: match.searchResult,
                            onTap: () => _openBook(match),
                          )),
                  ],
                ),
              ),

            // AI Search History
            if (!_isSearching && !_hasSearched && _historyManager.history.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: _historyManager.history.length,
                  itemBuilder: (context, index) {
                    final item = _historyManager.history[index];
                    return ListTile(
                      leading: const Icon(Icons.history),
                      title: Text(item.query, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${item.result.results.length} results • ${item.timestamp.toLocal().toString().split('.')[0]}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await _historyManager.delete(item.query);
                          setState(() {});
                        },
                      ),
                      onTap: () {
                        _loadFromHistory(item);
                      },
                    );
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }
}
