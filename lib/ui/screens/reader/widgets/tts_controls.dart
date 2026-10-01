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
  const TtsControls({super.key});

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

    return Material(
      elevation: 3,
      shape: const StadiumBorder(),
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.92),
      child: Row(
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
      ),
    );
  }

  static Future<void> _play(BuildContext context,
      {int? page, String? sentence}) async {
    final reader = context.read<ReaderViewController>();
    final tts = context.read<TtsService>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final languages =
        chosen(options(context.read<ShownLanguagesProvider>()));
    final note = await reader.readAloud(tts,
        languages: languages,
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
    final all = options(shown);
    final before = chosen(all);
    final speedBefore = Prefs.ttsSpeed;
    var selection = {...before};
    var speed = speedBefore;

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
                const Text('Each sentence is read in every language chosen, '
                    'in this order, before the next. Pāḷi is read by a '
                    'Kannada voice.'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final language in all)
                      FilterChip(
                        label: Text(nameOf(language)),
                        selected: selection.contains(language),
                        // At least one stays chosen.
                        onSelected: selection.contains(language) &&
                                selection.length == 1
                            ? null
                            : (on) => setState(() {
                                  on
                                      ? selection.add(language)
                                      : selection.remove(language);
                                  Prefs.ttsLanguages = all
                                      .where(selection.contains)
                                      .toList();
                                }),
                      ),
                  ],
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
    // rather than waiting for the next start.
    if (!context.mounted) return;
    final tts = context.read<TtsService>();
    final reader = context.read<ReaderViewController>();
    final position = tts.position.value;
    final changed =
        speed != speedBefore || selection.length != before.length ||
            !selection.containsAll(before);
    if (changed &&
        tts.isPlaying &&
        tts.bookUuid == reader.bookUuid &&
        position != null) {
      await _play(context, page: position.page, sentence: position.sentence);
    }
  }
}
