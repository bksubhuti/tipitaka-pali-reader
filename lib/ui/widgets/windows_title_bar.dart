import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tipitaka_pali/utils/windows_accent.dart';
import 'package:window_manager/window_manager.dart';

/// A title bar drawn by the app, for Windows only.
///
/// The native caption is asked for and its styles are set, but on recent
/// Windows builds it draws only a barely visible close glyph and no minimize
/// or maximize at all. The buttons still work, so the window can be moved and
/// closed, but a reader cannot see what to click. Drawing them here makes them
/// visible regardless of what the system does with the caption.
///
/// Deliberately plain: the app's own colours, no gradients, no hover
/// animation beyond a quiet background, and close turns red only on hover
/// because that is the one action worth marking.
class WindowsTitleBar extends StatelessWidget {
  final String title;

  const WindowsTitleBar({super.key, this.title = ''});

  /// Only Windows needs this. Other platforms draw their own correctly.
  static bool get isNeeded => Platform.isWindows;

  /// The glyphs Windows itself draws in a caption, from the same icon font.
  ///
  /// A dash, a square and a letter X from a general icon set look close but
  /// never quite right: the proportions and stroke weights differ from the
  /// ones beside them on every other window. These are the actual codepoints
  /// Windows uses, so they match.
  static const _minimiseGlyph = '\uE921'; // ChromeMinimize
  static const _maximiseGlyph = '\uE922'; // ChromeMaximize
  static const _restoreGlyph = '\uE923'; // ChromeRestore
  static const _closeGlyph = '\uE8BB'; // ChromeClose

  /// Segoe Fluent Icons on Windows 11, Segoe MDL2 Assets on Windows 10.
  static const _glyphFont = 'Segoe Fluent Icons';
  static const _glyphFallback = ['Segoe MDL2 Assets'];

  /// The system UI font at the size Windows uses for a caption.
  ///
  /// The app sets a Pali-capable font across its whole theme, which is right
  /// for the text but wrong for window chrome: it makes the title read
  /// smaller and unlike every other window on the desktop. This is chrome,
  /// so it follows the system.
  static TextStyle _titleStyle(Color foreground) => TextStyle(
        fontFamily: 'Segoe UI',
        fontFamilyFallback: const ['Segoe UI Variable', 'Arial'],
        fontSize: 14,
        color: foreground,
        // Without this the text is drawn with the yellow double underline
        // Flutter uses to flag text that has no Material ancestor.
        decoration: TextDecoration.none,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Windows tints title bars with the accent colour only when the user has
    // asked it to; otherwise the bar stays plain and the accent shows in the
    // window border alone.
    final background = WindowsAccent.titleBarColour() ??
        theme.appBarTheme.backgroundColor ??
        theme.colorScheme.surface;
    final foreground = WindowsAccent.foregroundOn(background);

    // Material, so the buttons and title are not drawn as unstyled text. This
    // bar sits above the app's Navigator, where there is no Material to
    // inherit from.
    return Material(
      color: background,
      child: SizedBox(
      // The height Windows gives a caption.
      height: 32,
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    title,
                    style: _titleStyle(foreground),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
          _Button(
              glyph: _minimiseGlyph,
              foreground: foreground,
              onPressed: windowManager.minimize),
          _MaximizeButton(foreground: foreground),
          _Button(
            glyph: _closeGlyph,
            foreground: foreground,
            hoverColor: const Color(0xFFC42B1C),
            hoverForeground: Colors.white,
            onPressed: windowManager.close,
          ),
        ],
      ),
      ),
    );
  }
}

class _MaximizeButton extends StatefulWidget {
  final Color foreground;
  const _MaximizeButton({required this.foreground});

  @override
  State<_MaximizeButton> createState() => _MaximizeButtonState();
}

class _MaximizeButtonState extends State<_MaximizeButton> {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.isMaximized().then((value) {
      if (mounted) setState(() => _maximized = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _Button(
      glyph: _maximized
          ? WindowsTitleBar._restoreGlyph
          : WindowsTitleBar._maximiseGlyph,
      foreground: widget.foreground,
      onPressed: () async {
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
        if (mounted) {
          final value = await windowManager.isMaximized();
          if (mounted) setState(() => _maximized = value);
        }
      },
    );
  }
}

class _Button extends StatefulWidget {
  final String glyph;
  final Color foreground;
  final VoidCallback onPressed;
  final Color? hoverColor;
  final Color? hoverForeground;

  const _Button({
    required this.glyph,
    required this.foreground,
    required this.onPressed,
    this.hoverColor,
    this.hoverForeground,
  });

  @override
  State<_Button> createState() => _ButtonState();
}

class _ButtonState extends State<_Button> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final background = _hovered
        ? (widget.hoverColor ?? widget.foreground.withAlpha(24))
        : Colors.transparent;
    final foreground = _hovered && widget.hoverForeground != null
        ? widget.hoverForeground!
        : widget.foreground;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          // The size Windows gives a caption button.
          width: 46,
          height: 32,
          color: background,
          alignment: Alignment.center,
          child: Text(
            widget.glyph,
            style: TextStyle(
              fontFamily: WindowsTitleBar._glyphFont,
              fontFamilyFallback: WindowsTitleBar._glyphFallback,
              fontSize: 10,
              color: foreground,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}
