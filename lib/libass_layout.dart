import 'dart:collection';
import 'dart:math';

import 'package:flutter/painting.dart';

import 'appearance_settings.dart' show bundledFont;
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
  /// subtitle) in the whole height; that one already holds the main
  /// subtitle's lines (see [secondAss]), so it goes where the main one does.
  static double secondaryPosition(String main, {required int position, required double scale, double aspect = 16 / 9, double fontSize = _font, double? em, int margin = marginY, double? gap, bool whole = false}) {
    final room = _canvas - margin;
    // Lumtub's copy holds the main subtitle too, drawn invisible under the
    // second one: libass itself makes the room for it, in the fonts it
    // really draws with, so the two share one bottom edge.
    if (whole) return (room * position / 100 / _canvas * 1000).floorToDouble().clamp(0, 1000) / 10;
    final lines = max(1, lineCount(main, scale: scale, aspect: aspect, em: em ?? fontSize));
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

  /// The ems of a line in libass's room for [aspect], with letters [em]
  /// units wide at [scale].
  static double roomEms({required double em, required double scale, double aspect = 16 / 9}) => (_canvas * max(aspect, 0.5) - 2 * _margin) / (em * scale);

  /// [text] with line breaks where the Flutter subtitle view wraps it in
  /// [room] ems of [font]. libass breaks lines only at spaces, so Chinese,
  /// Japanese, Thai, Khmer, Burmese and other text written without them
  /// would run off both edges; Flutter breaks by the script's own rules.
  static String wrap(String text, double room, {String font = '', bool bold = false}) {
    // Lines that fit with room to spare are left as they are.
    if (room <= 2 || text.split('\n').every((line) => _ems(line) <= room * 0.9)) return text;
    const size = 32.0;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size, height: 1.3, fontFamily: font.isEmpty ? null : font, fontFamilyFallback: const [bundledFont], fontWeight: bold ? FontWeight.w700 : FontWeight.normal),
      ),
      textDirection: TextDirection.ltr,
    );
    List<String> linesAt(double ems) {
      painter.layout(maxWidth: ems * size);
      final lines = <String>[];
      var offset = 0;
      while (offset < text.length) {
        final range = painter.getLineBoundary(TextPosition(offset: offset));
        if (range.end <= offset) break;
        lines.add(text.substring(offset, range.end).replaceAll('\n', '').trimRight());
        offset = range.end;
        // The break itself, when the text had one.
        if (offset < text.length && text[offset] == '\n') offset++;
      }
      if (offset < text.length) lines.add(text.substring(offset));
      return lines;
    }

    // A little spare: libass draws in the system's font, measured here in
    // Flutter's, and the two are never quite as wide.
    final width = room * 0.92;
    var lines = linesAt(width);
    // Balanced, as subtitles are set by hand: the narrowest width that
    // keeps as many lines, so they come out about as long as each other
    // instead of a full line and a stub.
    if (lines.length > 1) {
      var narrow = width / lines.length, wide = width;
      for (var i = 0; i < 10; i++) {
        final middle = (narrow + wide) / 2;
        if (linesAt(middle).length <= lines.length) {
          wide = middle;
        } else {
          narrow = middle;
        }
      }
      lines = linesAt(wide);
    }
    painter.dispose();
    return lines.join('\n');
  }

  /// A rough width in ems: full-width characters (CJK, kana, Hangul) one
  /// each, Latin letters by their usual widths in a sans-serif font (i, l
  /// and punctuation narrow, m and w wide, capitals wider than small
  /// letters), anything else a little over half.
  static double _ems(String line) {
    var width = 0.0;
    for (final rune in line.runes) {
      // Marks above and below a letter (Thai, Khmer, Devanagari vowels and
      // tones) take no room of their own.
      if (rune >= 0x300 && _mark.hasMatch(String.fromCharCode(rune))) continue;
      width += _wide(rune) ? 1.0 : _latin(rune);
    }
    return width;
  }

  static final _mark = RegExp(r'[\p{Mn}\p{Me}]', unicode: true);

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
      // The Flutter view's outline, in mpv's units.
      border: outlineFor(border) * unit,
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

  /// How far the outline reaches out from the letters, in the Flutter
  /// view's logical pixels, for the 描边 setting [border]: both drawings
  /// use it.
  static double outlineFor(double border) => 0.7 * border;

  /// libass sizes a font by its whole line (ascent and descent, as Windows
  /// does), the Flutter view by its em: how many ems a line of [font] is.
  /// Read from the fonts' OS/2 tables; others are taken as 1.3.
  static double lineEms(String font) => switch (font.toLowerCase()) {
        'microsoft yahei' || 'microsoft yahei ui' || '微软雅黑' => 1.32,
        'noto sans cjk sc' || 'noto sans cjk tc' || 'noto sans cjk jp' || 'noto sans cjk kr' || 'noto sans sc' || 'noto sans kr' || 'source han sans sc' || 'source han sans' => 1.448,
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
/// [outline] is the outline's width for a letter one unit wide. [scale]
/// sizes everything in it, for a libmpv without secondary-sub-scale.
String secondAss(List<SubtitleCue> cues, PlayerSettings settings, {required double outline, double room = 0, String? font, MainUnder? main, double aspect = 16 / 9, double scale = 1, bool blurred = false}) {
  font ??= settings.secondaryFont.isEmpty ? 'sans-serif' : PlayerSettings.fontForThisSystem(settings.secondaryFont);
  final unit = secondEm * scale;
  final size = unit * settings.secondaryScale * LibassLook.lineEms(font);
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
  final width = box ? unit * 0.12 : outline * unit;
  final out = StringBuffer()
    ..writeln('[Script Info]')
    ..writeln('ScriptType: v4.00+')
    // As wide as the picture, as mpv makes it for the main subtitle: lines
    // then wrap at the same width in both (a portrait video's too).
    ..writeln('PlayResX: ${(720 * aspect.clamp(0.3, 4.0)).round()}')
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
  // Braces would open override tags; line breaks are ASS's own.
  String ass(String text) => text.replaceAll('{', '(').replaceAll('}', ')').replaceAll(RegExp(r'\r?\n'), r'\N');
  // 模糊翻译: libass blurs the outline alone when there is one, so the
  // letters lose it and are blurred themselves, as the Flutter view blurs.
  final blur = blurred ? '{\\bord0\\shad0\\blur${(size * blurEms).toStringAsFixed(1)}}' : '';
  String second(String text) => '$blur${ass(LibassLayout.wrap(text, room, font: settings.secondaryFont, bold: settings.subtitleBold))}';
  if (main == null || main.cues.isEmpty) {
    for (final cue in cues) {
      out.writeln('Dialogue: 0,${stamp(cue.start)},${stamp(cue.end)},Default,,0,0,0,,${second(cue.text)}');
    }
    return out.toString();
  }
  // The main subtitle's lines under the second one's, invisible, at the
  // main subtitle's font and size: libass stacks the second one above them
  // however tall its fonts really draw, whatever the player's size. One
  // event for each stretch of time in which the same lines show, so libass
  // never stacks two events of this copy on each other.
  final mainSize = unit * settings.subtitleScale * LibassLook.lineEms(main.font);
  final mainTag = '{\\fn${main.font.replaceAll(RegExp(r'[{}\\,]'), ' ')}\\fs${mainSize.toStringAsFixed(2)}\\b${settings.subtitleBold ? 1 : 0}}';
  // The gap the Flutter view leaves between the two, as a line that tall.
  final gap = '{\\alpha&HFF&\\fs${(unit * 6 / 32).toStringAsFixed(2)}}\\h';
  // Broken as Lumtub's copy of the main subtitle breaks them, blank lines
  // left out as there.
  final mainText = [for (final cue in main.cues) ass(LibassLayout.wrap(cue.text, main.room, font: main.wrapFont, bold: settings.subtitleBold).replaceAll(RegExp(r'\n\s*\n'), '\n'))];
  final secondText = [for (final cue in cues) second(cue.text)];
  final times = <Duration>{for (final cue in cues) ...[cue.start, cue.end], for (final cue in main.cues) ...[cue.start, cue.end]}.toList()..sort();
  final seconds = _Showing(cues), mains = _Showing(main.cues);
  String? last;
  Duration? lastStart, lastEnd;
  void flush() {
    if (last != null) out.writeln('Dialogue: 0,${stamp(lastStart!)},${stamp(lastEnd!)},Default,,0,0,0,,$last');
  }

  for (var i = 0; i + 1 < times.length; i++) {
    final from = times[i], to = times[i + 1];
    if (to <= from) continue;
    // libass stacks a later event above an earlier one.
    final above = [for (final i in seconds.at(from).toList().reversed) secondText[i]];
    final under = [for (final i in mains.at(from).toList().reversed) mainText[i]];
    final text = above.isEmpty ? null : under.isEmpty ? above.join(r'\N') : '${above.join(r'\N')}\\N$gap\\N{\\alpha&HFF&}$mainTag${under.join(r'\N')}';
    if (text == last && lastEnd == from) {
      lastEnd = to;
      continue;
    }
    flush();
    last = text;
    lastStart = from;
    lastEnd = to;
  }
  flush();
  return out.toString();
}

/// The cues of a list showing from one time on, for times asked in order:
/// one pass over the list, as a long video has thousands.
class _Showing {
  _Showing(this.cues) : _byStart = List.generate(cues.length, (i) => i)..sort((a, b) => cues[a].start.compareTo(cues[b].start));

  final List<SubtitleCue> cues;
  final List<int> _byStart;
  final _now = SplayTreeSet<int>();
  var _next = 0;

  /// The cues (by index, in list order) shown from [time] to the next time
  /// any cue starts or ends.
  Iterable<int> at(Duration time) {
    while (_next < _byStart.length && cues[_byStart[_next]].start <= time) {
      final i = _byStart[_next++];
      if (cues[i].text.trim().isNotEmpty) _now.add(i);
    }
    _now.removeWhere((i) => cues[i].end <= time);
    return _now;
  }
}

/// The main subtitle drawn invisible under the second one in [secondAss]:
/// its [cues], in [font] (as libmpv draws it), broken into lines as for
/// [room] ems of [wrapFont] (the 字幕字体 setting).
typedef MainUnder = ({List<SubtitleCue> cues, String font, double room, String wrapFont});

/// A letter of [secondAss] at secondary-sub-scale 1, in mpv's units.
const secondEm = 20.0;

/// How far 模糊翻译 blurs the second subtitle, in letters: libass's \\blur
/// for its line height. The Flutter view's blur matches it.
const blurEms = 0.25;
