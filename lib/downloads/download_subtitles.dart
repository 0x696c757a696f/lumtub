import '../l10n/l10n.dart';
import '../libass_layout.dart';
import '../models.dart';
import '../player_settings.dart';
import '../subtitle_cues.dart';
import '../subtitle_translation.dart';
import '../translation.dart';
import 'download_selection.dart';

/// The subtitles a video offers for download: its own, and YouTube's
/// translation of them into any language.
class SubtitleChoices {
  SubtitleChoices(List<SubtitleOption> offered, {this.language})
      : own = [for (final o in offered) if (o.kind == SubtitleKind.uploaded || o.kind == SubtitleKind.automatic) o],
        _listed = [for (final o in offered) if (o.kind == SubtitleKind.translated) o];

  /// The creator's and YouTube's automatic subtitles.
  final List<SubtitleOption> own;
  final List<SubtitleOption> _listed;
  /// yt-dlp's tag for the language spoken.
  final String? language;

  bool get isEmpty => own.isEmpty;

  /// The language [tag] names among the translation languages.
  static TranslationLanguage? targetOf(String tag) =>
      TranslationLanguage.all.where((l) => l.youtube == tag).firstOrNull ?? TranslationLanguage.all.where((l) => speaks(tag, l)).firstOrNull;

  /// The name of [option]'s language, also for a translation YouTube
  /// gives no name.
  static String languageOf(SubtitleOption option) {
    final name = SubtitleOption.languageName(option.language, option.name);
    return name == option.language ? targetOf(option.language)?.label ?? name : name;
  }

  /// What [option] is listed as, such as `German (auto-translated)`.
  static String labelOf(SubtitleOption option) => switch (option.kind) {
        SubtitleKind.translated => tr('{0} (auto-translated)', [languageOf(option)]),
        SubtitleKind.automatic => tr('{0} (auto-generated)', [languageOf(option)]),
        _ => option.label,
      };

  /// YouTube's translation of the video's subtitles into [target], null
  /// when nothing can be translated.
  SubtitleOption? translation(TranslationLanguage target) => translationOf([...own, ..._listed], target, language: language);

  /// The subtitle [pick] names, or null when the video no longer has it.
  SubtitleOption? resolve(SubtitlePick pick) {
    final listed = own.where(pick.matches).firstOrNull;
    if (listed != null) return listed;
    if (pick.kind != SubtitleKind.translated) return null;
    final target = targetOf(pick.language);
    return target == null ? null : translation(target);
  }

  /// A subtitle in the language of [tag]: the creator's, else YouTube's
  /// automatic one, else a translation.
  SubtitleOption? inLanguage(String tag) {
    for (final kind in [SubtitleKind.uploaded, SubtitleKind.automatic]) {
      final match = own.where((o) => o.kind == kind && (o.language == tag || sameLanguage(o.language, tag))).firstOrNull;
      if (match != null) return match;
    }
    final target = targetOf(tag);
    return target == null ? null : translation(target);
  }

  /// The subtitle in the language the video is spoken in.
  SubtitleOption? get original => originalSubtitle(own, language: language);
}

/// A line of a bilingual track: [top]'s text over [bottom]'s, either
/// empty where only the other has a line.
typedef BilingualLine = ({Duration start, Duration end, String top, String bottom});

/// [top] and [bottom] shown together: the timeline split wherever either
/// changes, each piece with the lines of both shown then. Pieces with the
/// same lines are joined, and slivers left by lines that end a moment
/// apart are dropped.
List<BilingualLine> bilingualLines(List<SubtitleCue> top, List<SubtitleCue> bottom) {
  final marks = <Duration>{for (final c in [...top, ...bottom]) ...[c.start, c.end]}.toList()..sort();
  String at(List<SubtitleCue> cues, Duration from, Duration to) =>
      [for (final c in cues) if (c.start <= from && c.end >= to) c.text.trim()].where((t) => t.isNotEmpty).join(' ');
  final out = <BilingualLine>[];
  for (var i = 0; i + 1 < marks.length; i++) {
    final from = marks[i], to = marks[i + 1];
    if (to <= from) continue;
    final (upper, lower) = (at(top, from, to), at(bottom, from, to));
    if (upper.isEmpty && lower.isEmpty) continue;
    final last = out.lastOrNull;
    if (last != null && last.top == upper && last.bottom == lower && last.end == from) {
      out[out.length - 1] = (start: last.start, end: to, top: upper, bottom: lower);
    } else {
      out.add((start: from, end: to, top: upper, bottom: lower));
    }
  }
  return [
    for (final (i, c) in out.indexed)
      if (c.end - c.start >= const Duration(milliseconds: 120) || (i > 0 && out[i - 1].end != c.start) && (i + 1 == out.length || out[i + 1].start != c.end)) c,
  ];
}

