import '../models.dart';
import '../video_repository.dart';
import 'app_controller.dart' show PageMode;

/// A place 返回 comes back to: a page with what it showed, or a video
/// and where it was.
class BackEntry {
  const BackEntry.page(this.mode, {this.query, this.channel, this.channelTab = ChannelTab.videos, this.playlistId, this.youtubePlaylist})
      : video = null,
        position = null,
        queue = const [];

  const BackEntry.video(VideoItem this.video, {required this.mode, this.position, this.queue = const []})
      : query = null,
        channel = null,
        channelTab = ChannelTab.videos,
        playlistId = null,
        youtubePlaylist = null;

  /// The page under the video, or the page itself.
  final PageMode mode;
  /// The search on the explore page.
  final String? query;
  final ChannelRef? channel;
  final ChannelTab channelTab;
  final String? playlistId;
  final PlaylistResult? youtubePlaylist;

  final VideoItem? video;
  final Duration? position;
  final List<VideoItem> queue;

  /// Whether this shows the same thing as [other].
  bool same(BackEntry other) {
    final video = this.video;
    if (video != null || other.video != null) return video?.id == other.video?.id;
    if (mode != other.mode) return false;
    return switch (mode) {
      PageMode.explore => query == other.query,
      PageMode.channel => channel?.id == other.channel?.id && channelTab == other.channelTab,
      PageMode.playlist => playlistId == other.playlistId,
      PageMode.youtubePlaylist => youtubePlaylist?.id == other.youtubePlaylist?.id,
      _ => true,
    };
  }

  @override
  String toString() => video != null ? 'video ${video!.id}' : '${mode.name}${query == null ? '' : ' “$query”'}';
}

/// Where 返回 goes, newest last. It keeps the last [limit] places and
/// never the same place twice in a row.
class BackStack {
  static const limit = 50;
  final _entries = <BackEntry>[];

  bool get isEmpty => _entries.isEmpty;
  int get length => _entries.length;
  BackEntry? get last => _entries.lastOrNull;

  void push(BackEntry entry) {
    if (_entries.lastOrNull?.same(entry) ?? false) _entries.removeLast();
    _entries.add(entry);
    if (_entries.length > limit) _entries.removeAt(0);
  }

  BackEntry? pop() => _entries.isEmpty ? null : _entries.removeLast();

  void clear() => _entries.clear();
}
