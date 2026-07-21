import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../business_logic/models/search_result.dart';
import '../services/database/database_helper.dart';
import '../services/prefs.dart';
import '../env/env.dart';
import '../services/repositories/fts_repo.dart';
import '../services/repositories/page_content_repo.dart';
import '../ui/screens/home/search_page/search_page.dart';
import '../utils/pali_english_stripper.dart';

/// A search result paired with the term and query mode that found it,
/// so we can properly highlight it in the reader.
class AiMatchedResult {
  final SearchResult searchResult;
  final String term;
  final QueryMode queryMode;

  AiMatchedResult({
    required this.searchResult,
    required this.term,
    required this.queryMode,
  });

  Map<String, dynamic> toJson() {
    return {
      'searchResult': searchResult.toJson(),
      'term': term,
      'queryMode': queryMode.index,
    };
  }

  factory AiMatchedResult.fromJson(Map<String, dynamic> json) {
    return AiMatchedResult(
      searchResult:
          SearchResult.fromJson(json['searchResult'] as Map<String, dynamic>),
      term: json['term'] as String,
      queryMode: QueryMode.values[json['queryMode'] as int],
    );
  }
}

/// Represents the AI's decision on what to do next in the search loop.
class AiPlan {
  final List<int> selectedIndices;
  final List<int> requestOverflowIndices;
  final List<String> thoughtProcess;
  final bool isFullyAnswered;
  final List<String> nextQueries;

  AiPlan({
    required this.selectedIndices,
    required this.requestOverflowIndices,
    required this.thoughtProcess,
    required this.isFullyAnswered,
    required this.nextQueries,
  });
}

/// Result from the AI search process, including the curated results
/// and a summary message explaining what was found.
class AiSearchResult {
  final List<AiMatchedResult> results;
  final String summary;

  AiSearchResult({required this.results, required this.summary});

  Map<String, dynamic> toJson() {
    return {
      'results': results.map((e) => e.toJson()).toList(),
      'summary': summary,
    };
  }

  factory AiSearchResult.fromJson(Map<String, dynamic> json) {
    return AiSearchResult(
      results: (json['results'] as List<dynamic>)
          .map((e) => AiMatchedResult.fromJson(e as Map<String, dynamic>))
          .toList(),
      summary: json['summary'] as String,
    );
  }
}

