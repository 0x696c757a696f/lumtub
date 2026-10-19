import 'player_settings.dart';

class VideoFormatSelector {
  /// A yt-dlp format expression for [settings].
  ///
  /// VP9 is preferred only after hardware decoding was verified, then H.264,
  /// which every Windows GPU decodes. AV1 is left out of automatic selection:
  /// it is the most expensive codec to decode and YouTube serves the same
  /// resolutions in VP9. A quality above 1080p asks for VP9 or AV1 first,
  /// because YouTube offers H.264 only up to 1080p.
  static String expressionFor(PlayerSettings settings) {
    final height = settings.maxHeight > 0 ? '[height<=?${settings.maxHeight}]' : '';
    if (!settings.autoSelectCodec) {
      return height.isEmpty ? 'ytdl' : 'bestvideo$height+bestaudio/best$height/best';
    }
    final vp9Hardware = settings.decoderResults['vp9']?.isHardware ?? false;
    final codecs = [
      if (vp9Hardware || settings.maxHeight > 1080) 'vp9',
      if (settings.maxHeight > 1080) 'av01',
      'avc1',
    ];
    return [
      for (final codec in codecs) 'bestvideo[vcodec^=$codec]$height+bestaudio',
      'bestvideo$height+bestaudio',
      'best$height',
      'best',
    ].join('/');
  }
}
