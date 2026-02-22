class FoundInfo {
  final String term;
  final int index;
  final int pageNumber;
  final int pageIndex;
  final int occurrenceInPage;

  FoundInfo({
    required this.term,
    required this.index,
    required this.pageNumber,
    required this.pageIndex,
    required this.occurrenceInPage,
  });

  @override
  String toString() {
    return 'term: $term\n'
        'index:$index\n'
        'pageNumber:$pageNumber\n'
        'index in Page:$occurrenceInPage';
  }
}
