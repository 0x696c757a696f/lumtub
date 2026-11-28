import 'l10n/l10n.dart';
import 'library_store.dart';
import 'models.dart';

/// A name as people sort it: letter case aside, runs of digits by value
/// ("Part 2" before "Part 10"). Made once per entry, so a sort of n
/// entries lowercases n names rather than one pair per comparison.
class NameKey implements Comparable<NameKey> {
  NameKey(this.text) : _lower = text.toLowerCase();
  final String text;
  final String _lower;

  @override
  int compareTo(NameKey other) {
    final x = _lower;
    final y = other._lower;
    var i = 0;
    var j = 0;
    while (i < x.length && j < y.length) {
      final p = x.codeUnitAt(i);
      final q = y.codeUnitAt(j);
      if (_digit(p) && _digit(q)) {
        // Leading zeros aside, a longer run of digits is the bigger number;
        // equal lengths compare digit by digit, so no number is parsed.
        while (i < x.length - 1 && x.codeUnitAt(i) == 0x30 && _digit(x.codeUnitAt(i + 1))) {
          i++;
        }
        while (j < y.length - 1 && y.codeUnitAt(j) == 0x30 && _digit(y.codeUnitAt(j + 1))) {
          j++;
        }
        var ei = i;
        var ej = j;
        while (ei < x.length && _digit(x.codeUnitAt(ei))) {
          ei++;
        }
        while (ej < y.length && _digit(y.codeUnitAt(ej))) {
          ej++;
        }
        if (ei - i != ej - j) return (ei - i).compareTo(ej - j);
        for (; i < ei; i++, j++) {
          final d = x.codeUnitAt(i).compareTo(y.codeUnitAt(j));
          if (d != 0) return d;
        }
        continue;
      }
      if (p != q) return p.compareTo(q);
      i++;
      j++;
    }
    final rest = (x.length - i).compareTo(y.length - j);
    return rest != 0 ? rest : text.compareTo(other.text);
  }
}

bool _digit(int c) => c >= 0x30 && c <= 0x39;

/// [items] sorted by the key [keyOf] gives each, worked out once per entry
/// (n keys, then O(n log n) comparisons of ready values). Stable: entries
/// with equal keys keep their order. A null key goes last.
List<T> _sortedBy<T>(List<T> items, Comparable<dynamic>? Function(T item) keyOf) {
  final keyed = [for (var i = 0; i < items.length; i++) (i, keyOf(items[i]))];
  keyed.sort((a, b) {
    final x = a.$2;
    final y = b.$2;
    final c = x == null || y == null ? (x == null ? (y == null ? 0 : 1) : -1) : x.compareTo(y);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final (i, _) in keyed) items[i]];
}

/// The order of the 订阅分组 chips and lists.
enum GroupOrder {
  manual('Custom order'),
  name('Name'),
  size('Most channels'),
  recent('Newest video first');

  const GroupOrder(this._label);
  final String _label;
  String get label => tr(_label);

  static GroupOrder parse(Object? raw) => values.where((v) => v.name == raw).firstOrNull ?? manual;
}

/// [groups] in [order]; [rank] places each channel by its newest video in
/// the subscriptions feed, 0 for the newest, by channel id.
List<ChannelGroup> orderGroups(List<ChannelGroup> groups, GroupOrder order,
        {Map<String, int> rank = const {}}) =>
    switch (order) {
      GroupOrder.manual => groups,
      GroupOrder.name => _sortedBy(groups, (g) => NameKey(g.name)),
      GroupOrder.size => _sortedBy(groups, (g) => -g.channels.length),
      GroupOrder.recent => _sortedBy(groups, (g) {
          int? first;
          for (final id in g.channels) {
            final at = rank[id];
            if (at != null && (first == null || at < first)) first = at;
          }
          return first;
        }),
    };

/// The order of the followed channels on the subscriptions page and in
/// their full list.
enum ChannelOrder {
  recent('Newest video first'),
  name('Name'),
  followed('Recently followed'),
  watched('Most watched');

