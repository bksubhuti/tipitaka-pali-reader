import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../business_logic/models/search_result.dart';
import '../services/database/database_helper.dart';
import '../services/prefs.dart';
import '../services/repositories/fts_repo.dart';
import '../ui/screens/home/search_page/search_page.dart';


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
  final List<String> thoughtProcess;
  final bool isFullyAnswered;
  final List<String> nextQueries;

  AiPlan({
    required this.selectedIndices,
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
    _agentLog.clear();
    _lightInputTokens = 0;
    _lightOutputTokens = 0;
    _heavyInputTokens = 0;
    _heavyOutputTokens = 0;
    _lightOpenRouterCost = 0.0;
    _heavyOpenRouterCost = 0.0;
    _lightModelUsed = '';
    _heavyModelUsed = '';
    final apiKey = Prefs.useGeminiDirect ? Prefs.geminiDirectApiKey : Prefs.openRouterApiKey;

    if (apiKey.isEmpty) {
      return AiSearchResult(
        results: [],
        summary: 'No API key configured. Please set one in AI Settings.',
      );
    }

    final bestResults = <AiMatchedResult>[];
    final triedQueries = <String>[];
    final ftsRepo = FtsDatabaseRepository(_dbHelper);

    _addLog('🤖 **Agent started** analyzing query: "$userQuery"');

    // Iteration 0: Bootstrap the search
    List<String> nextQueriesToSearch =
        await _generateInitialQueries(userQuery, apiKey);
    List<AiMatchedResult> newResults = [];

    // Run the Agentic Loop
    try {
      for (int iteration = 1; iteration <= 5; iteration++) {
        if (_isCancelled) break;
        _updateStatus('--- Iteration $iteration ---');

        if (nextQueriesToSearch.isNotEmpty) {
          _updateStatus(
              '✅ Validating ${nextQueriesToSearch.length} Pāḷi queries against dictionary...');
          final validated = await _validateTerms(nextQueriesToSearch);
          triedQueries.addAll(validated);
          newResults.clear();

          for (final query in validated) {
            _updateStatus('🔍 Searching database for "$query"...');
            try {
              final isMultiWord = query.contains(' ');
              final queryMode =
                  isMultiWord ? QueryMode.distance : QueryMode.prefix;
              final wordDistance = isMultiWord ? 12 : 0;

              final results =
                  await ftsRepo.getResults(query, queryMode, wordDistance);
              _updateStatus('   Found ${results.length} raw matches.');

              // Sample max maxResults per query to prevent token overflow
              List<SearchResult> sampled = results;
              if (results.length > maxResults) {
                final step = (results.length / maxResults).floor();
                sampled = List.generate(maxResults, (i) => results[i * step]);
              }

              for (final r in sampled) {
                newResults.add(AiMatchedResult(
                  searchResult: r,
                  term: query,
                  queryMode: queryMode,
                ));
              }
            } catch (e) {
              debugPrint('Error searching $query: $e');
            }
          }
        }

        if (newResults.isEmpty) {
          _addLog('⚠️ No results found for these queries. Rethinking...');
        } else {
          _updateStatus('📚 Reading ${newResults.length} passages...');
        }

        _updateStatus('🧠 AI is evaluating findings and planning...');

        // HYBRID ROUTING STRATEGY:
        // Use the light model for Iterations 1 & 2. Switch to the heavy model for Iteration 3+.
        bool isHeavyLifting = iteration >= 3;

        final plan = await _evaluateAndPlan(
          userQuery: userQuery,
          apiKey: apiKey,
          triedQueries: triedQueries,
          bestResultsCount: bestResults.length,
          newResults: newResults,
          isHeavy: isHeavyLifting,
        );

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
          if (idx >= 0 && idx < newResults.length) {
            final r = newResults[idx];
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

        if (plan.isFullyAnswered) {
          _addLog(
              '✅ **Search Complete:** AI determined all relevant instances have been found.');
          break;
        }

        if (plan.nextQueries.isEmpty) {
          _addLog('🏁 AI has exhausted its search ideas.');
          break;
        }

        nextQueriesToSearch = plan.nextQueries;
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

    if (Prefs.useGeminiDirect) {
      lightCost = (_lightInputTokens / 1000000.0) * 0.25 +
          (_lightOutputTokens / 1000000.0) * 1.50;
      heavyCost = (_heavyInputTokens / 1000000.0) * 1.50 +
          (_heavyOutputTokens / 1000000.0) * 9.00;
    } else {
      lightCost = _lightOpenRouterCost;
      heavyCost = _heavyOpenRouterCost;
    }

    final double totalCost = lightCost + heavyCost;

    // Determine model names for the log
    String modelInfo = '';
    if (Prefs.useGeminiDirect) {
      if (_lightModelUsed.isNotEmpty) modelInfo += 'Light: $_lightModelUsed';
      if (_heavyModelUsed.isNotEmpty) {
        if (modelInfo.isNotEmpty) modelInfo += ', ';
        modelInfo += 'Heavy: $_heavyModelUsed';
      }
    } else {
      if (_lightModelUsed.isNotEmpty) modelInfo += 'Light: $_lightModelUsed';
      if (_heavyModelUsed.isNotEmpty) {
        if (modelInfo.isNotEmpty) modelInfo += ', ';
        modelInfo += 'Heavy: $_heavyModelUsed';
      }
    }

    _addLog('💰 Cost: \$${totalCost.toStringAsFixed(6)} | $modelInfo');
    _addLog('📊 Tokens: ${_lightInputTokens + _heavyInputTokens} in, ${_lightOutputTokens + _heavyOutputTokens} out');
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

    return AiSearchResult(
      results: bestResults,
      summary: summaryBuffer.toString(),
    );
  }

  /// Initial prompt with explicit Chain of Thought instructions.
  Future<List<String>> _generateInitialQueries(
      String userQuery, String apiKey) async {
    final prompt =
        '''You are an expert in Theravada Buddhism and the Pāḷi Tipiṭaka.
The user is asking: "$userQuery"

Task:
1. Formulate a chain of thought. Consider major canonical events and key figures related to the query.
2. Generate 3-6 Pāḷi search terms (single words or short phrases) to find relevant passages. 
CRITICAL: You must use proper Pāḷi diacritics (ā, ī, ū, ṃ, ṭ, ḍ, ṇ, ñ, ṅ, ḷ).
NEVER use hyphens or dashes. For compound words, either combine them entirely (e.g., "sotadvāravīthi") or use spaces (e.g., "sota dvāra"). Do not write "sota-dvāra".

Respond ONLY with a JSON object in this exact format:
{
  "thinking": "Ananda famously cried during the Buddha's passing. I need to search for 'rodati' or 'assu' in the context of the Parinibbāna.",
  "next_queries": ["ānanda rodati", "assu", "soka"]
}''';

    try {
      final response = await _callAi(prompt, apiKey, isHeavy: false);
      if (response == null) return [];

      final jsonStr = _extractJson(response);
      if (jsonStr == null) return [];

      final data = jsonDecode(jsonStr);

      final thinking = data['thinking']?.toString() ?? '';
      if (thinking.isNotEmpty) {
        _addLog('🧠 $thinking');
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
    required int bestResultsCount,
    required List<AiMatchedResult> newResults,
    required bool isHeavy,
  }) async {
    final buffer = StringBuffer();
    int wordCount = 0;
    // each FTS result is 25 but we have prompts too. originally 1000 maxwords for 20 fixed results numbers
    int maxWords = Prefs.aiMaxResults * 50;

    for (int i = 0; i < newResults.length && wordCount < maxWords; i++) {
      final r = newResults[i].searchResult;
      final cleanDesc = r.description
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      final words = cleanDesc.split(' ');
      final allowedWords = maxWords - wordCount;
      final truncDesc = words.length > allowedWords
          ? '${words.take(allowedWords).join(' ')}...'
          : cleanDesc;

      buffer.write(
          '[$i] ${r.book.name}, ${r.suttaName}, Pg ${r.pageNumber}: "$truncDesc"\n');
      wordCount += words.take(allowedWords).length;
    }

    final prompt =
        '''You are an expert in Theravada Buddhism and the Pāḷi Tipiṭaka.
The user asks: "$userQuery"

We are running an autonomous search loop.
Currently saved relevant results: $bestResultsCount
Queries we have already tried: ${triedQueries.join(', ')}

Here are new search results we just found:
${buffer.toString().isEmpty ? "(No results found for the last queries)" : buffer.toString()}

Task:
1. Review the new results. Keep EVERY result that accurately relates to the user's question. 
2. Formulate a step-by-step thought process. Explicitly mention what you found, what you discarded, and why.
3. If there are still other known canonical events related to the prompt that you haven't found yet, set is_fully_answered to false and suggest new Pāḷi queries.

Respond ONLY with JSON (no markdown):
{
  "thought_process": [
    "Result 1 shows Ananda crying at Mahāpajāpatī's passing, I will keep it.",
    "Result 4 shows Ananda crying at Sāriputta's passing, I will keep it.",
    "I have not found the famous Parinibbāna reference yet, so I must keep searching."
  ],
  "selected_new_indices": [1, 4],
  "is_fully_answered": false,
  "next_queries": ["kapiśīsaṃ upanissāya", "parinibbāna ānanda"]
}''';

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

  Future<List<String>> _validateTerms(List<String> terms) async {
    final db = await _dbHelper.database;
    final validated = <String>[];

    for (final term in terms) {
      final words = term.split(' ').where((w) => w.isNotEmpty).toList();
      bool allWordsValid = true;
      final validatedWords = <String>[];

      for (final word in words) {
        final exact = await db
            .rawQuery('SELECT word FROM words WHERE word = ? LIMIT 1', [word]);
        if (exact.isNotEmpty) {
          validatedWords.add(word);
          continue;
        }

        final prefix = await db.rawQuery(
            'SELECT word FROM words WHERE word LIKE ? ORDER BY frequency DESC LIMIT 3',
            ['$word%']);
        if (prefix.isNotEmpty) {
          validatedWords.add(word);
          continue;
        }

        if (word.length > 3) {
          final stem = word.substring(0, word.length - 1);
          final stemMatch = await db.rawQuery(
              'SELECT word FROM words WHERE word LIKE ? ORDER BY frequency DESC LIMIT 1',
              ['$stem%']);
          if (stemMatch.isNotEmpty) {
            validatedWords.add(stemMatch.first['word'] as String);
            continue;
          }
        }
        allWordsValid = false;
        break;
      }

      if (allWordsValid && validatedWords.isNotEmpty) {
        validated.add(validatedWords.join(' '));
      } else {
        validated.add(term); // Fallback to avoid empty lists
      }
    }
    return validated;
  }

  Future<List<String>> _getActiveFlashModels(String apiKey,
      {required bool isHeavy}) async {
    final heavyPref = Prefs.aiHeavyModel;
    final lightPref = Prefs.aiLightModel;

    final lightModel =
        lightPref.isNotEmpty ? lightPref : 'gemini-3.1-flash-lite';
    final heavyModel = heavyPref.isNotEmpty ? heavyPref : 'gemini-3.5-flash';

    if (!isHeavy) {
      return [lightModel];
    }

    // For heavy iterations, try the heavy model first, but fallback to light if it fails or hits a hard quota.
    return [heavyModel, lightModel];
  }

  Future<String?> _callAi(String prompt, String apiKey,
      {required bool isHeavy}) async {
    if (Prefs.useGeminiDirect) {
      return _callGemini(prompt, apiKey, isHeavy: isHeavy);
    } else {
      return _callOpenRouter(prompt, apiKey, isHeavy: isHeavy);
    }
  }

  Future<String?> _callOpenRouter(String prompt, String apiKey,
      {required bool isHeavy}) async {
    final lightPref = Prefs.openRouterLightModel;
    final heavyPref = Prefs.openRouterHeavyModel;

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
      final endpoint = 'https://openrouter.ai/api/v1/chat/completions';

      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          debugPrint(
              '[AiSearch] Attempting connection to OpenRouter model $model (Try ${attempt + 1})...');

          final response = await http.post(
            Uri.parse(endpoint),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
              'HTTP-Referer': 'https://americanmonk.org',
              'X-Title': 'Tipitaka Pali Reader',
            },
            body: utf8.encode(jsonEncode(requestBody)),
          ).timeout(const Duration(seconds: 30));

          if (_isCancelled) {
            throw Exception('Cancelled by user');
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
            debugPrint('[AiSearch] API Error: ${data['error']['message']}');
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
            debugPrint('[AiSearch] Model: $model | Tokens: $pTokens in, $cTokens out | Cost: \$${cost.toStringAsFixed(6)}');
          }

          return content;
        } catch (e) {
          debugPrint('[AiSearch] Network error: $e');
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

          final response = await http.post(
            Uri.parse('$endpoint?key=$apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(requestBody),
          );

          if (_isCancelled) {
            throw Exception('Cancelled by user');
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
            debugPrint('[AiSearch] API Error: ${data['error']['message']}');
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
          break;
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
