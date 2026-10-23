import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models.dart';
import '../video_repository.dart';

/// Pages through a listing such as search results or a channel's uploads,
/// keeping the items, loading state and last error for the page that shows
/// them. One [Listing] serves every page, so each page continues where the
/// last one stopped.
class VideoListLoader extends ChangeNotifier {
  VideoListLoader(this._open, {this.pageSize = 20, this.limit, this.where, this.matches, this.rank, this.fill = 1});

  final Listing Function() _open;
  final int pageSize;
  /// Stop after this many videos, if set.
  final int? limit;
  /// Leaves out videos that fail this test, such as the one playing.
  final bool Function(VideoItem item)? where;
  /// Keeps only entries whose title passes, such as a search inside one
  /// channel tab. Pages that add nothing are skipped over, up to a limit.
  final bool Function(String title)? matches;
  /// Orders each page's videos, highest first, before they are shown.
  final double Function(VideoItem item)? rank;
  /// With [where] or [matches], pages are read until this many entries
  /// show, so a strict filter still leaves something to scroll.
  final int fill;

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

  /// Waits before each automatic retry after a failure, longer each time;
  /// once they are used up only the 重试 button tries again.
  static List<Duration> retryDelays = const [Duration(seconds: 5), Duration(seconds: 15), Duration(seconds: 45), Duration(minutes: 2)];

  /// Loaders waiting to retry. When any loader gets an answer the network
  /// is back, so these retry at once instead of waiting their turn.
  static final _failing = <VideoListLoader>{};
  int _retries = 0;
  Timer? _retryTimer;

  /// Errors a retry would only make worse, or cannot fix.
  static final _noRetry = RegExp(r'429|Too Many Requests|Sign in to confirm|not a bot|Private video|unavailable', caseSensitive: false);

  void _scheduleRetry() {
    final message = error;
    if (_disposed || message == null || _noRetry.hasMatch(message) || _retries >= retryDelays.length) return;
    _failing.add(this);
    _retryTimer?.cancel();
    _retryTimer = Timer(retryDelays[_retries++], _retryNow);
  }

  void _retryNow() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _failing.remove(this);
    if (!_disposed && error != null) loadMore(retry: true);
  }

  void _succeeded() {
    _retries = 0;
    if (_failing.isEmpty) return;
    for (final other in _failing.toList()) {
      if (other != this) other._retryNow();
    }
  }

  /// Fetches the next page. After a failure only [retry] fetches again, so
  /// scrolling does not hammer a failing source; a retry starts the listing
  /// over and skips what is already shown. Failures are retried a few
  /// times on their own, sooner when another list loads again.
  void loadMore({bool retry = false}) {
    if (loading || !hasMore || (error != null && !retry)) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    _failing.remove(this);
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
    _page(_listing!, count, 0, 0);
  }

  void _page(Listing listing, int count, int skipped, int shownBefore) {
    var fresh = 0;
    var shown = shownBefore;
    // A search page can contain dozens of entries.  Publishing each one used
    // to copy the whole accumulated list and rebuild the result sliver once
    // per entry.  Keep one page local and publish it together instead.
    final pendingVideos = <VideoItem>[];
    final pendingChannels = <ChannelResult>[];
    final pendingPlaylists = <PlaylistResult>[];
    _subscription = listing.next(count).listen(
      (entry) {
        fresh++;
        final match = matches;
        if (entry is ChannelResult) {
          if (match != null || !_seen.add(entry.ref.id)) return;
          pendingChannels.add(entry);
        } else if (entry is PlaylistResult) {
          if ((match != null && !match(entry.title)) || !_seen.add(entry.id)) return;
          pendingPlaylists.add(entry);
        } else if (entry is VideoItem) {
          if (where?.call(entry) == false || (match != null && !match(entry.title)) || !_seen.add(entry.id)) return;
          if (limit != null && items.length + pendingVideos.length >= limit!) return;
          pendingVideos.add(entry);
        }
        shown++;
      },
      onError: (Object e) => error = '$e',
      onDone: () {
        final order = rank;
        if (pendingVideos.isNotEmpty) {
          if (order == null) {
            items = [...items, ...pendingVideos];
          } else {
            final scored = [for (final item in pendingVideos) (item, order(item))]..sort((a, b) => b.$2.compareTo(a.$2));
            items = [...items, for (final (item, _) in scored) item];
          }
        }
        if (pendingChannels.isNotEmpty) channels = [...channels, ...pendingChannels];
        if (pendingPlaylists.isNotEmpty) playlists = [...playlists, ...pendingPlaylists];
        final full = limit != null && items.length >= limit!;
        final more = !full && !listing.done && fresh > 0;
        // A filtered page with nothing to show would leave nothing to
        // scroll, so the next one is read straight away.
        if ((matches != null || where != null) && error == null && more && shown < fill && skipped < 25 && !_disposed) {
          _page(listing, pageSize, skipped + 1, shown);
          return;
        }
        loading = false;
        hasMore = !full && (error != null || more);
        if (error == null) {
          if (fresh > 0) _succeeded();
        } else {
          _scheduleRetry();
        }
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
    _retryTimer?.cancel();
    _failing.remove(this);
    unawaited(_subscription?.cancel());
    _listing?.close();
    super.dispose();
  }
}
