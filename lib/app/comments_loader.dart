import 'package:flutter/foundation.dart';

import '../youtube_comments.dart';
import '../app_log.dart';
import '../friendly_error.dart';
import '../l10n/l10n.dart';

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

  /// Ratings changed here, by comment id, ahead of the next load.
  final _rated = <String, String>{};

  /// Like buttons found for comments their list came without, by id: the
  /// TV app gives them only on the page of one comment.
  final _found = <String, CommentRating>{};
  /// A comment with buttons, whose actions others' are made from.
  (String, CommentRating)? _template;

  /// `like`, `dislike` or empty for [comment], as last pressed here.
  String ratingOf(YoutubeComment comment) => _rated[comment.id] ?? comment.rating?.state ?? _found[comment.id]?.state ?? '';

  /// Whether [comment] can be liked: its buttons came with it, or can be
  /// found or made signed in.
  bool canRate(YoutubeComment comment) =>
      comment.rating != null || _found.containsKey(comment.id) || ((_post ? _source.webSignedIn : _source.signedIn) && (comment.detailToken != null || _template != null));

  void _learn(Iterable<YoutubeComment> comments) {
    for (final c in comments) {
      final rating = c.rating;
      if (rating == null) continue;
      _found[c.id] = rating;
      _template ??= (c.id, rating);
    }
  }

  /// [comment]'s buttons: as they came, from its own page, or made from
  /// another comment's.
  Future<CommentRating?> _ratingFor(YoutubeComment comment) async {
    final known = comment.rating ?? _found[comment.id];
    if (known != null) return known;
    final detail = comment.detailToken;
    if (detail != null) {
      try {
        _learn((await _source.more(detail, post: _post)).comments);
      } catch (e) {
        logInfo('Could not read the page of comment ${comment.id}: $e');
      }
      if (_found[comment.id] case final found?) return found;
    }
    final template = _template;
    final made = template?.$2.forComment(template.$1, comment.id);
    if (made != null) _found[comment.id] = made;
    return made;
  }

  /// Presses like or dislike ([want]) on [comment]: shown at once, taken
  /// back if YouTube refuses. Returns why it failed, or null.
  Future<String?> rate(YoutubeComment comment, String want) async {
    final before = ratingOf(comment);
    final rating = await _ratingFor(comment);
    if (rating == null) return tr('YouTube 没有给这条评论点赞按钮');
    final action = rating.actionFor(before, want);
    if (action == null) return null;
    _rated[comment.id] = before == want ? '' : want;
    _notify();
    try {
      await _source.rate(action, post: _post);
      return null;
    } catch (e) {
      _rated[comment.id] = before;
      _notify();
      return friendlyError(e);
    }
  }

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
      if (!started) {
        count = page.count;
        createParams = page.createParams;
      }
      started = true;
      _learn(page.comments);
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
      _learn(page.comments);
      // The TV app's replies page starts with the comment itself.
      final seen = {comment.id, for (final c in thread.replies) c.id};
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

  /// The post's comment box, when it was loaded with the cookie sign-in.
  String? createParams;

  bool get canCreate => _post && createParams != null && _source.webSignedIn;

  /// Writes [text] under the post. Returns why it failed, or null.
  Future<String?> create(String text) async {
    final params = createParams;
    if (params == null) return tr('这个帖子没有评论框');
    try {
      await _source.create(params, text);
      return null;
    } catch (e) {
      return friendlyError(e);
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

/// Lower-cased once per comment, not once per keystroke.
final _searchText = Expando<String>();

/// Whether [comment] holds every word of [query], in its text or author's
/// name, ignoring case.

bool commentMatches(YoutubeComment comment, List<String> words) {
  if (words.isEmpty) return true;
  final text = _searchText[comment] ??= '${comment.text}\n${comment.author}'.toLowerCase();
  return words.every(text.contains);
}

/// [query] as the lower-case words [commentMatches] looks for.
List<String> commentQueryWords(String query) => [for (final word in query.toLowerCase().split(RegExp(r'\s+'))) if (word.isNotEmpty) word];
