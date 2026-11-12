import 'dart:async';
import 'dart:convert';

import 'package:media_kit/media_kit.dart';

import 'models.dart';
import 'translation.dart';

/// Translated and bilingual subtitles. YouTube translates captions itself
/// when a caption address carries `tlang=<language>`, so nothing is sent to
/// another service. The secondary subtitle is mpv's `secondary-sid`, shown
/// together with the main one (as PiliNara's 副字幕 does).

/// [source] translated into [target] by YouTube.
SubtitleOption translatedOption(SubtitleOption source, TranslationLanguage target) {
  final uri = Uri.parse(source.url);
  return SubtitleOption(
    language: target.youtube,
    name: '',
    url: uri.replace(queryParameters: {...uri.queryParameters, 'tlang': target.youtube}).toString(),
    kind: SubtitleKind.translated,
  );
}

/// The subtitle of [options] in [target], translated by YouTube from:
/// 1. [from], the first subtitle shown, so a second one says the same thing
///    line for line; when [from] is itself a translation, its source;
/// 2. else the video's own subtitle in the language it is spoken in
///    ([language], yt-dlp's tag), the creator's before YouTube's automatic
///    one, as a translation of a translation loses more;
/// 3. else any subtitle of the video's in another language.
/// Null when the video has no subtitle in another language to translate.
SubtitleOption? translationOf(List<SubtitleOption> options, TranslationLanguage target, {SubtitleOption? from, String? language}) {
  if (from != null) {
    final source = from.kind == SubtitleKind.translated ? _untranslated(from) : from;
    if (source != null && !speaks(source.language, target)) return translatedOption(source, target);
  }
  final original = originalSubtitle(options, language: language);
  if (original != null && original.kind != SubtitleKind.translated && !speaks(original.language, target)) return translatedOption(original, target);
  final listed = options.where((o) => o.kind == SubtitleKind.translated && speaks(o.language, target)).firstOrNull;
  if (listed != null) return listed;
  final source = options.where((o) => o.kind != SubtitleKind.translated && !speaks(o.language, target)).firstOrNull;
  return source == null ? null : translatedOption(source, target);
}

/// What a YouTube translation was made from: its address without `tlang`,
/// in the language its `lang` names.
SubtitleOption? _untranslated(SubtitleOption option) {
  final uri = Uri.tryParse(option.url);
  final language = uri?.queryParameters['lang'];
  if (uri == null || language == null || !uri.queryParameters.containsKey('tlang')) return null;
  return SubtitleOption(language: language, name: '', url: uri.replace(queryParameters: {...uri.queryParameters}..remove('tlang')).toString(), kind: SubtitleKind.automatic);
}

/// Whether a subtitle tagged [language] (YouTube's or mpv's tag) is in
/// [target]. Chinese is told apart by script: zh-Hans, zh-CN and bare zh
/// are simplified, zh-Hant, zh-TW and zh-HK traditional.
bool speaks(String? language, TranslationLanguage target) {
  final tag = (language ?? '').toLowerCase().replaceAll('_', '-');
  if (tag.isEmpty) return false;
  if (target.code == 'zh-CN') return const {'zh', 'zh-hans', 'zh-cn', 'zh-sg', 'chi', 'zho'}.contains(tag);
  if (target.code == 'zh-TW') return const {'zh-hant', 'zh-tw', 'zh-hk', 'zh-mo'}.contains(tag);
  return target.tags.any((code) => tag == code.toLowerCase() || tag.startsWith('${code.toLowerCase()}-'));
}

/// The subtitle of [options] to show in [target]: one the video has in
/// that language, uploaded before automatic, else a translation, of [from]
/// when it can be.
SubtitleOption? subtitleIn(List<SubtitleOption> options, TranslationLanguage target, {SubtitleOption? from, String? language}) {
  for (final kind in [SubtitleKind.uploaded, SubtitleKind.automatic, SubtitleKind.speech]) {
    final own = options.where((o) => o.kind == kind && speaks(o.language, target)).firstOrNull;
    if (own != null) return own;
  }
  return translationOf(options, target, from: from, language: language);
}

/// Whether the video has a subtitle of its own (not translated) in [target].
bool hasOwnSubtitle(List<SubtitleOption> options, TranslationLanguage target) =>
    options.any((o) => o.kind != SubtitleKind.translated && speaks(o.language, target));

