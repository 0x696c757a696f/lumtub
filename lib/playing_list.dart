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

  List<VideoItem> get ordered => reversed ? items.reversed.toList() : items;

  PlayingList withReversed(bool reversed) => PlayingList(id: id, title: title, items: items, reversed: reversed);
}
