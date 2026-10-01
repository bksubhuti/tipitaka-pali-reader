import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:tipitaka_pali/business_logic/models/page_content.dart';
import 'package:tipitaka_pali/services/language_installer.dart';
import 'package:tipitaka_pali/services/tts/tts_plan.dart';

/// What the speech engine has to do. Behind an interface so the reading
/// order and stopping can be tested without a voice.
abstract class TtsEngine {
  Future<bool> isAvailable(String language);
  Future<bool> setLanguage(String language);
  Future<void> setSpeed(double speed);

  /// Completes when the text has been spoken, or when [stop] cuts it short.
  Future<void> speak(String text);
  Future<void> stop();
}

class FlutterTtsEngine implements TtsEngine {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  Future<void> _init() async {
    if (_ready) return;
    _ready = true;
    // Speak returns when the utterance has finished, so sentences follow
    // one another without a completion handler to keep in step.
    await _tts.awaitSpeakCompletion(true);
  }

  @override
  Future<bool> isAvailable(String language) async {
    await _init();
    try {
      if (await _tts.isLanguageAvailable(language) == true) return true;
      // Some engines know a language only by its base code.
      final base = language.split('-').first;
      return await _tts.isLanguageAvailable(base) == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> setLanguage(String language) async {
    await _init();
    final set = await _tts.setLanguage(language);
    if (set == 1 || set == true) return true;
    final base = await _tts.setLanguage(language.split('-').first);
    return base == 1 || base == true;
  }

  /// [speed] is 1 for normal. The engines disagree on what normal is: 0.5 on
  /// Android, iOS and macOS, 1.0 on Windows.
  @override
  Future<void> setSpeed(double speed) async {
    await _init();
    final normal = !kIsWeb && Platform.isWindows ? 1.0 : 0.5;
    final rate = (normal * speed).clamp(0.1, !kIsWeb && Platform.isWindows ? 3.0 : 1.0);
    await _tts.setSpeechRate(rate.toDouble());
  }

  @override
  Future<void> speak(String text) async {
    await _init();
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async => _tts.stop();
}

/// Where the reading has got to, for the reader to highlight and follow.
@immutable
class TtsPosition {
  final String bookUuid;
  final int page;
  final String sentence;
  final String language;

  const TtsPosition({
    required this.bookUuid,
    required this.page,
    required this.sentence,
    required this.language,
  });
}

/// Reads a book aloud, sentence by sentence, from a starting sentence to the
/// end of the book or until stopped.
///
/// One at a time across the app: starting a reading in one book stops the
/// reading in another.
class TtsService extends ChangeNotifier {
  final TtsEngine _engine;

  TtsService({TtsEngine? engine}) : _engine = engine ?? FlutterTtsEngine();

  /// Whether reading aloud can work here at all.
  static bool get isSupported =>
      !kIsWeb &&
      (Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isWindows);

  final ValueNotifier<TtsPosition?> position = ValueNotifier(null);

  bool get isPlaying => _playing;
  bool _playing = false;

  /// The book being read, if any.
  String? get bookUuid => _bookUuid;
  String? _bookUuid;

  /// Moves on every start and stop. A reading loop that finds it changed has
  /// been superseded and ends without touching anything.
  int _session = 0;

  /// Starts reading [pages] from [startIndex], at [fromSentence] if given.
  ///
  /// [chosen] is the languages to speak, [TtsPlan.pali] among them if the
  /// Pali is wanted. Languages with no voice on this device are left out and
  /// named in the message returned; if none has a voice nothing starts.
  /// Returns null when everything chosen can be spoken.
  ///
  /// [onPage] is told each time the reading moves on to a new page, so the
  /// reader can turn to it.
  Future<String?> start({
    required String bookUuid,
    required List<PageContent> pages,
    required int startIndex,
    String? fromSentence,
    required Set<String> chosen,
    double speed = 1.0,
    void Function(int pageNumber)? onPage,
  }) async {
    await stop();
    final session = _session;

    final speakable = <String>{};
    final missing = <String>[];
    for (final language in chosen) {
      if (await _engine.isAvailable(TtsPlan.voiceFor(language))) {
        speakable.add(language);
      } else {
        missing.add(language);
      }
    }
    if (session != _session) return null;
    final note = missing.isEmpty ? null : _missingVoices(missing);
    if (speakable.isEmpty) return note;

    await _engine.setSpeed(speed);
    _playing = true;
    _bookUuid = bookUuid;
    notifyListeners();
    unawaited(_read(session, bookUuid, pages, startIndex, fromSentence,
        speakable, onPage));
    return note;
  }

  Future<void> _read(
    int session,
    String bookUuid,
    List<PageContent> pages,
    int startIndex,
    String? from,
    Set<String> speakable,
    void Function(int pageNumber)? onPage,
  ) async {
    String? language;
    try {
      for (var i = startIndex; i < pages.length; i++) {
        final page = pages[i];
        final sentences = page.sentences;
        // A page from the old page table has no sentences to read.
        if (sentences == null) break;
        final pageNumber = page.pageNumber ?? 0;
        if (i != startIndex) onPage?.call(pageNumber);

        final plan = TtsPlan.forPage(
            pageNumber, sentences, page.languages, speakable,
            from: i == startIndex ? from : null);
        for (final utterance in plan) {
          if (session != _session) return;
          position.value = TtsPosition(
            bookUuid: bookUuid,
            page: utterance.page,
            sentence: utterance.sentence,
            language: utterance.language,
          );
          if (utterance.language != language) {
            await _engine.setLanguage(TtsPlan.voiceFor(utterance.language));
            language = utterance.language;
          }
          if (session != _session) return;
          await _engine.speak(utterance.text);
        }
      }
    } catch (e) {
      debugPrint('reading aloud stopped: $e');
    }
    if (session == _session) _finished();
  }

  Future<void> stop() async {
    _session++;
    final wasPlaying = _playing;
    _finished();
    if (wasPlaying) await _engine.stop();
  }

  void _finished() {
    position.value = null;
    if (!_playing && _bookUuid == null) return;
    _playing = false;
    _bookUuid = null;
    notifyListeners();
  }

  static String _missingVoices(List<String> languages) {
    final names = languages
        .map((l) => l == TtsPlan.pali
            ? 'Pāḷi (a Kannada voice)'
            : LanguageInstaller.nameOf(l))
        .join(', ');
    return 'No voice on this device for $names, so it is skipped. '
        'Voices can be added in the system speech settings.';
  }

  @override
  void dispose() {
    _session++;
    if (_playing) _engine.stop();
    position.dispose();
    super.dispose();
  }
}
