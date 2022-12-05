import 'dart:convert';

List<PageContent> pageContentFromJson(String str) => List<PageContent>.from(
    json.decode(str).map((x) => PageContent.fromJson(x)));

String pageContentToJson(List<PageContent> data) =>
    json.encode(List<dynamic>.from(data.map((x) => x.toJson())));

class PageContent {
  int? id;
  String? bookID;
  int? pageNumber;
  String content;
  String? paragraphNumber;

  PageContent(
      {this.id = 0,
      this.bookID = "",
      this.pageNumber = 0,
      this.content = "",
      this.paragraphNumber = ""});

  factory PageContent.fromJson(Map<dynamic, dynamic> json) {
    return PageContent(
      id: json["id"] ?? 0,
      bookID: json["bookid"] ?? "n/a",
      pageNumber: json["page"] ?? "n/a",
      content: json["content"] ?? "n/a",
      paragraphNumber: json["paranum"] ?? "n/a",
    );
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "bookid": bookID,
        "page": pageNumber,
        "content": content,
        "paranum": paragraphNumber
      };

  @override
  String toString() {
    return '$id: $content';
  }
}
