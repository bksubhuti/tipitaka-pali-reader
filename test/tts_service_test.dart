import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tipitaka_pali/business_logic/models/page_content.dart';
import 'package:tipitaka_pali/services/tts/tts_plan.dart';
import 'package:tipitaka_pali/services/tts/tts_service.dart';
import 'package:tipitaka_pali/utils/page_composer.dart';

/// A voice that writes down what it was asked to say.
class _Engine extends TtsEngine {
  final Set<String> voices;
  final spoken = <String>[];
  String language = '';
  double speed = 1.0;
  Completer<void>? hold;

  /// Each utterance with the speed it was spoken at.
  final paced = <String>[];

  _Engine(this.voices);

  @override
  Future<bool> isAvailable(String l) async => voices.contains(l);
  @override
  Future<bool> setLanguage(String l) async {
    language = l;
    return true;
  }

  @override
  Future<void> setSpeed(double speed) async => this.speed = speed;
  @override
  Future<void> speak(String text) async {
    spoken.add('$language:$text');
    paced.add('$text@$speed');
    if (hold != null) await hold!.future;
  }

  @override
  Future<void> stop() async {
    final h = hold;
    hold = null;
    h?.complete();
  }
}

/// An engine that queues ahead, as Android does. The test says when each
/// queued utterance finishes playing.
class _QueueingEngine extends TtsEngine {
  final queued = <String>[];
  final playing = <Completer<void>>[];

  @override
  bool get queuesAhead => true;
  @override
  Future<bool> isAvailable(String l) async => true;
  @override
  Future<bool> setLanguage(String l) async => true;
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> speak(String text) async {}
  @override
  Future<({Future<void> done})> queue(String language, String text) async {
    queued.add('$language:$text');
    final done = Completer<void>();
    playing.add(done);
    return (done: done.future);
  }

  /// The utterance at the head of the queue finishes.
  void finishOne() => playing.removeAt(0).complete();

  @override
  Future<void> stop() async {
    for (final p in playing) {
      if (!p.isCompleted) p.complete();
    }
    playing.clear();
  }
}

PageContent _page(int number, List<String> palis, {String? english}) =>
    PageContent(
      pageNumber: number,
      content: '',
      languages: const ['en'],
      sentences: [
        for (var i = 0; i < palis.length; i++)
          PageSentence(
              paraId: number,
              lineId: i + 1,
              pali: palis[i],
              translations: [english == null ? '' : '$english ${i + 1}']),
      ],
    );

Future<void> _settle() => Future.delayed(const Duration(milliseconds: 10));

void main() {
  final pages = [
    _page(1, ['evaṃ', 'me'], english: 'thus'),
    _page(2, ['sutaṃ'], english: 'heard'),
  ];

  test('reads to the end of the book, turning the pages', () async {
    final engine = _Engine({'kn-IN', 'en-US'});
    final tts = TtsService(engine: engine);
    final turned = <int>[];
    await tts.start(
        bookUuid: 'b',
        pages: pages,
        startIndex: 0,
        chosen: {TtsPlan.pali, 'en'},
        onPage: turned.add);
    await _settle();

    expect(engine.spoken, [
      'kn-IN:ಏವಂ', 'en-US:thus 1',
      'kn-IN:ಮೇ', 'en-US:thus 2',
      'kn-IN:ಸುತಂ', 'en-US:heard 1',
    ]);
    expect(turned, [2]);
    expect(tts.isPlaying, isFalse);
    expect(tts.position.value, isNull);
  });

  test('the Pali and the translations each at their own speed', () async {
    final engine = _Engine({'kn-IN', 'en-US'});
    final tts = TtsService(engine: engine);
    await tts.start(
        bookUuid: 'b',
        pages: pages,
        startIndex: 1,
        chosen: {TtsPlan.pali, 'en'},
        speed: 1.5,
        paliSpeed: 0.5);
    await _settle();
    expect(engine.paced, ['ಸುತಂ@0.5', 'heard 1@1.5']);
  });

  test('starts at the sentence asked for', () async {
    final engine = _Engine({'kn-IN'});
    final tts = TtsService(engine: engine);
    await tts.start(
        bookUuid: 'b',
        pages: pages,
        startIndex: 0,
        fromSentence: 's1_2',
        chosen: {TtsPlan.pali});
    await _settle();
    expect(engine.spoken, ['kn-IN:ಮೇ', 'kn-IN:ಸುತಂ']);
  });

  test('a language with no voice is skipped and named', () async {
    final engine = _Engine({'en-US'});
    final tts = TtsService(engine: engine);
    final note = await tts.start(
        bookUuid: 'b',
        pages: pages,
        startIndex: 0,
        chosen: {TtsPlan.pali, 'en'});
    await _settle();
    expect(note, contains('Kannada'));
    expect(engine.spoken.every((s) => s.startsWith('en-US:')), isTrue);
  });

  test('with no voice at all nothing starts', () async {
    final engine = _Engine({});
    final tts = TtsService(engine: engine);
    final note = await tts.start(
        bookUuid: 'b', pages: pages, startIndex: 0, chosen: {TtsPlan.pali});
    expect(note, isNotNull);
    expect(tts.isPlaying, isFalse);
    expect(engine.spoken, isEmpty);
  });

  test('stop ends the reading where it is', () async {
    final engine = _Engine({'kn-IN'})..hold = Completer();
    final tts = TtsService(engine: engine);
    await tts.start(
        bookUuid: 'b', pages: pages, startIndex: 0, chosen: {TtsPlan.pali});
    await _settle();
    expect(tts.isPlaying, isTrue);
    expect(tts.position.value?.sentence, 's1_1');

    await tts.stop();
    await _settle();
    expect(engine.spoken, ['kn-IN:ಏವಂ']);
    expect(tts.isPlaying, isFalse);
    expect(tts.position.value, isNull);
  });

  test('queued ahead: the next is ready before this one ends, and the '
      'highlight stays on what is playing', () async {
    final engine = _QueueingEngine();
    final tts = TtsService(engine: engine);
    final turned = <int>[];
    await tts.start(
        bookUuid: 'b',
        pages: pages,
        startIndex: 0,
        chosen: {TtsPlan.pali, 'en'},
        onPage: turned.add);
    await _settle();

    // The first is playing and the second already waits behind it.
    expect(engine.queued, ['kn-IN:ಏವಂ', 'en-US:thus 1']);
    expect(tts.position.value?.language, TtsPlan.pali);

    engine.finishOne();
    await _settle();
    expect(tts.position.value?.language, 'en');
    expect(tts.position.value?.sentence, 's1_1');
    expect(engine.queued.length, 3, reason: 'one more queued behind');

    for (var i = 0; i < 4; i++) {
      engine.finishOne();
      await _settle();
    }
    expect(tts.position.value?.page, 2);
    expect(turned, [2]);

    engine.finishOne();
    await _settle();
    expect(tts.isPlaying, isFalse);
    expect(engine.queued.length, 6);
  });
}
