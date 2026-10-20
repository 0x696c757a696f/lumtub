import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'feed_quality.dart';
import 'library_store.dart' show WatchProgress;
import 'models.dart';

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

/// What the history says about taste, worked out on this computer only:
/// how much each channel is watched (skipped videos count against it) and
/// which words matter, weighted TF-IDF style so words in every title count
/// for little.
class TasteProfile {
  TasteProfile._(this.channels, this.words, this._idf, this._defaultIdf);

  /// Channel id (or name, when the id is unknown) to affinity; negative
  /// for channels mostly skipped.
  final Map<String, double> channels;
  /// Word to interest, already multiplied by the word's IDF.
  final Map<String, double> words;
  final Map<String, double> _idf;
  final double _defaultIdf;
  late final double _wordsNorm = sqrt(words.values.fold(0.0, (sum, v) => sum + v * v));
  late final double _maxChannel = channels.values.fold(0.0, max);

  /// [searches] are the words typed into search, newest first.
  factory TasteProfile.from({
    required List<VideoItem> history,
    WatchProgress? Function(String id)? progressOf,
    List<VideoItem> favorites = const [],
    Set<String> followed = const {},
    List<String> searches = const [],
    double decay = 0.93,
  }) {
    final channels = <String, double>{};
    final documents = <(Set<String>, double)>[];
    for (final (i, item) in history.indexed) {
      final progress = progressOf?.call(item.id);
      final recency = pow(decay, i).toDouble();
      final known = progress != null && progress.duration > Duration.zero;
      // Left within the first seconds: a sign against, not for.
      if (known && progress.fraction < 0.15 && progress.position < const Duration(seconds: 45)) {
        channels.update(channelKey(item), (v) => v - 0.5 * recency, ifAbsent: () => -0.5 * recency);
        continue;
      }
      final weight = recency * (0.3 + 0.7 * (known ? progress.fraction : 0.5));
      channels.update(channelKey(item), (v) => v + weight, ifAbsent: () => weight);
      documents.add((titleWords(item.title), weight));
    }
    for (final item in favorites) {
      channels.update(channelKey(item), (v) => v + 1, ifAbsent: () => 1);
      documents.add((titleWords(item.title), 1));
    }
    for (final (i, query) in searches.take(20).indexed) {
      documents.add((titleWords(query), 0.6 * pow(0.9, i)));
    }
    for (final id in followed) {
      channels.update(id, (v) => v + 1.5, ifAbsent: () => 1.5);
    }
    final count = documents.length;
    final df = <String, int>{};
    for (final (words, _) in documents) {
      for (final word in words) {
        df.update(word, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    double idfOf(int seen) => log((count + 1) / (seen + 1)) + 1;
    final idf = {for (final entry in df.entries) entry.key: idfOf(entry.value)};
    final words = <String, double>{};
    for (final (titleWords, weight) in documents) {
      for (final word in titleWords) {
        words.update(word, (v) => v + weight * idf[word]!, ifAbsent: () => weight * idf[word]!);
      }
    }
    return TasteProfile._(channels, words, idf, idfOf(0));
  }

  /// -1 to 1: how much [item]'s channel is watched, below 0 when mostly
  /// skipped.
  double channelAffinity(VideoItem item) {
    final top = _maxChannel;
    final value = channels[channelKey(item)] ?? 0;
    if (value < 0) return max(-1, value);
    return top <= 0 ? 0 : value / top;
  }

  /// 0 to 1: the cosine between [item]'s title and the history's words.
  double titleMatch(VideoItem item) {
    if (_wordsNorm == 0) return 0;
    var dot = 0.0;
    var norm = 0.0;
    for (final word in titleWords(item.title)) {
      final idf = _idf[word] ?? _defaultIdf;
      dot += (words[word] ?? 0) * idf;
      norm += idf * idf;
    }
    if (norm == 0) return 0;
    // Short titles against a long history give small cosines; scaled up so
    // a clear match reaches about 1.
    return min(1, 3 * dot / (_wordsNorm * sqrt(norm)));
  }

  /// The history's interest [item] belongs to most: its title word that
  /// weighs most in the history, if any weighs enough.
  String? interestOf(VideoItem item) {
    String? best;
    var bestWeight = 0.0;
    final top = words.values.fold(0.0, max);
    for (final word in titleWords(item.title)) {
      final weight = words[word] ?? 0;
      if (weight > bestWeight) {
        bestWeight = weight;
        best = word;
      }
    }
    return top > 0 && bestWeight >= 0.2 * top ? best : null;
  }

  /// The channels watched most, most first.
  List<String> topChannels(int count) =>
      (channels.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value))).take(count).map((e) => e.key).toList();

  /// The words the history is most about, most first.
  List<String> topWords(int count) =>
      (words.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(count).map((e) => e.key).toList();

  static String channelKey(VideoItem item) => item.channelId ?? 'name:${item.channel}';

  static const _stopWords = {
    'the', 'and', 'for', 'with', 'you', 'your', 'this', 'that', 'from', 'are', 'was', 'how', 'what', 'why', 'who',
    'official', 'video', 'videos', 'full', 'new', 'live', 'episode', 'part', 'feat', 'ft', 'vs', 'amp', 'mv',
    'hd', '4k', '1080p', 'shorts', 'channel',
  };

  /// Latin words of three letters or more, and pairs of neighbouring
  /// Chinese, Japanese or Korean characters, which stand in for words.
  static Set<String> titleWords(String title) {
    final lower = title.toLowerCase();
    final result = <String>{};
    for (final match in RegExp(r'[a-z][a-z0-9]{2,}').allMatches(lower)) {
      final word = match.group(0)!;
      if (!_stopWords.contains(word)) result.add(word);
    }
    for (final run in RegExp(r'[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]{2,}').allMatches(title)) {
      final text = run.group(0)!;
      for (var i = 0; i + 1 < text.length; i++) {
        result.add(text.substring(i, i + 2));
      }
    }
    return result;
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
  final random = Random(seed);
  final byId = <String, ({VideoItem item, double score, String reason})>{};
  for (final candidate in candidates) {
    final item = candidate.item;
    if (exclude.contains(item.id) || (notInterested?.videos.contains(item.id) ?? false) || item.isUpcoming) continue;
    final penalty = mix.penaltyOf(item);
    if (penalty == null) continue;
    var score = candidate.source.weight * candidate.seedWeight - penalty;
    final affinity = taste.channelAffinity(item);
    score += weights.channel * affinity;
    if (!taste.channels.containsKey(TasteProfile.channelKey(item))) score += weights.novelty;
    // A channel mostly skipped stays down whatever the lane.
    if (affinity < 0 && weights.channel == 0) score += 0.8 * affinity;
    score += weights.title * taste.titleMatch(item);
    final published = item.published;
    if (published != null) score += weights.fresh * exp(-clock.difference(published).inHours / (24 * 7));
    final views = item.viewCount;
    if (views != null && views > 0) score += weights.views * min(1, log(views) / ln10 / 7);
    final duration = item.duration;
    // Shorts and very long videos fit a home page less.
    if (duration != null && duration < 60) score -= 0.3;
    if (duration != null && duration > 3 * 3600) score -= 0.2;
    score -= 0.6 * (notInterested?.channels[TasteProfile.channelKey(item)] ?? 0);
    final known = byId[item.id];
    if (known == null) {
      byId[item.id] = (item: item, score: score, reason: candidate.reason);
    } else {
      // Suggested from more than one place: a stronger sign. The stronger
      // source gives the reason.
      byId[item.id] = (item: known.item, score: max(known.score, score) + 0.3, reason: score > known.score ? candidate.reason : known.reason);
    }
  }
  final pool = [
    for (final entry in byId.values)
      (item: entry.item, score: entry.score + random.nextDouble() * 0.35, reason: entry.reason, interest: taste.interestOf(entry.item)),
  ];
  final picked = <Recommendation>[];
  final perChannel = <String, int>{};
  final perInterest = <String, int>{};
  while (picked.length < count && pool.isNotEmpty) {
    var best = 0;
    var bestScore = double.negativeInfinity;
    for (final (i, entry) in pool.indexed) {
      final interest = entry.interest;
      final score = entry.score -
          0.45 * (perChannel[TasteProfile.channelKey(entry.item)] ?? 0) -
          (interest == null ? 0 : 0.2 * (perInterest[interest] ?? 0));
      if (score > bestScore) {
        bestScore = score;
        best = i;
      }
    }
    final chosen = pool.removeAt(best);
    picked.add(Recommendation(chosen.item, chosen.reason));
    perChannel.update(TasteProfile.channelKey(chosen.item), (v) => v + 1, ifAbsent: () => 1);
    if (chosen.interest case final interest?) perInterest.update(interest, (v) => v + 1, ifAbsent: () => 1);
  }
  return picked;
}
