import 'package:tipitaka_pali/business_logic/models/page_content.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/database/legacy_data_retirement.dart';
import 'package:tipitaka_pali/services/repositories/page_content_repo.dart';
import 'package:tipitaka_pali/services/repositories/sentence_page_content_repo.dart';

/// Sentences first, the old `pages` table for whatever they do not cover.
///
/// ePitaka does not carry every book TPR can open. Books imported from HTML,
/// and extension books installed from a zip, exist only in `pages` and have no
/// sentences and no page boundaries. Asking the sentence repository for one of
/// those returns null, and the reader renders null as an empty page: no error,
/// no explanation, just nothing there.
///
/// So a miss is a question rather than an answer. If the old table is still
/// present it is asked next, and the book reads as it always did.
class CompositePageContentRepository implements PageContentRepository {
  CompositePageContentRepository(this.databaseProvider)
      : _sentences = SentencePageContentRepository(databaseProvider),
        _pages = PageContentDatabaseRepository(databaseProvider);

  final DatabaseHelper databaseProvider;
  final SentencePageContentRepository _sentences;
  final PageContentDatabaseRepository _pages;

  /// Whether `pages` is still there to fall back to. Worked out once: the
  /// answer only changes when retirement runs, and that happens before any
  /// page is read.
  bool? _legacyPresent;

  Future<bool> _hasLegacy() async {
    if (_legacyPresent != null) return _legacyPresent!;
    try {
      final db = await databaseProvider.database;
      _legacyPresent = await LegacyDataRetirement.hasLegacyPages(db);
    } catch (_) {
      _legacyPresent = false;
    }
    return _legacyPresent!;
  }

  @override
  Future<PageContent?> getPageByBookAndPage(String bookID, int page) async {
    final fromSentences = await _sentences.getPageByBookAndPage(bookID, page);
    if (fromSentences != null) return fromSentences;
    if (!await _hasLegacy()) return null;
    return _pages.getPageByBookAndPage(bookID, page);
  }

  @override
  Future<PageContent> getPage(int id) async {
    if (await _hasLegacy()) return _pages.getPage(id);
    return _sentences.getPage(id);
  }

  @override
  Future<List<PageContent>> getPages(String bookId) async {
    final fromSentences = await _sentences.getPages(bookId);
    if (fromSentences.isNotEmpty) return fromSentences;
    if (!await _hasLegacy()) return fromSentences;
    return _pages.getPages(bookId);
  }
}
