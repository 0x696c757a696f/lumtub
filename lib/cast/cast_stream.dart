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

/// A picture stream and a sound stream the app joins for a TV
/// (native/lumtub_core/src/cast.rs): fragmented MP4 files with an index.
class CastSplit {
  const CastSplit({required this.video, required this.videoSize, required this.audio, required this.audioSize, required this.height});
  final String video;
  final int videoSize;
  final String audio;
  final int audioSize;
  final int height;
}

int _sizeOf(Map f) {
  if (f['filesize'] is num) return (f['filesize'] as num).toInt();
  final clen = Uri.tryParse(f['url']?.toString() ?? '')?.queryParameters['clen'];
  return int.tryParse(clen ?? '') ?? 0;
}

/// The best H.264 picture up to 1080p (30 fps rather than more at the same
/// height, which older TVs cannot decode) and the main AAC sound of a
/// yt-dlp extraction, as plain https MP4 files of known size. Null when
/// YouTube lists no such pair or [settings] disable H.264.
CastSplit? castSplitFromYtDlp(Map<String, dynamic> info, {PlayerSettings? settings}) {
  final formats = info['formats'];
  if (formats is! List) return null;
  bool plain(Map f) => (f['url']?.toString() ?? '').startsWith('https://') && f['protocol'] == 'https' && f['fragments'] == null && f['has_drm'] != true;
  Map? video;
  (int, int, int)? best;
  Map? audio;
  (int, int, int)? bestAudio;
  for (final f in formats.whereType<Map>()) {
    if (!plain(f) || _sizeOf(f) <= 0) continue;
    final v = f['vcodec']?.toString() ?? 'none';
    final a = f['acodec']?.toString() ?? 'none';
    if (a == 'none' && _isH264(v) && f['ext'] == 'mp4') {
      if (settings != null && !FormatPolicy.allowsName(settings, v)) continue;
      final height = f['height'] is num ? (f['height'] as num).toInt() : 0;
      final fps = f['fps'] is num ? (f['fps'] as num).round() : 30;
      if (height <= 0 || height > _castMaxHeight) continue;
      final rank = (height, fps <= 30 ? 1 : 0, f['tbr'] is num ? (f['tbr'] as num).round() : 0);
      if (best == null || _beats(rank, best)) (video, best) = (f, rank);
    } else if (v == 'none' && a.startsWith('mp4a') && (f['ext'] == 'm4a' || f['ext'] == 'mp4')) {
      final note = '${f['format_note'] ?? ''} ${f['format_id'] ?? ''}'.toLowerCase();
      if (note.contains('drc')) continue;
      final language = f['language_preference'] is num ? (f['language_preference'] as num).toInt() : 0;
      final abr = f['abr'] is num ? (f['abr'] as num).round() : 0;
      // The original or default track first, then about 128 kbit/s AAC LC.
      final rank = (language, abr <= 160 ? 1 : 0, abr);
      if (bestAudio == null || _beats(rank, bestAudio)) (audio, bestAudio) = (f, rank);
    }
  }
  if (video == null || audio == null) return null;
  return CastSplit(
    video: video['url'] as String,
    videoSize: _sizeOf(video),
    audio: audio['url'] as String,
    audioSize: _sizeOf(audio),
    height: (video['height'] as num).toInt(),
  );
}

bool _beats((int, int, int) a, (int, int, int) b) => a.$1 != b.$1 ? a.$1 > b.$1 : a.$2 != b.$2 ? a.$2 > b.$2 : a.$3 > b.$3;
