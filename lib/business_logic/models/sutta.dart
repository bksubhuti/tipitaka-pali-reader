class Sutta {
  final String name;
  final String bookID;
  final String bookName;
  final int pageNumber;
  final int endPage; // New field
  final String shortcut;

  Sutta({
    required this.name,
    required this.bookID,
    required this.bookName,
    required this.pageNumber,
    this.endPage = 0, // Default to 0
    this.shortcut = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'bookID': bookID,
      'bookName': bookName,
      'pageNumber': pageNumber,
      'endPage': endPage,
      'shortcut': shortcut
    };
  }

  factory Sutta.fromMap(Map<String, dynamic> map) {
    return Sutta(
      name: map['name'] ?? '',
      bookID: map['book_id'] ?? '',
      // Note: Without the JOIN, book_name might be the same as book_id
      // unless you handle it in the Repo query alias
      bookName: map['book_name'] ?? '',
      pageNumber: map['start_page']?.toInt() ?? 0,
      endPage: map['end_page']?.toInt() ?? 0, // Map from DB column
      shortcut: map['shortcut'] ?? '',
    );
  }

  @override
  String toString() =>
      'Sutta(name: $name, bookID: $bookID, page: $pageNumber-$endPage)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Sutta &&
        other.name == name &&
        other.bookID == bookID &&
        other.bookName == bookName &&
        other.pageNumber == pageNumber &&
        other.endPage == endPage &&
        other.shortcut == shortcut;
  }

  @override
  int get hashCode =>
      name.hashCode ^
      bookID.hashCode ^
      bookName.hashCode ^
      pageNumber.hashCode ^
      endPage.hashCode ^
      shortcut.hashCode;
}
