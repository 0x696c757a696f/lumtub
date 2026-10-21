import '../l10n/l10n.dart';
import '../models.dart';
import '../video_codec.dart';
import 'download_formats.dart';

/// The file a download is muxed into.
enum DownloadContainer {
  auto('自动（推荐）'),
  mkv('MKV'),
  mp4('MP4'),
  webm('WebM');

  const DownloadContainer(this._label);
  final String _label;
  String get label => tr(_label);

  static DownloadContainer byName(Object? name) => values.where((c) => c.name == name).firstOrNull ?? auto;
}

/// The container a video and audio pair goes into, and why a wanted one
/// does not work.
class ContainerPlan {
  const ContainerPlan(this.container, this.audio, {this.problem});
  /// Never [DownloadContainer.auto].
  final DownloadContainer container;
  final DownloadAudioFormat? audio;
  /// Why [wanted] cannot hold the streams without re-encoding, for display.
  final String? problem;
}

/// Picks the audio track and container for [video]. MKV holds anything, MP4
/// AV1/VP9/H.264 with AAC or Opus, WebM VP8/VP9/AV1 with Opus or Vorbis.
/// [wanted] auto takes MP4 for H.264 with AAC, WebM when everything fits it,
/// else MKV. Streams are only ever copied, never re-encoded.
ContainerPlan planContainer(DownloadContainer wanted, VideoCodec video, List<DownloadAudioFormat> audioBest) {
  DownloadAudioFormat? first(bool Function(DownloadAudioFormat) test) => audioBest.where(test).firstOrNull;
  final aac = first((a) => a.isAac);
  final mp4Audio = aac ?? first((a) => a.isOpus);
  final webmAudio = first((a) => a.isOpus || a.isVorbis);
  final webmVideo = video != VideoCodec.h264;
  final hasAudio = audioBest.isNotEmpty;
  switch (wanted) {
    case DownloadContainer.mkv:
      return ContainerPlan(DownloadContainer.mkv, audioBest.firstOrNull);
    case DownloadContainer.mp4:
      final problem = video == VideoCodec.vp8
          ? tr('MP4 不能容纳 VP8')
          : hasAudio && mp4Audio == null
              ? tr('MP4 没有可用的音轨')
              : null;
      return ContainerPlan(DownloadContainer.mp4, mp4Audio, problem: problem);
    case DownloadContainer.webm:
      final problem = !webmVideo
          ? tr('WebM 不能容纳 H.264')
          : hasAudio && webmAudio == null
              ? tr('WebM 没有可用的音轨')
              : null;
      return ContainerPlan(DownloadContainer.webm, webmAudio, problem: problem);
    case DownloadContainer.auto:
      if (video == VideoCodec.h264 && aac != null) return ContainerPlan(DownloadContainer.mp4, aac);
      if (webmVideo && webmAudio != null) return ContainerPlan(DownloadContainer.webm, webmAudio);
      return ContainerPlan(DownloadContainer.mkv, audioBest.firstOrNull);
  }
}

/// What the download dialog chose: locked format ids, and the container the
/// streams are merged into.
class DownloadSelection {
  const DownloadSelection({
    this.audioOnly = false,
    this.codec,
    this.height,
    this.videoId,
    this.audioId,
    this.container = DownloadContainer.mkv,
    this.size,
  });

  final bool audioOnly;
  /// The codec and height of the stream picked, null for audio only.
  final VideoCodec? codec;
  final int? height;
  final String? videoId;
  final String? audioId;
  /// Never [DownloadContainer.auto].
  final DownloadContainer container;
  /// Bytes in all, when known.
  final int? size;

  /// What the downloads list shows, such as `VP9 · 1080p · MP4`.
  String get label => audioOnly ? tr('仅音频') : '${codec?.label ?? ''} · ${height}p · ${container.label}';

  /// Whether ffmpeg has to join a video and an audio stream.
  bool get needsMerge => !audioOnly && videoId != null && audioId != null;

  /// yt-dlp's `--format`. Without ffmpeg ([merge] false) the streams cannot
  /// be joined, so the best single-file format of that height is taken.
  String format({required bool merge}) {
    if (audioOnly) return audioId ?? 'ba';
    if (!needsMerge) return videoId ?? 'b';
    if (merge) return '$videoId+$audioId';
    return 'b[height<=$height][ext=mp4]/b[height<=$height]/b[ext=mp4]/b';
  }

