class ParagraphMapping {
  int paragraph;
  String? baseBookID;
  int? basePageNumber;
  String expBookID;
  int expPageNumber;
  String bookName;

  /// The paragraph's number as printed, which can be a range ("31-32").
  /// Shown instead of [paragraph] when known: from the sentence data,
  /// [paragraph] is ePitaka's own count of paragraphs through the book.
  String? printedNumber;
  ParagraphMapping(
      {required this.paragraph,
      this.baseBookID,
      this.basePageNumber,
      required this.expBookID,
      required this.expPageNumber,
      required this.bookName,
      this.printedNumber});
}
