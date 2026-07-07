import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
}

/// Service that orchestrates AI-guided search of the Tipiṭaka.
class AiSearchService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final void Function(String message)? onStatusUpdate;

  // We keep a running log of what the agent did to show the user at the end
  final List<String> _agentLog = [];

  AiSearchService({this.onStatusUpdate});

  void _updateStatus(String message) {
    onStatusUpdate?.call(message);
    debugPrint('[AiSearch] $message');
  }

  void _addLog(String message) {
    _agentLog.add(message);
    _updateStatus(message);
  }

  /// Main entry point: perform a multi-turn AI-guided search.
  Future<AiSearchResult> search(String userQuery) async {
    _agentLog.clear();
    final apiKey = Prefs.geminiDirectApiKey;

    if (apiKey.isEmpty) {
      return AiSearchResult(
        results: [],
        summary: 'No Gemini API key configured. Please set one in AI Settings.',
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
    for (int iteration = 1; iteration <= 5; iteration++) {
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

            // Sample max 20 per query to prevent token overflow
            List<SearchResult> sampled = results;
            if (results.length > 20) {
              final step = (results.length / 20).floor();
              sampled = List.generate(20, (i) => results[i * step]);
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
      final plan = await _evaluateAndPlan(
        userQuery: userQuery,
        apiKey: apiKey,
        triedQueries: triedQueries,
        bestResultsCount: bestResults.length,
        newResults: newResults,
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

Respond ONLY with a JSON object in this exact format:
{
  "thinking": "Ananda famously cried during the Buddha's passing. I need to search for 'rodati' or 'assu' in the context of the Parinibbāna.",
  "next_queries": ["ānanda rodati", "assu", "soka"]
}''';

    try {
      final response = await _callGemini(prompt, apiKey);
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
  }) async {
    final buffer = StringBuffer();
    int wordCount = 0;
    const maxWords = 1000;

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
   CRITICAL: Do not just pick the single "best" one. If there are 5 different instances of the event (or related events), select ALL 5 indices. Build a comprehensive collection.
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
      final response = await _callGemini(prompt, apiKey);
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

  Future<List<String>> _getActiveFlashModels(String apiKey) async {
    // We hardcode this to ensure it strictly uses the highly capable 3.5 model
    // rather than falling back to weak preview or lite models that fail the agent loop.
    return [
      'gemini-3.5-flash',
      'gemini-3.1-flash-lite' // Ultimate fallback only if 3.5 is down
    ];
  }

  Future<String?> _callGemini(String prompt, String apiKey) async {
    final models = await _getActiveFlashModels(apiKey);

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
}
