import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app_log.dart';
import '../feed_quality.dart';
import '../library_store.dart' show WatchProgress;
import '../models.dart';
import '../recommendations.dart';
import '../l10n/l10n.dart';

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
    this.searches = const [],
    this.youtubeHome,
  });

  final List<VideoItem> history;
  final WatchProgress? Function(String id)? progressOf;
  final List<VideoItem> favorites;
  final List<ChannelRef> followed;
  /// The followed channels' newest videos, already loaded.
  final List<VideoItem> subscriptions;
  /// Words searched for, newest first; they count as interests.
  final List<String> searches;
  /// The signed-in account's own YouTube home feed; null when signed out.
  final Future<List<VideoItem>> Function()? youtubeHome;
  /// YouTube's suggestions next to a video.
  final Future<List<VideoItem>> Function(String videoId) related;
  /// A channel's newest videos.
  final Future<List<VideoItem>> Function(ChannelRef channel) channelUploads;
  /// This week's popular videos about a few words.
  final Future<List<VideoItem>> Function(String query) search;
}

/// The home page's 为你推荐, a B 站-style feed: four lanes (long-term
/// interests, recent interests, exploration, new and popular) gathered from
/// YouTube's suggestions, channels and searches, each ranked by
/// [recommend] and mixed by [mixLanes] in their shares. It scrolls on
/// without end, and a video watched a while ago changes what comes next.
/// All of it is worked out on this computer; nothing about the history
/// leaves it beyond the requests a watch page would make anyway.
class HomeFeed extends ChangeNotifier {
  HomeFeed(this.notInterested, {this.cacheFile});

  final NotInterested notInterested;
  /// Where the last first pages are kept, to show at once on the next launch.
  final File? cacheFile;

  /// How many sources load at once.
  static const maxConcurrentSources = 3;
  /// The first page is shown once this many sources answered, or after
  /// [firstPageWait], instead of after the slowest search.
  static const firstPageSources = 4;
  static const firstPageWait = Duration(seconds: 3);
  /// Videos kept in [cacheFile].
  static const cachedItems = pageSize * 2;

  /// Which kinds of video to show less of; set from the settings.
  FeedMix mix = const FeedMix();

  /// The feed so far, newest page last.
  List<VideoItem> items = const [];
  /// Why each of [items] is suggested, by video id.
  Map<String, String> reasons = const {};
  bool loading = false;
  /// The first page is shown but slower sources are still answering.
  bool gathering = false;
  /// Gathering more for the end of the feed.
  bool loadingMore = false;
  String? error;
  DateTime? loadedAt;

  static const pageSize = 24;

  final _candidates = <FeedLane, List<Candidate>>{};
  /// Ranked videos not shown yet, per lane.
  final _queues = <FeedLane, List<Recommendation>>{};
  final _placed = <FeedLane, int>{};
  /// Every video shown, watched or dismissed: never shown again.
  final _taken = <String>{};
  /// Videos whose suggestions were already asked for.
  final _expanded = <String>{};
  TasteProfile? _longTaste;
  TasteProfile? _recentTaste;
  HomeFeedSources? _sources;
  List<VideoItem> Function(List<VideoItem>)? _filter;
  int _seed = 0;
  int _generation = 0;
  bool _disposed = false;

  /// Whether this launch gathered the feed, rather than only restoring
  /// the last one, which has nothing more to show.
  bool get gathered => _longTaste != null;

  bool get stale => loadedAt == null || DateTime.now().difference(loadedAt!) > const Duration(minutes: 30);

  /// Shows the feed saved by the last launch while a new one is gathered;
  /// [filter] drops what was hidden since.
  Future<void> restore({List<VideoItem> Function(List<VideoItem>)? filter}) async {
    final file = cacheFile;
    if (file == null || items.isNotEmpty) return;
    try {
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final saved = [
        for (final entry in data['items'] as List? ?? const [])
          if (entry is Map<String, dynamic>) VideoItem.fromJson(entry),
      ].where((item) => !notInterested.videos.contains(item.id)).toList();
      if (_disposed || items.isNotEmpty || saved.isEmpty) return;
      items = filter?.call(saved) ?? saved;
      reasons = {for (final MapEntry(:key, :value) in (data['reasons'] as Map? ?? const {}).entries) '$key': '$value'};
      _notify();
    } catch (_) {
      // No feed saved yet, or an unreadable one: gather as usual.
    }
  }