  /// Extra arguments for the container, none when nothing is merged.
  List<String> containerArguments({required bool merge}) =>
      merge && needsMerge ? ['--merge-output-format', container.name] : const [];

  Map<String, dynamic> toJson() => {
        if (audioOnly) 'audioOnly': true,
        if (codec != null) 'codec': codec!.name,
        if (height != null) 'height': height,
        if (videoId != null) 'video': videoId,
        if (audioId != null) 'audio': audioId,
        'container': container.name,
        if (size != null) 'size': size,
      };

  /// The selection in [raw], or null when it holds no format to download.
  static DownloadSelection? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final audioOnly = raw['audioOnly'] == true;
    final video = raw['video']?.toString();
    final audio = raw['audio']?.toString();
    if (audioOnly ? audio == null : video == null) return null;
    final container = DownloadContainer.byName(raw['container']);
    return DownloadSelection(
      audioOnly: audioOnly,
      codec: VideoCodec.byName(raw['codec']),
      height: raw['height'] is int ? raw['height'] as int : null,
      videoId: audioOnly ? null : video,
      audioId: audio,
      container: container == DownloadContainer.auto ? DownloadContainer.mkv : container,
      size: raw['size'] is int ? raw['size'] as int : null,
    );
  }
}

/// A [DownloadSelection] for the dialog's current options, or the reason
/// there is none.
class DownloadPlan {
  const DownloadPlan(this.selection, {this.problem});
  final DownloadSelection? selection;
  /// Why the wanted container cannot be used with the streams; null when
  /// there is a selection, or nothing to select.
  final String? problem;
}

/// Builds the selection for [codec] (null: any), [height] (see
/// [DownloadFormats.pickHeight]) and [container] from [formats]; for
/// [audioOnly] the best m4a track, else the best track.
DownloadPlan planDownload(DownloadFormats formats, {VideoCodec? codec, int? height, DownloadContainer container = DownloadContainer.auto, bool audioOnly = false}) {
  final audio = formats.audioBest;
  if (audioOnly) {
    final track = audio.where((a) => a.ext == 'm4a').firstOrNull ?? audio.firstOrNull;
    if (track == null) return const DownloadPlan(null);
    return DownloadPlan(DownloadSelection(audioOnly: true, audioId: track.id, size: track.size, container: DownloadContainer.mkv));
  }
  final video = formats.pickVideo(codec, height: height);
  if (video == null) return const DownloadPlan(null);
  final plan = planContainer(container, video.codec, audio);
  if (plan.problem != null) return DownloadPlan(null, problem: plan.problem);
  final size = video.size == null ? null : video.size! + (plan.audio?.size ?? 0);
  return DownloadPlan(DownloadSelection(codec: video.codec, height: video.height, videoId: video.id, audioId: plan.audio?.id, container: plan.container, size: size));
}

/// The dialog's last choices, offered again next time.
class DownloadDefaults {
  const DownloadDefaults({this.codec = auto, this.height, this.container = DownloadContainer.auto});
  /// `auto`, [audioOnly], or a [VideoCodec] name.
  final String codec;
  final int? height;
  final DownloadContainer container;

  static const auto = 'auto';
  static const audioOnly = 'audio';

  /// The remembered codec, null for auto and audio only.
  VideoCodec? get videoCodec => VideoCodec.byName(codec);

  Map<String, dynamic> toJson() => {'codec': codec, if (height != null) 'height': height, 'container': container.name};

  static DownloadDefaults fromJson(Object? raw) {
    if (raw is! Map) return const DownloadDefaults();
    final codec = raw['codec']?.toString();
    final known = codec == audioOnly || VideoCodec.byName(codec) != null;
    return DownloadDefaults(
      codec: known ? codec! : auto,
      height: raw['height'] is int ? raw['height'] as int : null,
      container: DownloadContainer.byName(raw['container']),
    );
  }
}

/// The about-size text of [bytes] for the summary line.
String approximateSize(int bytes) => tr('约 {0}', [formatBytes(bytes)]);
