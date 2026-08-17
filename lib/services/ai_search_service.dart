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

  int _initialInputTokens = 0;
  int _initialOutputTokens = 0;
  int _lightInputTokens = 0;
  int _lightOutputTokens = 0;
  int _heavyInputTokens = 0;
  int _heavyOutputTokens = 0;
  double _initialOpenRouterCost = 0.0;
  double _lightOpenRouterCost = 0.0;
  double _heavyOpenRouterCost = 0.0;
  String _initialModelUsed = '';
  String _lightModelUsed = '';
  String _heavyModelUsed = '';

  AiSearchService({this.onStatusUpdate});

  List<String> _parseStringList(dynamic jsonValue) {
    if (jsonValue == null) return [];
    if (jsonValue is List) {
      return jsonValue.map((e) => e.toString()).toList();
    }
    if (jsonValue is String) {
      return [jsonValue];
    }
    return [];
  }

  List<int> _parseIntList(dynamic jsonValue) {
    if (jsonValue == null) return [];
    if (jsonValue is List) {
      return jsonValue
          .map((e) => int.tryParse(e.toString()))
          .whereType<int>()
          .toList();
    }
    if (jsonValue is int) return [jsonValue];
    return [];
  }

  String _getTargetLanguage(String scriptCode) {
    switch (scriptCode) {
      case 'si':
        return 'Sinhala';
      case 'hi':
        return 'Hindi';
      case 'th':
        return 'Thai';
      case 'lo':
        return 'Lao';
      case 'my':
        return 'Burmese';
      case 'km':
        return 'Khmer';
      case 'be':
        return 'Bengali';
      case 'gm':
        return 'Punjabi';
      case 'gj':
        return 'Gujarati';
      case 'te':
        return 'Telugu';
      case 'ka':
        return 'Kannada';
      case 'mm':
        return 'Malayalam';
      case 'cy':
        return 'Russian';
      case 'ti':
        return 'Tibetan';
      case 'ro':
      default:
        return 'English';
    }
  }

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
    if (Prefs.activeAiProviderMode == 2 && maxResults > 45) {
      maxResults = 45;
    }
    _httpClient = http.Client();
    _agentLog.clear();
    _initialInputTokens = 0;
    _initialOutputTokens = 0;
    _lightInputTokens = 0;
    _lightOutputTokens = 0;
    _heavyInputTokens = 0;
    _heavyOutputTokens = 0;
    _initialOpenRouterCost = 0.0;
    _lightOpenRouterCost = 0.0;
    _heavyOpenRouterCost = 0.0;
    _initialModelUsed = '';
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
      final triesLeft = Prefs.aiSponsoredTriesLeft;
      if (triesLeft <= 0) {
        return AiSearchResult(
          results: [],
          summary:
              'Daily limit reached for Sponsored Mode. Please try again tomorrow or configure your own API key in AI Settings.',
        );
      }
      Prefs.aiSponsoredTriesLeft = triesLeft - 1;
    }

    if (apiKey.isEmpty) {
      return AiSearchResult(
        results: [],
        summary: 'No API key configured. Please set one in AI Settings.',
      );
    }

    final bool goOnline = !userQuery.trimLeft().startsWith('@');
    if (!goOnline) {
      userQuery = userQuery.trimLeft().substring(1).trim();
      _addLog('🧪 Secret code "@" detected: using local prompts for testing.');
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
    }, goOnline: goOnline);
    List<int> requestOverflowIndices = [];

    // Run the Agentic Loop
    int consecutiveZeroFinds = 0;
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
              final wordDistance = isMultiWord ? 20 : 0;

              final results = await ftsRepo.getResults(
                  query, queryMode, wordDistance,
                  joinEnglish: false);
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
          goOnline: goOnline,
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

        // Track consecutive failed iterations
        if (newFinds == 0) {
          consecutiveZeroFinds++;
        } else {
          consecutiveZeroFinds = 0;
        }

        if (consecutiveZeroFinds >= 3) {
          _addLog(
              '🛑 AI has stalled without finding new relevant passages. Forcing early stop to save tokens.');
          break;
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
            ? 'OpenRouter (reported)'
            : (Prefs.aiSponsoredProvider.contains('deepseek')
                ? 'DeepSeek Sponsored (calculated)'
                : 'OpenRouter Sponsored (reported)'));

    double initialCost = 0.0;
    if (Prefs.activeAiProviderMode == 0) {
      // Gemini Direct pricing:
      // Gemini 1.5 Flash (Light): $0.075 / 1M input, $0.30 / 1M output
      lightCost = (_lightInputTokens / 1000000.0) * 0.075 +
          (_lightOutputTokens / 1000000.0) * 0.30;
      heavyCost = (_heavyInputTokens / 1000000.0) * 1.50 +
          (_heavyOutputTokens / 1000000.0) * 9.00;
    } else {
      initialCost = _initialOpenRouterCost;
      lightCost = _lightOpenRouterCost;
      heavyCost = _heavyOpenRouterCost;
    }

    final double totalCost = initialCost + lightCost + heavyCost;
    debugPrint('[AiSearch] 💰 Total Cost: \$${totalCost.toStringAsFixed(6)}');

    if (Prefs.activeAiProviderMode == 1) {
      _addLog(
          '💰 Total Cost: \$${totalCost.toStringAsFixed(6)} | Token Usage:');
      if (_initialModelUsed.isNotEmpty) {
        _addLog(
            '   ↳ Initial Model ($_initialModelUsed): \$${initialCost.toStringAsFixed(6)} (${_initialInputTokens} in, ${_initialOutputTokens} out)');
      }
      _addLog(
          '   ↳ Light Model ($_lightModelUsed): \$${lightCost.toStringAsFixed(6)} (${_lightInputTokens} in, ${_lightOutputTokens} out)');
      if (_heavyModelUsed.isNotEmpty) {
        _addLog(
            '   ↳ Heavy Model ($_heavyModelUsed): \$${heavyCost.toStringAsFixed(6)} (${_heavyInputTokens} in, ${_heavyOutputTokens} out)');
      }
      _addLog('   ↳ Pricing Source: $providerStr');
    } else {
      _addLog('📊 Token Usage:');
      if (_initialModelUsed.isNotEmpty) {
        _addLog(
            '   ↳ Initial Model ($_initialModelUsed): (${_initialInputTokens} in, ${_initialOutputTokens} out)');
      }
      _addLog(
          '   ↳ Light Model ($_lightModelUsed): (${_lightInputTokens} in, ${_lightOutputTokens} out)');
      if (_heavyModelUsed.isNotEmpty) {
        _addLog(
            '   ↳ Heavy Model ($_heavyModelUsed): (${_heavyInputTokens} in, ${_heavyOutputTokens} out)');
      }
    }

    if (Prefs.activeAiProviderMode == 2) {
      _addLog(
          '💡 **Note**: Sponsored Mode is a gift to help you get started or for those in restricted regions. May the generous donor of this API key gain great merit! \nFor faster speeds, better quality, and more daily queries, we highly recommend adding your own free Gemini key in the AI Settings.');
    }

    await _logCost(userQuery, initialCost, lightCost, heavyCost, totalCost);

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

  Future<List<String>> _generateInitialQueries(
      String userQuery, String apiKey, void Function(String) onThought,
      {bool goOnline = true}) async {
    final String targetLang = _getTargetLanguage(Prefs.currentScriptLanguage);
    String promptTemplate = await _getInitialPromptString(goOnline);
    final prompt = promptTemplate
        .replaceAll('{{userQuery}}', userQuery)
        .replaceAll('{{targetLang}}', targetLang);

    try {
      final String? response = await _callAi(
        prompt,
        apiKey,
        isHeavy: true,
        isInitialQuery: true,
      );
      if (response == null) return [];

      final jsonStr = _extractJson(response);
      if (jsonStr == null) return [];

      final data = jsonDecode(jsonStr);

      final thinking = data['thinking']?.toString() ?? '';
      if (thinking.isNotEmpty) {
        _addLog('🧠 $thinking');
        onThought(thinking);
      }

      return _parseStringList(data['next_queries'])
          .map((e) => e.toLowerCase().trim())
          .where((t) => t.isNotEmpty)
          .toList();
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
    bool goOnline = true,
  }) async {
    final buffer = StringBuffer();
    int wordCount = 0;
    int maxWords = Prefs.aiMaxResults * 40;
    if (Prefs.activeAiProviderMode == 2) {
      maxWords = 1000;
    }

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

    final String targetLang = _getTargetLanguage(Prefs.currentScriptLanguage);
    String promptTemplate =
        await _getPromptPlanEvaluatePromptString(goOnline: goOnline);
    final prompt = promptTemplate
        .replaceAll('{{userQuery}}', userQuery)
        .replaceAll('{{cumulativeContext}}', cumulativeContext)
        .replaceAll('{{previousThoughts}}', previousThoughts)
        .replaceAll('{{triedQueries}}', triedQueries.join(', '))
        .replaceAll(
            '{{fullTextResults}}',
            buffer.toString().isEmpty
                ? "(No full text results available)"
                : buffer.toString())
        .replaceAll(
            '{{overflowSummaryText}}',
            overflowSummary.isEmpty
                ? ""
                : "OVERFLOW SUMMARY (use OF- indices to request):\n$overflowSummary\n")
        .replaceAll('{{targetLang}}', targetLang);

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

      // SAFEGUARD 1: Force the 15-item limit in code
      final rawOverflow = _parseIntList(data['request_overflow_indices']);
      final safeOverflow = rawOverflow.take(30).toList();

      // SAFEGUARD 2: Prevent context explosion by capping selected indices per iteration
      final rawSelected = _parseIntList(data['selected_new_indices']);
      final safeSelected =
          rawSelected.take(10).toList(); // Max 10 new selections per turn

      // SAFEGUARD 3: Prevent infinite loops by blocking already tried queries
      final rawQueries = _parseStringList(data['next_queries'])
          .map((e) => e.toLowerCase().trim())
          .where((q) => q.isNotEmpty)
          .toList();
      final safeQueries =
          rawQueries.where((q) => !triedQueries.contains(q)).toList();

      return AiPlan(
        selectedIndices: safeSelected,
        requestOverflowIndices: safeOverflow,
        thoughtProcess: _parseStringList(data['thought_process']),
        // SAFEGUARD 4: If it generated queries but they were all filtered out as duplicates, force a stop.
        isFullyAnswered: data['is_fully_answered'] == true ||
            (rawQueries.isNotEmpty && safeQueries.isEmpty),
        nextQueries: safeQueries,
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

    final lightModel =
        lightPref.isNotEmpty ? lightPref : 'gemini-3.5-flash-lite';
    final heavyModel = heavyPref.isNotEmpty ? heavyPref : 'gemini-3.6-flash';

    if (!isHeavy) {
      return [lightModel];
    }

    // For heavy iterations, try the heavy model first, but fallback to light if it fails or hits a hard quota.
    return [heavyModel, lightModel];
  }

  Future<String?> _callAi(String prompt, String apiKey,
      {required bool isHeavy, bool isInitialQuery = false}) async {
    if (Prefs.activeAiProviderMode == 0) {
      return _callGemini(prompt, apiKey, isHeavy: isHeavy);
    } else {
      String apiUrl = 'https://openrouter.ai/api/v1/chat/completions';

      if (Prefs.activeAiProviderMode == 2) {
        if (Prefs.aiSponsoredProvider.isNotEmpty) {
          if (Prefs.aiSponsoredProvider.startsWith('http')) {
            apiUrl = Prefs.aiSponsoredProvider;
          } else {
            apiUrl =
                'https://${Prefs.aiSponsoredProvider}/api/v1/chat/completions';
          }

          if (apiUrl.contains('deepseek')) {
            apiKey = Env.deepSeekApiKey;
          }
        }
      }
      debugPrint('[AiSearch] _callAi resolved apiUrl: $apiUrl');

      return _callOpenRouter(prompt, apiKey,
          isHeavy: isHeavy, apiUrl: apiUrl, isInitialQuery: isInitialQuery);
    }
  }

  double _estimateModelCost(
      String model, int promptTokens, int completionTokens) {
    final m = model.toLowerCase();
    double inputRate = 0.14 / 1000000;
    double outputRate = 0.28 / 1000000;

    if (m.contains('reasoner') || m.contains('r1')) {
      inputRate = 0.55 / 1000000;
      outputRate = 2.19 / 1000000;
    } else if (m.contains('sonnet')) {
      inputRate = 3.0 / 1000000;
      outputRate = 15.0 / 1000000;
    } else if (m.contains('llama') || m.contains('flash')) {
      inputRate = 0.075 / 1000000;
      outputRate = 0.30 / 1000000;
    }

    return (promptTokens * inputRate) + (completionTokens * outputRate);
  }

  Future<String?> _callOpenRouter(String prompt, String apiKey,
      {required bool isHeavy,
      String apiUrl = 'https://openrouter.ai/api/v1/chat/completions',
      bool isInitialQuery = false}) async {
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

    List<String> models = !isHeavy ? [lightModel] : [heavyModel, lightModel];

    // Override with a specific cheap initial model if we are in sponsored mode
    if (isInitialQuery &&
        Prefs.activeAiProviderMode == 2 &&
        Prefs.aiSponsoredInitialModel.isNotEmpty) {
      models = [Prefs.aiSponsoredInitialModel];
    }

    // Standardize model IDs based on endpoint (OpenRouter vs Direct DeepSeek)
    models = models.map((m) {
      if (apiUrl.contains('api.deepseek.com') &&
          m.toLowerCase().startsWith('deepseek/')) {
        return m.substring(9);
      }
      return m;
    }).toList();

    final Map<String, dynamic> requestBody = {
      "messages": [
        {"role": "user", "content": prompt}
      ],
      "temperature": 0.4,
      "max_tokens": 4096
    };

    for (final model in models) {
      requestBody["model"] = model;
      final endpoint = apiUrl;

      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          final providerName =
              endpoint.contains('deepseek') ? 'DeepSeek' : 'OpenRouter';
          debugPrint(
              '[AiSearch] Attempting connection to $providerName model $model (Try ${attempt + 1}) at $endpoint...');
          debugPrint('[AiSearch] Request Body: ${jsonEncode(requestBody)}');

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
            debugPrint(
                '[AiSearch] API Error HTTP ${response.statusCode}: ${response.body}');
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
            double cost = (usage['cost'] as num?)?.toDouble() ?? 0.0;
            if (cost == 0.0 && (pTokens > 0 || cTokens > 0)) {
              cost = _estimateModelCost(model, pTokens, cTokens);
            }
            if (isInitialQuery &&
                Prefs.activeAiProviderMode == 2 &&
                Prefs.aiSponsoredInitialModel.isNotEmpty) {
              _initialInputTokens += pTokens;
              _initialOutputTokens += cTokens;
              _initialOpenRouterCost += cost;
              _initialModelUsed = model;
            } else if (isHeavy) {
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

  Future<void> _logCost(String userQuery, double initialCost, double lightCost,
      double heavyCost, double totalCost) async {
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
        "initialModel": _initialModelUsed,
        "lightModel": _lightModelUsed,
        "heavyModel": _heavyModelUsed,
        "initialInputTokens": _initialInputTokens,
        "initialOutputTokens": _initialOutputTokens,
        "lightInputTokens": _lightInputTokens,
        "lightOutputTokens": _lightOutputTokens,
        "heavyInputTokens": _heavyInputTokens,
        "heavyOutputTokens": _heavyOutputTokens,
        "initialCost": initialCost,
        "lightCost": lightCost,
        "heavyCost": heavyCost,
        "totalCost": totalCost
      });

      await file.writeAsString(jsonEncode(entries), mode: FileMode.write);
    } catch (e) {
      debugPrint('[AiSearch] Error logging cost to file: $e');
    }
  }

  Future<String> _getInitialPromptString(bool goOnline) async {
    if (goOnline) {
      try {
        final cacheBuster = DateTime.now().millisecondsSinceEpoch;
        final url = Uri.parse(
            'https://cdn.jsdelivr.net/gh/bksubhuti/tipitaka-pali-reader@master/mydownloads/initial_prompt_string.txt?v=$cacheBuster');
        final response = await http.get(url, headers: {
          'Cache-Control': 'no-cache',
        }).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200 && response.body.trim().isNotEmpty) {
          debugPrint('[AiSearch] Successfully fetched initial prompt online.');
          return response.body.trim();
        }
      } catch (e) {
        debugPrint('[AiSearch] Error fetching initial prompt online: $e');
      }
    }
    return '''You are an expert in Theravāda Buddhism and the Pāḷi Tipiṭaka.
The user is asking: "{{userQuery}}"

Task:
1. Formulate a step-by-step thought process. Identify key figures, events, and core concepts related to the query across the Suttas, Vinaya, and Commentaries (Aṭṭhakathā).
2. Generate 6 to 12 highly targeted Pāḷi search terms.
3. CRITICAL TWO-WORD RULE + STEM MATCHING:  
EVERY query MUST consist of EXACTLY TWO words separated by a space (e.g., "upāli vinaya", "assaji upatissa").  
Single-word queries and queries with 3 or more words are STRICTLY FORBIDDEN.  
The app executes a distance search, requiring both words to be within ~12–20 words of each other.  

Because the FTS engine uses substring / partial-wildcard matching, ALWAYS prefer the shortest meaningful stem rather than a fully declined form:  
- Search “puris” (not “puriso”, “purisa”, or “purisassa”) so that all cases and compounds are found.  
- The same rule applies to singular vs plural. For “eyes” do NOT search only the singular “cakkhu”. Search the stem without the vowel ending “cakkh” to catch variants, like cakkūni (this also catches the plural “cakkhūni”, “cakkhūnaṃ”, etc.).  
Never assume the singular form is enough; always choose the root that covers both singular and plural (and all cases).  
You CAN use short root words, but they MUST still be paired with a second contextual word.

4. CRITICAL: Do NOT include book names (e.g., 'dhammapada', 'majjhimanikaya', 'saṃyuttanikāya') in search terms.
5. You must use proper Pāḷi diacritics (ā, ī, ū, ṃ, ṭ, ḍ, ṇ, ñ, ṅ, ḷ).
6. TEXTUAL VARIANTS: The database uses the Chaṭṭha Saṅgāyana (CSCD) edition. If a common word has alternative spellings or synonyms in different traditions (e.g., 'suka' vs 'suva' for parrot, or 'kapi' vs 'makkaṭa' vs 'vānara' for monkey), include searches for BOTH root words. Do not assume your preferred spelling is the only one.
7. LANGUAGE: You must formulate your "thinking" field entirely in {{targetLang}} (if you know it, otherwise English).  Search terms should in roman pāḷi characters.
8. SUTTAS AND STORIES: The app has a special backend feature: if your second word is "sutta" or "vatthu", it will automatically join them to search for the compound title. Therefore, to search for a specific text, ALWAYS split it into two words (e.g., query "aṅgulimāla sutta" to find aṅgulimālasuttaṃ, or query "kisāgota vatthu" to find kisāgotamīvatthu). This perfectly obeys the two-word rule while getting a direct hit on the title.
9. UNIQUE CHARACTERS: Never search for a character's name as a single word. Always pair their name (or partial name) with a highly relevant context word (e.g., instead of just "paṭācārā", search "paṭācārā udaka").


CRITICAL SPELLING RULE (CSCD only):
You MUST use only the exact spellings found in the Chaṭṭha Saṅgāyana edition.
Never invent or “correct” diacritics.
Especially:
- saliva / phlegm = kheḷa (ḷ, NOT ṭ). Never write kheṭa.
- When in doubt about a rare technical term, prefer the shortest stem that is known to exist in CSCD and pair it with a second word.
If you are unsure of the correct CSCD spelling, do not generate that query.


Respond ONLY with a JSON object in this exact format:
{
  "thinking": "(Write your detailed thought process here in {{targetLang}})",
  "next_queries": ["ānanda rodati", "assaji upatissa", "sāriputta nirodha"]
}''';
  }

  Future<String> _getPromptPlanEvaluatePromptString(
      {bool goOnline = true}) async {
    if (goOnline) {
      try {
        final cacheBuster = DateTime.now().millisecondsSinceEpoch;
        final url = Uri.parse(
            'https://cdn.jsdelivr.net/gh/bksubhuti/tipitaka-pali-reader@master/mydownloads/prompt_plan_evaluate_string.txt?v=$cacheBuster');
        final response = await http.get(url, headers: {
          'Cache-Control': 'no-cache',
        }).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200 && response.body.trim().isNotEmpty) {
          debugPrint('[AiSearch] Successfully fetched evaluate prompt online.');
          return response.body.trim();
        }
      } catch (e) {
        debugPrint('[AiSearch] Error fetching evaluate prompt online: $e');
      }
    }
    return '''You are an expert in Theravāda Buddhism and the Pāḷi Tipiṭaka.
The user asks: "{{userQuery}}"

We are running an autonomous search loop (maximum 5 iterations).
{{cumulativeContext}}

PREVIOUS AI THOUGHTS (For context):
{{previousThoughts}}

Queries we have already tried (do not repeat these): {{triedQueries}}

Here are the FULL TEXT results for this round (use their numeric indices [0], [1], ... to select):
{{fullTextResults}}

{{overflowSummaryText}}

Task:
1. Carefully review the FULL TEXT results.
2. Select the most relevant passages using their indices and put them in "selected_new_indices". You MUST only select evidence that actually appears in the provided results.
3. Generate 6 to 10 highly targeted two-word Pāḷi search queries for the next round (if needed).
4. You may request up to 30 overflow items using "request_overflow_indices".

CRITICAL RULES:

TWO-WORD RULE:
Every query MUST consist of exactly two words separated by a space. Single-word queries are forbidden. The app requires both words to be within ~20 words of each other.

3. CRITICAL TWO-WORD RULE + STEM MATCHING:  
EVERY query MUST consist of EXACTLY TWO words separated by a space (e.g., "upāli vinaya", "assaji upatissa").  
Single-word queries and queries with 3 or more words are STRICTLY FORBIDDEN.  
The app executes a distance search, requiring both words to be within ~12–20 words of each other.  

Because the FTS engine uses substring / partial-wildcard matching, ALWAYS prefer the shortest meaningful stem rather than a fully declined form:  
- Search “puris” (not “puriso”, “purisa”, or “purisassa”) so that all cases and compounds are found.  
- The same rule applies to singular vs plural. For “eyes” do NOT search only the singular “cakkhu”. Search the stem without the vowel ending “cakkh” to catch variants, like cakkūni (this also catches the plural “cakkhūni”, “cakkhūnaṃ”, etc.).  
Never assume the singular form is enough; always choose the root that covers both singular and plural (and all cases).  
You CAN use short root words, but they MUST still be paired with a second contextual word.

TEXTUAL HIERARCHY:
Prefer primary canonical texts (Mūla / Vinaya / Sutta) over commentaries (Aṭṭhakathā) and later manuals. When both a root text and a commentary contain the answer, select the primary text.

CRITICAL SPELLING RULE (CSCD only):
You MUST use only the exact spellings found in the Chaṭṭha Saṅgāyana edition.
Never invent or “correct” diacritics.
Especially:
- saliva / phlegm = kheḷa (ḷ, NOT ṭ). Never write kheṭa.
- When in doubt about a rare technical term, prefer the shortest stem that is known to exist in CSCD and pair it with a second word.
If you are unsure of the correct CSCD spelling, do not generate that query.

PERSISTENCE & STOPPING RULE (very important):
- Do NOT set "is_fully_answered": true after only one evaluation round unless the results contain a precise, direct ruling that fully answers the question.
- For technical Vinaya or commentary questions, prefer continuing for at least one more round when the current results are only approximate or general.
- Set "is_fully_answered": true ONLY when the selected passages provide a clear, factual, and specific answer to the user’s exact question.
- General etiquette passages, Sekhiya rules, or related but non-specific texts are not enough to stop.

OVERFLOW USAGE (important):
- If the current results do not fully and precisely answer the question, you SHOULD request overflow items.
- Prefer requesting overflow from commentary books when looking for specific Vinaya rulings.
- It is better to request overflow items and continue than to stop early with only approximate results.
- Only skip overflow when you already have clear, direct evidence that answers the question.

DISCOVERY & CONTINUATION RULE:
- Keep all good results you have already selected.
- When a concrete, unusual, or highly specific technical phrase appears in the results or overflow, treat it as a discovery.
- In the next round you may generate new queries that reuse parts of that discovered phrase.
- Do not invent theoretical combinations that have not appeared in the results.  
- Only follow up on phrases that actually appeared in the current search results of this session.

OTHER GUIDANCE:
- If previous searches returned 0 or poor results, pivot to new synonyms or related concepts.
- SQL searches are fast — it is better to try more targeted queries than to stop early.
- Write your "thought_process" in {{targetLang}} (or English if unknown).

Respond ONLY with valid JSON:
{
  "thought_process": ["write your thoughts here in {{targetLang}}"],
  "selected_new_indices": [0, 2],
  "request_overflow_indices": [5, 8],
  "is_fully_answered": false,
  "next_queries": ["query1", "query2"]
}''';
  }
}
