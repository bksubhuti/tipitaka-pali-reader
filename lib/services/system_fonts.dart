import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:tipitaka_pali/utils/pali_script.dart';
import 'package:tipitaka_pali/utils/pali_script_converter.dart';

/// A font family installed on the device, the files it is in, and which of
/// the letters asked about ([SystemFonts.wanted]) it has.
class SystemFont {
  const SystemFont(this.family, this.files, this.letters);
  final String family;
  final List<String> files;
  final Set<int> letters;

  bool hasAll(Iterable<int> codes) => codes.every(letters.contains);
}

/// The fonts installed on the device, for the reader to choose from, and
/// loading the one chosen.
///
/// Flutter has no list of the system's fonts, so the font folders are read
/// and each file's own name for itself taken from it, with the letters it
/// has. A font is offered for a script only if it has every letter Pāḷi
/// needs in that script: the missing ones would come from another font,
/// and the text would look patched together.
///
/// A chosen font is loaded from its files rather than asked for by name.
/// On a computer the name alone would mostly do, but on Android it does
/// not, and loading it works the same everywhere.
class SystemFonts {
  SystemFonts._();

  /// The letters roman Pāḷi needs beyond plain a to z.
  static const List<int> paliLetters = [
    0x0101, 0x012B, 0x016B, // ā ī ū
    0x1E43, 0x1E45, 0x00F1, // ṃ ṅ ñ
    0x1E6D, 0x1E0D, 0x1E47, 0x1E37, // ṭ ḍ ṇ ḷ
  ];

  /// Pāḷi with every letter, vowel sign and nasal in it, written out in a
  /// script to find the letters a font needs for Pāḷi in that script.
  static const _paliSample = 'a ā i ī u ū e o ka kā ki kī ku kū ke ko kaṃ '
      'kha ga gha ṅa ca cha ja jha ña ṭa ṭha ḍa ḍha ṇa ta tha da dha na '
      'pa pha ba bha ma ya ra la va sa ha ḷa kka kya kra kva tta ddha ñca '
      '0 1 2 3 4 5 6 7 8 9';

  /// The letters Pāḷi needs written in [script].
  static Set<int> lettersFor(Script script) {
    if (script == Script.roman) return {...paliLetters};
    final text = PaliScript.getScriptOf(script: script, romanText: _paliSample);
    return {
      for (final rune in text.runes)
        if (rune > 0x7F && rune != 0x200C && rune != 0x200D) rune
    };
  }

  /// A few words of each language the app's menus or translations are in,
  /// for the letters a font for that language needs.
  static const Map<String, String> _languageSamples = {
    'my': 'မြန်မာဘာသာ',
    'si': 'සිංහල භාෂාව',
    'hi': 'हिन्दी भाषा',
    'lo': 'ພາສາລາວ',
    'th': 'ภาษาไทย',
    'km': 'ភាសាខ្មែរ',
    'zh': '中文设置',
    'bn': 'বাংলা ভাষা',
    'ccp': '𑄌𑄋𑄴𑄟𑄳𑄦',
    'ru': 'Русский язык',
    'vi': 'Tiếng Việt',
    'ja': '日本語の設定',
    'ta': 'தமிழ் மொழி',
    'pt': 'Português, tradução',
    'de': 'Deutsch, Übersetzung',
  };

  /// A few words in [language], to show a font with.
  static String sampleFor(String language) =>
      _languageSamples[language] ?? 'Thus have I heard.';

  /// The letters the menus need in the language [locale].
  ///
  /// A language written in Roman letters also needs the Pāḷi ones: its
  /// translations are full of Pāḷi names and terms, and its menus of book
  /// names.
  static Set<int> lettersForLanguage(String locale) {
    final sample = _languageSamples[locale] ?? 'abcdefghijklmnopqrstuvwxyz';
    final letters = {
      for (final rune in sample.runes)
        if (rune != 0x20 && rune != 0x2C) rune
    };
    if (letters.every((rune) => rune < 0x0250)) letters.addAll(paliLetters);
    return letters;
  }

  /// Every letter asked about, of every script and language.
  static Set<int> get wanted => {
        for (final script in Script.values) ...lettersFor(script),
        for (final locale in _languageSamples.keys)
          ...lettersForLanguage(locale),
        ...lettersForLanguage('en'),
      };

  static Future<List<SystemFont>>? _found;

