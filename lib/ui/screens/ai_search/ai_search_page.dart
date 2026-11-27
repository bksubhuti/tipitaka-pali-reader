import 'dart:io';

import 'package:tipitaka_pali/l10n/app_localizations.dart';
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
import 'package:tipitaka_pali/ui/dialogs/claude_extension_dialog.dart';
import 'package:tipitaka_pali/ui/dialogs/antigravity_extension_dialog.dart';
import 'package:tipitaka_pali/ui/dialogs/codex_extension_dialog.dart';
import 'package:tipitaka_pali/services/claude_share.dart';
import 'package:tipitaka_pali/services/update_check.dart';

class AiSearchPage extends StatefulWidget {
  final String query;

  const AiSearchPage({super.key, required this.query});

  @override
  State<AiSearchPage> createState() => _AiSearchPageState();
}

class _AiSearchPageState extends State<AiSearchPage> {
  late final TextEditingController _queryController;

  /// TPR Research's version when it is set up in Claude Desktop.
  String? _claudeVersion;

  /// The same when it is set up in Codex.
  String? _codexVersion;

  /// The same when it is set up in Antigravity.
  String? _antigravityVersion;
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
    if (ClaudeExtensionDialog.available) {
      ClaudeShare.extensionVersion().then((v) {
        if (mounted && v != null) setState(() => _claudeVersion = v);
      });
    }
    if (CodexExtensionDialog.available) {
      ClaudeShare.extensionVersion(host: 'codex').then((v) {
        if (mounted && v != null) setState(() => _codexVersion = v);
      });
    }
    if (AntigravityExtensionDialog.available) {
      ClaudeShare.extensionVersion(host: 'antigravity').then((v) {
        if (mounted && v != null) setState(() => _antigravityVersion = v);
      });
    }
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

  /// Opens Claude Desktop with the question typed in, asking it to answer
  /// from the reader's TPR books (TPR Research extension). Claude in the
  /// browser if the app is not there.
  void _sendToTpr() {
    FocusScope.of(context).unfocus();
    _runAiSearch();
  }

