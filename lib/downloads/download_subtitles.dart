import '../l10n/l10n.dart';
import '../models.dart';
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

/// One track of [top] and [bottom] together: each line of [top] with the
/// line of [bottom] shown at the same time under it. Where only one of
/// them has a line, that line is shown alone.
List<SubtitleCue> bilingualCues(List<SubtitleCue> top, List<SubtitleCue> bottom) {
  final marks = <Duration>{for (final c in [...top, ...bottom]) ...[c.start, c.end]}.toList()..sort();
  String at(List<SubtitleCue> cues, Duration from, Duration to) =>
      [for (final c in cues) if (c.start <= from && c.end >= to) c.text.trim()].where((t) => t.isNotEmpty).join(' ');
  final out = <SubtitleCue>[];
  for (var i = 0; i + 1 < marks.length; i++) {
    final from = marks[i], to = marks[i + 1];
    if (to <= from) continue;
    final text = [at(top, from, to), at(bottom, from, to)].where((t) => t.isNotEmpty).join('\n');
    if (text.isEmpty) continue;
    final last = out.lastOrNull;
    if (last != null && last.text == text && last.end == from) {
      out[out.length - 1] = (start: last.start, end: to, text: text);
    } else {
      out.add((start: from, end: to, text: text));
    }
  }
  // Slivers left by lines that end a moment apart are not shown alone.
  return [
    for (final (i, c) in out.indexed)
      if (c.end - c.start >= const Duration(milliseconds: 120) || (i > 0 && out[i - 1].end != c.start) && (i + 1 == out.length || out[i + 1].start != c.end)) c,
  ];
}
