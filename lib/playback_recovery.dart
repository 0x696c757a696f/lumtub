/// Decides when a video that stopped because of the network is reopened at
/// the same position, and when to give up and show the error.
class PlaybackRecovery {
  PlaybackRecovery({this.maxAttempts = 3, this.window = const Duration(minutes: 2), DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final int maxAttempts;
  final Duration window;
  final DateTime Function() _clock;
  final _attempts = <DateTime>[];

  /// How long buffering may stall during playback before reconnecting.
  static const stallTimeout = Duration(seconds: 20);

  /// Whether another attempt is allowed now; records it if so. Attempts
  /// older than [window] no longer count, so a long video can recover from
  /// several separate outages.
  bool tryAttempt() {
    final now = _clock();
    _attempts.removeWhere((time) => now.difference(time) > window);
    if (_attempts.length >= maxAttempts) return false;
    _attempts.add(now);
    return true;
  }

  void reset() => _attempts.clear();

  /// mpv reaches the end of a stream it can no longer read as if the video
  /// had finished; a real ending is within a few seconds of the duration.
  static bool endedEarly(Duration position, Duration duration) =>
      duration > const Duration(seconds: 30) && position > Duration.zero && position < duration - const Duration(seconds: 5);

  static final _network = RegExp(
    r'http|tcp|tls|ssl|network|connection|connect|timed? ?out|failed to open|unreachable|host|403|404|410|5\d\d|stream ended',
    caseSensitive: false,
  );

  /// Errors from reading the stream, as opposed to a broken subtitle or
  /// filter, which leave the video playing.
  static bool isNetworkError(String message) => !message.toLowerCase().contains('sub') && _network.hasMatch(message);
}
