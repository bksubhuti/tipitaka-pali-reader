import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:tipitaka_pali/services/language_installer.dart';
import 'package:tipitaka_pali/services/prefs.dart';
import 'package:tipitaka_pali/services/provider/shown_languages_provider.dart';
import 'package:tipitaka_pali/services/tts/tts_plan.dart';
import 'package:tipitaka_pali/services/tts/tts_service.dart';
import 'package:tipitaka_pali/ui/screens/reader/controller/reader_view_controller.dart';

/// Read aloud: play and stop, and which languages to hear.
///
/// The choices are the Pali and each translation shown on the page. Pali is
/// always offered, even when it is hidden on screen. At least one stays
/// chosen.
class TtsControls extends StatelessWidget {
  /// Plain buttons for the desktop control bar, rather than the floating
  /// pill shown over the text on phones and tablets.
  final bool inBar;

  const TtsControls({super.key, this.inBar = false});

  /// What can be read: the Pali, then the translations in the order shown.
  static List<String> options(ShownLanguagesProvider shown) =>
      [TtsPlan.pali, ...shown.shownLanguages];

  /// What the reader chose, narrowed to what can be read now. Everything,
  /// until they first choose.
  static Set<String> chosen(List<String> options) {
    final saved = Prefs.ttsLanguages;
    if (saved.isEmpty) return options.toSet();
    final kept = options.where(saved.contains).toSet();
    return kept.isEmpty ? {TtsPlan.pali} : kept;
  }

  static String _voiceName(String language) => language == TtsPlan.pali
      ? 'Pāḷi (it needs a ${TtsPlan.paliVoice.name} voice)'
      : nameOf(language);

  /// What reads the Pali unless Sinhala is chosen: Hindi on Windows, which
  /// has no Kannada voice, and Kannada everywhere else.
  static String get _defaultPaliVoice =>
      !kIsWeb && Platform.isWindows ? 'hi' : 'kn';

  /// Puts the reader's choice of Pali voice into effect, falling back to
  /// the default if the voice chosen is not on this device, say after a
  /// Sinhala voice was removed. Returns whether Sinhala can be offered.
  static Future<bool> _settlePaliVoice(TtsService tts) async {
    final sinhala =
        await tts.hasVoice(TtsPlan.paliVoices['si']!.engineLanguage);
    TtsPlan.paliVoiceKey =
        Prefs.ttsPaliVoice == 'si' && sinhala ? 'si' : _defaultPaliVoice;
    return sinhala;
  }

  static String nameOf(String language) =>
      language == TtsPlan.pali ? 'Pāḷi' : LanguageInstaller.nameOf(language);

