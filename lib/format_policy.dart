import 'l10n/l10n.dart';
import 'player_settings.dart';
import 'video_codec.dart';

/// The one place that decides which video formats may play and in what
/// order: yt-dlp expressions, Piped and Invidious streams, casting and the
/// quality menu all read it.
///
/// First the disabled codecs are removed, then the rest is ordered by the
/// [PlaybackStrategy]. A fallback only ever goes to another allowed codec; a
/// disabled one is never picked, so a video with nothing else fails with a
/// message instead of playing in a codec the user switched off.
class FormatPolicy {
  const FormatPolicy._();

  /// The key `settings.decoderResults` uses for [codec]; VP8 is never tested.
  static String? decoderKey(VideoCodec codec) => switch (codec) {
        VideoCodec.h264 => 'h264',
        VideoCodec.vp9 => 'vp9',
        VideoCodec.av1 => 'av1',
        VideoCodec.vp8 => null,
      };

  static bool _hardware(PlayerSettings settings, VideoCodec codec) {
    final key = decoderKey(codec);
    return key != null && (settings.decoderResults[key]?.isHardware ?? false);
  }

  /// Whether [codec] may play. Null (audio, unknown names) is not filtered.
  static bool allows(PlayerSettings settings, VideoCodec? codec) => codec == null || !settings.disabledCodecs.contains(codec);

  /// Whether a stream whose codec is called [name] may play.
  static bool allowsName(PlayerSettings settings, Object? name) => allows(settings, VideoCodec.of(name));

  /// The allowed codecs, most preferred first.
  ///
  /// - auto: codecs with verified hardware decoding first (VP9, AV1), then
  ///   H.264, which every Windows GPU decodes, then the rest. A cap above
  ///   1080p puts VP9 and AV1 before H.264, because YouTube offers H.264 only
  ///   up to 1080p. AV1, the most expensive codec to decode, therefore comes
  ///   before H.264 only when verified in hardware or when that cap needs it;
  ///   otherwise it is the last resort.
  /// - lowResource: H.264, then codecs with verified hardware decoding, then
  ///   the rest. Above 1080p the verified ones go first, as H.264 cannot
  ///   reach that height.
  /// - quality: no preference. yt-dlp ranks by resolution, frame rate and
  ///   bitrate, so the expression ignores this list; Piped and Invidious
  ///   streams use it as a tie-break after height (VP9, AV1, H.264, VP8).
  static List<VideoCodec> codecOrder(PlayerSettings settings) {
    final all = [for (final c in [VideoCodec.vp9, VideoCodec.av1, VideoCodec.h264, VideoCodec.vp8]) if (allows(settings, c)) c];
    final modern = all.where((c) => c == VideoCodec.vp9 || c == VideoCodec.av1).toList();
    final verified = modern.where((c) => _hardware(settings, c)).toList();
    final tall = settings.maxHeight > 1080;
    final h264 = all.where((c) => c == VideoCodec.h264);
    final front = switch (settings.strategy) {
      PlaybackStrategy.quality => const <VideoCodec>[],
      PlaybackStrategy.auto => [...verified, if (tall) ...modern, ...h264],
      PlaybackStrategy.lowResource => [if (tall) ...verified, ...h264, ...verified],
    };
    return [...{...front, ...all}];
  }

  /// The yt-dlp format expression for [settings].
  ///
  /// Every alternative, including the last `best`, carries the exclude
  /// filters of the disabled codecs, so no fallback can pick one. The quality
  /// strategy is yt-dlp's own `bestvideo`, written `ytdl` when nothing
  /// restricts it.
  static String expression(PlayerSettings settings) {
    final height = settings.maxHeight > 0 ? '[height<=?${settings.maxHeight}]' : '';
    final exclude = [for (final c in VideoCodec.values) if (settings.disabledCodecs.contains(c)) c.excludeFilter].join();
    final audio = switch (settings.audioQuality) {
      AudioQuality.best => 'bestaudio',
      AudioQuality.medium => 'bestaudio[abr<=?128]',
      AudioQuality.low => 'bestaudio[abr<=?64]',
    };
    if (settings.strategy == PlaybackStrategy.quality) {
      if (height.isEmpty && exclude.isEmpty && settings.audioQuality == AudioQuality.best) return 'ytdl';
      return 'bestvideo$exclude$height+$audio/best$exclude$height/best$exclude';
    }
    return [
      for (final codec in codecOrder(settings)) 'bestvideo${codec.onlyFilter}$height+$audio',
      'bestvideo$exclude$height+$audio',
      if (audio != 'bestaudio') 'bestvideo$exclude$height+bestaudio',
      'best$exclude$height',
      'best$exclude',
    ].join('/');
  }

  /// Names of the disabled codecs, e.g. `AV1、VP9`, or empty.
  static String disabledNames(PlayerSettings settings) => [for (final c in VideoCodec.values) if (settings.disabledCodecs.contains(c)) c.label].join('、');

  /// A one-line summary of the rule in force, for the settings page.
  static String summary(PlayerSettings settings) {
    final disabled = disabledNames(settings);
    final order = settings.strategy == PlaybackStrategy.quality ? tr('按分辨率和帧率择优') : [for (final c in codecOrder(settings)) c.label].join(' › ');
    final rule = tr('当前规则：{0}，编码顺序 {1}', [settings.strategy.label, order.isEmpty ? tr('无') : order]);
    return disabled.isEmpty ? rule : '$rule${tr('，已禁用 {0}', [disabled])}';
  }
}