/// Service that orchestrates AI-guided search of the Tipiṭaka.
class AiSearchService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final void Function(String message)? onStatusUpdate;

  // Add a persistent HTTP client for the entire search session
  http.Client _httpClient = http.Client();

  // We keep a running log of what the agent did to show the user at the end
  final List<String> _agentLog = [];
  bool _isCancelled = false;

  int _lightInputTokens = 0;
  int _lightOutputTokens = 0;
  int _heavyInputTokens = 0;
  int _heavyOutputTokens = 0;
  double _lightOpenRouterCost = 0.0;
  double _heavyOpenRouterCost = 0.0;
  String _lightModelUsed = '';
  String _heavyModelUsed = '';

  AiSearchService({this.onStatusUpdate});

  void cancel() {
    _isCancelled = true;
  }

  void _updateStatus(String message) {
    onStatusUpdate?.call(message);
    debugPrint('[AiSearch] $message');
  }

  void _addLog(String message) {
    _agentLog.add(message);
    _updateStatus(message);
  }

  /// Main entry point: perform a multi-turn AI-guided search.
  Future<AiSearchResult> search(String userQuery, {int maxResults = 30}) async {
    _httpClient = http.Client();
    _agentLog.clear();
    _lightInputTokens = 0;
    _lightOutputTokens = 0;
    _heavyInputTokens = 0;
    _heavyOutputTokens = 0;
    _lightOpenRouterCost = 0.0;
    _heavyOpenRouterCost = 0.0;
    _lightModelUsed = '';
    _heavyModelUsed = '';
    String apiKey = '';
    if (Prefs.activeAiProviderMode == 0) {
      apiKey = Prefs.geminiDirectApiKey;
    } else if (Prefs.activeAiProviderMode == 1) {
      apiKey = Prefs.openRouterKey;
    } else if (Prefs.activeAiProviderMode == 2) {
      apiKey = Env.openRouterApiKey;
      await Prefs.fetchSponsoredModelConfig();
      if (Prefs.aiSponsoredTriesLeft <= 0) {
        return AiSearchResult(
          results: [],
          summary:
              'Daily limit reached for Sponsored Mode. Please try again tomorrow or configure your own API key in AI Settings.',
        );
      }
      Prefs.aiSponsoredTriesLeft = Prefs.aiSponsoredTriesLeft - 1;
    }

    if (apiKey.isEmpty) {
      return AiSearchResult(
        results: [],
        summary: 'No API key configured. Please set one in AI Settings.',
      );
    }

    final bestResults = <AiMatchedResult>[];
    final generalOverflow = <AiMatchedResult>[];
    final triedQueries = <String>[];
    final ftsRepo = FtsDatabaseRepository(_dbHelper);

    _addLog('🤖 **Agent started** analyzing query: "$userQuery"');

    // Iteration 0: Bootstrap the search
    String aiMemory = '';
    List<String> nextQueriesToSearch =
        await _generateInitialQueries(userQuery, apiKey, (thought) {
      aiMemory = thought;
    });
    List<int> requestOverflowIndices = [];

    // Run the Agentic Loop
    try {
      for (int iteration = 1; iteration <= 5; iteration++) {
        if (_isCancelled) break;
        _updateStatus('--- Iteration $iteration ---');

        List<AiMatchedResult> requestedOverflow = [];
        if (requestOverflowIndices.isNotEmpty) {
          final sortedIndices = List<int>.from(requestOverflowIndices)
            ..sort((a, b) => b.compareTo(a));
          for (final idx in sortedIndices) {
            if (idx >= 0 && idx < generalOverflow.length) {
              requestedOverflow.add(generalOverflow.removeAt(idx));
            }
          }
          requestedOverflow = requestedOverflow.reversed.toList();
        }

        List<AiMatchedResult> newResults = [];

        if (nextQueriesToSearch.isNotEmpty) {
          triedQueries.addAll(nextQueriesToSearch);
          newResults.clear();

          for (final query in nextQueriesToSearch) {
            _addLog('🔍 Searching for "$query"...');
            try {
              final isMultiWord = query.contains(' ');
              final queryMode =
                  isMultiWord ? QueryMode.distance : QueryMode.prefix;
              final wordDistance = isMultiWord ? 12 : 0;

              final results =
                  await ftsRepo.getResults(query, queryMode, wordDistance);
              _addLog('   ↳ Found ${results.length} raw matches.');

              for (final r in results) {
                final existsInBest =
                    bestResults.any((b) => b.searchResult.id == r.id);
                final existsInReq =
                    requestedOverflow.any((req) => req.searchResult.id == r.id);
                final existsInGen =
                    generalOverflow.any((gen) => gen.searchResult.id == r.id);
                final existsInNew =
                    newResults.any((nw) => nw.searchResult.id == r.id);

                if (!existsInBest &&
                    !existsInReq &&
                    !existsInGen &&
                    !existsInNew) {
                  newResults.add(AiMatchedResult(
                    searchResult: r,
                    term: query,
                    queryMode: queryMode,
                  ));
                }
              }
            } catch (e) {
              debugPrint('Error searching $query: $e');
            }
          }
        }

        List<AiMatchedResult> currentFullText = [];
        currentFullText.addAll(requestedOverflow);

        int availableSlots = maxResults - currentFullText.length;
        if (availableSlots > 0) {
          currentFullText.addAll(newResults.take(availableSlots));
          generalOverflow.addAll(newResults.skip(availableSlots));
        } else {
          generalOverflow.addAll(newResults);
        }

        debugPrint(
            '[AiSearch] Budgeting Trace: maxResults=$maxResults, newResults.length=${newResults.length}');
        debugPrint(
            '[AiSearch] Budgeting Trace: currentFullText.length=${currentFullText.length}, generalOverflow.length=${generalOverflow.length}');

        if (currentFullText.isEmpty && generalOverflow.isEmpty) {
          _addLog('⚠️ No results found for these queries. Rethinking...');
        } else {
          _updateStatus('📚 Reading ${currentFullText.length} passages...');
        }

        _updateStatus('🧠 AI is evaluating findings and planning...');

        // HYBRID ROUTING STRATEGY:
        // The first initial query is heavy. The remaining evaluation iterations use the light model.
        bool isHeavyLifting = false;

        final plan = await _evaluateAndPlan(
          userQuery: userQuery,
          apiKey: apiKey,
          triedQueries: triedQueries,
          bestResults: bestResults,
          currentFullText: currentFullText,
          generalOverflow: generalOverflow,
          isHeavy: isHeavyLifting,
          previousThoughts: aiMemory,
        );

        // Update memory for the NEXT iteration using the current thoughts
        if (plan != null && plan.thoughtProcess.isNotEmpty) {
          aiMemory = plan.thoughtProcess.join(' ');
        }

        if (plan == null) {
          _addLog('❌ AI failed to plan next steps. Stopping early.');
          break;
        }

        // Display the AI's internal thought process to the user and save to log
        for (final thought in plan.thoughtProcess) {
          _addLog('🧠 $thought');
        }

        int newFinds = 0;
        for (final idx in plan.selectedIndices) {
          if (idx >= 0 && idx < currentFullText.length) {
            final r = currentFullText[idx];
            final exists =
                bestResults.any((b) => b.searchResult.id == r.searchResult.id);
            if (!exists) {
              bestResults.add(r);
              newFinds++;
            }
          }
        }

        if (newFinds > 0) {
          _addLog('🎯 Kept $newFinds highly relevant passages.');
        }

        if (plan.requestOverflowIndices.isNotEmpty) {
          _addLog(
              '📥 AI requested to view ${plan.requestOverflowIndices.length} items from overflow for the next iteration.');
        }

        if (plan.isFullyAnswered) {
          _addLog(
              '✅ **Search Complete:** AI determined all relevant instances have been found.');
          break;
        }

        if (plan.nextQueries.isEmpty && plan.requestOverflowIndices.isEmpty) {
          _addLog(
              '🏁 AI has exhausted its search ideas and requested no more overflow items.');
          break;
        }

        nextQueriesToSearch = plan.nextQueries;
        requestOverflowIndices = plan.requestOverflowIndices;
      }
    } catch (e) {
      if (_isCancelled) {
        _addLog('⚠️ Search cancelled by user.');
      } else {
        _addLog('⚠️ Search interrupted: $e');
      }
    }

    double lightCost = 0.0;
    double heavyCost = 0.0;

    final providerStr = Prefs.activeAiProviderMode == 0
        ? 'Gemini Direct (calculated)'
        : (Prefs.activeAiProviderMode == 1
            ? 'OpenRouter BYOK (reported)'
            : 'OpenRouter Sponsored (reported)');

    if (Prefs.activeAiProviderMode == 0) {
      // Gemini Direct pricing:
      // Gemini 1.5 Flash (Light): $0.075 / 1M input, $0.30 / 1M output
      lightCost = (_lightInputTokens / 1000000.0) * 0.075 +
          (_lightOutputTokens / 1000000.0) * 0.30;
      heavyCost = (_heavyInputTokens / 1000000.0) * 1.50 +
          (_heavyOutputTokens / 1000000.0) * 9.00;
    } else {
      lightCost = _lightOpenRouterCost;
      heavyCost = _heavyOpenRouterCost;
    }

    final double totalCost = lightCost + heavyCost;

    _addLog('💰 Total Cost: \$${totalCost.toStringAsFixed(6)}');
    _addLog(
        '   ↳ Light Model ($_lightModelUsed): \$${lightCost.toStringAsFixed(6)} (${_lightInputTokens} in, ${_lightOutputTokens} out)');
    if (_heavyModelUsed.isNotEmpty) {
      _addLog(
          '   ↳ Heavy Model ($_heavyModelUsed): \$${heavyCost.toStringAsFixed(6)} (${_heavyInputTokens} in, ${_heavyOutputTokens} out)');
    }
    _addLog('   ↳ Pricing Source: $providerStr');

    if (Prefs.activeAiProviderMode == 2) {
      _addLog(
          '💡 **Note**: Sponsored Mode is a gift to help you get started or for those in restricted regions. May the generous donor of this API key gain great merit! \nFor faster speeds, better quality, and more daily queries, we highly recommend adding your own free Gemini key in the AI Settings.');
    }

    await _logCost(userQuery, lightCost, heavyCost, totalCost);

    // Format a beautiful markdown log for the UI summary
    final summaryBuffer = StringBuffer();
    summaryBuffer.writeln(bestResults.isEmpty
        ? '### No relevant results found after 5 iterations.\n'
        : '### Found ${bestResults.length} relevant results.\n');

    summaryBuffer.writeln('**Agent Search Log:**');
    for (final log in _agentLog) {
      summaryBuffer.writeln('* $log');
    }

    // Free up the socket when the search loop is completely done
    _httpClient.close();

    return AiSearchResult(
      results: bestResults,
      summary: summaryBuffer.toString(),
    );
  }

  /// Initial prompt with explicit Chain of Thought instructions.
  Future<List<String>> _generateInitialQueries(
      String userQuery, String apiKey, void Function(String) onThought) async {
    final prompt =
        '''You are an expert in Theravāda Buddhism and the Pāḷi Tipiṭaka.
The user is asking: "$userQuery"

Task:
1. Formulate a step-by-step thought process. Identify key figures, events, and core concepts related to the query across the Suttas, Vinaya, and Commentaries (Aṭṭhakathā).
2. Generate 2 to 3 highly targeted Pāḷi search terms (single words or short phrases) to find relevant passages. 
   COMMON VS RARE WORDS: DO NOT search for common single words (e.g., 'bhikkhu'). You may search for single words ONLY if they are very rare proper nouns (e.g., 'paṭācārā'). However, if a name is short or could be a common noun (like 'koka' which also means wolf, or 'suka' which means parrot), you MUST pair it with one contextual noun using a space (e.g., 'koka sunakha' or 'suka rukkha'). Pairing a name with a context word is the most powerful way to filter out noise.
   - You CAN search for rare compounds, but remember the database uses substring matching. Search for root words (e.g., search "puris" to get puriso, purisa, purisassa).
3. CRITICAL RULE FOR SPACES: If you include a space in your query (e.g., "gihi cīvara"), the app executes a DISTANCE SEARCH, requiring both words to be within 12 words of each other. NEVER suggest queries with 3 or more words. Keep phrases to a maximum of 2 words.
4. CRITICAL: Do NOT include book names (e.g., 'dhammapada', 'majjhima') in search terms.
5. You must use proper Pāḷi diacritics (ā, ī, ū, ṃ, ṭ, ḍ, ṇ, ñ, ṅ, ḷ).
6. TEXTUAL VARIANTS: The database uses the Chaṭṭha Saṅgāyana (CSCD) edition. If a common word has alternative spellings or synonyms in different traditions (e.g., 'suka' vs 'suva' for parrot, or 'kapi' vs 'makkaṭa' vs 'vānara' for monkey), include searches for BOTH root words. Do not assume your preferred spelling is the only one.

Respond ONLY with a JSON object in this exact format:
{
  "thinking": "Ananda famously cried during the Buddha's passing. I need to search for 'rodati' or 'assu' in the context of the Parinibbāna.",
  "next_queries": ["ānanda rodati", "assu", "soka"]
}''';

    try {
      final response = await _callAi(prompt, apiKey, isHeavy: true);
      if (response == null) return [];

      final jsonStr = _extractJson(response);
      if (jsonStr == null) return [];

      final data = jsonDecode(jsonStr);

      final thinking = data['thinking']?.toString() ?? '';
      if (thinking.isNotEmpty) {
        _addLog('🧠 $thinking');
        onThought(thinking);
      }

      return (data['next_queries'] as List?)
              ?.map((e) => e.toString().toLowerCase().trim())
              .where((t) => t.isNotEmpty)
              .toList() ??
          [];
    } catch (e) {
      debugPrint('Initial query generation error: $e');
      return [];
    }
  }

  /// Evaluation prompt requiring step-by-step reasoning.
  Future<AiPlan?> _evaluateAndPlan({
    required String userQuery,
    required String apiKey,
    required List<String> triedQueries,
    required List<AiMatchedResult> bestResults,
    required List<AiMatchedResult> currentFullText,
    required List<AiMatchedResult> generalOverflow,
    required bool isHeavy,
    required String previousThoughts,
  }) async {
    final buffer = StringBuffer();
    int wordCount = 0;
    int maxWords = Prefs.aiMaxResults * 50;

    final pageContentRepo = PageContentDatabaseRepository(_dbHelper);

    for (int i = 0; i < currentFullText.length && wordCount < maxWords; i++) {
      final r = currentFullText[i].searchResult;
      final cleanDesc = r.description
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      final pageContent =
          await pageContentRepo.getPageByBookAndPage(r.book.id, r.pageNumber);

      final strippedPali = stripEnglishFromPali(
        mixedSample: cleanDesc,
        labeledPageHtml: pageContent?.content,
      );

      final words = strippedPali.split(' ');
      final allowedWords = maxWords - wordCount;
      final truncDesc = words.length > allowedWords
          ? '${words.take(allowedWords).join(' ')}...'
          : strippedPali;

      buffer.write(
          '[$i] ${r.book.name}, ${r.suttaName}, Pg ${r.pageNumber}: "$truncDesc"\n');
      wordCount += words.take(allowedWords).length;
    }

    String cumulativeContext =
        'Currently saved relevant results: ${bestResults.length}';

    if (bestResults.isNotEmpty) {
      final cumBuffer = StringBuffer();
      for (int i = 0; i < bestResults.length; i++) {
        final r = bestResults[i].searchResult;
        final cleanDesc = r.description
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

        final pageContent =
            await pageContentRepo.getPageByBookAndPage(r.book.id, r.pageNumber);

        final strippedPali = stripEnglishFromPali(
          mixedSample: cleanDesc,
          labeledPageHtml: pageContent?.content,
        );

        final shortDesc = strippedPali.length > 80
            ? '${strippedPali.substring(0, 80)}...'
            : strippedPali;

        cumBuffer.writeln(
            'R${i + 1}: ${r.book.name}, ${r.suttaName}, Pg ${r.pageNumber} - "$shortDesc"');
      }

      cumulativeContext = '''Previously saved results (refer to them by ID):
${cumBuffer.toString()}''';
    }

    // Compact Grouped Overflow Summary
    final overflowBuffer = StringBuffer();
    if (generalOverflow.isNotEmpty) {
      overflowBuffer.writeln('**Overflow** (OF# = index to request):');
      final grouped = <String, List<int>>{};
      for (int i = 0; i < generalOverflow.length; i++) {
        final key =
            '${generalOverflow[i].searchResult.book.name}|${generalOverflow[i].term}';
        grouped.putIfAbsent(key, () => []).add(i);
      }

      for (final entry in grouped.entries) {
        final parts = entry.key.split('|');
        final book = parts[0];
        final term = parts[1];
        final indices = entry.value.map((e) => 'OF-$e').join(', ');
        overflowBuffer.writeln('- $book | "$term" → $indices');
      }
    }
    final overflowSummary = overflowBuffer.toString();

    final prompt =
        '''You are an expert in Theravāda Buddhism and the Pāḷi Tipiṭaka.
The user asks: "$userQuery"

We are running an autonomous search loop.
$cumulativeContext

PREVIOUS AI THOUGHTS (For context):
$previousThoughts

Queries we have already tried (do not repeat these): ${triedQueries.join(', ')}

Here are the FULL TEXT results for this round (use their numeric indices [0], [1], ... to select):
${buffer.toString().isEmpty ? "(No full text results available)" : buffer.toString()}

${overflowSummary.isEmpty ? "" : "OVERFLOW SUMMARY (use OF- indices to request):\n$overflowSummary\n"}

Task:
1. Review the FULL TEXT results carefully.
2. Select the most relevant ones using their indices [0], [1], etc.
3. If you want to see more from overflow, list up to a MAXIMUM of 10 OF- indices in "request_overflow_indices".
4. If you have 2-4 strong results that answer the question well, set "is_fully_answered": true and STOP.
5. If not fully answered, propose new queries based on what failed or succeeded. 
   - RULE: If a query contains a space, the app requires all words to be within 12 words of each other. Maximum 2 words per query. Never write full Pāḷi sentences.

Respond ONLY with valid JSON:
{
  "thought_process": ["short thoughts only"],
  "selected_new_indices": [0, 2],
  "request_overflow_indices": [5, 8],
  "is_fully_answered": false,
  "next_queries": ["query1", "query2"]
}''';

    debugPrint('[AiSearch] Prompt length: ${prompt.length} chars');
    final approxWords = prompt.split(RegExp(r'\s+')).length;
    _addLog(
        '📊 Sending ~${approxWords} words to AI (New items: ${currentFullText.length} | Saved: ${bestResults.length} | Overflow: ${generalOverflow.length})');

    try {
      final response = await _callAi(prompt, apiKey, isHeavy: isHeavy);
      if (response == null) return null;

      final jsonStr = _extractJson(response);
      if (jsonStr == null) return null;

      final data = jsonDecode(jsonStr);
      return AiPlan(
        selectedIndices: (data['selected_new_indices'] as List?)
                ?.map((e) => e is int ? e : int.tryParse(e.toString()) ?? -1)
                .toList() ??
            [],
        requestOverflowIndices: (data['request_overflow_indices'] as List?)
                ?.map((e) => e is int ? e : int.tryParse(e.toString()) ?? -1)
                .toList() ??
            [],
        thoughtProcess: (data['thought_process'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        isFullyAnswered: data['is_fully_answered'] == true,
        nextQueries: (data['next_queries'] as List?)
                ?.map((e) => e.toString().toLowerCase().trim())
                .where((q) => q.isNotEmpty)
                .toList() ??
            [],
      );
    } catch (e) {
      debugPrint('Plan error: $e');
      return null;
    }
  }

  Future<List<String>> _getActiveFlashModels(String apiKey,
      {required bool isHeavy}) async {
    String lightPref = '';
    String heavyPref = '';

    if (Prefs.activeAiProviderMode == 0) {
      lightPref = Prefs.aiLightModel;
      heavyPref = Prefs.aiHeavyModel;
    } else if (Prefs.activeAiProviderMode == 1) {
      lightPref = Prefs.openRouterLightModel;
      heavyPref = Prefs.openRouterHeavyModel;
    } else if (Prefs.activeAiProviderMode == 2) {
      lightPref = Prefs.aiSponsoredLightModel;
      heavyPref = Prefs.aiSponsoredHeavyModel;
    }

    final lightModel = lightPref.isNotEmpty ? lightPref : 'gemini-1.5-flash-8b';
    final heavyModel = heavyPref.isNotEmpty ? heavyPref : 'gemini-1.5-flash';

    if (!isHeavy) {
      return [lightModel];
    }

    // For heavy iterations, try the heavy model first, but fallback to light if it fails or hits a hard quota.
    return [heavyModel, lightModel];
  }

  Future<String?> _callAi(String prompt, String apiKey,
      {required bool isHeavy}) async {
    if (Prefs.activeAiProviderMode == 0) {
      return _callGemini(prompt, apiKey, isHeavy: isHeavy);
    } else {
      String apiUrl = 'https://openrouter.ai/api/v1/chat/completions';
      if (Prefs.activeAiProviderMode == 2 &&
          Prefs.aiSponsoredProvider.isNotEmpty) {
        apiUrl = Prefs.aiSponsoredProvider.contains('deepseek')
            ? 'https://api.deepseek.com/chat/completions'
            : 'https://${Prefs.aiSponsoredProvider}/api/v1/chat/completions';
      }

      return _callOpenRouter(prompt, apiKey, isHeavy: isHeavy, apiUrl: apiUrl);
    }
  }

  Future<String?> _callOpenRouter(String prompt, String apiKey,
      {required bool isHeavy,
      String apiUrl = 'https://openrouter.ai/api/v1/chat/completions'}) async {
    String lightPref = '';
    String heavyPref = '';

    if (Prefs.activeAiProviderMode == 1) {
      lightPref = Prefs.openRouterLightModel;
      heavyPref = Prefs.openRouterHeavyModel;
    } else if (Prefs.activeAiProviderMode == 2) {
      lightPref = Prefs.aiSponsoredLightModel;
      heavyPref = Prefs.aiSponsoredHeavyModel;
    }

    final lightModel =
        lightPref.isNotEmpty ? lightPref : 'meta-llama/llama-3-8b-instruct';
    final heavyModel =
        heavyPref.isNotEmpty ? heavyPref : 'anthropic/claude-3.5-sonnet';

    final models = !isHeavy ? [lightModel] : [heavyModel, lightModel];

    final Map<String, dynamic> requestBody = {
      "messages": [
        {"role": "user", "content": prompt}
      ],
      "temperature": 0.4
    };

    for (final model in models) {
      requestBody["model"] = model;
      final endpoint = apiUrl;

      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          debugPrint(
              '[AiSearch] Attempting connection to OpenRouter model $model (Try ${attempt + 1})...');

          final response = await _httpClient
              .post(
                Uri.parse(endpoint),
                headers: {
                  'Authorization': 'Bearer $apiKey',
                  'Content-Type': 'application/json',
                  'HTTP-Referer': 'https://americanmonk.org',
                  'X-Title': 'Tipitaka Pali Reader',
                  'User-Agent': 'TipitakaPaliReader/1.0',
                },
                body: utf8.encode(jsonEncode(requestBody)),
              )
              .timeout(const Duration(seconds: 50));

          if (_isCancelled) {
            final msg = 'Cancelled by user';
            _addLog('❌ $msg');
            throw Exception(msg);
          }

          if (response.statusCode == 429) {
            debugPrint('[AiSearch] Rate limited. Waiting...');
            await Future.delayed(Duration(seconds: attempt == 0 ? 3 : 6));
            continue;
          }

          if (response.statusCode != 200) {
            debugPrint('[AiSearch] API Error HTTP ${response.statusCode}');
            break;
          }

          final data = jsonDecode(response.body);
          if (data.containsKey('error')) {
            final msg = data['error']['message'];
            debugPrint('[AiSearch] API Error: $msg');
            _addLog('❌ API Error: $msg');
            break;
          }

          final content = data['choices']?[0]?['message']?['content'] ?? '';
          if (content.isEmpty) break;

          final usage = data['usage'];
          if (usage != null) {
            final pTokens = usage['prompt_tokens'] as int? ?? 0;
            final cTokens = usage['completion_tokens'] as int? ?? 0;
            final cost = (usage['cost'] as num?)?.toDouble() ?? 0.0;
            if (isHeavy) {
              _heavyInputTokens += pTokens;
              _heavyOutputTokens += cTokens;
              _heavyOpenRouterCost += cost;
              _heavyModelUsed = model;
            } else {
              _lightInputTokens += pTokens;
              _lightOutputTokens += cTokens;
              _lightOpenRouterCost += cost;
              _lightModelUsed = model;
            }
            debugPrint(
                '[AiSearch] Model: $model | Tokens: $pTokens in, $cTokens out | Cost: \$${cost.toStringAsFixed(6)}');
          }

          return content;
        } catch (e) {
          debugPrint('[AiSearch] Network error: $e');
          _addLog('❌ Network Error: $e');
          break;
        }
      }
    }
    return null;
  }

  Future<String?> _callGemini(String prompt, String apiKey,
      {required bool isHeavy}) async {
    final models = await _getActiveFlashModels(apiKey, isHeavy: isHeavy);

    final requestBody = {
      "contents": [
        {
          "parts": [
            {"text": prompt}
          ]
        }
      ],
      "generationConfig": {
        "temperature": 0.4,
        "maxOutputTokens": 4096,
      }
    };

    for (final model in models) {
      final endpoint =
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent';

      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          // Only log the actual API network calls to standard debugPrint, keep the user UI clean
          debugPrint(
              '[AiSearch] Attempting connection to $model (Try ${attempt + 1})...');

          final response = await _httpClient.post(
            Uri.parse('$endpoint?key=$apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(requestBody),
          );

          if (_isCancelled) {
            final msg = 'Cancelled by user';
            _addLog('❌ $msg');
            throw Exception(msg);
          }

          if (response.statusCode == 429) {
            if (response.body.contains('limit: 0')) {
              debugPrint('[AiSearch] Model $model not available on free tier.');
              break;
            }
            debugPrint('[AiSearch] Rate limited. Waiting...');
            await Future.delayed(Duration(seconds: attempt == 0 ? 3 : 6));
            continue;
          }

          if (response.statusCode != 200) {
            debugPrint('[AiSearch] API Error HTTP ${response.statusCode}');
            break;
          }

          final data = jsonDecode(response.body);
          if (data.containsKey('error')) {
            final msg = data['error']['message'];
            debugPrint('[AiSearch] API Error: $msg');
            _addLog('❌ API Error: $msg');
            break;
          }

          final usageMetadata = data['usageMetadata'];
          if (usageMetadata != null) {
            final promptTokens = usageMetadata['promptTokenCount'] as int? ?? 0;
            final candidatesTokens =
                usageMetadata['candidatesTokenCount'] as int? ?? 0;
            if (isHeavy) {
              _heavyInputTokens += promptTokens;
              _heavyOutputTokens += candidatesTokens;
              _heavyModelUsed = model;
            } else {
              _lightInputTokens += promptTokens;
              _lightOutputTokens += candidatesTokens;
              _lightModelUsed = model;
            }
          }

          final parts = data['candidates']?[0]?['content']?['parts'];
          final text = parts?.map((e) => e['text']).join('\n') ?? '';
          if (text.isEmpty) break;

          return text;
        } catch (e) {
          debugPrint('[AiSearch] Network error: $e');
          if (attempt == 0) {
            _addLog('⚠️ Network Error (Retrying...): $e');
            await Future.delayed(const Duration(seconds: 2));
            continue;
          } else {
            _addLog('❌ Network Error: $e');
            break;
          }
        }
      }
    }
    return null;
  }

  String? _extractJson(String text) {
    // Escaped using hex codes (\x60) so the UI parser doesn't mistake it for a markdown file cutoff.
    final fenced = RegExp(r'\x60\x60\x60(?:json)?\s*([\s\S]*?)\s*\x60\x60\x60');
    final match = fenced.firstMatch(text);
    if (match != null) return match.group(1)?.trim();

    final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
    if (jsonMatch != null) return jsonMatch.group(0);

    return null;
  }

  Future<void> _logCost(String userQuery, double lightCost, double heavyCost,
      double totalCost) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/ai_cost_ledger.json');

      List<dynamic> entries = [];
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          entries = jsonDecode(content) as List<dynamic>;
        }
      }

      entries.add({
        "timestamp": DateTime.now().toUtc().toIso8601String(),
        "userQuery": userQuery,
        "lightModel": _lightModelUsed,
        "heavyModel": _heavyModelUsed,
        "lightInputTokens": _lightInputTokens,
        "lightOutputTokens": _lightOutputTokens,
        "heavyInputTokens": _heavyInputTokens,
        "heavyOutputTokens": _heavyOutputTokens,
        "lightCost": lightCost,
        "heavyCost": heavyCost,
        "totalCost": totalCost
      });

      await file.writeAsString(jsonEncode(entries), mode: FileMode.write);
    } catch (e) {
      debugPrint('[AiSearch] Error logging cost to file: $e');
    }
  }
}
