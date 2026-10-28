import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/posts_loader.dart';
import '../../app/video_list_loader.dart';
import '../../community_posts.dart';
import '../../models.dart';
import '../../thumbnail_cache.dart';
import '../../video_repository.dart';
import '../comments_view.dart';
import '../common.dart';
import '../rating_buttons.dart';
import '../theme.dart';
import '../translatable.dart';
import '../video_card.dart';
import '../../l10n/l10n.dart';

/// A channel's page: header with follow button, tabs for videos, Shorts,
/// live streams, playlists and posts, and a search inside the channel.
class ChannelPage extends StatefulWidget {
  const ChannelPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<ChannelPage> createState() => _ChannelPageState();
}

class _ChannelPageState extends State<ChannelPage> {
  /// Below this width a post's comments open as their own page instead of
  /// beside the posts.
  static const _sideBySide = 960.0;
  static const _panelWidth = 440.0;

  /// The post whose comments are open on the right.
  CommunityPost? _commentsFor;

  AppController get controller => widget.controller;

  void _openComments(CommunityPost post, bool wide) {
    if (wide) {
      setState(() => _commentsFor = _commentsFor?.id == post.id ? null : post);
    } else {
      showPostComments(context, controller, post);
    }
  }

  void _closeComments() => setState(() => _commentsFor = null);

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= _sideBySide;
        final posts = controller.channelPosts;
        // Only while that post is still listed.
        final open = _commentsFor;
        final shown = wide && open != null && posts != null && posts.posts.any((p) => p.id == open.id) ? open : null;
        final list = _list(context, wide, shown);
        if (shown == null) return list;
        return CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): _closeComments},
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: list),
            const VerticalDivider(width: 1),
            SizedBox(width: _panelWidth, child: PostCommentsPanel(key: ValueKey(shown.id), controller: controller, post: shown, onClose: _closeComments)),
          ]),
        );
      });

  Widget _list(BuildContext context, bool wide, CommunityPost? shown) {
    final channel = controller.channel;
    final loader = controller.channelVideos;
    final posts = controller.channelPosts;
    if (channel == null || (loader == null && posts == null)) {
      return StatusView(icon: Icons.account_circle_outlined, title: tr('没有打开的频道'));
    }
    final tab = controller.channelTab;
    final searching = controller.channelQuery != null;
    return NearEndListener(
      onNearEnd: () {
        loader?.loadMore();
        posts?.loadMore();
      },
      child: CustomScrollView(key: const PageStorageKey('list'), slivers: [
        SliverToBoxAdapter(child: ChannelHeader(controller: controller, channel: channel, onBack: controller.goBack)),
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, 16),
          child: Row(children: [
            Expanded(child: searching
                ? Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(tr('搜索“{0}”', [controller.channelQuery]), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    // 全部 is YouTube's channel search; the others filter
                    // one tab by title.
                    for (final value in <ChannelTab?>[null, ...ChannelTab.values])
                      ChoiceChip(
                        label: Text(value?.label ?? tr('全部')),
                        selected: controller.channelSearchTab == value,
                        onSelected: (_) => controller.searchChannel(controller.channelQuery!, within: value),
                      ),
                  ])
                : Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final value in ChannelTab.values)
                      ChoiceChip(label: Text(value.label), selected: tab == value, onSelected: (_) => controller.setChannelTab(value)),
                  ])),
            const SizedBox(width: 12),
            SizedBox(width: 240, child: _ChannelSearchField(key: ValueKey((channel.id, controller.channelQuery == null)), controller: controller)),
          ]),
        )),
        if (posts != null) ..._postSlivers(context, posts, wide, shown) else ..._listingSlivers(context, loader!, tab, searching),
        const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
      ]),
    );
  }

  List<Widget> _listingSlivers(BuildContext context, VideoListLoader loader, ChannelTab tab, bool searching) {
    final items = loader.items;
    final playlists = loader.playlists;
    final error = loader.error;
    final empty = items.isEmpty && playlists.isEmpty;
    return [
      if (playlists.isNotEmpty) ...[
        SliverPlaylistGrid(items: playlists, onOpen: controller.openYoutubePlaylist),
        if (items.isNotEmpty) const SliverToBoxAdapter(child: SizedBox(height: AppStyle.cardSpacing)),
      ],
      if (items.isNotEmpty) SliverVideoGrid(items: items, thumbnails: controller.thumbnailDirectory, onOpen: (item) => controller.play(item, from: items)),
      if (loader.loading) ...[
        if (!empty) const SliverToBoxAdapter(child: SizedBox(height: AppStyle.cardSpacing)),
        SliverSkeletonGrid(rows: empty ? 3 : 1),
      ],
      if (error != null)
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, AppStyle.cardSpacing, AppStyle.pagePadding, 0),
          child: ErrorBanner(empty ? tr('无法加载：{0}', [error]) : tr('加载更多失败：{0}', [error]), onRetry: () => loader.loadMore(retry: true)),
        )),
      if (empty && !loader.loading && error == null)
        SliverFillRemaining(hasScrollBody: false, child: searching
            ? StatusView(icon: Icons.search_off_rounded, title: tr('频道里没有找到相关内容'), message: tr('换个关键词试试。'))
            : StatusView(icon: Icons.video_library_outlined, title: tr('这个频道没有{0}', [tab.label]))),
    ];
  }

  List<Widget> _postSlivers(BuildContext context, PostsLoader loader, bool wide, CommunityPost? shown) {
    final posts = loader.posts;
    final error = loader.error;
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppStyle.pagePadding),
        sliver: SliverList.separated(
          itemCount: posts.length,
          separatorBuilder: (context, i) => const SizedBox(height: AppStyle.cardSpacing),
          itemBuilder: (context, i) => Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: PostCard(
                controller: controller,
                post: posts[i],
                channel: controller.channel!,
                selected: shown?.id == posts[i].id,
                onPlay: (video) => controller.play(video),
                onComments: () => _openComments(posts[i], wide),
              ),
            ),
          ),
        ),
      ),
      if (loader.loading)
        const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))),
      if (error != null)
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, AppStyle.cardSpacing, AppStyle.pagePadding, 0),
          child: ErrorBanner(posts.isEmpty ? tr('无法加载社区帖子：{0}', [error]) : tr('加载更多失败：{0}', [error]), onRetry: () => loader.loadMore(retry: true)),
        )),
      if (posts.isEmpty && !loader.loading && error == null)
        SliverFillRemaining(
          hasScrollBody: false,
          child: controller.channelQuery != null
              ? StatusView(icon: Icons.search_off_rounded, title: tr('没有找到相关的社区帖子'), message: tr('只搜索了最近的帖子，换个关键词试试。'))
              : StatusView(icon: Icons.forum_outlined, title: tr('这个频道还没有社区帖子')),
        ),
    ];
  }
}

