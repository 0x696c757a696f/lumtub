import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models.dart';
import '../video_repository.dart';

/// Pages through a listing such as search results or a channel's uploads,
/// keeping the items, loading state and last error for the page that shows
/// them. One [Listing] serves every page, so each page continues where the
/// last one stopped.
class VideoListLoader extends ChangeNotifier {
  VideoListLoader(this._open, {this.pageSize = 20, this.limit, this.where, this.matches});

  final Listing Function() _open;
  final int pageSize;
  /// Stop after this many videos, if set.
  final int? limit;
  /// Leaves out videos that fail this test, such as the one playing.
  final bool Function(VideoItem item)? where;
  /// Keeps only entries whose title passes, such as a search inside one
  /// channel tab. Pages that add nothing are skipped over, up to a limit.
  final bool Function(String title)? matches;

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
    loading = true;
    error = null;
    _notify();
    _page(_listing!, count, 0);
  }

  void _page(Listing listing, int count, int skipped) {
    var fresh = 0;
    var shown = 0;
    _subscription = listing.next(count).listen(
      (entry) {
        fresh++;
        final match = matches;
        if (entry is ChannelResult) {
          if (match != null || !_seen.add(entry.ref.id)) return;
          channels = [...channels, entry];
        } else if (entry is PlaylistResult) {
          if ((match != null && !match(entry.title)) || !_seen.add(entry.id)) return;
          playlists = [...playlists, entry];
        } else if (entry is VideoItem) {
          if (where?.call(entry) == false || (match != null && !match(entry.title)) || !_seen.add(entry.id)) return;
          if (limit != null && items.length >= limit!) return;
          items = [...items, entry];
        }
        shown++;
        _notify();
      },
      onError: (Object e) => error = '$e',
      onDone: () {
        final full = limit != null && items.length >= limit!;
        final more = !full && !listing.done && fresh > 0;
        // A filtered page with nothing to show would leave nothing to
        // scroll, so the next one is read straight away.
        if (matches != null && error == null && more && shown == 0 && skipped < 25 && !_disposed) {
          _page(listing, pageSize, skipped + 1);
          return;
        }
        loading = false;
        hasMore = !full && (error != null || more);
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
