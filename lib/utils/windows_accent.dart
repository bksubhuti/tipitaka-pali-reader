import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';

/// The colour Windows would paint a title bar.
///
/// Windows has two separate settings here and they are easy to confuse. The
/// accent colour is always set; whether title bars are *tinted* with it is the
/// "Show accent colour on title bars and window borders" switch. With that
/// switch off, Windows paints title bars plain and uses the accent only for
/// the thin window border, which is why a window can look faintly coloured
/// around the edge while its bar stays white.
///
/// So this reports the accent only when Windows would actually use it for the
/// bar. Following the accent unconditionally would make the app the only
/// coloured title bar on the desktop.
class WindowsAccent {
  WindowsAccent._();

  static Color? _cached;
  static bool _read = false;

  /// The title bar colour Windows would use, or null to leave it to the theme.
  static Color? titleBarColour() {
    if (!Platform.isWindows) return null;
    if (_read) return _cached;
    _read = true;
    try {
      if (!_accentOnTitleBars()) return _cached = null;
      _cached = _colorizationColour();
    } catch (_) {
      _cached = null;
    }
    return _cached;
  }

  /// Whether "show accent colour on title bars" is on.
  static bool _accentOnTitleBars() {
    final advapi = DynamicLibrary.open('advapi32.dll');
    final regGetValue = advapi.lookupFunction<
        Int32 Function(IntPtr, Pointer<Uint16>, Pointer<Uint16>, Uint32,
            Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint32>),
        int Function(int, Pointer<Uint16>, Pointer<Uint16>, int,
            Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint32>)>('RegGetValueW');

    final key = _utf16(r'SOFTWARE\Microsoft\Windows\DWM');
    final name = _utf16('ColorPrevalence');
    final value = calloc<Uint32>();
    final size = calloc<Uint32>()..value = 4;
    try {
      // HKEY_CURRENT_USER, RRF_RT_REG_DWORD
      final result = regGetValue(
          0x80000001, key, name, 0x00000018, nullptr, value, size);
      return result == 0 && value.value == 1;
    } finally {
      _free(key.cast());
      _free(name.cast());
      _free(value.cast());
      _free(size.cast());
    }
  }

  /// The composition colour, which is what Windows tints the bar with.
  static Color? _colorizationColour() {
    final dwmapi = DynamicLibrary.open('dwmapi.dll');
    final getColour = dwmapi.lookupFunction<
        Int32 Function(Pointer<Uint32>, Pointer<Int32>),
        int Function(Pointer<Uint32>, Pointer<Int32>)>(
        'DwmGetColorizationColor');

    final colour = calloc<Uint32>();
    final opaque = calloc<Int32>();
    try {
      if (getColour(colour, opaque) != 0) return null;
      // ARGB, but the alpha is a blend hint rather than transparency.
      return Color(0xFF000000 | (colour.value & 0x00FFFFFF));
    } finally {
      _free(colour.cast());
      _free(opaque.cast());
    }
  }

  /// Black or white, whichever can be read on [background].
  static Color foregroundOn(Color background) =>
      background.computeLuminance() > 0.5 ? Colors.black : Colors.white;

  // Minimal allocation helpers, so this file needs no extra package.
  static final _malloc = DynamicLibrary.process().lookupFunction<
      Pointer<Void> Function(IntPtr), Pointer<Void> Function(int)>('malloc');
  static final _freeFn = DynamicLibrary.process().lookupFunction<
      Void Function(Pointer<Void>), void Function(Pointer<Void>)>('free');

  static Pointer<T> calloc<T extends NativeType>() {
    final p = _malloc(8).cast<Uint32>();
    p.value = 0;
    return p.cast<T>();
  }

  static void _free(Pointer<Void> p) => _freeFn(p);

  static Pointer<Uint16> _utf16(String value) {
    final units = value.codeUnits;
    final p = _malloc((units.length + 1) * 2).cast<Uint16>();
    for (var i = 0; i < units.length; i++) {
      p[i] = units[i];
    }
    p[units.length] = 0;
    return p;
  }
}
