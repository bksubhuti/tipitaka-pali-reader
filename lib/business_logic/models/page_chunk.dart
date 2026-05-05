class PageChunk {
  final int pageNumber;
  final int chunkIndex;
  final String htmlContent;
  final bool isFirstChunkOfPage;

  PageChunk({
    required this.pageNumber,
    required this.chunkIndex,
    required this.htmlContent,
    this.isFirstChunkOfPage = false,
  });

  @override
  String toString() {
    return 'PageChunk(pageNumber: $pageNumber, chunkIndex: $chunkIndex)';
  }
}