  Future<void> _save() async {
    final file = cacheFile;
    if (file == null || items.isEmpty) return;
    final kept = items.take(cachedItems).toList();
    try {
      await file.parent.create(recursive: true);
      final partial = File('${file.path}.partial');
      await partial.writeAsString(jsonEncode({
        'items': [for (final item in kept) item.toJson()],
        'reasons': {for (final item in kept) if (reasons[item.id] != null) item.id: reasons[item.id]},
      }));
      await partial.rename(file.path);
    } catch (e) {
      logInfo('Could not save the recommendation cache: $e');
    }
  }

  /// Gathers everything again; [filter] drops blocked or hidden videos.
  /// With [keep], the videos shown stay and new ones follow them.
  Future<void> refresh(HomeFeedSources sources, {List<VideoItem> Function(List<VideoItem>)? filter, bool keep = false}) async {
    final generation = ++_generation;
    _sources = sources;
    _filter = filter;
    loading = true;
    error = null;
    _notify();
    _learnTastes(sources);
    final long = _longTaste!;
    final followed = {for (final c in sources.followed) c.id};
    final candidates = <FeedLane, List<Candidate>>{for (final lane in FeedLane.values) lane: []};
    final jobs = <Future<void>>[];
    var failures = 0;
    var answered = 0;
    final enough = Completer<void>();
    // Searches each start a yt-dlp process; a dozen at once pegs the CPU.
    var running = 0;
    final waiting = <Completer<void>>[];
    Future<void> gather(FeedLane lane, Future<List<VideoItem>> Function() load, RecommendSource source, double weight, int limit, String Function(VideoItem item) reason) async {
      while (running >= maxConcurrentSources) {
        final turn = Completer<void>();
        waiting.add(turn);
        await turn.future;
      }
      running++;
      try {
        final found = await load();
        candidates[lane]!.addAll(found.take(limit).map((item) => Candidate(item, source, seedWeight: weight, reason: reason(item))));
      } catch (e) {
        failures++;
        logInfo('Recommendation source failed: $e');
      } finally {
        running--;
        answered++;
        if (answered >= firstPageSources && !enough.isCompleted) enough.complete();
        if (waiting.isNotEmpty) waiting.removeAt(0).complete();
      }
    }

    final now = DateTime.now();
    for (final item in sources.subscriptions.take(80)) {
      final isNew = item.published != null && now.difference(item.published!) < const Duration(hours: 48);
      candidates[isNew ? FeedLane.fresh : FeedLane.longTerm]!.add(Candidate(item, RecommendSource.subscription, reason: isNew ? tr('你关注的 {0} 刚更新', [item.channel]) : tr('你关注的 {0}', [item.channel])));
    }
    // What YouTube itself suggests to the signed-in account.
    if (sources.youtubeHome case final home?) {
      jobs.add(gather(FeedLane.longTerm, home, RecommendSource.related, 1, 40, (_) => tr('YouTube 为你推荐')));
    }
    // Recent: what the last few videos and the newest search were about.
    for (final (i, seed) in sources.history.take(3).indexed) {
      _expanded.add(seed.id);
      jobs.add(gather(FeedLane.recent, () => sources.related(seed.id), RecommendSource.related, 1 - i * 0.1, 15, (_) => tr('看过《{0}》的人也在看', [_short(seed.title)])));
    }
    // Long-term: older favourites and the channels watched most.
    final kept = <VideoItem>[...sources.favorites.take(3), ...sources.history.skip(3).take(3)];
    for (final seed in kept) {
      if (!_expanded.add(seed.id)) continue;
      jobs.add(gather(FeedLane.longTerm, () => sources.related(seed.id), RecommendSource.related, 0.8, 10, (_) => tr('和你喜欢的《{0}》相似', [_short(seed.title)])));
    }
    var channels = 0;
    for (final key in long.topChannels(10)) {
      if (channels >= 3 || key.startsWith('name:') || followed.contains(key)) continue;
      final name = sources.history.where((item) => item.channelId == key).firstOrNull?.channel ?? '';
      channels++;
      jobs.add(gather(FeedLane.longTerm, () => sources.channelUploads(ChannelRef(key, name)), RecommendSource.channel, 1, 8, (item) => tr('你常看 {0}', [item.channel.isEmpty ? name : item.channel])));
    }
    // Searches each start yt-dlp and take seconds: after the HTTP sources.
    if (sources.searches.isNotEmpty) {
      final query = sources.searches.first;
      jobs.add(gather(FeedLane.recent, () => sources.search(query), RecommendSource.topic, 0.9, 10, (_) => tr('你最近搜过“{0}”', [query])));
    }
    // Explore: the interests past the strongest few.
    final words = long.topWords(10);
    for (var i = 4; i + 1 < words.length && i < 8; i += 2) {
      final query = '${words[i]} ${words[i + 1]}';
      jobs.add(gather(FeedLane.explore, () => sources.search(query), RecommendSource.topic, 1, 10, (_) => tr('探索：“{0}”', [query])));
    }
    // New and popular: this week's most watched about the main interest,
    // and in general.
    if (words.length >= 2) {
      final query = '${words[0]} ${words[1]}';
      jobs.add(gather(FeedLane.fresh, () => sources.search(query), RecommendSource.topic, 1, 10, (_) => tr('“{0}”本周热门', [query])));
    }
    jobs.add(gather(FeedLane.fresh, () => sources.search('热门'), RecommendSource.topic, 0.8, 12, (_) => tr('本周热门')));
    final all = Future.wait(jobs);
    // Show a first page as soon as there is enough for one; the rest of the
    // sources are ranked in as they answer and fill the pages after it.
    final wait = Timer(firstPageWait, () {
      if (!enough.isCompleted) enough.complete();
    });
    await Future.any([all, enough.future]);
    wait.cancel();
    if (generation != _generation || _disposed) return;
    if (candidates.values.every((list) => list.isEmpty)) await all;
    if (generation != _generation || _disposed) return;
    // The same lists keep filling from the sources still running.
    _candidates
      ..clear()
      ..addAll(candidates);
    _taken
      ..clear()
      ..addAll(sources.history.map((item) => item.id));
    _placed.clear();
    _seed = 0;
    if (keep) {
      _taken.addAll(items.map((item) => item.id));
    } else {
      items = const [];
      reasons = const {};
    }
    _rankAll();
    _appendPage();
    loading = false;
    loadedAt = DateTime.now();
    gathering = true;
    _notify();
    await all;
    if (generation != _generation || _disposed) return;
    gathering = false;
    _rankAll();
    if (items.length < pageSize) _appendPage();
    if (items.isEmpty && failures > 0 && failures == jobs.length) error = tr('推荐来源都没有响应');
    _notify();
    unawaited(_save());
    // Explore a step further from what was just shown.
    unawaited(_expand());
  }

