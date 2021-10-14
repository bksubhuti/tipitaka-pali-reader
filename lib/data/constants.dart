class DatabaseInfo {
  DatabaseInfo._();
  static const int version = 7;
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
    // 'tipitaka_pali_part.aj',
    // 'tipitaka_pali_part.ak',
    // 'tipitaka_pali_part.al',
  ];
}
