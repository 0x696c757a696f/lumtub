import 'models.dart';

/// Videos the user lined up with 下一个播放 / 加入播放队列. They play after
/// the current video, before the list it came from or autoplay goes on.
/// Kept for the session only.
class PlayQueue {
  final items = <VideoItem>[];

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;

  /// Puts [item] first; one already queued moves up.
  void addNext(VideoItem item) {
    items.removeWhere((other) => other.id == item.id);
    items.insert(0, item);
  }

  /// Puts [item] last; false when it was already queued.
  bool addLast(VideoItem item) {
    if (items.any((other) => other.id == item.id)) return false;
    items.add(item);
    return true;
  }

  void remove(String id) => items.removeWhere((item) => item.id == id);

  void clear() => items.clear();

  /// Moves the entry at [from] to [to], the index it has after the move.
  void move(int from, int to) {
    if (from < 0 || from >= items.length) return;
    items.insert(to.clamp(0, items.length - 1), items.removeAt(from));
  }

  /// Takes the first entry off, or null when empty.
  VideoItem? takeNext() => items.isEmpty ? null : items.removeAt(0);
}
