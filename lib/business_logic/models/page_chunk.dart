import 'package:tipitaka_pali/business_logic/models/page_content.dart';

class PageChunk {
  final int pageNumber;
  final int chunkIndex;
  final bool isFirstChunkOfPage;

  /// A chunk of a page that has not been built yet, and which block of it
  /// this is. The page composes itself the first time one of its chunks is
  /// drawn, so scrolling pays for what is on screen and nothing else.
  final PageContent? page;
  final int indexInPage;
  final String? _htmlContent;

  PageChunk({
    required this.pageNumber,
    required this.chunkIndex,
    String? htmlContent,
    this.page,
    this.indexInPage = 0,
    this.isFirstChunkOfPage = false,
  }) : _htmlContent = htmlContent;

  String get htmlContent {
    final stored = _htmlContent;
    if (stored != null) return stored;
    final blocks = page?.blocks ?? const <String>[];
    if (indexInPage < blocks.length) return blocks[indexInPage];
    // A page that turned out to hold fewer blocks than were counted. Showing
    // it whole is wrong but readable; showing nothing is a blank screen.
    return indexInPage == 0 ? (page?.content ?? '') : '';
  }

  @override
  String toString() {
    return 'PageChunk(pageNumber: $pageNumber, chunkIndex: $chunkIndex)';
  }
}
