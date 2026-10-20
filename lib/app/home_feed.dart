import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app_log.dart';
import '../library_store.dart' show WatchProgress;
import '../models.dart';
import '../recommendations.dart';

/// Where [HomeFeed] gathers videos from; each may fail on its own.
class HomeFeedSources {
  const HomeFeedSources({
    required this.history,
    required this.related,
    required this.channelUploads,
    required this.search,
    this.progressOf,
    this.favorites = const [],
    this.followed = const [],
    this.subscriptions = const [],
  });

  final List<VideoItem> history;
  final WatchProgress? Function(String id)? progressOf;
  final List<VideoItem> favorites;
  final List<ChannelRef> followed;
  /// The followed channels' newest videos, already loaded.
  final List<VideoItem> subscriptions;
  /// YouTube's suggestions next to a video.
  final Future<List<VideoItem>> Function(String videoId) related;
  /// A channel's newest videos.
  final Future<List<VideoItem>> Function(ChannelRef channel) channelUploads;
  /// This week's popular videos about a few words.
  final Future<List<VideoItem>> Function(String query) search;
}

/// The home page's 为你推荐: videos gathered from what was watched and
/// followed, then ordered by [recommend]. All of it is worked out on this
/// computer; nothing about the history leaves it beyond the requests a
/// watch page would make anyway.
class HomeFeed extends ChangeNotifier {
  HomeFeed(this.notInterested);

  final NotInterested notInterested;

  List<VideoItem> items = const [];
  bool loading = false;
  String? error;
  DateTime? loadedAt;
  List<Candidate> _candidates = const [];
  TasteProfile? _taste;
  Set<String> _exclude = const {};
  int _seed = 0;
  int _generation = 0;
  bool _disposed = false;

  /// How many videos the history's seeds, channels and topics each give.
  static const relatedSeeds = 6;
  static const channelSeeds = 3;
  static const topicSeeds = 2;

  bool get stale => loadedAt == null || DateTime.now().difference(loadedAt!) > const Duration(minutes: 30);

  /// Gathers videos again; [filter] drops blocked or hidden ones.
  Future<void> refresh(HomeFeedSources sources, {List<VideoItem> Function(List<VideoItem>)? filter}) async {
    final generation = ++_generation;
    loading = true;
    error = null;
    _notify();
    final taste = TasteProfile.from(
      history: sources.history,
      progressOf: sources.progressOf,
      favorites: sources.favorites,
      followed: {for (final c in sources.followed) c.id},
    );
    final followed = {for (final c in sources.followed) c.id};
    final candidates = <Candidate>[
      for (final item in sources.subscriptions.take(60)) Candidate(item, RecommendSource.subscription),
    ];
    final jobs = <Future<void>>[];
    var failures = 0;
    Future<void> gather(Future<List<VideoItem>> Function() load, RecommendSource source, double weight, int limit) async {
      try {
        final found = await load();
        candidates.addAll(found.take(limit).map((item) => Candidate(item, source, seedWeight: weight)));
      } catch (e) {
        failures++;
        logInfo('推荐来源失败：$e');
      }
    }

    // Seeds: the newest videos watched, then kept ones.
    final seeds = <VideoItem>[...sources.history.take(relatedSeeds), ...sources.favorites.take(2)];
    for (final (i, seed) in seeds.indexed) {
      final weight = (1 - i * 0.08).clamp(0.4, 1.0);
      jobs.add(gather(() => sources.related(seed.id), RecommendSource.related, weight, 12));
    }
    var channels = 0;
    for (final key in taste.topChannels(10)) {
      if (channels >= channelSeeds || key.startsWith('name:') || followed.contains(key)) continue;
      final name = sources.history.firstWhere((item) => item.channelId == key, orElse: () => VideoItem(id: '', title: '', channel: '', url: '')).channel;
      channels++;
      jobs.add(gather(() => sources.channelUploads(ChannelRef(key, name)), RecommendSource.channel, 1, 8));
    }
    final words = taste.topWords(topicSeeds * 2);
    for (var i = 0; i + 1 < words.length && i < topicSeeds * 2; i += 2) {
      final query = '${words[i]} ${words[i + 1]}';
      jobs.add(gather(() => sources.search(query), RecommendSource.topic, 1, 10));
    }
    // Nothing watched or followed yet: start from what is popular.
    if (jobs.isEmpty && candidates.isEmpty) jobs.add(gather(() => sources.search('热门'), RecommendSource.topic, 1, 24));
    await Future.wait(jobs);
    if (generation != _generation || _disposed) return;
    _taste = taste;
    _candidates = candidates;
    _exclude = {
      for (final item in sources.history) item.id,
    };
    _seed = 0;
    _rank(filter);
    loading = false;
    loadedAt = DateTime.now();
    if (items.isEmpty && failures > 0 && failures == jobs.length && candidates.isEmpty) error = '推荐来源都没有响应';
    _notify();
  }

  /// 换一批: the same videos, picked with different chance and without
  /// the ones just shown.
  void shuffle({List<VideoItem> Function(List<VideoItem>)? filter}) {
    if (_taste == null) return;
    _exclude = {..._exclude, for (final item in items) item.id};
    _seed++;
    _rank(filter);
    // Out of new videos: start over with all of them.
    if (items.isEmpty) {
      _exclude = const {};
      _rank(filter);
    }
    _notify();
  }

  /// Hides [item] now and counts against its channel from now on.
  Future<void> dismiss(VideoItem item) async {
    items = items.where((other) => other.id != item.id).toList();
    _notify();
    await notInterested.add(item);
  }

  void _rank(List<VideoItem> Function(List<VideoItem>)? filter) {
    final ranked = recommend(_candidates, taste: _taste!, exclude: _exclude, notInterested: notInterested, count: 48, seed: _seed);
    items = (filter?.call(ranked) ?? ranked).take(24).toList();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
