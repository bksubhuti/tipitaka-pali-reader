import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'ai_search_service.dart';

/// Represents a single historical AI search record.
class AiSearchHistoryItem {
  final String query;
  final AiSearchResult result;
  final DateTime timestamp;

  AiSearchHistoryItem({
    required this.query,
    required this.result,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'query': query,
      'result': result.toJson(),
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory AiSearchHistoryItem.fromJson(Map<String, dynamic> json) {
    return AiSearchHistoryItem(
      query: json['query'] as String,
      result: AiSearchResult.fromJson(json['result'] as Map<String, dynamic>),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

/// Service to persist and manage AI search history to a local JSON file.
class AiSearchHistoryManager {
  static const String _fileName = 'ai_search_history.json';
  static const int _maxHistoryLimit = 50;

  List<AiSearchHistoryItem> _history = [];

  // Singleton pattern
  static final AiSearchHistoryManager _instance = AiSearchHistoryManager._internal();

  factory AiSearchHistoryManager() {
    return _instance;
  }

  AiSearchHistoryManager._internal();

  /// Get the current history list
  List<AiSearchHistoryItem> get history => _history;

  /// Load the history from disk on startup
  Future<void> init() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        if (jsonString.isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(jsonString);
          _history = jsonList
              .map((e) => AiSearchHistoryItem.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[AiSearchHistoryManager] Error loading history: $e');
      _history = []; // fallback to empty
    }
  }

  /// Add a new search result to history
  Future<void> add(String query, AiSearchResult result) async {
    // Remove if exists to move it to the top
    _history.removeWhere((item) => item.query.toLowerCase() == query.toLowerCase());

    _history.insert(
      0,
      AiSearchHistoryItem(
        query: query,
        result: result,
        timestamp: DateTime.now(),
      ),
    );

    if (_history.length > _maxHistoryLimit) {
      _history.removeLast(); // Keep up to max limit
    }

    await _saveToDisk();
  }

  /// Delete a specific search by query
  Future<void> delete(String query) async {
    _history.removeWhere((item) => item.query.toLowerCase() == query.toLowerCase());
    await _saveToDisk();
  }

  /// Clear all history
  Future<void> deleteAll() async {
    _history.clear();
    await _saveToDisk();
  }

  Future<File> _getFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<void> _saveToDisk() async {
    try {
      final file = await _getFile();
      final jsonList = _history.map((e) => e.toJson()).toList();
      final jsonString = jsonEncode(jsonList);
      await file.writeAsString(jsonString);
    } catch (e) {
      debugPrint('[AiSearchHistoryManager] Error saving history: $e');
    }
  }
}
