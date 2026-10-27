import 'package:flutter/foundation.dart';

import '../youtube_comments.dart';
import '../friendly_error.dart';

/// The replies under one comment, loaded on demand.
class ReplyThread {
  List<YoutubeComment> replies = const [];
  String? next;
  bool loading = false;
  String? error;
}

/// Pages through the comments under a video or a community post.
class CommentsLoader extends ChangeNotifier {
  CommentsLoader(this._source, {this.videoId, this.postId}) : assert((videoId == null) != (postId == null));

  final YoutubeComments _source;
  final String? videoId;
  final String? postId;

  List<YoutubeComment> comments = const [];
  String count = '';
  bool newest = false;
  bool loading = false;
  bool started = false;
  String? error;
  String? _next;
  final replies = <String, ReplyThread>{};
  int _generation = 0;
  bool _disposed = false;

  bool get hasMore => !started || _next != null;
  bool get _post => postId != null;

  /// Starts over in the other sort order.
  Future<void> setNewest(bool value) {
    if (value == newest) return Future.value();
    newest = value;
    _generation++;
    loadingAll = false;
    comments = const [];
    replies.clear();
    started = false;
    loading = false;
    error = null;
    _next = null;
    return loadMore();
  }

  /// Fetches the next page; after a failure only [retry] fetches again.
  Future<void> loadMore({bool retry = false}) async {
    if (loading || !hasMore || (error != null && !retry)) return;
    final generation = _generation;
    loading = true;
    error = null;
    _notify();
    try {
      final next = _next;
      final page = started && next != null
          ? await _source.more(next, post: _post)
          : _post
              ? await _source.post(postId!, newest: newest)
              : await _source.video(videoId!, newest: newest);
      if (generation != _generation) return;
      if (!started) count = page.count;
      started = true;
      final seen = {for (final c in comments) c.id};
      comments = [...comments, ...page.comments.where((c) => seen.add(c.id))];
      // A page with nothing new would only repeat.
      _next = page.comments.isEmpty ? null : page.continuation;
    } catch (e) {
      if (generation == _generation) error = friendlyError(e);
    } finally {
      if (generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  /// Whether [loadAll] is running.
  bool loadingAll = false;

  /// Loads page after page, for 搜索评论 to look through all of them, up to
  /// [most] comments or until [stopLoadingAll].
  Future<void> loadAll({int most = 3000}) async {
    if (loadingAll) return;
    final generation = _generation;
    loadingAll = true;
    _notify();
    try {
      while (loadingAll && !_disposed && generation == _generation && hasMore && error == null && comments.length < most) {
        if (loading) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          continue;
        }
        await loadMore();
      }
    } finally {
      if (generation == _generation && loadingAll) {
        loadingAll = false;
        _notify();
      }
    }
  }

  void stopLoadingAll() {
    if (!loadingAll) return;
    loadingAll = false;
    _notify();
  }

  /// Loads [comment]'s replies, or the next page of them.
  Future<void> loadReplies(YoutubeComment comment) async {
    final thread = replies.putIfAbsent(comment.id, ReplyThread.new);
    final token = thread.replies.isEmpty ? comment.repliesToken : thread.next;
    if (thread.loading || token == null) return;
    final generation = _generation;
    thread
      ..loading = true
      ..error = null;
    _notify();
    try {
      final page = await _source.more(token, post: _post);
      if (generation != _generation) return;
      final seen = {for (final c in thread.replies) c.id};
      thread
        ..replies = [...thread.replies, ...page.comments.where((c) => seen.add(c.id))]
        ..next = page.comments.isEmpty ? null : page.continuation;
    } catch (e) {
      thread.error = friendlyError(e);
    } finally {
      thread.loading = false;
      _notify();
    }
  }

  /// Shows a comment the user just posted at the top.
  void addOwn(YoutubeComment comment) {
    comments = [comment, ...comments];
    _notify();
  }

  /// Shows a reply the user just posted under [parent].
  void addOwnReply(YoutubeComment parent, YoutubeComment reply) {
    final thread = replies.putIfAbsent(parent.id, ReplyThread.new);
    thread.replies = [...thread.replies, reply];
    _notify();
  }

  /// Hides [comment]'s replies again.
  void collapse(YoutubeComment comment) {
    if (replies.remove(comment.id) != null) _notify();
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

/// Whether [comment] holds every word of [query], in its text or author's
/// name, ignoring case.
bool commentMatches(YoutubeComment comment, List<String> words) {
  if (words.isEmpty) return true;
  final text = '${comment.text}\n${comment.author}'.toLowerCase();
  return words.every(text.contains);
}

/// [query] as the lower-case words [commentMatches] looks for.
List<String> commentQueryWords(String query) => [for (final word in query.toLowerCase().split(RegExp(r'\s+'))) if (word.isNotEmpty) word];
