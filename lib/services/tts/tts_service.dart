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

  /// Whether the engine can be handed the next utterance while the current
  /// one is still speaking, each in its own language.
  bool get queuesAhead => false;

  /// Queues [text] in [language] behind whatever is speaking. Completes once
  /// it is queued, with `done`, which completes when it has been spoken.
  Future<({Future<void> done})> queue(String language, String text) async {
    await setLanguage(language);
    return (done: speak(text));
  }
}

class FlutterTtsEngine extends TtsEngine {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  /// On Android each change of language makes the engine load the other
  /// voice, and a voice that is not on the device is fetched over the
  /// network — Kannada usually is. Sent one at a time, every switch between
  /// the Pali and a translation waited a second or two for that. Queued
  /// ahead, the next utterance is prepared while the current one plays.
  /// Android fixes an utterance's language when it is queued, so changing
  /// the language for the next one does not touch the one playing.
  @override
  bool get queuesAhead => !kIsWeb && Platform.isAndroid;

  /// Utterances queued ahead, oldest first, completed as each one ends.
  final List<Completer<void>> _queued = [];

  /// After a stop, end events for what was cut off can still arrive. They
  /// are ignored until something new starts.
  bool _awaitingStart = false;

  /// The utterance being spoken, completed when the engine says it is done.
  Completer<void>? _current;
  bool _started = false;
  final Stopwatch _sinceSpeak = Stopwatch();

  /// Completion is tracked here rather than with the plugin's
  /// awaitSpeakCompletion. When reading restarts mid-sentence, macOS can
  /// report the stopped utterance as finished after the next one has been
  /// sent, and the plugin hands that to whichever speak is waiting: the new
  /// sentence "finished" at once, the reading ran a step ahead of the voice,
  /// and the highlight sat on the next language while the previous one was
  /// still being spoken. So an end is believed only once the new utterance
  /// has started, or after long enough that it cannot be a stale one from
  /// an engine that does not report starts.
  Future<void> _init() async {
    if (_ready) return;
    _ready = true;
    await _tts.awaitSpeakCompletion(false);
    if (queuesAhead) await _tts.setQueueMode(1); // add, do not flush
    _tts.setStartHandler(() {
      _awaitingStart = false;
      if (_current != null) _started = true;
    });
    _tts.setCompletionHandler(_ended);
    _tts.setCancelHandler(_ended);
    _tts.setErrorHandler((_) => _ended(error: true));
  }

  void _ended({bool error = false}) {
    if (queuesAhead) {
      if (_awaitingStart && !error) return;
      if (_queued.isNotEmpty) {
        final done = _queued.removeAt(0);
        if (!done.isCompleted) done.complete();
      }
      return;
    }
    if (error || _started || _sinceSpeak.elapsedMilliseconds > 400) _finish();
  }

  @override
  Future<({Future<void> done})> queue(String language, String text) async {
    if (!queuesAhead) return super.queue(language, text);
    await _init();
    await setLanguage(language);
    final done = Completer<void>();
    _queued.add(done);
    final sent = await _tts.speak(text);
    if (sent != 1 && sent != true) {
      _queued.remove(done);
      if (!done.isCompleted) done.complete();
    }
    return (done: done.future);
  }

  void _finish() {
    final current = _current;
    _current = null;
    _started = false;
    if (current != null && !current.isCompleted) current.complete();
  }

  /// The Windows plugin has no isLanguageAvailable, and its setLanguage
  /// answers yes whether or not a voice matched, and matches only the full
  /// code. So on Windows the voices are listed and one is picked by locale.
  bool get _isWindows => !kIsWeb && Platform.isWindows;
  List<({String name, String locale})>? _windowsVoices;

  Future<List<({String name, String locale})>> _voices() async {
    if (_windowsVoices != null) return _windowsVoices!;
    final voices = <({String name, String locale})>[];
    try {
      for (final v in (await _tts.getVoices) as List? ?? const []) {
        final name = v['name']?.toString();
        final locale = v['locale']?.toString();
        if (name != null && locale != null) {
          voices.add((name: name, locale: locale));
        }
      }
    } catch (e) {
      debugPrint('could not list the voices: $e');
    }
    // An empty list is not kept, so a voice added while the app runs is
    // found on the next try.
    if (voices.isNotEmpty) _windowsVoices = voices;
    return voices;
  }

  /// A voice for [language], 'hi-IN' say: one for that exact locale, else
  /// one for the same base language.
  Future<({String name, String locale})?> _windowsVoiceFor(
      String language) async {
    final voices = await _voices();
    final want = language.toLowerCase();
    final base = want.split('-').first;
    for (final v in voices) {
      if (v.locale.toLowerCase() == want) return v;
    }
    for (final v in voices) {
      if (v.locale.toLowerCase().split('-').first == base) return v;
    }
    return null;
  }

