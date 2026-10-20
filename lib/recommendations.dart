import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
  const Candidate(this.item, this.source, {this.seedWeight = 1});
  final VideoItem item;
  final RecommendSource source;
  /// How much the video it came from counts: recent and finished videos
  /// count more.
  final double seedWeight;
}

/// What the watch history says about taste: how much each channel is
/// watched and which words the titles share. Built on this computer only.
class TasteProfile {
  TasteProfile._(this.channels, this.words);

  /// Channel id (or name, when the id is unknown) to affinity.
  final Map<String, double> channels;
  final Map<String, double> words;

  factory TasteProfile.from({
    required List<VideoItem> history,
    WatchProgress? Function(String id)? progressOf,
    List<VideoItem> favorites = const [],
    Set<String> followed = const {},
  }) {
    final channels = <String, double>{};
    final words = <String, double>{};
    void count(VideoItem item, double weight) {
      channels.update(channelKey(item), (v) => v + weight, ifAbsent: () => weight);
      for (final word in titleWords(item.title)) {
        words.update(word, (v) => v + weight, ifAbsent: () => weight);
      }
    }

    for (final (i, item) in history.indexed) {
      final progress = progressOf?.call(item.id);
      // Finished videos say more than ones left after a few seconds.
      final watched = progress == null || progress.duration <= Duration.zero ? 0.5 : progress.fraction;
      count(item, pow(0.93, i) * (0.3 + 0.7 * watched));
    }
    for (final item in favorites) {
      count(item, 1);
    }
    for (final id in followed) {
      channels.update(id, (v) => v + 1.5, ifAbsent: () => 1.5);
    }
    return TasteProfile._(channels, words);
  }

  double get _maxChannel => channels.values.fold(0.0, max);

  /// 0 to 1: how much [item]'s channel is watched.
  double channelAffinity(VideoItem item) {
    final top = _maxChannel;
    return top <= 0 ? 0 : (channels[channelKey(item)] ?? 0) / top;
  }

  /// 0 to 1: how much [item]'s title shares words with the history.
  double titleMatch(VideoItem item) {
    if (words.isEmpty) return 0;
    final top = words.values.fold(0.0, max);
    var sum = 0.0;
    for (final word in titleWords(item.title)) {
      sum += (words[word] ?? 0) / top;
    }
    return min(1, sum / 3);
  }

  /// The channels watched most, most first.
  List<String> topChannels(int count) =>
      (channels.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(count).map((e) => e.key).toList();

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
    for (final run in RegExp(r'[぀-ヿ㐀-鿿가-힯]{2,}').allMatches(title)) {
      final text = run.group(0)!;
      for (var i = 0; i + 1 < text.length; i++) {
        result.add(text.substring(i, i + 2));
      }
    }
    return result;
  }
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
/// near what was watched, from channels watched often, fresh and popular,
/// with no more than a few from one channel near the top and a little
/// chance mixed in so the feed does not narrow. [seed] changes the chance
/// for 换一批.
List<VideoItem> recommend(
  List<Candidate> candidates, {
  required TasteProfile taste,
  Set<String> exclude = const {},
  NotInterested? notInterested,
  int count = 24,
  int seed = 0,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final random = Random(seed);
  final byId = <String, ({VideoItem item, double score, int sources})>{};
  for (final candidate in candidates) {
    final item = candidate.item;
    if (exclude.contains(item.id) || (notInterested?.videos.contains(item.id) ?? false) || item.isUpcoming) continue;
    var score = candidate.source.weight * candidate.seedWeight;
    score += 0.8 * taste.channelAffinity(item);
    score += 0.6 * taste.titleMatch(item);
    final published = item.published;
    if (published != null) score += 0.5 * exp(-clock.difference(published).inHours / (24 * 7));
    final views = item.viewCount;
    if (views != null && views > 0) score += 0.3 * min(1, log(views) / ln10 / 7);
    final duration = item.duration;
    // Shorts and very long videos fit a home page less.
    if (duration != null && duration < 60) score -= 0.3;
    if (duration != null && duration > 3 * 3600) score -= 0.2;
    score -= 0.6 * (notInterested?.channels[TasteProfile.channelKey(item)] ?? 0);
    final known = byId[item.id];
    if (known == null) {
      byId[item.id] = (item: item, score: score, sources: 1);
    } else {
      // Suggested from more than one place: a stronger sign.
      byId[item.id] = (item: known.item, score: max(known.score, score) + 0.3, sources: known.sources + 1);
    }
  }
  final pool = [for (final entry in byId.values) (item: entry.item, score: entry.score + random.nextDouble() * 0.35)];
  final picked = <VideoItem>[];
  final perChannel = <String, int>{};
  while (picked.length < count && pool.isNotEmpty) {
    var best = 0;
    var bestScore = double.negativeInfinity;
    for (final (i, entry) in pool.indexed) {
      final score = entry.score - 0.45 * (perChannel[TasteProfile.channelKey(entry.item)] ?? 0);
      if (score > bestScore) {
        bestScore = score;
        best = i;
      }
    }
    final chosen = pool.removeAt(best).item;
    picked.add(chosen);
    perChannel.update(TasteProfile.channelKey(chosen), (v) => v + 1, ifAbsent: () => 1);
  }
  return picked;
}
