import '../format_policy.dart';
import '../piped_streams.dart';
import '../player_settings.dart';

/// A single progressive address a TV can play without extra headers.
class CastSource {
  const CastSource(this.url, {this.mime = 'video/mp4', this.height = 0});
  final String url;
  final String mime;
  final int height;
}

/// TVs and Chromecasts decode H.264 up to 1080p everywhere; more is a gamble.
const _castMaxHeight = 1080;

bool _isH264(String codec) => codec.startsWith('avc1') || codec.startsWith('h264');

/// The best file of a yt-dlp extraction with picture and sound together and
/// no fragments (format 22 or 18 style): mp4, H.264 first, then the highest
/// picture up to 1080p, skipping codecs [settings] disables. Null when
/// YouTube lists none.
CastSource? castSourceFromYtDlp(Map<String, dynamic> info, {PlayerSettings? settings}) {
  final formats = info['formats'];
  if (formats is! List) return null;
  final candidates = <(int, int, int, String)>[];
  for (final f in formats.whereType<Map>()) {
    final url = f['url']?.toString() ?? '';
    final protocol = f['protocol']?.toString() ?? '';
    if (!url.startsWith('http') || !(protocol == 'https' || protocol == 'http') || f['fragments'] != null) continue;
    final video = f['vcodec']?.toString() ?? 'none';
    final audio = f['acodec']?.toString() ?? 'none';
    if (video == 'none' || audio == 'none' || f['ext'] != 'mp4') continue;
    if (settings != null && !FormatPolicy.allowsName(settings, video)) continue;
    final height = f['height'] is num ? (f['height'] as num).toInt() : 0;
    final bitrate = f['tbr'] is num ? (f['tbr'] as num).round() : 0;
    // Higher tuples are better: allowed height, then H.264, then size.
    candidates.add((height <= _castMaxHeight ? 1 : 0, _isH264(video) ? 1 : 0, height * 100000 + bitrate, url));
  }
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) {
    for (final (x, y) in [(b.$1, a.$1), (b.$2, a.$2), (b.$3, a.$3)]) {
      if (x != y) return x.compareTo(y);
    }
    return 0;
  });
  final best = candidates.first;
  return CastSource(best.$4, height: best.$3 ~/ 100000);
}

/// The best muxed mp4 stream of a Piped or Invidious answer, by the same rules.
CastSource? castSourceFromRelay(PipedVideo video, {PlayerSettings? settings}) {
  final muxed = [for (final s in video.muxed) if (settings == null || FormatPolicy.allowsName(settings, s.codec)) s];
  if (video.live || muxed.isEmpty) return null;
  final sorted = [...muxed]..sort((a, b) {
      int rank(PipedStream s) => (s.height <= _castMaxHeight ? 4000000 : 0) + (_isH264(s.codec) ? 2000000 : 0) + s.height * 1000 + s.bitrate ~/ 1000;
      return rank(b).compareTo(rank(a));
    });
  return CastSource(sorted.first.url, height: sorted.first.height);
}
