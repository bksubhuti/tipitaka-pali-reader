import 'book.dart';

class SearchResult {
  // id will be used for sorting etc
  final int id;
  final Book book;
  final int pageNumber;
  final String description;
  final String suttaName;
  final bool isTranslation;
  final String? translation;

  SearchResult({
    required this.id,
    required this.book,
    required this.pageNumber,
    required this.description,
    required this.suttaName,
    this.isTranslation = false,
    this.translation,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'book': book.toJson(),
      'pageNumber': pageNumber,
      'description': description,
      'suttaName': suttaName,
      'isTranslation': isTranslation,
      'translation': translation,
    };
  }

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      id: json['id'] as int,
      book: Book.fromJson(json['book'] as Map<String, dynamic>),
      pageNumber: json['pageNumber'] as int,
      description: json['description'] as String,
      suttaName: json['suttaName'] as String,
      isTranslation: (json['isTranslation'] as bool?) ?? false,
      translation: json['translation'] as String?,
    );
  }
}
