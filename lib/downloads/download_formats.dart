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
/// `--dump-single-json` result (see `StreamResolver`).
class DownloadFormats {
  const DownloadFormats(this.video, this.audio);
  final List<DownloadVideoFormat> video;
  final List<DownloadAudioFormat> audio;

  bool get isEmpty => video.isEmpty && audio.isEmpty;

  /// Video-only and audio-only formats of [info]; storyboards, formats
  /// without an address, playlist streams and loudness-boosted copies are
  /// left out.
  factory DownloadFormats.parse(Map<String, dynamic> info) {
    final raw = info['formats'];
    final video = <DownloadVideoFormat>[];
    final audio = <DownloadAudioFormat>[];
    if (raw is List) {
      for (final f in raw.whereType<Map>()) {
        final id = f['format_id']?.toString() ?? '';
        final ext = f['ext']?.toString() ?? '';
        final url = f['url']?.toString() ?? '';
        final protocol = f['protocol']?.toString() ?? '';
        if (id.isEmpty || url.isEmpty || ext == 'mhtml' || protocol.contains('m3u8')) continue;
        final vcodec = VideoCodec.of(f['vcodec']);
        final acodec = f['acodec']?.toString() ?? '';
        final hasAudio = acodec.isNotEmpty && acodec != 'none';
        final size = _int(f['filesize']) ?? _int(f['filesize_approx']);
        final tbr = _num(f['tbr']);
        final height = _int(f['height']);
        if (vcodec != null && !hasAudio && height != null && height > 0) {
          video.add(DownloadVideoFormat(id: id, codec: vcodec, height: height, fps: _num(f['fps']), ext: ext, size: size, tbr: tbr, dynamicRange: f['dynamic_range']?.toString()));
        } else if (hasAudio && (f['vcodec'] == null || f['vcodec'] == 'none')) {
          // Loudness-boosted copies (`251-drc`) duplicate the normal track.
          if (id.endsWith('-drc') || '${f['format_note']}'.toUpperCase().contains('DRC')) continue;
          audio.add(DownloadAudioFormat(id: id, codec: acodec, abr: _num(f['abr']) ?? tbr, ext: ext, size: size, languagePreference: _int(f['language_preference'])));
        }
      }
    }
    return DownloadFormats(video, audio);
  }

  static const _dialogOrder = [VideoCodec.vp9, VideoCodec.av1, VideoCodec.h264, VideoCodec.vp8];

  /// Codecs this video has, in the order the dialog lists them.
  List<VideoCodec> get codecs => [
        for (final c in _dialogOrder)
          if (video.any((f) => f.codec == c)) c,
      ];

  /// Heights offered for [codec] (any codec when null), highest first.
  List<int> heightsFor(VideoCodec? codec) =>
      {for (final f in video) if (codec == null || f.codec == codec) f.height}.toList()..sort((a, b) => b.compareTo(a));

  /// The stream to download at [height] (see [pickHeight]) in [codec] (any
  /// when null): more frames, then SDR, then the better codec, then the
  /// higher bitrate.
  DownloadVideoFormat? pickVideo(VideoCodec? codec, {int? height}) {
    final heights = heightsFor(codec);
    if (heights.isEmpty) return null;
    final chosen = pickHeight(heights, height);
    final candidates = video.where((f) => f.height == chosen && (codec == null || f.codec == codec)).toList();
    candidates.sort((a, b) {
      final byFps = (b.fps ?? 0).compareTo(a.fps ?? 0);
      if (byFps != 0) return byFps;
      if (a.hdr != b.hdr) return a.hdr ? 1 : -1;
      final byCodec = _rank.indexOf(a.codec).compareTo(_rank.indexOf(b.codec));
      if (byCodec != 0) return byCodec;
      return (b.tbr ?? 0).compareTo(a.tbr ?? 0);
    });
    return candidates.first;
  }

  static const _rank = [VideoCodec.av1, VideoCodec.vp9, VideoCodec.h264, VideoCodec.vp8];

  /// The entry of [available] (highest first) for a wish of [wanted]: it, else
  /// the nearest below, else the lowest above; the highest without a wish.
  static int pickHeight(List<int> available, int? wanted) {
    if (wanted == null) return available.first;
    for (final h in available) {
      if (h <= wanted) return h;
    }
    return available.last;
  }

  /// Audio tracks, best first: the video's own language, then bitrate.
  List<DownloadAudioFormat> get audioBest => [...audio]..sort((a, b) {
      final byLanguage = (b.languagePreference ?? -1).compareTo(a.languagePreference ?? -1);
      return byLanguage != 0 ? byLanguage : (b.abr ?? 0).compareTo(a.abr ?? 0);
    });

  static int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v');
  static double? _num(Object? v) => v is num ? v.toDouble() : double.tryParse('$v');
}