  const ChannelOrder(this._label);
  final String _label;
  String get label => tr(_label);

  static ChannelOrder parse(Object? raw) =>
      values.where((v) => v.name == raw).firstOrNull ?? recent;
}

/// [channels], kept in the order they were followed, in [order]. [rank]
/// places a channel by its newest video in the feed (0 for the newest) and
/// [watched] counts its videos in the history; channels streaming now
/// ([live]) come first when sorted by newest video.
List<ChannelRef> orderChannels(
  List<ChannelRef> channels,
  ChannelOrder order, {
  Map<String, int> rank = const {},
  Map<String, int> watched = const {},
  Set<String> live = const {},
}) =>
    switch (order) {
      // Live channels go before all others: their rank moves below 0.
      ChannelOrder.recent => _sortedBy(channels, (c) {
          final at = rank[c.id];
          if (live.contains(c.id)) return (at ?? channels.length) - channels.length - 1;
          return at;
        }),
      ChannelOrder.name => _sortedBy(channels, (c) => NameKey(c.name.isEmpty ? c.id : c.name)),
      ChannelOrder.followed => channels.reversed.toList(),
      ChannelOrder.watched => _sortedBy(channels, (c) => -(watched[c.id] ?? 0)),
    };

/// How many videos of each channel [history] holds, by channel id.
Map<String, int> countByChannel(Iterable<VideoItem> history) {
  final counts = <String, int>{};
  for (final item in history) {
    final id = item.channelId;
    if (id != null) counts[id] = (counts[id] ?? 0) + 1;
  }
  return counts;
}

/// Each channel's place in [feed] (newest first): the index of its first
/// video there, by channel id.
Map<String, int> rankInFeed(Iterable<VideoItem> feed) {
  final found = <String, int>{};
  for (final item in feed) {
    final id = item.channelId;
    if (id != null) found.putIfAbsent(id, () => found.length);
  }
  return found;
}

/// The order of the playlists on the playlists page, after 收藏 and
/// 稍后观看.
enum PlaylistOrder {
  manual('Custom order'),
  name('Name'),
  created('Recently created'),
  size('Most videos');

  const PlaylistOrder(this._label);
  final String _label;
  String get label => tr(_label);

  static PlaylistOrder parse(Object? raw) =>
      values.where((v) => v.name == raw).firstOrNull ?? manual;
}

/// [playlists], kept in the order they were made or arranged, in [order].
List<LocalPlaylist> orderPlaylists(List<LocalPlaylist> playlists, PlaylistOrder order) =>
    switch (order) {
      PlaylistOrder.manual => playlists,
      PlaylistOrder.name => _sortedBy(playlists, (p) => NameKey(p.name)),
      // A playlist's id is the time it was made; copies of YouTube's lists
      // have none and follow the user's own.
      PlaylistOrder.created => _sortedBy(playlists, (p) {
          final made = p.id.startsWith(remotePlaylistPrefix) ? null : int.tryParse(p.id, radix: 36);
          return made == null ? null : -made;
        }),
      PlaylistOrder.size => _sortedBy(playlists, (p) => -p.items.length),
    };

/// The order of the videos in one playlist.
enum VideoOrder {
  added('Order added'),
  published('Upload date'),
  duration('Length'),
  title('Title');

  const VideoOrder(this._label);
  final String _label;
  String get label => tr(_label);

  static VideoOrder parse(Object? raw) => values.where((v) => v.name == raw).firstOrNull ?? added;
}

/// [items] in [order]: newest upload first, longest first, or by title.
List<VideoItem> orderVideos(List<VideoItem> items, VideoOrder order) => switch (order) {
      VideoOrder.added => items,
      VideoOrder.published => _sortedBy(items, (v) {
          final date = v.published;
          return date == null ? null : -date.microsecondsSinceEpoch;
        }),
      VideoOrder.duration => _sortedBy(items, (v) {
          final length = v.duration;
          return length == null ? null : -length;
        }),
      VideoOrder.title => _sortedBy(items, (v) => NameKey(v.title)),
    };
