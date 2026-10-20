import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/comments_loader.dart';
import '../models.dart';
import '../youtube_comments.dart';
import 'common.dart';
import 'linked_text.dart';
import 'pages/channel_page.dart';
import 'theme.dart';
import '../l10n/l10n.dart';

/// The comments under a video or a post: sort order, comments with their
/// replies, and a button for more. It loads when first shown.
class CommentsSection extends StatefulWidget {
  const CommentsSection({super.key, required this.controller, this.videoId, this.postId, this.onSeek});
  final AppController controller;
  final String? videoId;
  final String? postId;
  /// Seeks the video when a timestamp in a comment is clicked.
  final void Function(Duration position)? onSeek;

  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  late final _loader = CommentsLoader(widget.controller.comments, videoId: widget.videoId, postId: widget.postId)..loadMore();
  /// The comment a reply is being written to.
  String? _replyingTo;

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
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
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(loader.count.isEmpty ? tr('评论') : tr('评论 · {0}', [loader.count]), style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [ButtonSegment(value: false, label: Text(tr('热门'))), ButtonSegment(value: true, label: Text(tr('最新')))],
                selected: {loader.newest},
                onSelectionChanged: (value) => loader.setNewest(value.first),
              ),
            ]),
            const SizedBox(height: 8),
            if (_canWrite) CommentComposer(hint: tr('添加评论…'), onSubmit: _post),
            for (final comment in loader.comments)
              if (!widget.controller.preferences.blocksCommenter(comment.author, comment.channelId)) ..._thread(context, comment),
            if (loader.loading)
              const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))))
            else if (error != null)
              ErrorBanner(loader.comments.isEmpty ? tr('无法加载评论：{0}', [error]) : tr('加载更多评论失败：{0}', [error]), onRetry: () => loader.loadMore(retry: true))
            else if (loader.started && loader.comments.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(tr('还没有评论，或评论已关闭'), style: TextStyle(color: colors.outline)))
            else if (loader.hasMore)
              Center(child: TextButton(onPressed: loader.loadMore, child: Text(tr('加载更多评论')))),
          ]);
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
          LinkedText(comment.text, style: const TextStyle(height: 1.45), onTime: onSeek ?? (_) {}, onLink: openExternal),
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: TextField(
            controller: _text,
            autofocus: widget.autofocus,
            enabled: !_sending,
            minLines: 1,
            maxLines: 5,
            maxLength: 10000,
            decoration: InputDecoration(hintText: widget.hint, isDense: true, counterText: '', border: const OutlineInputBorder()),
          )),
          const SizedBox(width: 8),
          if (widget.onCancel != null) TextButton(onPressed: _sending ? null : widget.onCancel, child: Text(tr('取消'))),
          ListenableBuilder(
            listenable: _text,
            builder: (context, _) => FilledButton(
              onPressed: _sending || _text.text.trim().isEmpty ? null : _send,
              child: _sending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(tr('发布')),
            ),
          ),
        ]),
      );
}
