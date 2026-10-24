import 'models.dart';

/// How much of a kind of video 为你推荐 shows.
enum FeedLevel {
  /// Not touched.
  off,
  /// Ranked far down, so only strong matches show.
  reduce,
  /// Left out.
  drop;

  static FeedLevel parse(Object? raw, FeedLevel fallback) {
    for (final level in values) {
      if (level.name == raw) return level;
    }
    return fallback;
  }
}

/// The kinds of video For You can show less of, and how much less.
class FeedMix {
  const FeedMix({this.shorts = FeedLevel.off, this.vertical = FeedLevel.off});
  final FeedLevel shorts;
  final FeedLevel vertical;

  /// Score taken off a video of a reduced kind; a good match scores about
  /// 2 to 4, so this pushes it below nearly everything else.
  static const reducePenalty = 2.5;

  /// The score to take off [item], or null when it is left out.
  double? penaltyOf(VideoItem item) {
    var penalty = 0.0;
    for (final (level, matches) in [
      (shorts, isShort),
      (vertical, isVertical),
    ]) {
      if (level == FeedLevel.off || !matches(item)) continue;
      if (level == FeedLevel.drop) return null;
      penalty += reducePenalty;
    }
    return penalty;
  }
}

/// A Short: a /shorts/ address, a minute or less, or up to three minutes
/// tagged #shorts.
bool isShort(VideoItem item) {
  if (item.isShortListing || item.url.contains('/shorts/')) return true;
  final seconds = item.duration;
  if (seconds == null || seconds <= 0) return false;
  return seconds <= 60 || (seconds <= 180 && RegExp(r'#shorts?\b', caseSensitive: false).hasMatch('${item.title} ${item.description ?? ''}'));
}

/// Taller than wide, when the frame size is known.
bool isVertical(VideoItem item) {
  final width = item.width;
  final height = item.height;
  return width != null && height != null && width > 0 && height > width;
}
