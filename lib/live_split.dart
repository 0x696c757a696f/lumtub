import 'format_policy.dart';
import 'player_settings.dart';
import 'video_codec.dart';

/// A live stream's picture above 1080p and its sound. YouTube serves those
/// only as separate streams of numbered fragments (yt-dlp lists them with
/// `formats=incomplete`); lumtub_core's relay joins the fragments into one
/// growing stream each (see `relay_live.rs`).
class LiveSplit {
  const LiveSplit(this.video, this.audio);

  final Map<String, dynamic> video;
  final Map<String, dynamic> audio;

  String get videoUrl => video['url'] as String;
  String get audioUrl => audio['url'] as String;
  int get height => video['height'] as int;
  /// The User-Agent the addresses were issued for.
  String? get userAgent => (video['http_headers'] as Map?)?['User-Agent'] as String?;
  String get label => '${video['format_id']}+${audio['format_id']} (${height}p${video['fps'] ?? ''} ${video['vcodec']})';

  /// The tallest picture above 1080p within [settings]' cap in a codec they
  /// allow, with the AAC sound (140) or else the best other; null when
  /// [info] has none or the cap is 1080p or lower.
  static LiveSplit? pick(Map<String, dynamic> info, PlayerSettings settings) {
    final cap = settings.maxHeight;
    if (cap > 0 && cap <= 1080) return null;
    final formats = [for (final f in (info['formats'] as List? ?? const [])) if (f is Map<String, dynamic> && _fragmented(f)) f];
    final order = FormatPolicy.codecOrder(settings);
    int rank(VideoCodec? codec) {
      final i = codec == null ? -1 : order.indexOf(codec);
      return i < 0 ? order.length : i;
    }

    final videos = [
      for (final f in formats)
        if (f['acodec'] == 'none' && f['height'] is int && (f['height'] as int) > 1080 && (cap <= 0 || (f['height'] as int) <= cap))
          if (VideoCodec.of(f['vcodec']) case final codec? when FormatPolicy.allows(settings, codec)) f,
    ]..sort((a, b) {
        final byHeight = (b['height'] as int).compareTo(a['height'] as int);
        if (byHeight != 0) return byHeight;
        final byFps = _number(b['fps']).compareTo(_number(a['fps']));
        if (byFps != 0) return byFps;
        final byCodec = rank(VideoCodec.of(a['vcodec'])).compareTo(rank(VideoCodec.of(b['vcodec'])));
        if (byCodec != 0) return byCodec;
        return _number(b['tbr']).compareTo(_number(a['tbr']));
      });
    final audios = [
      for (final f in formats)
        if (f['vcodec'] == 'none' && f['acodec'] is String && f['acodec'] != 'none') f,
    ]..sort((a, b) {
        if (a['format_id'] == '140') return -1;
        if (b['format_id'] == '140') return 1;
        return _number(b['abr']).compareTo(_number(a['abr']));
      });
    if (videos.isEmpty || audios.isEmpty) return null;
    return LiveSplit(videos.first, audios.first);
  }

  /// A live address answering one fragment per `sq`: plain HTTPS, no
  /// manifest, no fragment list.
  static bool _fragmented(Map<String, dynamic> format) {
    final url = format['url'];
    if (format['protocol'] != 'https' || url is! String || format['manifest_url'] != null || format['fragments'] != null) return false;
    return Uri.tryParse(url)?.queryParameters['live'] == '1';
  }

  static num _number(Object? value) => value is num ? value : 0;
}
