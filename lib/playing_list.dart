import 'dart:collection';

import 'models.dart';

/// A playlist a video was played from, in the order it plays.
class PlayingList {
  const PlayingList({required this.id, required this.title, required this.items, this.reversed = false});

  /// The playlist's id, under which its order is remembered.
  final String id;
  final String title;
  /// The videos in the playlist's own order.
  final List<VideoItem> items;
  /// Played last to first (倒序).
  final bool reversed;

  /// [items] in the order they play: a view, not a copy, so asking for it
  /// costs nothing however long the playlist.
  List<VideoItem> get ordered => reversed ? _Reversed(items) : items;

  PlayingList withReversed(bool reversed) => PlayingList(id: id, title: title, items: items, reversed: reversed);
}

/// [_items] last to first, read through without copying.
class _Reversed extends ListBase<VideoItem> {
  _Reversed(this._items);
  final List<VideoItem> _items;

  @override
  int get length => _items.length;

  @override
  set length(int _) => throw UnsupportedError('a reversed playlist cannot be changed');

  @override
  VideoItem operator [](int index) => _items[_items.length - 1 - index];

  @override
  void operator []=(int index, VideoItem value) => throw UnsupportedError('a reversed playlist cannot be changed');
}
