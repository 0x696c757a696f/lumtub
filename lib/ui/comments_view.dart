import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../app/comments_loader.dart';
import '../models.dart';
import '../youtube_comments.dart';
import 'common.dart';
import 'linked_text.dart';
import 'pages/channel_page.dart';
import 'theme.dart';
import 'translatable.dart';
import '../l10n/l10n.dart';

/// The comments under a video or a post: sort order, comments with their
/// replies, and a button for more. It loads when first shown.
class CommentsSection extends StatefulWidget {
  const CommentsSection({super.key, required this.controller, this.videoId, this.postId, this.onSeek, this.scrollable = false, this.sliver = false, this.padding = EdgeInsets.zero});
  final AppController controller;
  /// Scrolls by itself and builds only the comments on screen; otherwise it
  /// sits in the page's own scrolling column.
  final bool scrollable;
  /// A sliver in the page's own scroll view, built only as far as it is
  /// scrolled into view; it loads once it first comes near the screen.
  final bool sliver;
  final EdgeInsets padding;
  final String? videoId;
  final String? postId;
  /// Seeks the video when a timestamp in a comment is clicked.
  final void Function(Duration position)? onSeek;

  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  late final _loader = CommentsLoader(widget.controller.comments, videoId: widget.videoId, postId: widget.postId);
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    if (!widget.sliver) _load();
  }

  void _load() {
    if (_asked || !mounted) return;
    _asked = true;
    unawaited(_loader.loadMore());
  }
  /// The comment a reply is being written to.
  String? _replyingTo;
  /// 搜索评论: open, and the words looked for.
  bool _searching = false;
  List<String> _words = const [];
  final _search = TextEditingController();

  @override
  void dispose() {
    _loader.dispose();
    _search.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _search.clear();
        _words = const [];
        _loader.stopLoadingAll();
      }
    });
  }

  /// [comment], or one of its loaded replies, holds the words searched.
  bool _matches(YoutubeComment comment) =>
      commentMatches(comment, _words) || (_loader.replies[comment.id]?.replies.any((reply) => commentMatches(reply, _words)) ?? false);

  Widget _searchBar(BuildContext context) {
    final loader = _loader;
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): _toggleSearch},
          child: TextField(
          controller: _search,
          autofocus: true,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            hintText: tr('搜索评论内容或作者'),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(tooltip: tr('关闭搜索'), icon: const Icon(Icons.close_rounded, size: 18), onPressed: _toggleSearch),
          ),
          onChanged: (text) => setState(() => _words = commentQueryWords(text)),
        ),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: Text(
            loader.loadingAll ? tr('正在加载全部评论… 已加载 {0} 条', [loader.comments.length]) : tr('在已加载的 {0} 条评论里搜索', [loader.comments.length]),
            style: TextStyle(color: colors.outline, fontSize: 12),
          )),
          if (loader.loadingAll)
            TextButton(onPressed: loader.stopLoadingAll, child: Text(tr('停止')))
          else if (loader.hasMore)
            TextButton(onPressed: loader.loadAll, child: Text(tr('加载全部评论再搜'))),
        ]),
      ]),
    );
  }

  /// Only video comments can be written: YouTube's API has none for posts.
  bool get _canWrite => widget.videoId != null && (widget.controller.account?.signedIn ?? false);

  YoutubeComment _own(String text) => YoutubeComment(
        id: 'own:${DateTime.now().microsecondsSinceEpoch}',
        author: widget.controller.account?.name ?? tr('我'),
        text: text,
        published: tr('刚刚'),
      );

  Future<bool> _post(String text) async {
    final posted = await widget.controller.account?.postComment(videoId: widget.videoId!, text: text) ?? false;
    if (posted) _loader.addOwn(_own(text.trim()));
    return posted;
  }

  Future<bool> _reply(YoutubeComment parent, String text) async {
    final posted = await widget.controller.account?.postComment(videoId: widget.videoId!, parentId: parent.id, text: text) ?? false;
    if (posted) {
      _loader.addOwnReply(parent, _own(text.trim()));
      if (mounted) setState(() => _replyingTo = null);
    }
    return posted;
  }

  /// [comment] and, once loaded, its replies.
  List<Widget> _thread(BuildContext context, YoutubeComment comment) {
    final loader = _loader;
    final thread = loader.replies[comment.id];
    Widget tile(YoutubeComment c, {bool reply = false}) => _CommentTile(
          comment: c,
          loader: loader,
          controller: widget.controller,
          onSeek: widget.onSeek,
          reply: reply,
          onReply: _canWrite && !reply && !c.id.startsWith('own:') ? () => setState(() => _replyingTo = _replyingTo == c.id ? null : c.id) : null,
        );
    final error = thread?.error;
    return [
      tile(comment),
      if (_replyingTo == comment.id)
        Padding(
          padding: const EdgeInsets.only(left: 44, bottom: 8),
          child: CommentComposer(hint: tr('回复 {0}…', [comment.author]), autofocus: true, onSubmit: (text) => _reply(comment, text), onCancel: () => setState(() => _replyingTo = null)),
        ),
      if (thread != null) ...[
        for (final reply in thread.replies) tile(reply, reply: true),
        Padding(
          padding: const EdgeInsets.only(left: 44),
          child: thread.loading
              ? const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
              : error != null
                  ? ErrorBanner(tr('无法加载回复：{0}', [error]), onRetry: () => loader.loadReplies(comment))
                  : thread.next != null
                      ? TextButton(onPressed: () => loader.loadReplies(comment), child: Text(tr('更多回复')))
                      : const SizedBox.shrink(),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _loader,
        builder: (context, _) {
          final colors = context.colors;
          final loader = _loader;
          final error = loader.error;
          final header = <Widget>[
            LayoutBuilder(builder: (context, constraints) {
              final order = SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [ButtonSegment(value: false, label: Text(tr('热门'))), ButtonSegment(value: true, label: Text(tr('最新')))],
                selected: {loader.newest},
                onSelectionChanged: (value) => loader.setNewest(value.first),
              );
              final title = Text(loader.count.isEmpty ? tr('评论') : tr('评论 · {0}', [loader.count]), style: Theme.of(context).textTheme.titleMedium);
              final search = IconButton(
                tooltip: tr('搜索评论'),
                isSelected: _searching,
                icon: const Icon(Icons.search_rounded),
                onPressed: _toggleSearch,
              );
              return constraints.maxWidth >= 520
                  ? Row(children: [title, const Spacer(), search, const SizedBox(width: 4), order])
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, const SizedBox(height: 8), Row(mainAxisAlignment: MainAxisAlignment.end, children: [search, order])]);
            }),
            const SizedBox(height: 8),
            if (_searching) _searchBar(context),
            if (_canWrite) CommentComposer(hint: tr('添加评论…'), onSubmit: _post),
          ];
          final prefs = widget.controller.preferences;
          final shown = [for (final comment in loader.comments) if (!prefs.blocksCommenter(comment.author, comment.channelId) && (_words.isEmpty || _matches(comment))) comment];
          final footer = <Widget>[
            if (loader.loading)
              const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))))
            else if (error != null)
              ErrorBanner(loader.comments.isEmpty ? tr('无法加载评论：{0}', [error]) : tr('加载更多评论失败：{0}', [error]), onRetry: () => loader.loadMore(retry: true))
            else if (loader.started && loader.comments.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(tr('还没有评论，或评论已关闭'), style: TextStyle(color: colors.outline)))
            else if (_words.isNotEmpty && shown.isEmpty && !loader.loadingAll)
              Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(tr('已加载的评论里没有找到'), style: TextStyle(color: colors.outline)))
            else if (loader.hasMore)
              Center(child: TextButton(onPressed: loader.loadMore, child: Text(tr('加载更多评论')))),
          ];
          Widget item(BuildContext context, int index) {
            // Not during the build that asked for it.
            if (!_asked) scheduleMicrotask(_load);
            if (index < header.length) return header[index];
            index -= header.length;
            if (index < shown.length) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: _thread(context, shown[index]));
            return footer[index - shown.length];
          }
          final count = header.length + shown.length + footer.length;
          if (widget.sliver) return SliverPadding(padding: widget.padding, sliver: SliverList.builder(itemCount: count, itemBuilder: item));
          if (!widget.scrollable) {
            return Padding(
              padding: widget.padding,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [...header, for (final comment in shown) ..._thread(context, comment), ...footer]),
            );
          }
          return ListView.builder(padding: widget.padding, itemCount: count, itemBuilder: item);
        },
      );
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, required this.loader, required this.controller, this.onSeek, this.reply = false, this.onReply});
  final YoutubeComment comment;
  final CommentsLoader loader;
  final AppController controller;
  final void Function(Duration position)? onSeek;
  final bool reply;
  final VoidCallback? onReply;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final small = TextStyle(color: colors.outline, fontSize: 12);
    final thread = loader.replies[comment.id];
    final channelId = comment.channelId;
    void openAuthor() {
      // From a page over the app (a post's comments), go back to it first.
      if (ModalRoute.of(context) case final route? when !route.isFirst) Navigator.of(context).pop();
      controller.openChannel(ChannelRef(channelId!, comment.author.replaceFirst(RegExp(r'^@'), '')));
    }
    return Padding(
      padding: EdgeInsets.only(top: 8, bottom: 8, left: reply ? 44 : 0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          customBorder: const CircleBorder(),
          onTap: channelId != null && ChannelRef.isValidId(channelId) ? openAuthor : null,
          child: ChannelAvatar(name: comment.author.replaceFirst(RegExp(r'^@'), ''), image: comment.avatar, radius: reply ? 12 : 16),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (comment.pinned) Text(tr('置顶'), style: small.copyWith(color: colors.primary)),
            Text(comment.author, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: comment.byUploader ? colors.primary : null)),
            Text(comment.published, style: small),
          ]),
          const SizedBox(height: 4),
          Translatable(
            controller: controller,
            text: comment.text,
            builder: (context, text) => LinkedText(text, style: const TextStyle(height: 1.45), onTime: onSeek ?? (_) {}, onLink: openExternal),
          ),
          const SizedBox(height: 4),
          Row(children: [
            Tooltip(
              message: tr('点赞数。YouTube 官方接口不支持给评论点赞'),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.thumb_up_outlined, size: 14, color: colors.outline),
                const SizedBox(width: 4),
                Text(comment.likes.isEmpty ? '0' : comment.likes, style: small),
              ]),
            ),
            if (comment.hearted) ...[
              const SizedBox(width: 12),
              Tooltip(message: tr('作者喜欢'), child: Icon(Icons.favorite_rounded, size: 14, color: colors.error)),
            ],
            if (onReply != null) ...[
              const SizedBox(width: 8),
              TextButton(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: onReply,
                child: Text(tr('回复'), style: TextStyle(fontSize: 12)),
              ),
            ],
          ]),
          if (!reply && comment.repliesToken != null)
            TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
              onPressed: () => thread == null ? loader.loadReplies(comment) : loader.collapse(comment),
              icon: Icon(thread == null ? Icons.expand_more_rounded : Icons.expand_less_rounded, size: 18),
              label: Text(thread == null ? (comment.replyCount > 0 ? tr('{0} 条回复', [comment.replyCount]) : tr('查看回复')) : tr('收起回复')),
            ),
        ])),
      ]),
    );
  }
}

