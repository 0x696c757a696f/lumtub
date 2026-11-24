part of 'app_controller.dart';

/// One sorted list and what it was worked out from: asked again with the
/// same inputs it is handed back as it is, so a rebuild sorts nothing.
class _Sorted<T> {
  _Sorted(this.key, this.value);
  final Object key;
  final List<T> value;
}

final _sortCache = Expando<Map<String, _Sorted<Object?>>>('sorted');

/// The order of 订阅分组, followed channels, playlists and each playlist's
/// videos: the sort chosen for each, and lists already in that order.
extension OrderActions on AppController {
  Map<String, _Sorted<Object?>> get _sorts => _sortCache[this] ??= {};

  /// [build]'s answer for [name], worked out again only when [key] changed.
  List<T> _memo<T>(String name, Object key, List<T> Function() build) {
    final kept = _sorts[name];
    if (kept != null && kept.key == key && kept.value is List<T>) return kept.value as List<T>;
    final value = build();
    _sorts[name] = _Sorted<Object?>(key, value);
    // A playlist page per id: keep the cache from growing with every list
    // ever opened.
    if (_sorts.length > 64) _sorts.remove(_sorts.keys.first);
    return value;
  }

  /// The 订阅分组 in the order chosen for them.
  List<ChannelGroup> get orderedGroups {
    final library = this.library;
    if (library == null) return const [];
    final order = preferences.groupOrder;
    return _memo('groups', (library.revision, identityHashCode(library.feed), order), () => orderGroups(library.channelGroups, order, rank: order == GroupOrder.recent ? _feedRank : const {}));
  }

  /// [channels] (all followed channels, or one group's) in the order chosen
  /// for them; [key] names the subset, so each keeps its own answer.
  List<ChannelRef> orderedChannels(List<ChannelRef> channels, {Object? key}) {
    final library = this.library;
    if (library == null) return channels;
    final order = preferences.channelOrder;
    final history = order == ChannelOrder.watched ? this.history : const <VideoItem>[];
    return _memo(
      'channels',
      (library.revision, identityHashCode(library.feed), order, key, channels.length, history.length, history.firstOrNull?.id),
      () => orderChannels(
        channels,
        order,
        rank: order == ChannelOrder.recent ? _feedRank : const {},
        watched: order == ChannelOrder.watched ? countByChannel(history) : const {},
        live: order == ChannelOrder.recent ? library.liveChannels : const {},
      ),
    );
  }

  /// Each channel's place in the subscriptions feed, worked out once per
  /// change of the library.
  Map<String, int> get _feedRank {
    final library = this.library!;
    final kept = _sorts['rank'];
    final key = (library.revision, identityHashCode(library.feed));
    if (kept != null && kept.key == key) return kept.value.single! as Map<String, int>;
    final rank = rankInFeed(library.feed);
    _sorts['rank'] = _Sorted<Object?>(key, [rank]);
    return rank;
  }

  /// The user's playlists in the order chosen for them.
  List<LocalPlaylist> get orderedPlaylists {
    final library = this.library;
    if (library == null) return const [];
    final order = preferences.playlistOrder;
    return _memo('playlists', (library.revision, order), () => orderPlaylists(library.playlists, order));
  }

  /// The order chosen for playlist [id]'s videos.
  VideoOrder videoOrder(String id) => preferences.videoOrders[id] ?? VideoOrder.added;

  /// The videos of 收藏, 稍后观看 or playlist [id], as stored.
  List<VideoItem>? savedVideos(String id) {
    final library = this.library;
    if (library == null) return null;
    if (id == AppController.favoritesPlaylistId) return library.favorites;
    if (id == AppController.watchLaterPlaylistId) return library.watchLater;
    return library.playlist(id)?.items;
  }

  /// Playlist [id]'s [items] in the order chosen for it, before 倒序.
  List<VideoItem> orderedVideos(String id, List<VideoItem> items) {
    final order = videoOrder(id);
    if (order == VideoOrder.added) return items;
    return _memo('videos:$id', (library?.revision, order, items.length, identityHashCode(items)), () => orderVideos(items, order));
  }

  Future<void> setGroupOrder(GroupOrder order) => savePreferences(preferences.copyWith(groupOrder: order));

  Future<void> setChannelOrder(ChannelOrder order) => savePreferences(preferences.copyWith(channelOrder: order));

  Future<void> setPlaylistOrder(PlaylistOrder order) => savePreferences(preferences.copyWith(playlistOrder: order));

  /// Shows and plays playlist [id] in [order]; the playlist playing now
  /// follows at once.
  Future<void> setVideoOrder(String id, VideoOrder order) async {
    final orders = {...preferences.videoOrders}..remove(id);
    if (order != VideoOrder.added) orders[id] = order;
    await savePreferences(preferences.copyWith(videoOrders: orders));
    _followOrder(id);
  }

  /// Keeps 收藏, 稍后观看 or playlist [id] in the order the user dragged
  /// its videos into, and shows it in that order from then on.
  Future<void> arrangeVideos(String id, List<VideoItem> order) async {
    final saved = savedVideos(id);
    if (saved == null) return;
    library!.arrangeVideos(saved, order);
    if (videoOrder(id) != VideoOrder.added || isReversed(id)) {
      final orders = {...preferences.videoOrders}..remove(id);
      await savePreferences(preferences.copyWith(videoOrders: orders, reversedPlaylists: [for (final other in preferences.reversedPlaylists) if (other != id) other]));
    }
    _followOrder(id);
  }

  /// The playing list, when it is [id], takes the order now chosen for it.
  void _followOrder(String id) {
    final list = playingList;
    final saved = savedVideos(id);
    if (list == null || list.id != id || saved == null) return;
    final items = List<VideoItem>.unmodifiable(orderedVideos(id, saved));
    _update(() {
      playingList = PlayingList(id: id, title: list.title, items: items, reversed: isReversed(id));
      queue = List.unmodifiable(playingList!.ordered);
    });
  }
}
