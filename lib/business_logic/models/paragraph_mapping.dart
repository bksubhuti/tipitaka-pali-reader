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

  /// The part of the volume the link goes to, where the volume holds
  /// several: "dasakanipāta-aṭṭhakathā" in aṭṭhakādinipātaaṭṭhakathā, as
  /// the root text has a book for each nipāta.
  String? partName;
  ParagraphMapping(
      {required this.paragraph,
      this.baseBookID,
      this.basePageNumber,
      required this.expBookID,
      required this.expPageNumber,
      required this.bookName,
      this.printedNumber,
      this.partName});
}
