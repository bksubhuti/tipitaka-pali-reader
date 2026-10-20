import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tipitaka_pali/services/system_fonts.dart';

/// Flutter loads only the first face of a font collection (.ttc). With
/// Palatino, from Palatino.ttc, that left no bold face, and bold was drawn by
/// thickening the regular letters, faintly. Each face is now loaded on its own.
void main() {
  // A collection of two one-table faces sharing nothing: 'aaaa' and 'bbbb'.
  Uint8List collection() {
    final b = BytesBuilder();
    void u32(int v) =>
        b.add([v >> 24 & 255, v >> 16 & 255, v >> 8 & 255, v & 255]);
    void u16(int v) => b.add([v >> 8 & 255, v & 255]);
    // ttc header: tag, version, two fonts at 20 and 48
    u32(0x74746366);
    u32(0x00010000);
    u32(2);
    u32(20);
    u32(48);
    for (final (tag, dataAt) in [(0x61616161, 76), (0x62626262, 80)]) {
      u32(0x00010000); // sfnt version
      u16(1); // one table
      u16(16);
      u16(0);
      u16(0);
      u32(tag);
      u32(0); // checksum
      u32(dataAt);
      u32(4);
    }
    b.add('AAAA'.codeUnits);
    b.add('BBBB'.codeUnits);
    return b.toBytes();
  }

  test('each face of a collection comes out as a font of its own', () {
    final faces = SystemFonts.facesOf(collection());
    expect(faces.length, 2);
    for (final (i, data) in [(0, 'AAAA'), (1, 'BBBB')].indexed) {
      final face = faces[i];
      expect(face.getUint32(0), 0x00010000);
      expect(face.getUint16(4), 1);
      final at = face.getUint32(12 + 8);
      final length = face.getUint32(12 + 12);
      expect(
          String.fromCharCodes(face.buffer.asUint8List(at, length)), data.$2);
    }
  });

  test('a single font is left as it is', () {
    final font = Uint8List.fromList([0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
    expect(SystemFonts.facesOf(font).single.lengthInBytes, 12);
  });
}
