import 'dart:convert';

List<SearchSuggestion> searchSuggestionFromJson(String str) =>
    List<SearchSuggestion>.from(
        json.decode(str).map((x) => SearchSuggestion.fromJson(x)));

String searchSuggestionToJson(List<SearchSuggestion> data) =>
    json.encode(List<dynamic>.from(data.map((x) => x.toJson())));

class SearchSuggestion {
  String word;
  int count;
  String plain;

  /// A word of a translation in its own script, shown and used as it is.
  /// Pali suggestions are stored in Roman letters and shown in the reader's
  /// script; turning a Myanmar word into Myanmar script would ruin it.
  bool asTyped;

  SearchSuggestion({
    this.word = "",
    this.plain = "",
    this.count = 0,
    this.asTyped = false,
  });

  factory SearchSuggestion.fromJson(Map<dynamic, dynamic> json) {
    return SearchSuggestion(
      word: json["word"] ?? "n/a",
      plain: json["plain"] ?? "n/a",
      count: json["frequency"] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        "word": word,
        "plain": plain,
        "frequency": count,
      };

  @override
  String toString() {
    return word;
  }
}
