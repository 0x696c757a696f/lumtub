import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models.dart';

/// Pages through a video listing such as a channel's uploads, keeping the
/// items, loading state and last error for the page that shows them.
class VideoListLoader extends ChangeNotifier {
  VideoListLoader(this._fetch, {this.pageSize = 20, this.limit});

  /// Starts the page beginning at the 1-based index.
  final Stream<VideoItem> Function(int start) _fetch;
  final int pageSize;
  /// Stop after this many items, if set.
  final int? limit;

  List<VideoItem> items = const [];
  bool loading = false;
  bool hasMore = true;
  String? error;

  StreamSubscription<VideoItem>? _subscription;
  bool _disposed = false;

  /// Fetches the next page. After a failure only [retry] fetches again, so
  /// scrolling does not hammer a failing source.
  void loadMore({bool retry = false}) {
    if (loading || !hasMore || (error != null && !retry)) return;
    final seen = {for (final item in items) item.id};
    var received = 0;
    loading = true;
    error = null;
    _notify();
    _subscription = _fetch(items.length + 1).listen(
      (item) {
        received++;
        if (seen.add(item.id) && (limit == null || items.length < limit!)) {
          items = [...items, item];
          _notify();
        }
      },
      onError: (Object e) => error = '$e',
      onDone: () {
        loading = false;
        hasMore = error != null || (received >= pageSize && (limit == null || items.length < limit!));
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
    super.dispose();
  }
}