/// One track of [top] and [bottom] together, [top]'s line over [bottom]'s.
List<SubtitleCue> bilingualCues(List<SubtitleCue> top, List<SubtitleCue> bottom) => [
      for (final l in bilingualLines(top, bottom)) (start: l.start, end: l.end, text: [l.top, l.bottom].where((t) => t.isNotEmpty).join('\n')),
    ];

/// [lines] as an ASS file that looks as the subtitle settings make
/// subtitles look in Lumtub: the first line in the first subtitle's font,
/// size, color, opacity, outline or background and position (style
/// `Default`), the second in the second subtitle's (style `Second`).
/// Lines are broken where Lumtub breaks them, as libass breaks only at
/// spaces.
String styledAss(List<BilingualLine> lines, PlayerSettings settings) {
  final look = LibassLook.standard(position: settings.subtitlePosition, border: settings.subtitleBorder);
  String fontOf(String font) => font.isEmpty ? 'sans-serif' : PlayerSettings.fontForThisSystem(font);
  final mainFont = fontOf(settings.subtitleFont), secondFont = fontOf(settings.secondaryFont);
  String colour(int rgb, double opacity) {
    final alpha = (255 * (1 - opacity.clamp(0, 1))).round();
    String hex(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '&H${hex(alpha)}${hex(rgb & 0xFF)}${hex((rgb >> 8) & 0xFF)}${hex((rgb >> 16) & 0xFF)}';
  }

  String stamp(Duration d) {
    final cs = (d.inMilliseconds / 10).round();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${cs ~/ 360000}:${two(cs ~/ 6000 % 60)}:${two(cs ~/ 100 % 60)}.${two(cs % 100)}';
  }

  final box = settings.subtitleBackground;
  String style(String name, String font, double scale, int color, double opacity) {
    final edge = box ? colour(0, 0.67 * opacity) : colour(0, opacity);
    final width = box ? look.em * scale * 0.12 : look.border * scale;
    final size = look.em * scale * LibassLook.lineEms(font);
    return 'Style: $name,${font.replaceAll(',', ' ')},${size.toStringAsFixed(2)},${colour(color, opacity)},&H000000FF,$edge,$edge,'
        '${settings.subtitleBold ? -1 : 0},0,0,0,100,100,0,0,${box ? 3 : 1},${width.toStringAsFixed(2)},0,2,25,25,${look.margin},1';
  }

  String text(String line, double scale, String font) => LibassLayout.wrap(line, LibassLayout.roomEms(em: look.em, scale: scale).floorToDouble(), font: font, bold: settings.subtitleBold)
      .replaceAll('{', '(')
      .replaceAll('}', ')')
      .replaceAll(RegExp(r'\r?\n'), r'\N');
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
    ..writeln(style('Default', mainFont, settings.subtitleScale, settings.subtitleColor, settings.subtitleOpacity))
    ..writeln(style('Second', secondFont, settings.secondaryScale, settings.secondaryColor, settings.secondaryOpacity))
    ..writeln()
    ..writeln('[Events]')
    ..writeln('Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text');
  for (final line in lines) {
    final parts = [
      if (line.top.isNotEmpty) text(line.top, settings.subtitleScale, settings.subtitleFont),
      if (line.bottom.isNotEmpty) '{\\rSecond}${text(line.bottom, settings.secondaryScale, settings.secondaryFont)}',
    ];
    out.writeln('Dialogue: 0,${stamp(line.start)},${stamp(line.end)},Default,,0,0,0,,${parts.join(r'\N')}');
  }
  return out.toString();
}

/// [ass] with each Dialogue line's times mapped by [shift] (where a time
/// lands once stretches were cut out of the video); a line left with no
/// time at all is dropped.
String shiftAss(String ass, Duration Function(Duration) shift) {
  final time = RegExp(r'^(\d+):(\d{2}):(\d{2})\.(\d{2})$');
  Duration? parse(String text) {
    final m = time.firstMatch(text.trim());
    if (m == null) return null;
    int n(int i) => int.parse(m[i]!);
    return Duration(hours: n(1), minutes: n(2), seconds: n(3), milliseconds: n(4) * 10);
  }

  String stamp(Duration d) {
    final cs = (d.inMilliseconds / 10).round();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${cs ~/ 360000}:${two(cs ~/ 6000 % 60)}:${two(cs ~/ 100 % 60)}.${two(cs % 100)}';
  }

  final out = StringBuffer();
  for (final line in ass.split('\n')) {
    if (line.startsWith('Dialogue:')) {
      final fields = line.substring('Dialogue:'.length).split(',');
      final start = fields.length > 9 ? parse(fields[1]) : null;
      final end = fields.length > 9 ? parse(fields[2]) : null;
      if (start != null && end != null) {
        final from = shift(start), to = shift(end);
        if (to <= from) continue;
        fields[1] = stamp(from);
        fields[2] = stamp(to);
        out.write('Dialogue:${fields.join(',')}\n');
        continue;
      }
    }
    out.write('$line\n');
  }
  final text = out.toString();
  return ass.endsWith('\n') ? text : text.substring(0, text.length - 1);
}

