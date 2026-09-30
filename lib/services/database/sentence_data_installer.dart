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
  /// A file already there is replaced only when the shipped one is a
  /// different size, which is how a new release of the sentence data is
  /// noticed. An older copy left in place would be keyed against sentences
  /// that have moved.
  ///
  /// This runs before the database is opened, and must: these files are
  /// attached to the connection, and Windows will not delete a file another
  /// handle still holds. Setup cannot do it — by the time it runs the reader
  /// has already opened the database behind it.
  ///
  /// Quiet about failure, like the attach that follows it: a build without
  /// the assets leaves the reader on pages rather than refusing to open.
  static Future<void> install(
    String dbDir, {
    void Function(String message)? onProgress,
  }) async {
    await _join(dbDir, AssetsFile.partsOfEpitaka, AssetsFile.epitakaFileName,
        'Copying sentence data', onProgress);
    await _join(dbDir, AssetsFile.partsOfExtension,
        AssetsFile.extensionFileName, 'Copying page markers', onProgress);
  }

  /// Which release of the shipped data is on disk, recorded beside it.
  ///
  /// Measuring the assets instead would mean loading a quarter of a gigabyte
  /// into memory at every start just to compare a number. Shipping different
  /// sentence data means raising the database version anyway — the Pali file
  /// is copied on that too — so the version is what is recorded.
  static File _stamp(String dbDir, String fileName) =>
      File(join(dbDir, '$fileName.version'));

  /// Whether both files are present, joined or not.
  static bool isInstalled(String dbDir) =>
      File(join(dbDir, AssetsFile.epitakaFileName)).existsSync() &&
      File(join(dbDir, AssetsFile.extensionFileName)).existsSync();

  static Future<void> _join(
    String dbDir,
    List<String> parts,
    String fileName,
    String label,
    void Function(String message)? onProgress,
  ) async {
    final file = File(join(dbDir, fileName));
    final stamp = _stamp(dbDir, fileName);
    final wanted = '${DatabaseInfo.version}';
    if (file.existsSync()) {
      final have = stamp.existsSync() ? stamp.readAsStringSync().trim() : '';
      if (have == wanted) return;
      onProgress?.call('$label: a newer copy is shipped');
      try {
        await file.delete();
      } catch (e) {
        // Held open by something. Leave what is there; the next start, before
        // anything opens it, will replace it.
        onProgress?.call('$label could not be replaced yet: $e');
        return;
      }
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
      try {
        await stamp.writeAsString(wanted);
      } catch (_) {
        // Without it the file is rewritten once more at the next start, which
        // is wasteful but not wrong.
      }
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
