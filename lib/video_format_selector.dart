import 'player_settings.dart';

class VideoFormatSelector {
  /// A yt-dlp format expression for [settings].
  ///
  /// Automatic selection prefers VP9 only after hardware decoding was
  /// verified, then H.264, which every Windows GPU decodes. AV1 is left out
  /// of automatic selection: it is the most expensive codec to decode and
  /// YouTube serves the same resolutions in VP9. A quality above 1080p asks
  /// for VP9 or AV1 first, because YouTube offers H.264 only up to 1080p.
  /// A chosen codec is asked for first and falls back like automatic mode.
  static String expressionFor(PlayerSettings settings) {
    final height = settings.maxHeight > 0 ? '[height<=?${settings.maxHeight}]' : '';
    final audio = switch (settings.audioQuality) {
      AudioQuality.best => 'bestaudio',
      AudioQuality.medium => 'bestaudio[abr<=?128]',
      AudioQuality.low => 'bestaudio[abr<=?64]',
    };
    if (settings.codec == CodecPreference.any) {
      return height.isEmpty && settings.audioQuality == AudioQuality.best ? 'ytdl' : 'bestvideo$height+$audio/best$height/best';
    }
    final codecs = codecOrder(settings);
    return [
      for (final codec in codecs) 'bestvideo[vcodec^=$codec]$height+$audio',
      'bestvideo$height+$audio',
      if (audio != 'bestaudio') 'bestvideo$height+bestaudio',
      'best$height',
      'best',
    ].join('/');
  }

  /// Video codecs to try, most preferred first, for [settings].
  static List<String> codecOrder(PlayerSettings settings) {
    final vp9Hardware = settings.decoderResults['vp9']?.isHardware ?? false;
    return switch (settings.codec) {
      CodecPreference.avc1 => ['avc1', if (settings.maxHeight > 1080 || settings.maxHeight == 0) 'vp9'],
      CodecPreference.vp9 => ['vp9', 'avc1'],
      CodecPreference.av01 => ['av01', 'vp9', 'avc1'],
      CodecPreference.any => ['vp9', 'av01', 'avc1'],
      _ => [
          if (vp9Hardware || settings.maxHeight > 1080) 'vp9',
          if (settings.maxHeight > 1080) 'av01',
          'avc1',
        ],
    };
  }
}
