import 'package:flutter/foundation.dart';

import '../community_posts.dart';
import '../models.dart';
import '../friendly_error.dart';

/// Pages through a channel's posts for the 社区 tab.
class PostsLoader extends ChangeNotifier {
  PostsLoader(this._source, this.channel, {this.matches});

  final CommunityPosts _source;
  final ChannelRef channel;
  /// Keeps only posts whose text passes, for a search inside the channel.
  final bool Function(String text)? matches;

  List<CommunityPost> posts = const [];
  bool loading = false;
  bool hasMore = true;
  String? error;
  String? _continuation;
  bool _started = false;
  bool _disposed = false;

  /// Ratings changed here, by post id, ahead of the next load.
  final _rated = <String, String>{};

  /// `like`, `dislike` or empty for [post], as last pressed here.
  String ratingOf(CommunityPost post) => _rated[post.id] ?? post.rating?.state ?? '';

  /// Presses like or dislike ([want]) on [post]: shown at once, taken back
  /// if YouTube refuses. Returns why it failed, or null.
  Future<String?> rate(CommunityPost post, String want) async {
    final before = ratingOf(post);
    final action = post.rating?.actionFor(before, want);
    final signIn = _source.signIn;
    if (action == null || signIn == null) return null;
    _rated[post.id] = before == want ? '' : want;
    _notify();
    try {
      await signIn.rate(action);
      return null;
    } catch (e) {
      _rated[post.id] = before;
      _notify();
      return friendlyError(e);
    }
  }

  /// Fetches the next page; after a failure only [retry] fetches again.
  Future<void> loadMore({bool retry = false}) async {
    if (loading || !hasMore || (error != null && !retry)) return;
    loading = true;
    error = null;
    _notify();
    try {
      // A search reads on until a page has a match, up to a limit.
      for (var pages = 0; pages < 25; pages++) {
        final page = _started && _continuation != null ? await _source.next(_continuation!) : await _source.first(channel);
        if (_disposed) return;
        _started = true;
        final seen = {for (final post in posts) post.id};
        final fresh = page.posts.where((post) => seen.add(post.id) && (matches?.call(post.text) ?? true)).toList();
        posts = [...posts, ...fresh];
        _continuation = page.continuation;
        hasMore = page.continuation != null && page.posts.isNotEmpty;
        if (fresh.isNotEmpty || !hasMore || matches == null) break;
      }
    } catch (e) {
      error = friendlyError(e);
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