  @override
  Future<bool> isAvailable(String language) async {
    await _init();
    if (_isWindows) return await _windowsVoiceFor(language) != null;
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
    if (_isWindows) {
      final voice = await _windowsVoiceFor(language);
      if (voice == null) return false;
      final set =
          await _tts.setVoice({'name': voice.name, 'locale': voice.locale});
      return set == 1 || set == true;
    }
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
    _finish();
    final current = Completer<void>();
    _current = current;
    _started = false;
    _sinceSpeak
      ..reset()
      ..start();
    final sent = await _tts.speak(text);
    if (sent != 1 && sent != true) _finish();
    return current.future;
  }

  @override
  Future<void> stop() async {
    if (queuesAhead) _awaitingStart = true;
    await _tts.stop();
    _finish();
    for (final done in _queued) {
      if (!done.isCompleted) done.complete();
    }
    _queued.clear();
  }
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

  /// Whether this device has a voice for an engine language, e.g. 'si-LK'.
  Future<bool> hasVoice(String engineLanguage) =>
      _engine.isAvailable(engineLanguage);

  /// Those of [languages] that have a voice on this device.
  Future<Set<String>> speakable(Iterable<String> languages) async {
    final out = <String>{};
    for (final language in languages) {
      if (await _engine.isAvailable(TtsPlan.voiceFor(language))) {
        out.add(language);
      }
    }
    return out;
  }

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

  /// Everything to say from the starting point to the end of the book, in
  /// order, page by page as it is reached.
  Iterable<TtsUtterance> _utterances(List<PageContent> pages, int startIndex,
      String? from, Set<String> speakable) sync* {
    for (var i = startIndex; i < pages.length; i++) {
      final page = pages[i];
      final sentences = page.sentences;
      // A page from the old page table has no sentences to read.
      if (sentences == null) return;
      yield* TtsPlan.forPage(
          page.pageNumber ?? 0, sentences, page.languages, speakable,
          from: i == startIndex ? from : null);
    }
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
    try {
      final upcoming =
          _utterances(pages, startIndex, from, speakable).iterator;
      if (!upcoming.moveNext()) {
        if (session == _session) _finished();
        return;
      }
      var current = upcoming.current;
      var page = pages[startIndex].pageNumber ?? 0;
      String? language;
      Future<void>? currentDone;
      if (_engine.queuesAhead) {
        currentDone = (await _engine.queue(
                TtsPlan.voiceFor(current.language), current.text))
            .done;
      }

      while (true) {
        if (session != _session) return;
        if (current.page != page) {
          page = current.page;
          onPage?.call(page);
        }
        position.value = TtsPosition(
          bookUuid: bookUuid,
          page: current.page,
          sentence: current.sentence,
          language: current.language,
        );
        final next = upcoming.moveNext() ? upcoming.current : null;

        if (_engine.queuesAhead) {
          // The next one goes in now, so it is ready when this one ends.
          Future<void>? nextDone;
          if (next != null) {
            nextDone = (await _engine.queue(
                    TtsPlan.voiceFor(next.language), next.text))
                .done;
          }
          if (session != _session) return;
          await currentDone;
          currentDone = nextDone;
        } else {
          if (current.language != language) {
            await _engine.setLanguage(TtsPlan.voiceFor(current.language));
            language = current.language;
          }
          if (session != _session) return;
          await _engine.speak(current.text);
        }

        if (next == null) break;
        current = next;
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
            ? 'Pāḷi (a ${TtsPlan.paliVoice.name} voice)'
            : LanguageInstaller.nameOf(l))
        .join(', ');
    return 'No voice on this device for $names, so it is skipped. '
        '$addVoicesHint';
  }

  static bool get _isWindows => !kIsWeb && Platform.isWindows;

  /// How to add a voice, said where a voice is missing. Windows gets the
  /// way there spelled out: the settings are hard to find, and on a metered
  /// connection the download goes round in circles asking for apps to be
  /// closed, without saying why.
  static String get addVoicesHint => _isWindows
      ? 'On Windows, add one in Settings → Time & language → Speech → '
          'Add voices; Hindi reads the Pāḷi. If it keeps asking for apps '
          'to be closed, turn off Metered connection for your network '
          'while it downloads.'
      : 'Voices can be added in the system speech settings.';

  /// The system's speech settings, where it can open them.
  static Uri? get speechSettings =>
      _isWindows ? Uri.parse('ms-settings:speech') : null;

  @override
  void dispose() {
    _session++;
    if (_playing) _engine.stop();
    position.dispose();
    super.dispose();
  }
}
