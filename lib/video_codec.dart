/// Video codec families, matched from the codec names yt-dlp, Piped and
/// Invidious report (`av01.0.08M.08`, `vp09.00.51.08`, `vp9`, `avc1.640028`).
///
/// Shared by the playback format policy and the download dialog, so both
/// read a codec the same way.
enum VideoCodec {
  av1('AV1', ['av01', 'av1']),
  vp9('VP9', ['vp09', 'vp9']),
  h264('H.264', ['avc1', 'avc3', 'h264']),
  vp8('VP8', ['vp08', 'vp8']);

  const VideoCodec(this.label, this.prefixes);
  final String label;
  /// Lower-case name prefixes that mean this codec.
  final List<String> prefixes;

  /// The family of [name], or null for audio-only (`none`), missing or
  /// unknown codecs.
  static VideoCodec? of(Object? name) {
    final codec = name?.toString().toLowerCase().trim() ?? '';
    if (codec.isEmpty || codec == 'none') return null;
    for (final c in values) {
      if (c.prefixes.any(codec.startsWith)) return c;
    }
    return null;
  }

  static VideoCodec? byName(Object? name) => values.where((c) => c.name == name).firstOrNull;

  /// The codecs YouTube offers at every quality; one of them must stay
  /// enabled, or no video plays.
  static const main = {av1, vp9, h264};

  /// Whether some video can still play with [disabled] disabled.
  static bool playableWithout(Set<VideoCodec> disabled) => !disabled.containsAll(main);

  /// yt-dlp filters keeping only formats of this codec, e.g. `[vcodec~='^(vp09|vp9)']`.
  String get onlyFilter => "[vcodec~='^(${prefixes.join('|')})']";

  /// yt-dlp filters dropping this codec, one per name prefix.
  String get excludeFilter => [for (final p in prefixes) '[vcodec!^=$p]'].join();
}

/// 1080p, or 1080p60 for more than 30 frames a second, as YouTube writes it.
/// A portrait video ([aspect], width over height, below 1) is named by its
/// width, as YouTube names it: 1080×1920 is 1080p, not 1920p.
String heightLabel(int height, [num? fps, String p = 'p', double? aspect]) {
  final size = aspect != null && aspect > 0 && aspect < 1 ? shortSide(height, aspect) : height;
  return fps != null && fps > 30.5 ? '$size$p${fps.round()}' : '$size$p';
}

/// The width of a portrait picture [height] tall, snapped to the usual
/// sizes it is near (YouTube's 1080×1920 may come as 1080×1918).
int shortSide(int height, double aspect) {
  final width = (height * aspect).round();
  for (final usual in const [144, 240, 360, 480, 720, 1080, 1440, 2160, 4320]) {
    if ((width - usual).abs() <= usual * 0.04) return usual;
  }
  return width;
}