  /// The next page at the end of the feed, gathering more first when the
  /// lanes run low.
  Future<void> loadMore() async {
    if (loading || loadingMore || _longTaste == null) return;
    if (_remaining < pageSize) {
      loadingMore = true;
      _notify();
      await _expand();
      loadingMore = false;
    }
    _appendPage();
    _notify();
  }

  /// 换一批: a new first page, picked with different chance, without the
  /// videos just shown.
  void shuffle({List<VideoItem> Function(List<VideoItem>)? filter}) {
    if (_longTaste == null) return;
    _filter = filter ?? _filter;
    _taken.addAll(items.map((item) => item.id));
    _seed++;
    _placed.clear();
    items = const [];
    reasons = const {};
    _rankAll();
    _appendPage();
    if (items.isEmpty) {
      // Out of new videos: start over with all of them.
      _taken.clear();
      _rankAll();
      _appendPage();
    }
    _notify();
    if (_remaining < pageSize) unawaited(_expand());
  }

  /// Learns from a video just watched for a while: its suggestions go to
  /// the top of the recent lane, and the next videos shown follow it. A
  /// video left within seconds counts against its channel instead.
  Future<void> learn(VideoItem watched, HomeFeedSources sources, {required bool skipped}) async {
    if (_longTaste == null) return;
    _sources = sources;
    _taken.add(watched.id);
    _learnTastes(sources);
    if (!skipped && _expanded.add(watched.id)) {
      try {
        final found = await sources.related(watched.id);
        if (_disposed) return;
        final list = _candidates.putIfAbsent(FeedLane.recent, () => []);
        list.insertAll(0, found.take(15).map((item) => Candidate(item, RecommendSource.related, seedWeight: 1.2, reason: tr('刚看完《{0}》，接着看', [_short(watched.title)]))));
      } catch (e) {
        logInfo('Recommendation source failed: $e');
      }
    }
    _rankAll();
    // Put a few of the newest suggestions at the top of the feed.
    if (!skipped) {
      final next = (_queues[FeedLane.recent] ?? []).where((r) => !_taken.contains(r.item.id)).take(4).toList();
      if (next.isNotEmpty) {
        final videos = _filter?.call(next.map((r) => r.item).toList()) ?? next.map((r) => r.item).toList();
        _taken.addAll(next.map((r) => r.item.id));
        items = [...videos, ...items];
        reasons = {...reasons, for (final r in next) r.item.id: r.reason};
      }
    }
    _notify();
  }