/// The comments under [post] as their own page, for narrow windows.
Future<void> showPostComments(BuildContext context, AppController controller, CommunityPost post) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        body: SafeArea(child: PostCommentsPanel(controller: controller, post: post, onClose: () => Navigator.of(context).pop())),
      ),
    ));

/// A post's comments beside the posts: the post's text, then its
/// comments, scrolling on their own.
class PostCommentsPanel extends StatelessWidget {
  const PostCommentsPanel({super.key, required this.controller, required this.post, required this.onClose});
  final AppController controller;
  final CommunityPost post;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
          child: Row(children: [
            Expanded(child: Text(tr('帖子评论'), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
            IconButton(tooltip: tr('关闭 (Esc)'), icon: const Icon(Icons.close_rounded), onPressed: onClose),
          ]),
        ),
        if (post.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(post.text, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.colors.outline, height: 1.4)),
          ),
        const Divider(height: 1),
        Expanded(
          child: CommentsSection(
            key: PageStorageKey('post-comments:${post.id}'),
            controller: controller,
            postId: post.id,
            scrollable: true,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          ),
        ),
      ]);
}

/// One community post: text, images, an attached video or poll, likes.
class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.controller, required this.post, required this.channel, required this.onPlay, this.onComments, this.selected = false});
  final AppController controller;
  final CommunityPost post;
  /// Whether its comments are open beside it.
  final bool selected;
  final VoidCallback? onComments;
  final ChannelRef channel;
  final void Function(VideoItem video) onPlay;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final video = post.video;
    return Card(
      shape: selected ? RoundedRectangleBorder(borderRadius: AppStyle.cardRadius, side: BorderSide(color: colors.primary, width: 1.5)) : null,
      child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ChannelAvatar(name: channel.name, radius: 16),
          const SizedBox(width: 10),
          Expanded(child: Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(post.published, style: TextStyle(color: colors.outline, fontSize: 12)),
        ]),
        if (post.text.isNotEmpty) ...[
          const SizedBox(height: 10),
          Translatable(controller: controller, text: post.text, builder: (context, text) => SelectableText(text, style: const TextStyle(height: 1.5))),
        ],
        if (post.images.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 240,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: post.images.length,
              separatorBuilder: (context, i) => const SizedBox(width: 8),
              itemBuilder: (context, i) => ClipRRect(
                borderRadius: AppStyle.thumbnailRadius,
                child: Image.network(
                  post.images[i],
                  cacheHeight: (240 * MediaQuery.devicePixelRatioOf(context)).ceil(),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => const SizedBox(width: 240),
                ),
              ),
            ),
          ),
        ],
        if (post.choices.isNotEmpty && controller.channelPosts != null) ...[
          const SizedBox(height: 10),
          _Poll(post: post, loader: controller.channelPosts!),
        ] else if (post.poll.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final choice in post.poll)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(border: Border.all(color: colors.outlineVariant), borderRadius: BorderRadius.circular(8)),
              child: Text(choice),
            ),
        ],
        if (video != null) ...[
          const SizedBox(height: 10),
          CompactVideoTile(item: video, onOpen: () => onPlay(video)),
        ],
        const SizedBox(height: 8),
        Row(children: [
          RatingButtons(
            likes: post.likes,
            state: controller.channelPosts?.ratingOf(post) ?? '',
            loaded: post.rating?.state ?? '',
            onRate: post.rating == null || controller.channelPosts == null ? null : (want) => controller.channelPosts!.rate(post, want),
          ),
          const SizedBox(width: 16),
          TextButton.icon(
            onPressed: onComments,
            icon: const Icon(Icons.comment_outlined, size: 16),
            label: Text(post.comments.isEmpty ? tr('评论') : post.comments, style: const TextStyle(fontSize: 12)),
          ),
          const Spacer(),
          TextButton.icon(onPressed: () => openExternal(post.url), icon: const Icon(Icons.open_in_new_rounded, size: 16), label: Text(tr('在浏览器中查看'))),
        ]),
      ]),
    ));
  }
}

