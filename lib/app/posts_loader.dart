import 'package:flutter/foundation.dart';

import '../community_posts.dart';
import '../models.dart';

/// Pages through a channel's posts for the 社区 tab.
class PostsLoader extends ChangeNotifier {
  PostsLoader(this._source, this.channel);

  final CommunityPosts _source;
  final ChannelRef channel;

  List<CommunityPost> posts = const [];
  bool loading = false;
  bool hasMore = true;
  String? error;
  String? _continuation;
  bool _started = false;
  bool _disposed = false;

  /// Fetches the next page; after a failure only [retry] fetches again.
  Future<void> loadMore({bool retry = false}) async {
    if (loading || !hasMore || (error != null && !retry)) return;
    loading = true;
    error = null;
    _notify();
    try {
      final page = _started && _continuation != null ? await _source.next(_continuation!) : await _source.first(channel);
      _started = true;
      final seen = {for (final post in posts) post.id};
      posts = [...posts, ...page.posts.where((post) => seen.add(post.id))];
      _continuation = page.continuation;
      hasMore = page.continuation != null && page.posts.isNotEmpty;
    } catch (e) {
      error = '$e';
    } finally {
      loading = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
