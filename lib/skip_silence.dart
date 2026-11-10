/// Plays silent stretches faster. libmpv has no skip-silence of its own, so
/// an ffmpeg `silencedetect` filter is added to the audio chain and mpv's
/// `af-metadata` for it is read; the speed goes up while it reports silence
/// and returns to the viewer's at its end.
class SilenceSkipper {
  SilenceSkipper({this.boost = 4.0});

  /// The label of the filter in mpv's audio chain.
  static const label = 'lumtub_silence';

  /// The mpv property holding what the filter last reported.
  static const property = 'af-metadata/$label';

  /// What `af add` takes: quieter than -30 dB for half a second is silence.
  static const filter = '@$label:lavfi=[silencedetect=n=-30dB:d=0.5]';

  /// The speed during silence.
  final double boost;

  /// Whether silence is being skipped.
  bool enabled = false;

  /// The speed the viewer chose, which silence returns to.
  double userRate = 1.0;

  bool _boosted = false;

  /// Whether the speed is raised for silence now.
  bool get boosted => _boosted;

  /// Starts skipping, with [rate] as the viewer's speed.
  void enable(double rate) {
    enabled = true;
    userRate = rate;
    _boosted = false;
  }

  /// Stops skipping; the speed to go back to when it was raised, else null.
  double? disable() {
    final back = _boosted ? userRate : null;
    enabled = false;
    _boosted = false;
    return back;
  }

  /// A new video starts at speed [rate], not in silence.
  void reset(double rate) {
    userRate = rate;
    _boosted = false;
  }

  /// Whether [text], mpv's `af-metadata` for the filter, says silence
  /// started (true), ended (false) or says neither (null). The text is
  /// matched by its keys, so JSON or mpv's plain listing both read.
  static bool? silenceIn(String text) {
    if (text.contains('silence_end')) return false;
    if (text.contains('silence_start')) return true;
    return null;
  }

  /// [text] from the filter: the speed to set, or null to leave it.
  double? onMetadata(String text) {
    if (!enabled) return null;
    switch (silenceIn(text)) {
      case true:
        if (_boosted || userRate >= boost) return null;
        _boosted = true;
        return boost;
      case false:
        if (!_boosted) return null;
        _boosted = false;
        return userRate;
      case null:
        return null;
    }
  }

  /// mpv reports speed [rate]. True when the viewer chose it, so it is
  /// theirs to keep; false when it is only what this class set.
  bool observeRate(double rate) {
    if (!enabled) {
      userRate = rate;
      return true;
    }
    if (rate == boost) return false;
    if (_boosted) {
      if (rate == userRate) return false;
      _boosted = false;
    }
    userRate = rate;
    return true;
  }
}
