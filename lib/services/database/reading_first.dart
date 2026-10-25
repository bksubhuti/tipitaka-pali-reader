/// Reading comes before indexing.
///
/// The search index is built, and each language added to it, in the
/// background while the app is in use. Both go through the one database
/// connection, so a book opened meanwhile had its queries wait behind every
/// batch of the index: a book that opens in under a second took eighty
/// seconds while Myanmar was indexed, and on a slower phone, installing
/// English and then a second language straight away, the reader stood empty
/// for minutes. That was reported as a blank screen.
///
/// So a book's loading is marked, and the index, between its batches, waits
/// for it to finish, and for a moment after: the reader's next reads, the
/// book's details, bookmarks and headings, come straight after the pages,
/// and on a phone, where a batch takes a second or more, each waiting behind
/// one left the book almost blank for the minute after installing English.
/// Not for ever: a load that never ends must not stop the index, so the
/// wait has a limit.
class ReadingFirst {
  ReadingFirst._();

  static int _reading = 0;
  static DateTime _lastRead = DateTime(0);

  /// How long the index stays held after a read ends.
  static const _after = Duration(milliseconds: 1500);

  static bool get _busy =>
      _reading > 0 || DateTime.now().difference(_lastRead) < _after;

  /// Runs [read], with the index held back between batches until it ends.
  static Future<T> run<T>(Future<T> Function() read) async {
    _reading++;
    try {
      return await read();
    } finally {
      _reading--;
      _lastRead = DateTime.now();
    }
  }

  /// The index's pause between batches: a frame let through, as it always
  /// was, and while a book is loading, a wait for it, up to [limit].
  static Future<void> pause(
      {Duration limit = const Duration(seconds: 15)}) async {
    await Future.delayed(Duration.zero);
    final until = DateTime.now().add(limit);
    while (_busy && DateTime.now().isBefore(until)) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }
}
