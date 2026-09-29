import 'package:flutter_test/flutter_test.dart';

import 'package:tipitaka_pali/business_logic/models/page_chunk.dart';
import 'package:tipitaka_pali/business_logic/models/page_content.dart';

/// A page builds itself when it is first looked at.
///
/// The reader's list knows how many blocks a book has before any page is
/// built, and draws only the blocks on screen. So the page must stay unbuilt
/// until one of its blocks is wanted, and must not be built twice.
void main() {
  group('a page that has not been built', () {
    test('is not built until it is read', () {
      var built = 0;
      final page = PageContent(
        pageNumber: 1,
        blockCount: 2,
        build: () {
          built++;
          return '<p class="bodytext">one</p><p class="bodytext">two</p>';
        },
      );

      expect(built, 0, reason: 'holding a page must not build it');
      expect(page.content, contains('one'));
      expect(built, 1);
    });

    test('is built once, however often it is read', () {
      var built = 0;
      final page = PageContent(
        blockCount: 1,
        build: () {
          built++;
          return '<p class="bodytext">text</p>';
        },
      );

      page.content;
      page.content;
      page.blocks;
      page.blocks;
      expect(built, 1, reason: 'scrolling back to a page must not rebuild it');
    });

    test('splits into the blocks the list scrolls through', () {
      final page = PageContent(
        build: () => '<p class="bodytext">one</p>'
            '<p class="gatha1">two</p>'
            '<p class="noindentbodytext">three</p>',
      );
      expect(page.blocks.length, 3);
      expect(page.blocks[1], '<p class="gatha1">two</p>');
    });

    test('a page given its text outright still works', () {
      // The page-shaped path hands over HTML it has already read.
      final page = PageContent(content: '<p class="bodytext">given</p>');
      expect(page.content, contains('given'));
      expect(page.blocks.length, 1);
    });
  });

  group('a chunk of an unbuilt page', () {
    test('does not build the page until it is drawn', () {
      var built = 0;
      final page = PageContent(
        blockCount: 2,
        build: () {
          built++;
          return '<p class="bodytext">one</p><p class="bodytext">two</p>';
        },
      );
      final chunks = [
        for (var i = 0; i < 2; i++)
          PageChunk(
              pageNumber: 1, chunkIndex: i, page: page, indexInPage: i),
      ];

      expect(built, 0, reason: 'building the list must not build the pages');
      expect(chunks[1].htmlContent, contains('two'));
      expect(built, 1);
    });

    test('a chunk beyond what the page holds shows nothing rather than break',
        () {
      final page = PageContent(
        blockCount: 3,
        build: () => '<p class="bodytext">only one</p>',
      );
      final chunk =
          PageChunk(pageNumber: 1, chunkIndex: 2, page: page, indexInPage: 2);
      expect(chunk.htmlContent, '');
    });

    test('a chunk given its own html keeps it', () {
      final chunk = PageChunk(
          pageNumber: 1, chunkIndex: 0, htmlContent: '<p>direct</p>');
      expect(chunk.htmlContent, '<p>direct</p>');
    });
  });
}
