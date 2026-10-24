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
    return settings.hwdec != 'no' && key != null && (settings.decoderResults[key]?.isHardware ?? false);
  }

  /// Whether [codec] may play. Null (audio, unknown names) is not filtered.
  static bool allows(PlayerSettings settings, VideoCodec? codec) => codec == null || !settings.disabledCodecs.contains(codec);

  /// Whether a stream whose codec is called [name] may play.
  static bool allowsName(PlayerSettings settings, Object? name) => allows(settings, VideoCodec.of(name));

  /// The allowed codecs, most preferred first.
  ///
  /// - auto: removes user-disabled codecs, then uses the verified decoder
  ///   ladder: AV1 hardware decoding, then VP9 hardware decoding, then H.264.
  ///   When hardware decoding is off or none has verified hardware decoding,
  ///   software H.264 comes first,
  ///   then VP9 and AV1.
  /// - lowResource: H.264, then codecs with verified hardware decoding, then
  ///   the rest. Above 1080p the verified ones go first, as H.264 cannot
  ///   reach that height.
  /// - quality: no preference. yt-dlp ranks by resolution, frame rate and
  ///   bitrate, so the expression ignores this list; Piped and Invidious
  ///   streams use it as a tie-break after height (VP9, AV1, H.264, VP8).
  static List<VideoCodec> codecOrder(PlayerSettings settings) {
    final all = [for (final c in [VideoCodec.av1, VideoCodec.vp9, VideoCodec.h264, VideoCodec.vp8]) if (allows(settings, c)) c];
    final modern = all.where((c) => c == VideoCodec.vp9 || c == VideoCodec.av1).toList();
    final av1Hardware = _hardware(settings, VideoCodec.av1);
    final vp9Hardware = _hardware(settings, VideoCodec.vp9);
    final verified = modern.where((c) => _hardware(settings, c)).toList();
    final tall = settings.maxHeight > 1080;
    final h264 = all.where((c) => c == VideoCodec.h264);
    final front = switch (settings.strategy) {
      PlaybackStrategy.quality => const <VideoCodec>[],
      PlaybackStrategy.auto => av1Hardware
          ? [VideoCodec.av1, VideoCodec.vp9, ...h264]
          : vp9Hardware
          ? [VideoCodec.vp9, ...h264, VideoCodec.av1]
          : [...h264, VideoCodec.vp9, VideoCodec.av1],
      PlaybackStrategy.lowResource => [if (tall) ...verified, ...h264, ...verified],
    };
    return [...{...front, ...all}.where(all.contains)];
  }

  /// Heights YouTube serves, lowest first.
  static const _ladder = [720, 1080, 1440, 2160, 4320];

  /// [settings] with automatic quality capped at the tallest display: a 4K
  /// stream on a 1080p screen costs four times the download, decoding,
  /// memory and GPU scaling for no visible gain. Automatic selection also
  /// stays at 1080p until VP9 or AV1 has actually been verified in hardware:
  /// YouTube has H.264 at that height, so this avoids selecting an unverified
  /// modern codec for 1440p or 4K. A chosen quality cap, codec restriction,
  /// or quality strategy is left alone. [displayHeight] is in physical
  /// pixels; 0 when unknown.
  static PlayerSettings forDisplay(PlayerSettings settings, int displayHeight) {
    if (settings.maxHeight > 0 || settings.strategy == PlaybackStrategy.quality || settings.disabledCodecs.isNotEmpty) return settings;
    final modernHardware = [VideoCodec.vp9, VideoCodec.av1].any((codec) => _hardware(settings, codec));
    final decoderCap = settings.strategy == PlaybackStrategy.auto && !modernHardware ? 1080 : 0;
    final displayCap = displayHeight <= 0 ? 0 : _ladder.where((h) => h >= displayHeight * 0.95).firstOrNull ?? 0;
    final caps = [if (decoderCap > 0) decoderCap, if (displayCap > 0) displayCap];
    if (caps.isEmpty) return settings;
    return settings.copyWith(maxHeight: caps.reduce((a, b) => a < b ? a : b));
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
      'bestvideo$exclude$height+$audio',
      if (audio != 'bestaudio') 'bestvideo$exclude$height+bestaudio',
      'best$exclude$height',
      'best$exclude',
    ].join('/');
  }

  /// Within the user's selected quality cap, yt-dlp first ranks by picture
  /// quality, then breaks ties by the verified decoder ladder. This keeps a
  /// 1080p AVC stream ahead of a 360p VP9 stream, while still choosing
  /// hardware-decoded AV1 or VP9 when the quality tier is equal.
  static String? formatSort(PlayerSettings settings) {
    if (settings.strategy == PlaybackStrategy.quality) return null;
    final first = codecOrder(settings).firstOrNull;
    if (first == null) return null;
    final preferred = switch (first) {
      VideoCodec.av1 => 'av01',
      VideoCodec.vp9 => 'vp9',
      VideoCodec.h264 => 'avc',
      VideoCodec.vp8 => 'vp8',
    };
    return 'res,fps,vcodec:$preferred';
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
