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
import 'package:tipitaka_pali/utils/platform_info.dart';
import 'package:tipitaka_pali/utils/pali_script.dart';
import 'package:tipitaka_pali/services/provider/script_language_provider.dart';
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

  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!Prefs.aiTermsOfService) {
        _showTermsOfServiceDialog();
      }
    });

    _queryController = TextEditingController(text: widget.query);
    _focusNode = FocusNode(
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            if (HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isShiftPressed) {
              final text = _queryController.text;
              final selection = _queryController.selection;

              if (selection.start == -1 || selection.end == -1) {
                _queryController.text = text + '\n';
                _queryController.selection = TextSelection.collapsed(
                    offset: _queryController.text.length);
              } else {
                final newText =
                    text.replaceRange(selection.start, selection.end, '\n');
                _queryController.value = TextEditingValue(
                  text: newText,
                  selection:
                      TextSelection.collapsed(offset: selection.start + 1),
                );
              }
              return KeyEventResult.handled;
            } else {
              if (!_isSearching) {
                _runAiSearch();
              }
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      },
    );
    _initHistory();
  }

  @override
  void dispose() {
    _queryController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _initHistory() async {
    await _historyManager.init();
    if (mounted) {
      setState(() {});
      if (widget.query.trim().isNotEmpty) {
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

    final result =
        await _aiSearchService!.search(query, maxResults: _maxResults.toInt());

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

  void _showTermsOfServiceDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Suggested API Terms of Use Disclaimer'),
        content: SizedBox(
            width: Prefs.panelWidth,
            child: const SingleChildScrollView(
              child: Text('''Third-Party API Usage & Liability

Dāna or sponsored service does not use American made AI models.  

This application allows users to connect to third-party AI services (such as OpenRouter and Google AI Studio) using their own personal API keys. By entering your API key, you acknowledge and agree to the following:

Provider Terms of Service: You are solely responsible for complying with the Terms of Service, usage limits, and billing policies of your chosen AI API provider.

Geographic Restrictions & Compliance: You are strictly responsible for ensuring your use of the API complies with the provider's regional availability and export policies. The developer assumes no liability if a user accesses these services from an unsupported region (e.g., via VPN or other masking tools) in violation of the provider's rules.

No App Liability: The developer of this application is not responsible for any account suspensions, API key revocations, or financial charges incurred from your use of third-party APIs. The app functions solely as a local interface to transmit your requests.'''),
            )),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              // Use the page's context (not the dialog's) to pop
              if (this.mounted && Navigator.canPop(this.context)) {
                Navigator.pop(this.context); // Close search window
              }
            },
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Prefs.aiTermsOfService = true;
              Navigator.pop(context); // Close dialog
            },
            child: const Text('Agree'),
          ),
        ],
      ),
    );
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
      final currentScript =
          context.read<ScriptLanguageProvider>().currentScript;

      for (int i = 0; i < _results.length; i++) {
        final r = _results[i].searchResult;
        final cleanDesc = r.description
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

        final translatedDesc =
            PaliScript.getScriptOf(script: currentScript, romanText: cleanDesc);
        final translatedBook = PaliScript.getScriptOf(
            script: currentScript, romanText: r.book.name);
        final translatedPage = PaliScript.getScriptOf(
            script: currentScript, romanText: r.pageNumber.toString());

        buffer.writeln('${i + 1}. Book: $translatedBook');
        if (r.suttaName.isNotEmpty) {
          final translatedSutta = PaliScript.getScriptOf(
              script: currentScript, romanText: r.suttaName);
          buffer.writeln('   Sutta: $translatedSutta');
        }
        buffer.writeln('   Page: $translatedPage');
        buffer.writeln('   "$translatedDesc"');
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
                final url =
                    Uri.parse('https://aistudio.google.com/rate-limit/');
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
          if (!_isSearching && _hasSearched)
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'Show History',
              onPressed: () {
                setState(() {
                  _hasSearched = false;
                  _queryController.clear();
                  _summary = '';
                  _results.clear();
                  _logs.clear();
                });
              },
            ),
          if (!_isSearching &&
              !_hasSearched &&
              _historyManager.history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear History',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Clear AI History?'),
                    content: const Text(
                        'Are you sure you want to delete all saved AI searches?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Clear')),
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
          // The UI is no longer blocked because we gracefully fallback to Sponsored Mode
          ...[
            // Search Input
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (Prefs.aiProviderMode == 2)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(
                        'Sponsored Mode: ${Prefs.aiSponsoredTriesLeft} queries remaining today',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: (Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.fontSize ??
                                      12.0) *
                                  1.3,
                              color: Prefs.aiSponsoredTriesLeft > 0
                                  ? Colors.green
                                  : Colors.red,
                            ),
                      ),
                    ),
                  // Slider for results count
                  if (Prefs.aiProviderMode != 2)
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
                          focusNode: _focusNode,
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
            if (!_isSearching &&
                !_hasSearched &&
                _historyManager.history.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: _historyManager.history.length,
                  itemBuilder: (context, index) {
                    final item = _historyManager.history[index];
                    return ListTile(
                      leading: const Icon(Icons.history),
                      title: Text(item.query,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
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
