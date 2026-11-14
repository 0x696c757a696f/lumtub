import 'dart:math';
import 'dart:ui' show Size;

import 'player_settings.dart';
import 'subtitle_cues.dart';

/// Where mpv's secondary subtitle goes while libmpv (libass) draws
/// subtitles: just above the main one, however many lines that has.
///
/// mpv lays text subtitles out on a 720-unit-tall canvas, with the font at
/// 38 units times `sub-scale` and 25 units of margin left and right; libass
/// puts lines one font size apart (measured on the libmpv Lumtub ships for
/// Windows: 43 px apart at 808 px, 38/720 of the height). `sub-pos` and
/// `secondary-sub-pos` give where a subtitle's bottom edge sits as a share
/// of the height above `sub-margin-y`, not of the whole height. The main
/// subtitle's lines are counted here the way libass wraps them, rounding
/// up, so the secondary one sits just above it.
class LibassLayout {
  static const _canvas = 720.0;
  static const _font = 38.0;
  static const _margin = 25.0;

  /// `sub-margin-y`, set by Lumtub: mpv's default changed between versions.
  static const marginY = 34;

  /// The gap between the two subtitles, in percent of the picture.
  static const _gap = 1.0;

  /// `secondary-sub-pos` for a main subtitle showing [main]. [fontSize] is
  /// `sub-font-size` (a line's height), [em] the width a letter is measured
  /// in, [margin] `sub-margin-y` and [gap] the room between the two, all in
  /// mpv's units of a 720-tall picture. mpv places a plain subtitle in the
  /// room above the margin, but an ASS one ([whole], Lumtub's styled second
  /// subtitle) in the whole height.
  static double secondaryPosition(String main, {required int position, required double scale, double aspect = 16 / 9, double fontSize = _font, double? em, int margin = marginY, double? gap, bool whole = false}) {
    final lines = max(1, lineCount(main, scale: scale, aspect: aspect, em: em ?? fontSize));
    final room = _canvas - margin;
    // The main subtitle's top, then the second one's bottom just above it.
    final bottom = room * position / 100 - lines * fontSize * scale - (gap ?? _gap * _canvas / 100);
    return (bottom / (whole ? _canvas : room) * 1000).floorToDouble().clamp(0, 1000) / 10;
  }

  /// How many lines libass draws [text] on, wrapping at the canvas width.
  static int lineCount(String text, {required double scale, double aspect = 16 / 9, double em = _font}) {
    final room = (_canvas * max(aspect, 0.5) - 2 * _margin) / (em * scale);
    var lines = 0;
    for (final line in text.replaceAll(_invisible, '').trim().split('\n')) {
      final width = _ems(line.trim());
      if (width == 0) continue;
      lines += max(1, (width / room).ceil());
    }
    return lines;
  }

  /// A rough width in ems: full-width characters (CJK, kana, Hangul) one
  /// each, Latin letters by their usual widths in a sans-serif font (i, l
  /// and punctuation narrow, m and w wide, capitals wider than small
  /// letters), anything else a little over half.
  static double _ems(String line) {
    var width = 0.0;
    for (final rune in line.runes) {
      width += _wide(rune) ? 1.0 : _latin(rune);
    }
    return width;
  }

  /// Zero-width and direction marks, which take no room on screen.
  static final _invisible = RegExp('[\u00AD\u200B-\u200F\u202A-\u202E\u2060-\u2064\uFEFF]');

  static const _narrow = " .,:;'!|il\u0131jI[]()";
  static const _thin = 'ftr-"/';
  static const _broad = 'mwMW';

  static double _latin(int rune) {
    final c = String.fromCharCode(rune);
    if (_narrow.contains(c)) return 0.26;
    if (_thin.contains(c)) return 0.33;
    if (_broad.contains(c)) return 0.85;
    if (rune >= 0x41 && rune <= 0x5A) return 0.66;
    if ((rune >= 0x61 && rune <= 0x7A) || (rune >= 0x30 && rune <= 0x39) || (rune >= 0xC0 && rune <= 0x24F)) return 0.54;
    return 0.58;
  }

  static bool _wide(int rune) =>
      (rune >= 0x1100 && rune <= 0x115F) ||
      (rune >= 0x2E80 && rune <= 0xA4CF) ||
      (rune >= 0xAC00 && rune <= 0xD7A3) ||
      (rune >= 0xF900 && rune <= 0xFAFF) ||
      (rune >= 0xFE30 && rune <= 0xFE4F) ||
      (rune >= 0xFF00 && rune <= 0xFF60) ||
      (rune >= 0xFFE0 && rune <= 0xFFE6) ||
      (rune >= 0x1F300 && rune <= 0x1FAFF) ||
      (rune >= 0x20000 && rune <= 0x3FFFD);
}

/// How mpv draws subtitles so that they look as the Flutter subtitle view
/// draws them in the same player: the same letter size, the same room
/// below, the same outline and gap between the two. The view sizes text
/// in logical pixels of the player ([view]); mpv in units of a 720-tall
/// picture, the video fitted in that player.
class LibassLook {
  const LibassLook({required this.em, required this.margin, required this.border, required this.gap});

  /// A letter's size (an em) at subtitle size 1, in mpv's units.
  final double em;

  /// `sub-margin-y`: the room under the main subtitle.
  final int margin;

  /// `sub-border-size`.
  final double border;

  /// The room between the two subtitles.
  final double gap;

