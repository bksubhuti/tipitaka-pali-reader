import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:tipitaka_pali/services/database/database_helper.dart';
import 'package:tipitaka_pali/services/repositories/page_content_repo.dart';

class TtsHelpers {
  static Future<bool> hasEnglish() async {
    try {
      // Check for English translation in mula_ma_01 page 2
      final dbProvider = DatabaseHelper();
      final pageContentRepo = PageContentDatabaseRepository(dbProvider);
      final pageContent = await pageContentRepo.getPageByBookAndPage('mula_ma_01', 2);
      
      if (pageContent != null) {
        return pageContent.content.contains('<span class="translation_text english_text">');
      }
    } catch (e) {
      debugPrint('Error checking hasEnglish: $e');
    }
    return false;
  }

  static Future<bool> isTtsSupported() async {
    if (kIsWeb) return false;
    
    if (!(Platform.isAndroid || Platform.isIOS || Platform.isWindows || Platform.isMacOS)) {
      return false;
    }
    
    return await hasEnglish();
  }
}