/// A field for writing a comment or reply, with 发布 and, for replies, 取消.
class CommentComposer extends StatefulWidget {
  const CommentComposer({super.key, required this.hint, required this.onSubmit, this.onCancel, this.autofocus = false});
  final String hint;
  /// Posts the text; returns whether it went through.
  final Future<bool> Function(String text) onSubmit;
  final VoidCallback? onCancel;
  final bool autofocus;

  @override
  State<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<CommentComposer> {
  final _text = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final posted = await widget.onSubmit(text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (posted) _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13);
    // The field takes the whole width, as on YouTube, with its buttons
    // under it, so a narrow comments panel still leaves room to write.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _text,
          autofocus: widget.autofocus,
          enabled: !_sending,
          minLines: 1,
          maxLines: 6,
          maxLength: 10000,
          style: small,
          decoration: InputDecoration(
            hintText: widget.hint,
            hintMaxLines: 1,
            hintStyle: small?.copyWith(overflow: TextOverflow.ellipsis),
            isDense: true,
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          if (widget.onCancel != null) TextButton(style: _compact, onPressed: _sending ? null : widget.onCancel, child: Text(tr('取消'))),
          const SizedBox(width: 4),
          ListenableBuilder(
            listenable: _text,
            builder: (context, _) => FilledButton(
              style: _compact,
              onPressed: _sending || _text.text.trim().isEmpty ? null : _send,
              child: _sending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(tr('发布')),
            ),
          ),
        ]),
      ]),
    );
  }

  static const _compact = ButtonStyle(
    visualDensity: VisualDensity.compact,
    textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 13)),
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
  );
}
