import 'dart:math' as math;

/// 音量平衡: evens out loudness between videos and within one, as a chain
/// in libmpv's audio filters.
///
/// Between videos it uses the loudness YouTube measured for each one
/// (`playerConfig.audioConfig.loudnessDb`, how far it is above YouTube's
/// reference level): a quiet video is raised, a loud one lowered, before
/// anything else. Within a video a slow dynamic normaliser lifts quiet
/// passages and holds loud ones back; the strength sets how far it may go
/// and how quickly it follows. A limiter last keeps raised peaks from
/// clipping. Gains go through `alimiter`'s input level rather than the
/// `volume` filter, which some libmpv builds leave out.
abstract final class VolumeBalance {
  /// The label of the chain in mpv's audio filters.
  static const label = 'lumtub_balance';

  /// The most a video is raised or lowered to meet the others, in dB.
  static const maxBoost = 9.0;
  static const maxCut = 12.0;

  /// The gain in dB that brings a video YouTube measured at [loudnessDb]
  /// to the reference level.
  static double gainFor(double loudnessDb) => (-loudnessDb).clamp(-maxCut, maxBoost);

  /// What `af add` takes for [strength] (1 to 100), with YouTube's
  /// [loudnessDb] for the video when known. A livestream follows faster,
  /// as it has no whole to measure. [withLimiters] false leaves out the
  /// `alimiter` stages, for a libmpv without them.
  static String filter(int strength, {double? loudnessDb, bool live = false, bool withLimiters = true}) {
    final s = strength.clamp(1, 100) / 100;
    // A wider Gaussian window follows more slowly: gentle at low strength.
    final window = _odd((61 - 50 * s).round());
    final maxGain = (1 + 9 * s).toStringAsFixed(1);
    final frame = live ? 150 : 400;
    final stages = [
      if (withLimiters && loudnessDb != null && gainFor(loudnessDb).abs() >= 0.5) 'alimiter=level_in=${_linear(gainFor(loudnessDb))}:limit=1:level=0',
      'dynaudnorm=f=$frame:g=$window:m=$maxGain:p=0.95:r=0.2',
      if (withLimiters) 'alimiter=limit=0.95:level=0:attack=5:release=60',
    ];
    return '@$label:lavfi=[${stages.join(',')}]';
  }

  static int _odd(int n) => n.isOdd ? n : n + 1;

  /// [db] as alimiter's linear input level (0.016 to 64).
  static String _linear(double db) => math.pow(10, db / 20).clamp(0.016, 64).toStringAsFixed(3);

  /// YouTube's measured loudness from a `/player` answer, read without
  /// decoding the whole answer.
  static double? loudnessIn(String playerAnswer) {
    final match = RegExp(r'"loudnessDb"\s*:\s*(-?[0-9]+(?:\.[0-9]+)?)').firstMatch(playerAnswer);
    return match == null ? null : double.tryParse(match[1]!);
  }
}
