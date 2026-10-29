import 'dart:async';

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

/// The subtitle of [options] in [target]: one YouTube lists, else the first
/// original-language track translated. Null when the video has no subtitle
/// in another language to translate.
SubtitleOption? translationOf(List<SubtitleOption> options, TranslationLanguage target) {
  final listed = options.where((o) => o.kind == SubtitleKind.translated && speaks(o.language, target)).firstOrNull;
  if (listed != null) return listed;
  final source = options.where((o) => o.kind != SubtitleKind.translated && !speaks(o.language, target)).firstOrNull;
  return source == null ? null : translatedOption(source, target);
}

/// Whether a subtitle tagged [language] (YouTube's or mpv's tag) is in
/// [target]. Chinese is told apart by script: zh-Hans, zh-CN and bare zh
/// are simplified, zh-Hant, zh-TW and zh-HK traditional.
bool speaks(String? language, TranslationLanguage target) {
  final tag = (language ?? '').toLowerCase().replaceAll('_', '-');
  if (tag.isEmpty) return false;
  if (target.code == 'zh-CN') return const {'zh', 'zh-hans', 'zh-cn', 'zh-sg', 'chi', 'zho'}.contains(tag);
  if (target.code == 'zh-TW') return const {'zh-hant', 'zh-tw', 'zh-hk', 'zh-mo'}.contains(tag);
  final code = target.code.toLowerCase();
  return tag == code || tag.startsWith('$code-');
}

/// The subtitle of [options] to show in [target]: one the video has in
/// that language, uploaded before automatic, else YouTube's translation.
SubtitleOption? subtitleIn(List<SubtitleOption> options, TranslationLanguage target) {
  for (final kind in [SubtitleKind.uploaded, SubtitleKind.automatic, SubtitleKind.speech]) {
    final own = options.where((o) => o.kind == kind && speaks(o.language, target)).firstOrNull;
    if (own != null) return own;
  }
  return translationOf(options, target);
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
    final before = player.state.track.subtitle;
    var track = _loaded(player, option);
    if (track == null) {
      // "auto" adds the track without choosing it as the main subtitle.
      await platform.command(['sub-add', file ?? option.url, 'auto', option.label, option.language]);
      track = await _waitFor(player, option);
      if (track == null) return false;
    }
    await platform.setProperty('secondary-sid', track.id);
    // mpv may have picked the new track as the main one too.
    if (player.state.track.subtitle.id == track.id && before.id != track.id) await player.setSubtitleTrack(before);
    return true;
  }

  /// Turns the second subtitle off. mpv then reports its text as
  /// unavailable, which media_kit ignores, so the last line stays in
  /// `Player.state.subtitle`; the subtitle view is told not to draw it
  /// (`SubtitleViewConfiguration.secondary`).
  static Future<void> off(NativePlayer platform) => platform.setProperty('secondary-sid', 'no');

  static SubtitleTrack? _loaded(Player player, SubtitleOption option) =>
      player.state.tracks.subtitle.where((t) => t.title == option.label && t.id != 'auto' && t.id != 'no').firstOrNull;

  static Future<SubtitleTrack?> _waitFor(Player player, SubtitleOption option) async {
    if (_loaded(player, option) != null) return _loaded(player, option);
    try {
      await player.stream.tracks.firstWhere((_) => _loaded(player, option) != null).timeout(const Duration(seconds: 8));
    } on TimeoutException {
      return null;
    }
    return _loaded(player, option);
  }
}