/// A poll that can be voted in: a choice is voted for by tapping it, and
/// tapped again to take the vote back. The shares show once YouTube gave
/// them, which it does after a vote.
class _Poll extends StatelessWidget {
  const _Poll({required this.post, required this.loader});
  final CommunityPost post;
  final PostsLoader loader;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final voted = loader.voteOf(post);
    Future<void> vote(int index) async {
      final failed = await loader.vote(post, index);
      if (failed != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failed)));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (index, choice) in post.choices.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: voted == index ? colors.primary : colors.outlineVariant, width: voted == index ? 1.5 : 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => vote(index),
              child: Stack(children: [
                if (voted >= 0 && choice.ratio != null)
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: choice.ratio!.clamp(0.0, 1.0),
                      child: ColoredBox(color: colors.primary.withValues(alpha: 0.12)),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(children: [
                    Icon(voted == index ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 18, color: voted == index ? colors.primary : colors.outline),
                    const SizedBox(width: 8),
                    Expanded(child: Text(choice.text)),
                    if (voted >= 0 && choice.percent.isNotEmpty) Text(choice.percent, style: TextStyle(color: colors.outline, fontSize: 12)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      if (post.votes.isNotEmpty) Text(post.votes, style: TextStyle(color: colors.outline, fontSize: 12)),
    ]);
  }
}

/// Searches the open channel's videos; clearing it lists the uploads again.
class _ChannelSearchField extends StatefulWidget {
  const _ChannelSearchField({super.key, required this.controller});
  final AppController controller;

  @override
  State<_ChannelSearchField> createState() => _ChannelSearchFieldState();
}

class _ChannelSearchFieldState extends State<_ChannelSearchField> {
  bool get _posts {
    final controller = widget.controller;
    return controller.channelQuery == null ? controller.channelTab == ChannelTab.posts : controller.channelSearchTab == ChannelTab.posts;
  }

  late final _text = TextEditingController(text: widget.controller.channelQuery ?? '');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _text,
        textInputAction: TextInputAction.search,
        // Typed on the 社区 tab, it searches the posts; otherwise the
        // whole channel, until another chip is picked.
        onSubmitted: (text) => widget.controller.searchChannel(text, within: _posts ? ChannelTab.posts : widget.controller.channelSearchTab),
        decoration: InputDecoration(
          isDense: true,
          hintText: _posts ? tr('搜索频道内的帖子') : tr('搜索频道内的视频'),
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: ListenableBuilder(
            listenable: _text,
            builder: (context, _) => _text.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: tr('清除'),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      _text.clear();
                      widget.controller.searchChannel('');
                    },
                  ),
          ),
          border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
        ),
      );
}

/// Channel name, follow button and a link to the channel on YouTube.
class ChannelHeader extends StatelessWidget {
  const ChannelHeader({super.key, required this.controller, required this.channel, this.onBack});
  final AppController controller;
  final ChannelRef channel;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final name = channel.name.isEmpty ? tr('YouTube 频道') : channel.name;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding - 8, 8, AppStyle.pagePadding, 20),
      child: Row(children: [
        if (onBack != null) IconButton(tooltip: tr('返回 (Alt+←)'), onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded)),
        const SizedBox(width: 8),
        ChannelAvatar(name: name, radius: 28),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(tr('YouTube 频道'), style: TextStyle(color: colors.onSurfaceVariant)),
        ])),
        FollowButton(controller: controller, channel: channel),
        const SizedBox(width: 8),
        IconButton(tooltip: tr('在浏览器中打开'), onPressed: () => openExternal(channel.url), icon: const Icon(Icons.open_in_new_rounded)),
        ChannelMenuButton(controller: controller, channel: channel),
      ]),
    );
  }
}

