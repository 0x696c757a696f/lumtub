import 'dart:convert';

import 'models.dart';
import 'native_core.dart';

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
/// tagged #shorts (native/lumtub_core/src/filter.rs). Without the library
/// nothing counts as one.
bool isShort(VideoItem item) {
  final core = NativeCore.instance;
  if (core == null) return false;
  // Feeds rank and filter the same videos again on every refresh and rebuild.
  if (_shorts.length > 20000) _shorts.clear();
  return _shorts[Object.hash(item.id, item.url, item.title, item.description, item.duration, item.isShortListing)] ??= _askCore(core, item);
}

final _shorts = <int, bool>{};

bool _askCore(NativeCore core, VideoItem item) {
  final json = jsonEncode({
    'u': item.url,
    't': '${item.title} ${item.description ?? ''}',
    if (item.duration case final seconds?) 'd': seconds,
    'l': item.isShortListing,
  });
  return core.withText(json, core.isShort);
}

/// Taller than wide, when the frame size is known.
bool isVertical(VideoItem item) {
  final width = item.width;
  final height = item.height;
  return width != null && height != null && width > 0 && height > width;
}