  /// Hides [item] now and counts against its channel from now on.
  Future<void> dismiss(VideoItem item) async {
    items = items.where((other) => other.id != item.id).toList();
    _taken.add(item.id);
    _notify();
    await notInterested.add(item);
  }

  int get _remaining => _queues.values.fold(0, (sum, queue) => sum + queue.where((r) => !_taken.contains(r.item.id)).length);

  void _learnTastes(HomeFeedSources sources) {
    final followed = {for (final c in sources.followed) c.id};
    _longTaste = TasteProfile.from(
      history: sources.history,
      progressOf: sources.progressOf,
      favorites: sources.favorites,
      followed: followed,
      searches: sources.searches,
      decay: 0.97,
    );
    _recentTaste = TasteProfile.from(
      history: sources.history.take(10).toList(),
      progressOf: sources.progressOf,
      searches: sources.searches.take(3).toList(),
      decay: 0.7,
    );
  }

  void _rankAll() {
    for (final lane in FeedLane.values) {
      final taste = lane == FeedLane.recent ? _recentTaste! : _longTaste!;
      _queues[lane] = recommend(
        _candidates[lane] ?? const [],
        taste: taste,
        exclude: _taken,
        notInterested: notInterested,
        count: 200,
        seed: _seed * 31 + lane.index,
        weights: lane.weights,
        mix: mix,
      );
    }
  }

  void _appendPage() {
    final page = mixLanes(_queues, pageSize, taken: _taken, placed: _placed);
    final videos = page.map((r) => r.item).toList();
    final shown = _filter?.call(videos) ?? videos;
    items = [...items, ...shown];
    reasons = {...reasons, for (final r in page) r.item.id: r.reason};
  }

  /// Asks for the suggestions next to a few videos already shown, so the
  /// feed can go on: close ones feed the recent lane, the rest explore.
  Future<void> _expand() async {
    final sources = _sources;
    if (sources == null) return;
    final seeds = items.reversed.where((item) => !_expanded.contains(item.id)).take(4).toList();
    if (seeds.isEmpty) return;
    final generation = _generation;
    await Future.wait(seeds.map((seed) async {
      _expanded.add(seed.id);
      try {
        final found = await sources.related(seed.id);
        if (generation != _generation) return;
        final close = (_recentTaste?.titleMatch(seed) ?? 0) > 0.3;
        _candidates.putIfAbsent(close ? FeedLane.recent : FeedLane.explore, () => []).addAll(found.take(12).map(
              (item) => Candidate(item, RecommendSource.related, seedWeight: 0.7, reason: tr('由《{0}》延伸', [_short(seed.title)])),
            ));
      } catch (e) {
        logInfo('Recommendation source failed: $e');
      }
    }));
    if (generation != _generation || _disposed) return;
    _rankAll();
  }

  static String _short(String title) => title.length > 24 ? '${title.substring(0, 24)}…' : title;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
