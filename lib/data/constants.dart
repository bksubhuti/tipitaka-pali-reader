const String highlightTagName = 'highlight';

class DatabaseInfo {
  DatabaseInfo._();
  static const int version = 58;
  static const String fileName = 'tipitaka_pali.db';
}

class AssetsFile {
  AssetsFile._();
  static const String baseAssetsFolderPath = 'assets';
  static const String databaseFolderPath = 'database';
  static const List<String> partsOfDatabase = <String>[
    'tipitaka_pali_part.aa',
    'tipitaka_pali_part.ab',
    'tipitaka_pali_part.ac',
    'tipitaka_pali_part.ad',
    'tipitaka_pali_part.ae',
    'tipitaka_pali_part.af',
    'tipitaka_pali_part.ag',
    'tipitaka_pali_part.ah',
    'tipitaka_pali_part.ai',
    'tipitaka_pali_part.aj',
    'tipitaka_pali_part.ak',
    'tipitaka_pali_part.al',
    'tipitaka_pali_part.am',
    'tipitaka_pali_part.an',
  ];

  /// ePitaka's sentences, headings and book links, trimmed to what TPR reads
  /// and split the same way. Built by assets/database/split_epitaka.sh.
  static const List<String> partsOfEpitaka = <String>[
    'epitaka_part.aa',
    'epitaka_part.ab',
    'epitaka_part.ac',
    'epitaka_part.ad',
    'epitaka_part.ae',
    'epitaka_part.af',
  ];

  /// TPR's own additions: page boundaries, page markers and orphan flags,
  /// keyed the way ePitaka keys its sentences.
  static const List<String> partsOfExtension = <String>[
    'tpr_extension_part.aa',
  ];

  /// What each set of parts is called once joined.
  static const String epitakaFileName = 'epitaka.db';
  static const String extensionFileName = 'tpr_extension.db';
}

const double navigationBarWidth = 50;

const String kdartTheme = 'default_dark_theme';
const String kblackTheme = 'black';
const String kGotoID = 'goto';
const int seypia = 0xfffbf0da;
const int maxBooksOpened = 30;
const int maxWordsLookedUp = 50;
