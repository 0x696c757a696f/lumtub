/// Decides when a video that stopped because of the network is reopened at
/// the same position, and when to give up and show the error.
class PlaybackRecovery {
  PlaybackRecovery({this.maxAttempts = 3, this.window = const Duration(minutes: 2), DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final int maxAttempts;
  final Duration window;
  final DateTime Function() _clock;
  final _attempts = <DateTime>[];
  Duration? _position;
  DateTime? _observedAt;
  DateTime? _advancedAt;
  Duration _progress = Duration.zero;

  bool get awaitingProgress => _position != null;
  bool get stalled => awaitingProgress && _clock().difference(_advancedAt!) >= stallTimeout;

  /// How long buffering may stall during playback before reconnecting.
  static const stallTimeout = Duration(seconds: 20);

  /// Whether another attempt is allowed now; records it if so. Attempts
  /// older than [window] no longer count, so a long video can recover from
  /// several separate outages.
  bool tryAttempt({Duration position = Duration.zero}) {
    final now = _clock();
    _attempts.removeWhere((time) => now.difference(time) > window);
    if (_attempts.length >= maxAttempts) return false;
    _attempts.add(now);
    _position = position;
    _observedAt = now;
    _advancedAt = now;
    _progress = Duration.zero;
    return true;
  }

  /// Opening or seeking to the resume point is not playback. Count only
  /// decoded, advancing playback; a seek starts the observation again.
  bool observeProgress(Duration position, {required bool playing, required bool buffering, required bool decoded, double rate = 1}) {
    final previous = _position;
    if (previous == null) return false;
    final now = _clock();
    final elapsed = now.difference(_observedAt!);
    final advance = position - previous;
    _position = position;
    _observedAt = now;
    final maximumAdvance = Duration(microseconds: (elapsed.inMicroseconds * rate).round()) + const Duration(milliseconds: 500);
    if (!playing || buffering || !decoded || advance < Duration.zero || advance > maximumAdvance) {
      _progress = Duration.zero;
      return false;
    }
    if (advance == Duration.zero) return false;
    _advancedAt = now;
    _progress += advance;
    if (_progress < const Duration(seconds: 10)) return false;
    reset();
    return true;
  }

  void cancelPending() {
    _position = null;
    _observedAt = null;
    _advancedAt = null;
    _progress = Duration.zero;
  }

  void reset() {
    _attempts.clear();
    cancelPending();
  }

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

  // DXGI_ERROR_DEVICE_REMOVED, _HUNG and _RESET.
  static final _deviceLost = RegExp(r'\b887a000[567]\b', caseSensitive: false);

  /// Whether an mpv log line says the graphics device went away, as after
  /// a driver reset: hardware-decoded frames can no longer reach the
  /// picture, which then flickers or freezes until the output is made again.
  static bool graphicsLost(String text) => text.contains('Mapping hardware decoded surface failed') || _deviceLost.hasMatch(text);
}

/// Where to reopen a video after its stream failed. mpv that can no longer
/// read a stream may jump to its end before it reports the video finished;
/// the place before that jump is where the viewer was.
class ResumePoint {
  ResumePoint({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  Duration _position = Duration.zero;
  DateTime? _observedAt;
  Duration? _beforeJump;
  DateTime? _jumpedAt;

  /// How long after a jump a failure is still taken to have caused it.
  static const window = Duration(seconds: 15);

  /// The last position seen, jump or not.
  Duration get current => _position;

  /// Where playback was before a recent jump forward, else [current].
  Duration get beforeFailure {
    final jumpedAt = _jumpedAt;
    if (jumpedAt == null || _clock().difference(jumpedAt) > window) return _position;
    return _beforeJump!;
  }

  void start(Duration position) {
    _position = position;
    _observedAt = null;
    _beforeJump = null;
    _jumpedAt = null;
  }

  void observe(Duration position, {double rate = 1}) {
    final now = _clock();
    final observedAt = _observedAt;
    if (observedAt != null) {
      final elapsed = now.difference(observedAt);
      final allowed = Duration(microseconds: (elapsed.inMicroseconds * rate).round()) + const Duration(seconds: 2);
      final jumpedAt = _jumpedAt;
      final recentJump = jumpedAt != null && now.difference(jumpedAt) <= window;
      // A seek by the viewer looks the same; within [window] the earliest
      // place counts, so a failure soon after a seek resumes before it.
      if (position - _position > allowed && !recentJump) {
        _beforeJump = _position;
        _jumpedAt = now;
      }
    }
    _position = position;
    _observedAt = now;
  }
}
