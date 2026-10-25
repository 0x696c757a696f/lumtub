import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'feed_quality.dart';
import 'library_store.dart' show WatchProgress;
import 'models.dart';
import 'native_core.dart';

/// Where a recommended video came from.
enum RecommendSource {
  /// Suggested by YouTube next to a video watched or kept.
  related(1.0),
  /// New from a followed channel.
  subscription(0.9),
  /// New from a channel watched often but not followed.
  channel(0.7),
  /// Popular in a topic the history is about.
  topic(0.5);

  const RecommendSource(this.weight);
  final double weight;
}

class Candidate {
  const Candidate(this.item, this.source, {this.seedWeight = 1, this.reason = ''});
  final VideoItem item;
  final RecommendSource source;
  /// How much the video it came from counts: recent and finished videos
  /// count more.
  final double seedWeight;
  /// Why it is suggested, shown on its card.
  final String reason;
}

/// A picked video and why.
class Recommendation {
  const Recommendation(this.item, this.reason);
  final VideoItem item;
  final String reason;
}

/// What the history says about taste, worked out on this computer only by
/// lumtub_core (native/lumtub_core/src/taste.rs): how much each channel is
/// watched (skipped videos count against it) and which words matter,
/// weighted TF-IDF style so words in every title count for little. Without
/// the library it knows nothing, and [recommend] keeps the sources' order.
class TasteProfile implements Finalizable {
  TasteProfile._(this._core, this._handle);

  final NativeCore? _core;
  final Pointer<Void> _handle;

  /// [searches] are the words typed into search, newest first.
  factory TasteProfile.from({
    required List<VideoItem> history,
    WatchProgress? Function(String id)? progressOf,
    List<VideoItem> favorites = const [],
    Set<String> followed = const {},
    List<String> searches = const [],
    double decay = 0.93,
  }) {
    final core = NativeCore.instance;
    if (core == null) return TasteProfile._(null, nullptr);
    final json = jsonEncode({
      'decay': decay,
      'history': [
        for (final item in history)
          {
            'k': channelKey(item),
            't': item.title,
            if (progressOf?.call(item.id) case final progress? when progress.duration > Duration.zero) ...{
              'f': progress.fraction,
              // Left within the first seconds.
              'skip': progress.fraction < 0.15 && progress.position < const Duration(seconds: 45),
            },
          },
      ],
      'favorites': [for (final item in favorites) {'k': channelKey(item), 't': item.title}],
      'followed': followed.toList(),
      'searches': searches,
    });
    final handle = core.withText(json, core.tasteNew);
    if (handle == nullptr) return TasteProfile._(null, nullptr);
    final taste = TasteProfile._(core, handle);
    core.tasteFinalizer.attach(taste, handle);
    return taste;
  }

  /// -1 to 1: how much [item]'s channel is watched, below 0 when mostly
  /// skipped.
  double channelAffinity(VideoItem item) {
    final core = _core;
    return core == null ? 0 : core.withText(channelKey(item), (bytes, length) => core.tasteAffinity(_handle, bytes, length));
  }

  /// 0 to 1: how close [item]'s title is to the history's words.
  double titleMatch(VideoItem item) {
    final core = _core;
    return core == null ? 0 : core.withText(item.title, (bytes, length) => core.tasteMatch(_handle, bytes, length));
  }

  /// The history's interest [item] belongs to most: its title word that
  /// weighs most in the history, if any weighs enough.
  String? interestOf(VideoItem item) {
    final core = _core;
    return core?.take(core.withText(item.title, (bytes, length) => core.tasteInterest(_handle, bytes, length)));
  }

  /// The channels watched most, most first.
  List<String> topChannels(int count) => _top(false, count);

  /// The words the history is most about, most first.
  List<String> topWords(int count) => _top(true, count);

  List<String> _top(bool words, int count) {
    final core = _core;
    final json = core?.take(core.tasteTop(_handle, words, count));
    return json == null ? [] : (jsonDecode(json) as List).cast<String>();
  }

  /// [index, reason index] pairs from lumtub_recommend, or null.
  List<(int, int)>? _rank(String json) {
    final core = _core;
    final answer = core?.take(core.withText(json, (bytes, length) => core.recommend(_handle, bytes, length)));
    if (answer == null) return null;
    return [for (final pair in jsonDecode(answer) as List) ((pair as List)[0] as int, pair[1] as int)];
  }

  static String channelKey(VideoItem item) => item.channelId ?? 'name:${item.channel}';

  /// Latin words of three letters or more, and pairs of neighbouring
  /// Chinese, Japanese or Korean characters, which stand in for words.
  static Set<String> titleWords(String title) {
    final core = NativeCore.instance;
    final json = core?.take(core.withText(title, core.titleWords));
    return json == null ? {} : (jsonDecode(json) as List).cast<String>().toSet();
  }
}

/// The four parts of the home feed, B 站-style, and their share of it.
/// Each ranks its videos with its own weights.
enum FeedLane {
  /// What the whole history keeps coming back to.
  longTerm(0.35, RankWeights(channel: 0.8, title: 0.6, fresh: 0.3, views: 0.3)),
  /// What the last few videos were about; follows the latest watch.
  recent(0.30, RankWeights(channel: 0.5, title: 0.9, fresh: 0.3, views: 0.2)),
  /// Near the interests but from channels not watched yet.
  explore(0.20, RankWeights(channel: 0, title: 0.3, fresh: 0.2, views: 0.5, novelty: 0.5)),
  /// New and popular now.
  fresh(0.15, RankWeights(channel: 0.3, title: 0.2, fresh: 1.2, views: 0.6));