  /// The fonts found, by family name. Looked for once, away from the UI.
  static Future<List<SystemFont>> list() {
    final folders = _fontFolders();
    final codes = wanted.toList()..sort();
    return _found ??= Isolate.run(() => _scan(folders, codes));
  }

  static final Set<String> _loaded = {};

  /// Makes [family] usable as a fontFamily, from its [files].
  static Future<void> load(String family, List<String> files) async {
    if (_loaded.contains(family)) return;
    final loader = FontLoader(family);
    var any = false;
    for (final path in files) {
      final file = File(path);
      if (!file.existsSync()) continue;
      loader.addFont(
          file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
      any = true;
    }
    if (!any) return;
    await loader.load();
    _loaded.add(family);
  }

  static List<String> _fontFolders() {
    final home = Platform.environment['HOME'] ?? '';
    if (Platform.isMacOS || Platform.isIOS) {
      return [
        '/System/Library/Fonts',
        '/Library/Fonts',
        if (home.isNotEmpty) '$home/Library/Fonts',
      ];
    }
    if (Platform.isWindows) {
      final windows = Platform.environment['WINDIR'] ?? r'C:\Windows';
      final local = Platform.environment['LOCALAPPDATA'];
      return [
        '$windows\\Fonts',
        if (local != null) '$local\\Microsoft\\Windows\\Fonts',
      ];
    }
    if (Platform.isLinux) {
      return [
        '/usr/share/fonts',
        '/usr/local/share/fonts',
        // The computer's own fonts, from inside a Flatpak.
        '/run/host/fonts',
        '/run/host/user-fonts',
        if (home.isNotEmpty) '$home/.fonts',
        if (home.isNotEmpty) '$home/.local/share/fonts',
      ];
    }
    if (Platform.isAndroid) {
      return ['/system/fonts', '/product/fonts'];
    }
    return [];
  }

  static List<SystemFont> _scan(List<String> folders, List<int> codes) {
    final files = <String, List<String>>{};
    final letters = <String, Set<int>>{};
    for (final folder in folders) {
      final dir = Directory(folder);
      if (!dir.existsSync()) continue;
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(recursive: true, followLinks: false);
      } catch (_) {
        continue; // not readable, as some are from inside a sandbox
      }
      for (final entry in entries) {
        if (entry is! File) continue;
        final name = entry.path.toLowerCase();
        if (!name.endsWith('.ttf') &&
            !name.endsWith('.otf') &&
            !name.endsWith('.ttc')) {
          continue;
        }
        (String, Set<int>)? read;
        try {
          read = _read(entry, codes);
        } catch (_) {
          read = null; // damaged, or not what its name says
        }
        if (read == null) continue;
        final (family, has) = read;
        // 'System Font' is already offered, as the platform's own.
        if (family.startsWith('.') || family == 'System Font') continue;
        files.putIfAbsent(family, () => []).add(entry.path);
        letters.putIfAbsent(family, () => {}).addAll(has);
      }
    }
    final fonts = files.entries
        .map((e) => SystemFont(e.key, e.value..sort(), letters[e.key]!))
        .toList()
      ..sort((a, b) => a.family.toLowerCase().compareTo(b.family.toLowerCase()));
    return fonts;
  }

  /// The family name of the font in [file], and which of [codes] it has.
  /// Of a collection (.ttc), the first font, the one that loads from it.
  static (String, Set<int>)? _read(File file, List<int> codes) {
    final raf = file.openSync();
    try {
      ByteData read(int offset, int length) {
        raf.setPositionSync(offset);
        final bytes = raf.readSync(length);
        if (bytes.length < length) throw const FormatException('short');
        return ByteData.sublistView(bytes);
      }

      var start = 0;
      final head = read(0, 12);
      if (head.getUint32(0) == 0x74746366) {
        // 'ttcf'
        start = read(12, 4).getUint32(0);
      }
      final numTables = read(start, 6).getUint16(4);
      final records = read(start + 12, numTables * 16);
      int? nameAt, nameLength, cmapAt, cmapLength;
      for (var i = 0; i < numTables; i++) {
        final tag = records.getUint32(i * 16);
        final offset = records.getUint32(i * 16 + 8);
        final length = records.getUint32(i * 16 + 12);
        if (tag == 0x6E616D65) {
          // 'name'
          nameAt = offset;
          nameLength = length;
        } else if (tag == 0x636D6170) {
          // 'cmap'
          cmapAt = offset;
          cmapLength = length;
        }
      }
      if (nameAt == null || cmapAt == null) return null;
      if (cmapLength! > 4 << 20 || nameLength! > 1 << 20) return null;
      final family = _familyName(read(nameAt, nameLength));
      if (family == null) return null;
      return (family, _has(read(cmapAt, cmapLength), codes));
    } finally {
      raf.closeSync();
    }
  }

