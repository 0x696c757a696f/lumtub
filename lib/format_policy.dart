import 'dart:convert';
import 'dart:math';

import 'l10n/l10n.dart';
import 'native_core.dart';
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

  /// The policy for [settings], worked out by lumtub_core
  /// (native/lumtub_core/src/format_policy.rs). Without the library
  /// yt-dlp's and mpv's defaults apply, minus the disabled codecs.
  static _Policy _policy(PlayerSettings settings, {int displayHeight = 0}) {
    final core = NativeCore.instance;
    final json = jsonEncode({
      'strategy': settings.strategy.name,
      'disabled': [for (final c in VideoCodec.values) if (settings.disabledCodecs.contains(c)) c.name],
      'hardware': [for (final c in VideoCodec.values) if (_hardware(settings, c)) c.name],
      'maxHeight': settings.maxHeight,
      'audio': settings.audioQuality.name,
      'display': max(0, displayHeight),
    });
    final answer = core?.take(core.withText(json, core.formatPolicy));
    if (answer == null) {
      return _Policy([for (final c in VideoCodec.values) if (allows(settings, c)) c], 'ytdl', null, 0);
    }
    final data = jsonDecode(answer) as Map<String, dynamic>;
    return _Policy(
      [for (final name in data['order'] as List) if (VideoCodec.byName(name) case final codec?) codec],
      data['expression'] as String,
      data['formatSort'] as String?,
      data['displayHeight'] as int,
    );
  }

  /// The allowed codecs, most preferred first.
  ///
  /// - auto: removes user-disabled codecs, then uses the verified decoder
  ///   ladder: AV1 hardware decoding, then VP9 hardware decoding, then H.264.
  ///   When hardware decoding is off or none has verified hardware decoding,
  ///   software H.264 comes first, then VP9 and AV1.
  /// - lowResource: H.264, then codecs with verified hardware decoding, then
  ///   the rest. Above 1080p the verified ones go first, as H.264 cannot
  ///   reach that height.
  /// - quality: no preference. yt-dlp ranks by resolution, frame rate and
  ///   bitrate, so the expression ignores this list; Piped and Invidious
  ///   streams use it as a tie-break after height (VP9, AV1, H.264, VP8).
  static List<VideoCodec> codecOrder(PlayerSettings settings) => _policy(settings).order;

  /// [settings] with automatic quality capped at the tallest display: a 4K
  /// stream on a 1080p screen costs four times the download, decoding,
  /// memory and GPU scaling for no visible gain. Automatic selection also
  /// stays at 1080p until VP9 or AV1 has actually been verified in hardware:
  /// YouTube has H.264 at that height, so this avoids selecting an unverified
  /// modern codec for 1440p or 4K. A chosen quality cap, codec restriction,
  /// or quality strategy is left alone. [displayHeight] is in physical
  /// pixels; 0 when unknown.
  static PlayerSettings forDisplay(PlayerSettings settings, int displayHeight) {
    final cap = _policy(settings, displayHeight: displayHeight).displayHeight;
    return cap > 0 ? settings.copyWith(maxHeight: cap) : settings;
  }

  /// The yt-dlp format expression for [settings].
  ///
  /// Every alternative, including the last `best`, carries the exclude
  /// filters of the disabled codecs, so no fallback can pick one. The quality
  /// strategy is yt-dlp's own `bestvideo`, written `ytdl` when nothing
  /// restricts it.
  static String expression(PlayerSettings settings) => _policy(settings).expression;

  /// Within the user's selected quality cap, yt-dlp first ranks by picture
  /// quality, then breaks ties by the verified decoder ladder. This keeps a
  /// 1080p AVC stream ahead of a 360p VP9 stream, while still choosing
  /// hardware-decoded AV1 or VP9 when the quality tier is equal.
  static String? formatSort(PlayerSettings settings) => _policy(settings).formatSort;

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

class _Policy {
  const _Policy(this.order, this.expression, this.formatSort, this.displayHeight);
  final List<VideoCodec> order;
  final String expression;
  final String? formatSort;
  final int displayHeight;
}