  /// For a player [view] showing a picture of [aspect], whose subtitle view
  /// scales text by [textScale] and its padding by [paddingScale].
  /// [position] is the 字幕位置 setting, [border] the 描边 one.
  factory LibassLook.of({required Size view, required double aspect, required double textScale, double paddingScale = 1, required int position, required double border}) {
    final picture = view.isEmpty ? 720.0 : min(view.height, view.width / max(aspect, 0.1));
    final unit = LibassLayout._canvas / max(picture, 1);
    // The view's bottom padding, less the band below the picture that mpv
    // cannot draw in.
    final below = (24 + (100 - position) * 4.0) * paddingScale - max(0.0, (view.height - picture) / 2);
    return LibassLook(
      em: 32 * textScale * unit,
      margin: (max(0.0, below) * unit).round(),
      // Four shadows border / 2 out and blurred as far read as an outline
      // about 0.7 of the setting thick.
      border: 0.7 * border * unit,
      gap: 6 * textScale * unit,
    );
  }

  /// A video filling a 16:9 player 720 tall, before the player's own size
  /// is known. [byHeight] sizes text as Android does, [caption] times 5.33%
  /// of the player's height.
  static LibassLook standard({required int position, required double border, bool byHeight = false, double caption = 1}) => LibassLook.of(
        view: const Size(1280, 720),
        aspect: 16 / 9,
        textScale: byHeight ? max(12.0, 720 * 0.0533 * caption) / 32 : sqrt(1280 * 720 / (1920 * 1080)),
        position: position,
        border: border,
      );

  /// libass sizes a font by its whole line (ascent and descent, as Windows
  /// does), the Flutter view by its em: how many ems a line of [font] is.
  /// Read from the fonts' OS/2 tables; others are taken as 1.3.
  static double lineEms(String font) => switch (font.toLowerCase()) {
        'microsoft yahei' || 'microsoft yahei ui' || '微软雅黑' => 1.32,
        'noto sans cjk sc' || 'noto sans cjk tc' || 'noto sans cjk jp' || 'noto sans cjk kr' || 'noto sans sc' || 'source han sans sc' || 'source han sans' => 1.448,
        'noto serif cjk sc' || 'noto serif cjk tc' || 'source han serif sc' => 1.438,
        'pingfang sc' || 'pingfang tc' || 'pingfang hk' => 1.4,
        'simhei' || 'simsun' || 'nsimsun' || 'kaiti' || 'fangsong' => 1.0,
        'segoe ui' => 1.33,
        'arial' || 'liberation sans' || 'helvetica' => 1.117,
        'inter' => 1.21,
        'roboto' => 1.172,
        'dejavu sans' || 'dejavu serif' => 1.164,
        _ => 1.3,
      };

  /// `sub-font-size` for [font]: a line as tall as the view's em in it.
  double fontSize(String font) => em * lineEms(font);
}

/// The second subtitle as an ASS file in its own font, color, opacity,
/// size, outline and background, which mpv cannot set apart from the first
/// subtitle's. Its letters are [secondEm] units at secondary-sub-scale 1;
/// [outline] is the outline's width for a letter one unit wide.
String secondAss(List<SubtitleCue> cues, PlayerSettings settings, {required double outline}) {
  final font = settings.secondaryFont.isEmpty ? 'sans-serif' : PlayerSettings.fontForThisSystem(settings.secondaryFont);
  final size = secondEm * settings.secondaryScale * LibassLook.lineEms(font);
  String colour(int rgb, double opacity) {
    final alpha = (255 * (1 - opacity.clamp(0, 1))).round();
    final r = (rgb >> 16) & 0xFF, g = (rgb >> 8) & 0xFF, b = rgb & 0xFF;
    String hex(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '&H${hex(alpha)}${hex(b)}${hex(g)}${hex(r)}';
  }

  String stamp(Duration d) {
    final cs = (d.inMilliseconds / 10).round();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${cs ~/ 360000}:${two(cs ~/ 6000 % 60)}:${two(cs ~/ 100 % 60)}.${two(cs % 100)}';
  }

  final opacity = settings.secondaryOpacity;
  final box = settings.subtitleBackground;
  final edge = box ? colour(0, 0.67 * opacity) : colour(0, opacity);
  final width = box ? secondEm * 0.12 : outline * secondEm;
  final out = StringBuffer()
    ..writeln('[Script Info]')
    ..writeln('ScriptType: v4.00+')
    ..writeln('PlayResX: 1280')
    ..writeln('PlayResY: 720')
    ..writeln('ScaledBorderAndShadow: yes')
    ..writeln('WrapStyle: 0')
    ..writeln()
    ..writeln('[V4+ Styles]')
    ..writeln('Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding')
    ..writeln('Style: Default,${font.replaceAll(',', ' ')},${size.toStringAsFixed(2)},${colour(settings.secondaryColor, opacity)},&H000000FF,$edge,$edge,${settings.subtitleBold ? -1 : 0},0,0,0,100,100,0,0,${box ? 3 : 1},${width.toStringAsFixed(2)},0,2,25,25,0,1')
    ..writeln()
    ..writeln('[Events]')
    ..writeln('Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text');
  for (final cue in cues) {
    // Braces would open override tags; line breaks are ASS's own.
    final text = cue.text.replaceAll('{', '(').replaceAll('}', ')').replaceAll(RegExp(r'\r?\n'), r'\N');
    out.writeln('Dialogue: 0,${stamp(cue.start)},${stamp(cue.end)},Default,,0,0,0,,$text');
  }
  return out.toString();
}

/// A letter of [secondAss] at secondary-sub-scale 1, in mpv's units.
const secondEm = 20.0;
