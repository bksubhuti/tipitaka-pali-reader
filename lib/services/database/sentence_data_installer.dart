import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:tipitaka_pali/data/constants.dart';

/// Puts the sentence databases beside the Pali one, joining their asset parts.
///
/// This runs on every start rather than at first setup only. A reader who
/// already had TPR installed never goes through setup again: the database is
/// there and its version has not moved, so nothing is copied. If the sentence
/// data arrived only that way it would never arrive at all for them, and the
/// app would fall back to the pages table without saying why.
///
/// Joining is skipped once the file exists, so after the first start this
/// costs two `exists` checks.
class SentenceDataInstaller {
  SentenceDataInstaller._();

  /// Joins both sets of parts into [dbDir] if they are not already there.
  ///
  /// [replace] rewrites files that exist. Setup passes it, because a version
  /// change means the shipped data itself moved and an older copy left in
  /// place would be keyed against sentences that are no longer there. Ordinary
  /// starts do not, so nothing is rewritten under a reader who has it already.
  ///
  /// Quiet about failure, like the attach that follows it: a build without
  /// the assets leaves the reader on pages rather than refusing to open.
  static Future<void> install(
    String dbDir, {
    bool replace = false,
    void Function(String message)? onProgress,
  }) async {
    await _join(dbDir, AssetsFile.partsOfEpitaka, AssetsFile.epitakaFileName,
        'Copying sentence data', replace, onProgress);
    await _join(dbDir, AssetsFile.partsOfExtension,
        AssetsFile.extensionFileName, 'Copying page markers', replace,
        onProgress);
  }

  /// Whether both files are present, joined or not.
  static bool isInstalled(String dbDir) =>
      File(join(dbDir, AssetsFile.epitakaFileName)).existsSync() &&
      File(join(dbDir, AssetsFile.extensionFileName)).existsSync();

  static Future<void> _join(
    String dbDir,
    List<String> parts,
    String fileName,
    String label,
    bool replace,
    void Function(String message)? onProgress,
  ) async {
    final file = File(join(dbDir, fileName));
    if (file.existsSync()) {
      if (!replace) return;
      await file.delete();
    }

    // A part-written file is worse than none: it attaches and then answers
    // nothing. Write to a temporary name and move it into place at the end.
    final partial = File(join(dbDir, '$fileName.part'));
    try {
      if (partial.existsSync()) await partial.delete();
      var done = 0;
      for (final part in parts) {
        final bytes = await rootBundle.load(
            '${AssetsFile.baseAssetsFolderPath}/${AssetsFile.databaseFolderPath}/$part');
        await partial.writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          mode: FileMode.append,
        );
        done++;
        onProgress?.call('$label ${((done / parts.length) * 100).round()}%');
      }
      await partial.rename(file.path);
    } catch (e) {
      if (partial.existsSync()) {
        try {
          await partial.delete();
        } catch (_) {}
      }
      onProgress?.call('$label could not be completed: $e');
    }
  }
}