  @override
  Widget build(BuildContext context) {
    if (!TtsService.isSupported) return const SizedBox.shrink();
    final reader = context.read<ReaderViewController>();
    // A book that only exists in the old page table has no sentences.
    if (reader.pages.isEmpty || reader.pages.first.sentences == null) {
      return const SizedBox.shrink();
    }
    final tts = context.watch<TtsService>();
    final playingHere = tts.isPlaying && tts.bookUuid == reader.bookUuid;
    final theme = Theme.of(context);

    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(playingHere ? Icons.stop : Icons.play_arrow),
          tooltip: playingHere ? 'Stop reading' : 'Read aloud',
          onPressed: playingHere ? tts.stop : () => _play(context),
        ),
        IconButton(
          icon: const Icon(Icons.record_voice_over_outlined),
          tooltip: 'Read aloud: languages and speed',
          onPressed: () => _showOptions(context),
        ),
      ],
    );
    if (inBar) return buttons;

    return Material(
      elevation: 3,
      shape: const StadiumBorder(),
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.92),
      child: buttons,
    );
  }

  static Future<void> _play(BuildContext context,
      {int? page, String? sentence}) async {
    final reader = context.read<ReaderViewController>();
    final tts = context.read<TtsService>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    await _settlePaliVoice(tts);
    if (!context.mounted) return;
    final voiced = await tts
        .speakable(options(context.read<ShownLanguagesProvider>()));
    if (voiced.isEmpty) {
      messenger?.showSnackBar(const SnackBar(
          content: Text('There is no voice on this device for these '
              'languages. Voices can be added in the system speech '
              'settings.'),
          duration: Duration(seconds: 6)));
      return;
    }
    final note = await reader.readAloud(tts,
        languages: chosen(voiced.toList()),
        speed: Prefs.ttsSpeed,
        page: page,
        sentence: sentence);
    if (note != null) {
      messenger?.showSnackBar(SnackBar(
          content: Text(note), duration: const Duration(seconds: 6)));
    }
  }

  Future<void> _showOptions(BuildContext context) async {
    final shown = context.read<ShownLanguagesProvider>();
    final offered = options(shown);
    final sinhalaVoice = await _settlePaliVoice(context.read<TtsService>());
    if (!context.mounted) return;
    // Only languages this device can speak are offered; the rest are named
    // underneath, so a missing one is explained rather than silently absent.
    final voiced = await context.read<TtsService>().speakable(offered);
    if (!context.mounted) return;
    final all = offered.where(voiced.contains).toList();
    final unvoiced = offered.where((l) => !voiced.contains(l)).toList();
    final before = chosen(all);
    final speedBefore = Prefs.ttsSpeed;
    var selection = {...before};
    var speed = speedBefore;
    // The speed the reading is actually going at, which moves when a live
    // change is applied, so closing the panel does not restart it again.
    var speedApplied = speedBefore;
    var selectionApplied = {...before};
    var paliVoice = TtsPlan.paliVoiceKey;
    var paliVoiceApplied = paliVoice;
    Timer? settle;

    /// Restarts the reading from the sentence being read, so a change is
    /// heard at once rather than when the panel closes.
    Future<void> restartHere() async {
      if (!context.mounted) return;
      final tts = context.read<TtsService>();
      final reader = context.read<ReaderViewController>();
      final position = tts.position.value;
      if (!tts.isPlaying ||
          tts.bookUuid != reader.bookUuid ||
          position == null) {
        return;
      }
      await _play(context, page: position.page, sentence: position.sentence);
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Read aloud',
                    style: Theme.of(sheetContext).textTheme.titleMedium),
                const SizedBox(height: 4),
                // The Pali voice is named only where there is one; on
                // Windows there is no Kannada voice, and the Pali is
                // explained below with the other missing voices.
                Text('Each sentence is read in every language chosen, '
                    'in this order, before the next.'
                    '${all.contains(TtsPlan.pali) ? ' Pāḷi is read by a '
                        '${TtsPlan.paliVoice.name} voice.' : ''}'),
                const SizedBox(height: 12),
                for (final language in all)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(nameOf(language)),
                    value: selection.contains(language),
                    // At least one stays on.
                    onChanged: selection.contains(language) &&
                            selection.length == 1
                        ? null
                        : (on) => setState(() {
                              on
                                  ? selection.add(language)
                                  : selection.remove(language);
                              Prefs.ttsLanguages =
                                  all.where(selection.contains).toList();
                              // Heard straight away, once the switches have
                              // been left alone for a moment.
                              settle?.cancel();
                              settle = Timer(
                                  const Duration(milliseconds: 500), () {
                                selectionApplied = {...selection};
                                speedApplied = speed;
                                restartHere();
                              });
                            }),
                  ),
                // Only where the device has a Sinhala voice: then the Pali
                // can be read the way Sri Lankan listeners hear it.
                if (sinhalaVoice)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Read Pāḷi in Sinhala'),
                    subtitle: Text(
                        'Sinhala script and a Sinhala voice, instead of '
                        '${TtsPlan.paliVoices[_defaultPaliVoice]!.name}'),
                    value: paliVoice == 'si',
                    onChanged: (on) => setState(() {
                      paliVoice = on ? 'si' : _defaultPaliVoice;
                      Prefs.ttsPaliVoice = paliVoice;
                      TtsPlan.paliVoiceKey = paliVoice;
                      settle?.cancel();
                      settle = Timer(const Duration(milliseconds: 500), () {
                        paliVoiceApplied = paliVoice;
                        selectionApplied = {...selection};
                        speedApplied = speed;
                        restartHere();
                      });
                    }),
                  ),
                if (all.isEmpty)
                  const Text('No voice on this device can read these '
                      'languages.'),
                if (unvoiced.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'No voice on this device for '
                      '${unvoiced.map(_voiceName).join(', ')}. '
                      'Voices can be added in the system speech settings.',
                      style: Theme.of(sheetContext).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Speed'),
                    Expanded(
                      child: Slider(
                        value: speed,
                        min: 0.5,
                        max: 2.0,
                        divisions: 6,
                        label: '${speed.toStringAsFixed(2)}×',
                        onChanged: (value) => setState(() {
                          speed = value;
                          Prefs.ttsSpeed = value;
                          // Applied once the slider rests for a moment, not
                          // at every step of a drag, each of which would
                          // restart the sentence.
                          settle?.cancel();
                          settle = Timer(const Duration(milliseconds: 500), () {
                            speedApplied = value;
                            selectionApplied = {...selection};
                            restartHere();
                          });
                        }),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // A change made while reading takes effect from the sentence being read,
    // rather than waiting for the next start. A change already applied live
    // is not applied a second time.
    settle?.cancel();
    if (!context.mounted) return;
    final changed = speed != speedApplied ||
        paliVoice != paliVoiceApplied ||
        selection.length != selectionApplied.length ||
        !selection.containsAll(selectionApplied);
    if (changed) await restartHere();
  }

}