/// The video's subtitle in the language it is spoken in: YouTube generates
/// automatic subtitles in that language, so an uploaded one in the same
/// language comes first, then the automatic one, then any uploaded one.
/// [language], yt-dlp's tag for the video, wins when a subtitle has it.
SubtitleOption? originalSubtitle(List<SubtitleOption> options, {String? language}) {
  if (language != null && language.isNotEmpty) {
    for (final kind in [SubtitleKind.uploaded, SubtitleKind.automatic, SubtitleKind.speech]) {
      final own = options.where((o) => o.kind == kind && sameLanguage(o.language, language)).firstOrNull;
      if (own != null) return own;
    }
  }
  final automatic = options.where((o) => o.kind == SubtitleKind.automatic).firstOrNull;
  final uploaded = options.where((o) => o.kind == SubtitleKind.uploaded);
  if (automatic == null) return uploaded.firstOrNull ?? options.where((o) => o.kind == SubtitleKind.speech).firstOrNull;
  return uploaded.where((o) => sameLanguage(o.language, automatic.language)).firstOrNull ?? automatic;
}

/// The rows under 原语言 in the subtitle panel: a subtitle in each of
/// [targets] (a name such as 界面语言 and its language), in order, each
/// language once and none in the language [spoken] is in. The video's own
/// subtitle in a language comes before YouTube's translation.
List<({String name, TranslationLanguage language, SubtitleOption option})> languageRows(
  List<SubtitleOption> options,
  SubtitleOption? spoken,
  List<(String, TranslationLanguage)> targets,
) {
  final rows = <({String name, TranslationLanguage language, SubtitleOption option})>[];
  for (final (name, language) in targets) {
    if (rows.any((r) => r.language.code == language.code)) continue;
    if (spoken != null && speaks(spoken.language, language)) continue;
    final option = subtitleIn(options, language, from: spoken);
    if (option == null || identical(option, spoken)) continue;
    rows.add((name: name, language: language, option: option));
  }
  return rows;
}

/// Whether two tags name one language; Chinese scripts count as different.
bool sameLanguage(String? a, String? b) {
  String base(String? tag) {
    final t = (tag ?? '').toLowerCase().replaceAll('_', '-');
    if (const {'zh', 'zh-hans', 'zh-cn', 'zh-sg', 'chi', 'zho'}.contains(t)) return 'zh-hans';
    if (const {'zh-hant', 'zh-tw', 'zh-hk', 'zh-mo'}.contains(t)) return 'zh-hant';
    return t.split('-').first;
  }

  final x = base(a);
  return x.isNotEmpty && x == base(b);
}

/// The subtitle tracks libmpv has now, by id. media_kit's copy of the
/// list arrives later and keeps a replaced track for a while.
Future<Map<String, SubtitleTrack>> mpvSubtitleTracks(NativePlayer platform) async {
  final list = jsonDecode(await platform.getProperty('track-list'));
  return {
    if (list is List)
      for (final t in list.whereType<Map>())
        if (t['type'] == 'sub' && t['id'] != null) '${t['id']}': SubtitleTrack('${t['id']}', t['title'] as String?, t['lang'] as String?),
  };
}

/// [option]'s track among [tracks], if it is loaded.
SubtitleTrack? subtitleTrackOf(Map<String, SubtitleTrack> tracks, SubtitleOption option) =>
    tracks.values.where((t) => t.title == option.label).firstOrNull;

/// Sets and clears mpv's secondary subtitle.
class SecondarySubtitle {
  /// Shows [option] as the secondary subtitle, adding the track to [player]
  /// first if it is not loaded; null turns the secondary subtitle off.
  /// Returns whether it worked. [file] holds the track, fetched already.
  static Future<bool> set(Player player, SubtitleOption? option, {String? file}) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return false;
    if (option == null) {
      await off(platform);
      return true;
    }
    final before = await platform.getProperty('sid');
    var track = subtitleTrackOf(await mpvSubtitleTracks(platform), option);
    if (track == null) {
      // "auto" adds the track without choosing it as the main subtitle. A
      // file being replaced by more of its translation can't be opened for
      // a moment on Windows, so a failed add is tried once more.
      for (var attempt = 0; track == null && attempt < 2; attempt++) {
        if (attempt > 0) await Future<void>.delayed(const Duration(milliseconds: 500));
        try {
          await platform.command(['sub-add', file ?? option.url, 'auto', option.label, option.language]);
        } catch (_) {
          if (attempt > 0) rethrow;
        }
        track = subtitleTrackOf(await mpvSubtitleTracks(platform), option);
      }
      if (track == null) return false;
    }
    await platform.setProperty('secondary-sid', track.id);
    // mpv may have picked the new track as the main one too.
    if (await platform.getProperty('sid') == track.id && before != track.id) await platform.setProperty('sid', before.isEmpty ? 'no' : before);
    return true;
  }

  /// Turns the second subtitle off. mpv then reports its text as
  /// unavailable, which media_kit ignores, so the last line stays in
  /// `Player.state.subtitle`; the subtitle view is told not to draw it
  /// (`SubtitleViewConfiguration.secondary`).
  static Future<void> off(NativePlayer platform) => platform.setProperty('secondary-sid', 'no');

}
