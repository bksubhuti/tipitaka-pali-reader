class Book {
  String id;
  String name;
  int firstPage;
  int lastPage;
  int paraNum;

  Book(
      {required this.id,
      required this.name,
      this.firstPage = 0,
      this.lastPage = 0,
      this.paraNum = 0});

  @override
  String toString() {
    return 'Book #$id $name';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'firstPage': firstPage,
      'lastPage': lastPage,
      'paraNum': paraNum,
    };
  }

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      id: json['id'] as String,
      name: json['name'] as String,
      firstPage: json['firstPage'] as int? ?? 0,
      lastPage: json['lastPage'] as int? ?? 0,
      paraNum: json['paraNum'] as int? ?? 0,
    );
  }
}