  /// The typographic family (name 16) if given, which keeps a family's
  /// weights together, else the family (name 1). English, from the Windows
  /// names when there are some, as those are Unicode.
  static String? _familyName(ByteData table) {
    final count = table.getUint16(2);
    final strings = table.getUint16(4);
    String? best;
    var bestScore = -1;
    for (var i = 0; i < count; i++) {
      final at = 6 + i * 12;
      final platform = table.getUint16(at);
      final encoding = table.getUint16(at + 2);
      final language = table.getUint16(at + 4);
      final nameId = table.getUint16(at + 6);
      final length = table.getUint16(at + 8);
      final offset = table.getUint16(at + 10);
      if (nameId != 1 && nameId != 16) continue;
      int score;
      String text;
      final from = strings + offset;
      if (from + length > table.lengthInBytes) continue;
      if (platform == 3 || platform == 0) {
        final units = <int>[
          for (var j = 0; j + 1 < length; j += 2) table.getUint16(from + j)
        ];
        text = String.fromCharCodes(units);
        score = platform == 3 && language == 0x409 ? 4 : 2;
      } else if (platform == 1 && encoding == 0) {
        text = String.fromCharCodes(
            [for (var j = 0; j < length; j++) table.getUint8(from + j)]);
        score = 1;
      } else {
        continue;
      }
      if (nameId == 16) score += 8;
      text = text.trim();
      if (text.isNotEmpty && score > bestScore) {
        best = text;
        bestScore = score;
      }
    }
    return best;
  }

  /// Those of [codes] the cmap [table] maps to a glyph.
  static Set<int> _has(ByteData table, List<int> codes) {
    final count = table.getUint16(2);
    int? format4, format12;
    for (var i = 0; i < count; i++) {
      final at = 4 + i * 8;
      final platform = table.getUint16(at);
      final encoding = table.getUint16(at + 2);
      final offset = table.getUint32(at + 4);
      if (offset + 4 > table.lengthInBytes) continue;
      final unicode =
          platform == 0 || (platform == 3 && (encoding == 1 || encoding == 10));
      if (!unicode) continue;
      final format = table.getUint16(offset);
      if (format == 12) format12 ??= offset;
      if (format == 4) format4 ??= offset;
    }
    if (format12 != null) {
      return {for (final c in codes) if (_inFormat12(table, format12, c)) c};
    }
    if (format4 != null) {
      return {
        for (final c in codes)
          if (c <= 0xFFFF && _inFormat4(table, format4, c)) c
      };
    }
    return const {};
  }

  static bool _inFormat12(ByteData t, int at, int code) {
    final groups = t.getUint32(at + 12);
    for (var i = 0; i < groups; i++) {
      final g = at + 16 + i * 12;
      final first = t.getUint32(g);
      final last = t.getUint32(g + 4);
      if (code < first) return false; // groups are in order
      if (code <= last) return t.getUint32(g + 8) + code - first != 0;
    }
    return false;
  }

  static bool _inFormat4(ByteData t, int at, int code) {
    final segments = t.getUint16(at + 6) ~/ 2;
    final ends = at + 14;
    final starts = ends + segments * 2 + 2;
    final deltas = starts + segments * 2;
    final rangeOffsets = deltas + segments * 2;
    for (var i = 0; i < segments; i++) {
      if (t.getUint16(ends + i * 2) < code) continue;
      final first = t.getUint16(starts + i * 2);
      if (code < first) return false;
      final delta = t.getUint16(deltas + i * 2);
      final rangeAt = rangeOffsets + i * 2;
      final rangeOffset = t.getUint16(rangeAt);
      if (rangeOffset == 0) return (code + delta) & 0xFFFF != 0;
      final glyphAt = rangeAt + rangeOffset + (code - first) * 2;
      if (glyphAt + 2 > t.lengthInBytes) return false;
      return t.getUint16(glyphAt) != 0;
    }
    return false;
  }
}
