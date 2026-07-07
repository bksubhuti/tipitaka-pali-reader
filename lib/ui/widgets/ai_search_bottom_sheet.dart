import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:tipitaka_pali/services/ai_search_service.dart';
import 'package:tipitaka_pali/ui/screens/home/openning_books_provider.dart';
import 'package:tipitaka_pali/ui/screens/home/search_page/search_page.dart';
import 'package:tipitaka_pali/ui/screens/reader/mobile_reader_container.dart';
import 'package:tipitaka_pali/ui/screens/home/widgets/search_result_list_tile.dart';
import 'package:tipitaka_pali/utils/platform_info.dart';

/// Bottom sheet that shows the AI search progress and results.
/// Used for both mobile and desktop via showModalBottomSheet.
class AiSearchBottomSheet extends StatefulWidget {
  final String query;

  const AiSearchBottomSheet({super.key, required this.query});

  @override
  State<AiSearchBottomSheet> createState() => _AiSearchBottomSheetState();
}

class _AiSearchBottomSheetState extends State<AiSearchBottomSheet> {
  final List<String> _logs = ['Starting AI search...'];
  bool _isSearching = true;
  List<AiMatchedResult> _results = [];
  String _summary = '';

  @override
  void initState() {
    super.initState();
    _runAiSearch();
  }

  Future<void> _runAiSearch() async {
    final service = AiSearchService(
      onStatusUpdate: (message) {
        if (mounted) {
          setState(() {
            _logs.add(message);
          });
        }
      },
    );

    final result = await service.search(widget.query);

    if (mounted) {
      setState(() {
        _isSearching = false;
        _results = result.results;
        _summary = result.summary;
        _logs.add('Search complete');
      });
    }
  }

  void _openBook(AiMatchedResult match) {
    final openningBookProvider = context.read<OpenningBooksProvider>();
    openningBookProvider.add(
      book: match.searchResult.book,
      currentPage: match.searchResult.pageNumber,
      textToHighlight: match.term,
      // For single AI words (prefix), use anywhere to guarantee partial substring highlighting ignoring boundaries
      queryMode: match.queryMode == QueryMode.prefix ? QueryMode.anywhere : match.queryMode,
    );

    if (Mobile.isPhone(context)) {
      Navigator.pop(context); // Close bottom sheet
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const MobileReaderContainer()));
    }
  }

  Future<void> _copyToClipboard() async {
    final buffer = StringBuffer();
    buffer.writeln('AI Search Query: "${widget.query}"');
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
        const SnackBar(content: Text('Copied thinking and results to clipboard')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
        minHeight: 200,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.auto_awesome,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'AI Search: "${widget.query}"',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!_isSearching)
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy thinking and results',
                    onPressed: _copyToClipboard,
                  ),
                if (!_isSearching)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
              ],
            ),
          ),

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
                      color:
                          Theme.of(context).dividerColor.withValues(alpha: 0.1),
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
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
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
          if (!_isSearching)
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
                                  color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SelectableText(
                                  _summary,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${_results.length} results found',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
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
        ],
      ),
    );
  }
}
