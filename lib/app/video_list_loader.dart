import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models.dart';
import '../video_repository.dart';

/// Pages through a listing such as search results or a channel's uploads,
/// keeping the items, loading state and last error for the page that shows
/// them. One [Listing] serves every page, so each page continues where the
/// last one stopped.
class VideoListLoader extends ChangeNotifier {
  VideoListLoader(this._open, {this.pageSize = 20, this.limit, this.where});

  final Listing Function() _open;
  final int pageSize;
  /// Stop after this many videos, if set.
  final int? limit;
  /// Leaves out videos that fail this test, such as the one playing.
  final bool Function(VideoItem item)? where;

  List<VideoItem> items = const [];
  /// Channels the listing found; only searches list them.
  List<ChannelResult> channels = const [];
  /// Playlists the listing found.
  List<PlaylistResult> playlists = const [];
  bool loading = false;
  bool hasMore = true;
  String? error;

  Listing? _listing;
  StreamSubscription<Object>? _subscription;
  final _seen = <String>{};
  bool _disposed = false;

  /// Fetches the next page. After a failure only [retry] fetches again, so
  /// scrolling does not hammer a failing source; a retry starts the listing
  /// over and skips what is already shown.
  void loadMore({bool retry = false}) {
    if (loading || !hasMore || (error != null && !retry)) return;
    // A listing that ended with an error starts over and has to get past
    // everything already shown.
    var count = pageSize;
    if (_listing == null || _listing!.done) {
      if (_listing != null) count += _seen.length;
      _listing?.close();
      _listing = _open();
    }
    final listing = _listing!;
    var fresh = 0;
    loading = true;
    error = null;
    _notify();
    _subscription = listing.next(count).listen(
      (entry) {
        if (entry is ChannelResult) {
          if (!_seen.add(entry.ref.id)) return;
          channels = [...channels, entry];
        } else if (entry is PlaylistResult) {
          if (!_seen.add(entry.id)) return;
          playlists = [...playlists, entry];
        } else if (entry is VideoItem) {
          if (where?.call(entry) == false || !_seen.add(entry.id)) return;
          if (limit != null && items.length >= limit!) return;
          items = [...items, entry];
        }
        fresh++;
        _notify();
      },
      onError: (Object e) => error = '$e',
      onDone: () {
        loading = false;
        final full = limit != null && items.length >= limit!;
        hasMore = !full && (error != null || (!listing.done && fresh > 0));
        _notify();
      },
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    _listing?.close();
    super.dispose();
  }
}
