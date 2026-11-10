part of 'app_controller.dart';

/// The play queue, the previous and next video, and playlist order.
extension QueueActions on AppController {
  /// Plays the next video in the queue, if there is one.
  Future<void> playNext({bool keepMini = false}) async {
    if (await playQueued(null, keepMini)) return;
    final next = upNext;
    final suggestions = relatedItems;
    if (next.isNotEmpty) {
      await play(next.first, keepMini: keepMini);
    } else if (suggestions.isNotEmpty) {
      await play(suggestions.first, from: suggestions, keepMini: keepMini);
    }
  }

  @visibleForTesting
  Future<void> playAfterEndForTest() => _playAfterEnd();

  /// 下一个播放: [item] goes to the front of [playQueue].
  void queueNext(VideoItem item) {
    _update(() => playQueue.addNext(item));
    _notice(tr('Will play after the current video'));
  }

  /// 加入播放队列: [item] goes to the end of [playQueue].
  void queueLast(VideoItem item) {
    final added = playQueue.addLast(item);
    _update(() {});
    _notice(added ? tr('Added to the play queue') : tr('The play queue already has this video'));
  }

  void removeQueued(String id) => _update(() => playQueue.remove(id));

  void clearQueue() => _update(playQueue.clear);

  void moveQueued(int from, int to) => _update(() => playQueue.move(from, to));

  /// Plays [item], or the first of [playQueue], and takes it off the queue.
  /// The list the current video came from carries on after the queued ones.
  /// False when there was nothing to play.
  Future<bool> playQueued([VideoItem? item, bool keepMini = false]) async {
    final next = item ?? playQueue.items.firstOrNull;
    if (next == null) return false;
    _update(() => playQueue.remove(next.id));
    final at = playing == null ? -1 : queue.indexWhere((other) => other.id == playing!.id);
    final rest = [for (final other in queue) if (other.id != next.id) other];
    final from = at < 0 ? null : [...rest.take(at + 1), next, ...rest.skip(at + 1)];
    await play(next, from: from, keepMini: keepMini);
    return true;
  }

  /// The video before the current one in the queue, if it was opened from one.
  VideoItem? get previousInQueue {
    final current = playing;
    if (current == null) return null;
    final index = queue.indexWhere((item) => item.id == current.id);
    return index > 0 ? queue[index - 1] : null;
  }

  /// Plays the video that was playing before this one, or else the one
  /// before it in the list it was opened from.
  Future<void> playPrevious() async {
    if (_played.isEmpty) {
      if (previousInQueue case final previous?) await play(previous);
      return;
    }
    final item = _played.removeLast();
    await play(item);
    // play() noted the video left behind; going back is not a new step.
    if (_played.isNotEmpty && _played.last.id == item.id) _played.removeLast();
  }

  /// Related videos that pass the content filters.
  List<VideoItem> get relatedItems => visible(related?.items ?? const []);

  /// Whether playlist [id] is shown and played last to first.
  bool isReversed(String id) => preferences.reversedPlaylists.contains(id);

  /// Shows and plays playlist [id] last to first, or in its own order; the
  /// playlist playing now follows at once.
  Future<void> setReversed(String id, bool reversed) async {
    final ids = [for (final other in preferences.reversedPlaylists) if (other != id) other, if (reversed) id];
    final list = playingList;
    if (list != null && list.id == id && list.reversed != reversed) {
      _update(() {
        playingList = list.withReversed(reversed);
        queue = List.unmodifiable(playingList!.ordered);
      });
    }
    await savePreferences(preferences.copyWith(reversedPlaylists: ids));
  }

  /// Plays playlist [id] from [start], or from its first video in the
  /// order chosen for it.
  Future<void> playList(String id, String title, List<VideoItem> items, {VideoItem? start}) {
    final list = PlayingList(id: id, title: title, items: List.unmodifiable(items), reversed: isReversed(id));
    return play(start ?? list.ordered.first, list: list);
  }

  /// Reads the rest of the open YouTube playlist, so it can be shown last
  /// to first.
  void loadWholeYoutubePlaylist() {
    final loader = youtubePlaylistVideos;
    if (loader == null || _loadingWhole == loader) return;
    _loadingWhole = loader;
    void more() {
      if (!identical(loader, youtubePlaylistVideos) || !loader.hasMore || loader.error != null || loader.items.length >= 5000) {
        loader.removeListener(more);
        if (identical(_loadingWhole, loader)) _loadingWhole = null;
        return;
      }
      if (!loader.loading) scheduleMicrotask(loader.loadMore);
    }
    loader.addListener(more);
    more();
  }

  /// Videos after the current one in the queue, or the whole queue when the
  /// current video was opened from elsewhere.
  List<VideoItem> get upNext {
    final current = playing;
    if (current == null) return const [];
    final index = queue.indexWhere((item) => item.id == current.id);
    return index < 0 ? queue : queue.sublist(index + 1);
  }
}
