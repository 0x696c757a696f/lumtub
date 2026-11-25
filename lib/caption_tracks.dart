import 'dart:convert';

/// One subtitle track a `/player` answer lists: YouTube's own address of
/// it, its language and whether YouTube made it from the audio (`asr`).
/// Translations are never listed here: YouTube offers them apart.
typedef CaptionTrack = ({String url, String language, bool automatic});

/// The fields of a `/player` answer [captionTracksOf] reads, for a field
/// mask.
const captionTrackFields = 'captions.playerCaptionsTracklistRenderer.captionTracks.baseUrl,'
    'captions.playerCaptionsTracklistRenderer.captionTracks.languageCode,captions.playerCaptionsTracklistRenderer.captionTracks.kind';

/// The subtitle tracks of a `/player` answer; none when it has none or
/// cannot be read. At most 200 are read.
List<CaptionTrack> captionTracksOf(List<int> bytes) {
  Object? json;
  try {
    json = jsonDecode(utf8.decode(bytes, allowMalformed: true));
  } catch (_) {
    return const [];
  }
  if (json is! Map) return const [];
  final captions = json['captions'];
  final renderer = captions is Map ? captions['playerCaptionsTracklistRenderer'] : null;
  final tracks = renderer is Map ? renderer['captionTracks'] : null;
  if (tracks is! List) return const [];
  return [
    for (final t in tracks.take(200))
      if (t is Map && t['baseUrl'] is String && t['languageCode'] is String && (t['baseUrl'] as String).length <= 4000 && (t['languageCode'] as String).length <= 35)
        (url: t['baseUrl'] as String, language: t['languageCode'] as String, automatic: t['kind'] == 'asr'),
  ];
}

/// The track of [tracks] in [language] (`zh` takes `zh-Hans` and
/// `zh-TW`): the uploader's first, else YouTube's automatic one.
CaptionTrack? captionTrackIn(List<CaptionTrack> tracks, String language) {
  bool ours(CaptionTrack t) => t.language == language || t.language.startsWith('$language-');
  return tracks.where((t) => ours(t) && !t.automatic).firstOrNull ?? tracks.where((t) => ours(t) && t.automatic).firstOrNull;
}

/// [track]'s address asking for WebVTT; null unless it is YouTube's own
/// timedtext address, so an answer cannot send the app anywhere else.
Uri? timedTextUrl(CaptionTrack track) {
  final raw = track.url;
  final url = Uri.tryParse(raw.startsWith('/') ? 'https://www.youtube.com$raw' : raw);
  if (url == null || url.scheme != 'https' || !(url.host == 'www.youtube.com' || url.host == 'youtube.com') || url.path != '/api/timedtext') return null;
  // Every value kept as given, repeated ones too; only the format is ours.
  return url.replace(queryParameters: {...url.queryParametersAll, 'fmt': 'vtt'});
}