/// A round avatar: the channel's picture when a search listed one, else the
/// first letter of its name.
class ChannelAvatar extends StatelessWidget {
  const ChannelAvatar({super.key, required this.name, this.radius = 18, this.image, this.cacheFile});
  final String name;
  final double radius;
  final String? image;
  /// Where the picture is kept once downloaded, so a long list of
  /// subscriptions does not fetch every picture again on each visit.
  final File? cacheFile;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final letter = name.trim().isEmpty ? '?' : String.fromCharCode(name.trim().runes.first).toUpperCase();
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: colors.primaryContainer,
      child: Text(letter, style: TextStyle(fontSize: radius * 0.85, fontWeight: FontWeight.w600, color: colors.onPrimaryContainer)),
    );
    final url = image;
    if (url == null) return fallback;
    final file = cacheFile;
    return ClipOval(child: Image(
      image: ResizeImage.resizeIfNeeded((radius * 4).round(), null, file == null ? NetworkImage(url) : CachedThumbnail(url, file)),
      width: radius * 2,
      height: radius * 2,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stack) => fallback,
    ));
  }
}

/// A channel in search results: avatar, name, subscribers and follow button.
class ChannelResultTile extends StatelessWidget {
  const ChannelResultTile({super.key, required this.controller, required this.result});
  final AppController controller;
  final ChannelResult result;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ref = result.ref;
    final name = ref.name.isEmpty ? tr('YouTube 频道') : ref.name;
    final meta = [if (result.handle != null) result.handle!, if (result.subscribers != null) result.subscribers!].join(' · ');
    return Card(child: InkWell(
      onTap: () => controller.openChannel(ref),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(children: [
          ChannelAvatar(name: name, radius: 30, image: result.avatar),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            if (meta.isNotEmpty) Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13)),
            if (result.description.isNotEmpty)
              Text(result.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13)),
          ])),
          const SizedBox(width: 12),
          FollowButton(controller: controller, channel: ChannelRef(ref.id, ref.name, result.avatar ?? ref.avatar)),
        ]),
      ),
    ));
  }
}

/// 屏蔽此频道 and 不推荐此频道, or undoing them, for a channel page or the
/// video playing.
class ChannelMenuButton extends StatelessWidget {
  const ChannelMenuButton({super.key, required this.controller, required this.channel});
  final AppController controller;
  final ChannelRef channel;

  @override
  Widget build(BuildContext context) {
    final prefs = controller.preferences;
    final blocked = prefs.isBlocked(channel.id);
    final unrecommended = prefs.isUnrecommended(channel.id);
    PopupMenuItem<String> entry(String value, IconData icon, String label) =>
        PopupMenuItem(value: value, child: ListTile(dense: true, leading: Icon(icon), title: Text(label)));
    return PopupMenuButton<String>(
      tooltip: tr('更多'),
      icon: const Icon(Icons.more_vert_rounded),
      itemBuilder: (context) => [
        unrecommended
            ? entry('recommend', Icons.thumb_up_off_alt_outlined, tr('恢复推荐此频道'))
            : entry('unrecommend', Icons.thumb_down_off_alt_outlined, tr('不推荐此频道')),
        blocked ? entry('unblock', Icons.person_outline_rounded, tr('取消屏蔽此频道')) : entry('block', Icons.block_rounded, tr('屏蔽此频道')),
      ],
      onSelected: (choice) => switch (choice) {
        'recommend' => controller.setRecommendChannel(channel, true),
        'unrecommend' => controller.setRecommendChannel(channel, false),
        'unblock' => controller.unblockChannel(channel.id),
        _ => controller.blockChannel(channel),
      },
    );
  }
}

class FollowButton extends StatelessWidget {
  const FollowButton({super.key, required this.controller, required this.channel});
  final AppController controller;
  final ChannelRef channel;

  @override
  Widget build(BuildContext context) {
    final library = controller.library;
    if (library == null) return const SizedBox.shrink();
    final following = library.isFollowing(channel.id);
    void toggle() {
      final now = controller.toggleFollow(channel);
      final youtube = (controller.account?.canWrite ?? false) && controller.preferences.syncFollowToYoutube;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(now ? (youtube ? tr('已关注，并在 YouTube 上订阅') : tr('已关注，新视频会出现在“订阅”里')) : (youtube ? tr('已取消关注和 YouTube 订阅') : tr('已取消关注')))));
    }

    return following
        ? FilledButton.tonalIcon(onPressed: toggle, icon: const Icon(Icons.check_rounded), label: Text(tr('已关注')))
        : FilledButton.icon(onPressed: toggle, icon: const Icon(Icons.add_rounded), label: Text(tr('关注')));
  }
}
