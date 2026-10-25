import 'dart:convert';
import 'dart:isolate';

import '../native_core.dart';
import '../video_codec.dart';

/// A video-only stream of a video, as yt-dlp lists it.
class DownloadVideoFormat {
  const DownloadVideoFormat({required this.id, required this.codec, required this.height, this.fps, this.ext = '', this.size, this.tbr, this.dynamicRange});
  final String id;
  final VideoCodec codec;
  final int height;
  final double? fps;
  final String ext;
  /// Bytes, exact or approximate.
  final int? size;
  final double? tbr;
  /// `SDR`, `HDR10`, ... when yt-dlp says.
  final String? dynamicRange;

  bool get hdr => dynamicRange != null && dynamicRange!.toUpperCase() != 'SDR';
}

/// An audio-only stream of a video.
class DownloadAudioFormat {
  const DownloadAudioFormat({required this.id, required this.codec, this.abr, this.ext = '', this.size, this.languagePreference});
  final String id;
  /// yt-dlp's `acodec`, such as `mp4a.40.2` or `opus`.
  final String codec;
  final double? abr;
  final String ext;
  final int? size;
  /// yt-dlp's `language_preference`: higher is the video's original language.
  final int? languagePreference;

  bool get isAac => codec.toLowerCase().startsWith('mp4a');
  bool get isOpus => codec.toLowerCase().startsWith('opus');
  bool get isVorbis => codec.toLowerCase().startsWith('vorbis');
}

/// The streams a video offers for download, read from yt-dlp's
/// `--dump-single-json` result (see `StreamResolver`). Reading the list and
/// picking from it is done by lumtub_core (native/lumtub_core/src/downloads.rs);
/// without it there is nothing to pick and the dialog offers its simple
/// choices.
class DownloadFormats {
  const DownloadFormats(this.video, this.audio, {this.preference = const []});
  final List<DownloadVideoFormat> video;
  final List<DownloadAudioFormat> audio;
  /// The codecs automatic picks may take, most preferred first: the
  /// playback order (`FormatPolicy.codecOrder`), so a download plays as
  /// smoothly as the stream would. Empty: any codec, the best picture.
  final List<VideoCodec> preference;

  bool get isEmpty => video.isEmpty && audio.isEmpty;

  /// [parse] away from the UI isolate: [info] runs to a few megabytes.
  static Future<DownloadFormats> parseInBackground(Map<String, dynamic> info, {List<VideoCodec> preference = const []}) =>
      Isolate.run(() => DownloadFormats.parse(info, preference: preference));

  /// Video-only and audio-only formats of [info]; storyboards, formats
  /// without an address, playlist streams and loudness-boosted copies are
  /// left out.
  factory DownloadFormats.parse(Map<String, dynamic> info, {List<VideoCodec> preference = const []}) {
    final core = NativeCore.instance;
    if (core == null) return DownloadFormats(const [], const [], preference: preference);
    final parsed = jsonDecode(core.take(core.withText(jsonEncode(info), core.downloadFormats)) ?? '{}') as Map<String, dynamic>;
    return DownloadFormats(
      [
        for (final f in (parsed['video'] as List? ?? const []).cast<Map<String, dynamic>>())
          DownloadVideoFormat(
            id: f['id'] as String,
            codec: VideoCodec.byName(f['codec'])!,
            height: f['height'] as int,
            fps: (f['fps'] as num?)?.toDouble(),
            ext: f['ext'] as String? ?? '',
            size: f['size'] as int?,
            tbr: (f['tbr'] as num?)?.toDouble(),
            dynamicRange: f['range'] as String?,
          ),
      ],
      [for (final f in (parsed['audio'] as List? ?? const []).cast<Map<String, dynamic>>()) _audio(f)],
      preference: preference,
    );
  }

  static DownloadAudioFormat _audio(Map<String, dynamic> f) => DownloadAudioFormat(
        id: f['id'] as String,
        codec: f['codec'] as String,
        abr: (f['abr'] as num?)?.toDouble(),
        ext: f['ext'] as String? ?? '',
        size: f['size'] as int?,
        languagePreference: f['language'] as int?,
      );

  /// The streams in the form lumtub_core reads.
  Map<String, dynamic> toJson() => {
        'video': [
          for (final f in video)
            {'id': f.id, 'codec': f.codec.name, 'height': f.height, if (f.fps != null) 'fps': f.fps, 'ext': f.ext, if (f.size != null) 'size': f.size, if (f.tbr != null) 'tbr': f.tbr, if (f.dynamicRange != null) 'range': f.dynamicRange},
        ],
        'audio': [for (final a in audio) _audioJson(a)],
      };

  static Map<String, dynamic> _audioJson(DownloadAudioFormat a) =>
      {'id': a.id, 'codec': a.codec, if (a.abr != null) 'abr': a.abr, 'ext': a.ext, if (a.size != null) 'size': a.size, if (a.languagePreference != null) 'language': a.languagePreference};

  /// lumtub_core's answer for these options: the codecs, the automatic
  /// codec, the heights, the picked stream, the audio best first and the
  /// plan.
  Map<String, dynamic> choose({VideoCodec? codec, int? height, String container = 'auto', bool audioOnly = false}) {
    final core = NativeCore.instance;
    if (core == null) return const {};
    final json = jsonEncode({
      ...toJson(),
      'preference': [for (final c in preference) c.name],
      if (codec?.name != null) 'codec': codec?.name,
      if (height != null) 'height': height,
      'container': container,
      'audioOnly': audioOnly,
    });
    return jsonDecode(core.take(core.withText(json, core.downloadChoose)) ?? '{}') as Map<String, dynamic>;
  }

  /// Codecs this video has, in the order the dialog lists them.
  List<VideoCodec> get codecs => [for (final name in choose()['codecs'] as List? ?? const []) VideoCodec.byName(name)!];

  /// The codec an automatic pick takes: the first of [preference] the video
  /// has, or null (any) when it has none of them or [preference] is empty.
  VideoCodec? get automaticCodec => VideoCodec.byName(choose()['automatic']);

  /// Heights offered for [codec] (the [automaticCodec] when null), highest
  /// first.
  List<int> heightsFor(VideoCodec? codec) => (choose(codec: codec)['heights'] as List? ?? const []).cast<int>();

  /// The stream to download at [height] in [codec] (any when null): it,
  /// else the nearest below, else the lowest above, the highest without a
  /// wish; then more frames, SDR, the better codec and the higher bitrate.
  DownloadVideoFormat? pickVideo(VideoCodec? codec, {int? height}) {
    final id = choose(codec: codec, height: height)['video'];
    return video.where((f) => f.id == id).firstOrNull;
  }

  /// Audio tracks, best first: the video's own language, then bitrate.
  List<DownloadAudioFormat> get audioBest => [
        for (final id in choose()['audioBest'] as List? ?? const []) audio.firstWhere((a) => a.id == id),
      ];
}