  Future<void> _askClaude() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Type a question first.')));
      return;
    }
    final prompt = 'Using TPR Research, search my TPR books and answer: '
        '$query\n\nQuote the Pāḷi with its translation and TPR links.';
    final q = Uri.encodeQueryComponent(prompt);
    if (!await launchUrl(Uri.parse('claude://claude.ai/new?q=$q'))) {
      await launchUrl(Uri.parse('https://claude.ai/new?q=$q'),
          mode: LaunchMode.externalApplication);
    }
  }

  /// Opens Codex with the question typed in, as [_askClaude] does.
  Future<void> _askCodex() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Type a question first.')));
      return;
    }
    if (!await CodexExtensionDialog.ask(query) && mounted) {
      // Linux has only the codex command: the question is copied.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(Platform.isLinux
              ? 'Question copied: paste it into codex.'
              : 'Could not open ChatGPT.')));
    }
  }

  /// Opens Antigravity with the question typed in, as [_askCodex] does.
  Future<void> _askAntigravity() async {
    final query = _queryController.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    if (query.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Type a question first.')));
      return;
    }
    final opened = await AntigravityExtensionDialog.ask(query);
    messenger.showSnackBar(SnackBar(
        content: Text(opened
            ? 'Opening Gemini (Antigravity). If the question is not filled in, '
                'paste it: it is copied.'
            : 'Could not open Antigravity. The question is copied.')));
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
        title: Text(AppLocalizations.of(context)!.aiTermsTitle),
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
            child: Text(AppLocalizations.of(context)!.close),
          ),
          FilledButton(
            onPressed: () {
              Prefs.aiTermsOfService = true;
              Navigator.pop(context); // Close dialog
            },
            child: Text(AppLocalizations.of(context)!.agree),
          ),
        ],
      ),
    );
  }

  /// How AI Search differs from an AI chat: it finds real passages in the
  /// Tipiṭaka on the device and works from those, rather than answering
  /// from what the model remembers.
  void _showWhatIsRag() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.whatIsRag),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Text(AppLocalizations.of(context)!.ragExplanation),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.close),
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
      MobileReaderContainer.show(context);
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

        final translatedDesc = r.isTranslation
            ? cleanDesc
            : PaliScript.getScriptOf(
                script: currentScript, romanText: cleanDesc);
        final cleanTranslation = (r.translation ?? '')
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        final translatedBook = PaliScript.getScriptOf(
            script: currentScript, romanText: r.book.name);
        final translatedPage = PaliScript.getScriptOf(
            script: currentScript, romanText: r.pageNumber.toString());

        buffer.writeln('${i + 1}. Book: $translatedBook');
        if (r.suttaName.isNotEmpty && r.suttaName != 'n/a') {
          final translatedSutta = PaliScript.getScriptOf(
              script: currentScript, romanText: r.suttaName);
          buffer.writeln('   Sutta: $translatedSutta');
        }
        buffer.writeln('   Page: $translatedPage');
        buffer.writeln('   "$translatedDesc"');
        if (cleanTranslation.isNotEmpty) {
          buffer.writeln('   "$cleanTranslation"');
        }
        buffer.writeln('');
      }
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!.aiCopiedToClipboard)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.aiSearch),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: AppLocalizations.of(context)!.whatIsRag,
            onPressed: _showWhatIsRag,
          ),
          if (_isSearching)
            TextButton.icon(
              icon: const Icon(Icons.stop, size: 20),
              label: Text(AppLocalizations.of(context)!.cancel),
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
              tooltip: AppLocalizations.of(context)!.aiCheckRateLimit,
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
              tooltip: AppLocalizations.of(context)!.aiCopyResults,
              onPressed: _copyToClipboard,
            ),
          if (!_isSearching && _hasSearched)
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: AppLocalizations.of(context)!.showHistory,
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
              tooltip: AppLocalizations.of(context)!.clearHistory,
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title:
                        Text(AppLocalizations.of(context)!.aiClearHistoryTitle),
                    content: Text(
                        AppLocalizations.of(context)!.aiClearHistoryMessage),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(AppLocalizations.of(context)!.cancel)),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(AppLocalizations.of(context)!.clear)),
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
                    Builder(builder: (context) {
                      String message1 =
                          '${AppLocalizations.of(context)!.aiSponsoredRemaining(Prefs.aiSponsoredTriesLeft)}\n';
                      String message2 =
                          AppLocalizations.of(context)!.aiSponsoredHint;
                      if (Prefs.aiSponsoredIsBlacklistedCountry) {
                        message2 = "";
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          message1 + message2,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                      );
                    }),
                  // Slider for results count
                  if (Prefs.aiProviderMode != 2)
                    Row(
                      children: [
                        Text(
                          AppLocalizations.of(context)!.aiResultsToAnalyze,
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
                            hintText: AppLocalizations.of(context)!.aiAskHint,
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
                      Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (!_isSearching && _hasSearched)
                            IconButton(
                              icon: const Icon(Icons.clear),
                              tooltip:
                                  AppLocalizations.of(context)!.clearSearch,
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
                          if (!_isSearching && _hasSearched)
                            const SizedBox(height: 8),
                          // With TPR Research set up in Claude Desktop: two
                          // ways to ask, TPR's own AI search above, Claude
                          // below. Otherwise the one send button.
                          if (_claudeVersion == null &&
                              _codexVersion == null &&
                              _antigravityVersion == null)
                            IconButton.filled(
                              icon: const Icon(Icons.send),
                              onPressed: _isSearching ? null : _sendToTpr,
                            )
                          else ...[
                            Tooltip(
                              message: 'Search inside TPR',
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  minimumSize: const Size(80, 36),
                                ),
                                onPressed: _isSearching ? null : _sendToTpr,
                                child: const Text('TPR'),
                              ),
                            ),
                            if (_claudeVersion != null) ...[
                              const SizedBox(height: 8),
                              Tooltip(
                                message: 'Search with Claude Desktop',
                                // the name only: Anthropic's logo needs their
                                // approval
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFD97757),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    minimumSize: const Size(80, 36),
                                  ),
                                  onPressed: _askClaude,
                                  child: const Text('Claude'),
                                ),
                              ),
                            ],
                            if (_codexVersion != null) ...[
                              const SizedBox(height: 8),
                              Tooltip(
                                message: 'Search with ChatGPT (Codex)',
                                // the name only, as for Claude
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.black,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    minimumSize: const Size(80, 36),
                                  ),
                                  onPressed: _askCodex,
                                  child: const Text('ChatGPT'),
                                ),
                              ),
                            ],
                            if (_antigravityVersion != null) ...[
                              const SizedBox(height: 8),
                              Tooltip(
                                message: 'Search with Gemini (Antigravity)',
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF4285F4),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    minimumSize: const Size(80, 36),
                                  ),
                                  onPressed: _askAntigravity,
                                  child: const Text('Gemini'),
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ],
                  ),
                  // A newer TPR Research is out (messages.json): offered
                  // here too, where the Claude button is used.
                  if (_claudeVersion != null &&
                      UpdateCheck.isOlder(
                          _claudeVersion!, UpdateCheck.tprResearchLatest))
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(Icons.system_update_alt, size: 18),
                        label: Text('Update TPR Research '
                            '(${UpdateCheck.tprResearchLatest})'),
                        onPressed: () => ClaudeExtensionDialog.show(context),
                      ),
                    ),
                  if (_codexVersion != null &&
                      UpdateCheck.isOlder(
                          _codexVersion!, UpdateCheck.tprResearchLatest))
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(Icons.system_update_alt, size: 18),
                        label: Text('Update TPR Research for ChatGPT '
                            '(${UpdateCheck.tprResearchLatest})'),
                        onPressed: () => CodexExtensionDialog.show(context),
                      ),
                    ),
                  if (_antigravityVersion != null &&
                      UpdateCheck.isOlder(
                          _antigravityVersion!, UpdateCheck.tprResearchLatest))
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(Icons.system_update_alt, size: 18),
                        label: Text('Update TPR Research for Gemini '
                            '(${UpdateCheck.tprResearchLatest})'),
                        onPressed: () =>
                            AntigravityExtensionDialog.show(context),
                      ),
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
                            AppLocalizations.of(context)!.aiNoResults,
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
