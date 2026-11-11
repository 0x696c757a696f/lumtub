import 'dart:math';

/// Where mpv's secondary subtitle goes while libmpv (libass) draws
/// subtitles: just above the main one, however many lines that has.
///
/// mpv lays text subtitles out on a 720-unit-tall canvas, with the font at
/// 38 units times `sub-scale` and 25 units of margin left and right, and
/// both `sub-pos` and `secondary-sub-pos` give where a subtitle's bottom
/// edge sits, in percent of the height. The main subtitle's lines are
/// counted here the way libass wraps them, rounding up, so the secondary
/// one is never drawn over it.
class LibassLayout {
  static const _canvas = 720.0;
  static const _font = 38.0;
  static const _margin = 25.0;

  /// A line's height, in percent of the canvas at sub-scale 1.
  static const _line = 6.5;

  /// The gap between the two subtitles, in percent.
  static const _gap = 1.5;

  /// `secondary-sub-pos` for a main subtitle showing [main].
  static int secondaryPosition(String main, {required int position, required double scale, double aspect = 16 / 9}) {
    final lines = max(1, lineCount(main, scale: scale, aspect: aspect));
    return (position - lines * _line * scale - _gap).floor().clamp(0, 100);
  }

  /// How many lines libass draws [text] on, wrapping at the canvas width.
  static int lineCount(String text, {required double scale, double aspect = 16 / 9}) {
    final room = (_canvas * max(aspect, 0.5) - 2 * _margin) / (_font * scale);
    var lines = 0;
    for (final line in text.trim().split('\n')) {
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
