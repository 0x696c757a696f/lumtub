import 'player_settings.dart';

class VideoFormatSelector {
  /// A yt-dlp format expression for automatic playback only.
  ///
  /// Format selection happens before opening the URL. It never changes a
  /// manually selected track or resolution after playback has started.
  static String expressionFor(PlayerSettings settings) {
    if (!settings.autoSelectCodec) return 'ytdl';
    final av1Hardware = settings.decoderResults['av1']?.isHardware ?? false;
    final vp9Hardware = settings.decoderResults['vp9']?.isHardware ?? false;
    if (av1Hardware) {
      return 'bestvideo[vcodec^=av01]+bestaudio/bestvideo[vcodec^=vp9]+bestaudio/bestvideo[vcodec^=avc1]+bestaudio/best';
    }
    if (vp9Hardware) {
      return 'bestvideo[vcodec^=vp9]+bestaudio/bestvideo[vcodec^=avc1]+bestaudio/best';
    }
    return 'bestvideo[vcodec^=avc1]+bestaudio/best';
  }
}