  const FeedLane(this.share, this.weights);
  final double share;
  final RankWeights weights;
}

/// How much each signal counts when ranking.
class RankWeights {
  const RankWeights({this.channel = 0.8, this.title = 0.6, this.fresh = 0.5, this.views = 0.3, this.novelty = 0});
  final double channel;
  final double title;
  final double fresh;
  final double views;
  /// For channels the history has never seen.
  final double novelty;
}

/// Takes from [lanes] in proportion to their [FeedLane.share]: each slot
/// goes to the lane furthest behind its share, skipping empty ones and
/// videos already taken. Returns at most [count]; the lanes are consumed.
List<Recommendation> mixLanes(Map<FeedLane, List<Recommendation>> lanes, int count, {Set<String>? taken, Map<FeedLane, int>? placed}) {
  final seen = taken ?? <String>{};
  final counts = placed ?? {for (final lane in FeedLane.values) lane: 0};
  final result = <Recommendation>[];
  while (result.length < count) {
    final total = counts.values.fold(0, (a, b) => a + b) + 1;
    FeedLane? next;
    var behind = double.negativeInfinity;
    for (final lane in FeedLane.values) {
      final queue = lanes[lane];
      if (queue == null) continue;
      while (queue.isNotEmpty && seen.contains(queue.first.item.id)) {
        queue.removeAt(0);
      }
      if (queue.isEmpty) continue;
      final gap = lane.share * total - (counts[lane] ?? 0);
      if (gap > behind) {
        behind = gap;
        next = lane;
      }
    }
    if (next == null) break;
    final pick = lanes[next]!.removeAt(0);
    seen.add(pick.item.id);
    counts.update(next, (v) => v + 1, ifAbsent: () => 1);
    result.add(pick);
  }
  return result;
}

/// Videos and channels marked 不感兴趣, kept on this computer.
class NotInterested {
  NotInterested(this.file);
  final File? file;
  final videos = <String>{};
  final channels = <String, int>{};

  Future<void> load() async {
    final file = this.file;
    if (file == null) return;
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is! Map) return;
      for (final id in data['videos'] is List ? data['videos'] as List : const []) {
        if (id is String) videos.add(id);
      }
      final map = data['channels'];
      if (map is Map) {
        for (final entry in map.entries) {
          if (entry.key is String && entry.value is int) channels[entry.key as String] = entry.value as int;
        }
      }
    } catch (_) {}
  }

  Future<void> add(VideoItem item) async {
    videos.add(item.id);
    final key = TasteProfile.channelKey(item);
    channels.update(key, (v) => v + 1, ifAbsent: () => 1);
    // Keep the newest few hundred.
    while (videos.length > 500) {
      videos.remove(videos.first);
    }
    await _save();
  }

  Future<void> clear() async {
    videos.clear();
    channels.clear();
    await _save();
  }

  Future<void> _save() async {
    final file = this.file;
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({'videos': videos.toList(), 'channels': channels}));
    } catch (_) {}
  }
}

/// Orders [candidates] for the home page, like a video site's feed: videos
/// near what was watched, from channels watched often, fresh and popular.
/// Near the top no channel and no interest repeats much, and a little
/// chance is mixed in so the feed does not narrow. [seed] changes the
/// chance for 换一批. [mix] drops or ranks down the kinds of video the
/// settings want less of.
List<Recommendation> recommend(
  List<Candidate> candidates, {
  required TasteProfile taste,
  Set<String> exclude = const {},
  NotInterested? notInterested,
  int count = 24,
  int seed = 0,
  DateTime? now,
  RankWeights weights = const RankWeights(),
  FeedMix mix = const FeedMix(),
}) {
  final clock = now ?? DateTime.now();
  final kept = <Candidate>[];
  final rows = <Map<String, Object>>[];
  for (final candidate in candidates) {
    final item = candidate.item;
    if (exclude.contains(item.id) || (notInterested?.videos.contains(item.id) ?? false) || item.isUpcoming) continue;
    final penalty = mix.penaltyOf(item);
    if (penalty == null) continue;
    final key = TasteProfile.channelKey(item);
    kept.add(candidate);
    rows.add({
      'id': item.id,
      'k': key,
      't': item.title,
      's': candidate.source.weight * candidate.seedWeight,
      'p': penalty + 0.6 * (notInterested?.channels[key] ?? 0),
      if (item.published case final published?) 'a': clock.difference(published).inHours,
      if (item.viewCount case final views?) 'v': views,
      if (item.duration case final duration?) 'd': duration,
    });
  }
  final picks = taste._rank(jsonEncode({
    'candidates': rows,
    'weights': {'channel': weights.channel, 'title': weights.title, 'fresh': weights.fresh, 'views': weights.views, 'novelty': weights.novelty},
    'count': count,
    'seed': seed,
  }));
  if (picks != null) return [for (final (video, reason) in picks) Recommendation(kept[video].item, kept[reason].reason)];
  final seen = <String>{};
  return [
    for (final candidate in kept)
      if (seen.add(candidate.item.id)) Recommendation(candidate.item, candidate.reason),
  ].take(count).toList();
}
