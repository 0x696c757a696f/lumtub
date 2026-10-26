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
  bool isTarget(SubtitleOption o) => o.language == target.youtube || o.language == target.code;
  final listed = options.where((o) => o.kind == SubtitleKind.translated && isTarget(o)).firstOrNull;
  if (listed != null) return listed;
  final source = options.where((o) => o.kind != SubtitleKind.translated && !isTarget(o)).firstOrNull;
  return source == null ? null : translatedOption(source, target);
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
      await platform.setProperty('secondary-sid', 'no');
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
