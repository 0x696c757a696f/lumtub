import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/posts_loader.dart';
import '../../app/video_list_loader.dart';
import '../../community_posts.dart';
import '../../models.dart';
import '../../video_repository.dart';
import '../comments_view.dart';
import '../common.dart';
import '../theme.dart';
import '../video_card.dart';

/// A channel's page: header with follow button, tabs for videos, Shorts,
/// live streams, playlists and posts, and a search inside the channel.
class ChannelPage extends StatelessWidget {
  const ChannelPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final channel = controller.channel;
    final loader = controller.channelVideos;
    final posts = controller.channelPosts;
    if (channel == null || (loader == null && posts == null)) {
      return const StatusView(icon: Icons.account_circle_outlined, title: '没有打开的频道');
    }
    final tab = controller.channelTab;
    final searching = controller.channelQuery != null;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 800) {
          loader?.loadMore();
          posts?.loadMore();
        }
        return false;
      },
      child: CustomScrollView(key: const PageStorageKey('list'), slivers: [
        SliverToBoxAdapter(child: ChannelHeader(controller: controller, channel: channel, onBack: controller.goBack)),
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, 16),
          child: Row(children: [
            Expanded(child: searching
                ? Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text('搜索“${controller.channelQuery}”', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    // 全部 is YouTube's channel search; the others filter
                    // one tab by title.
                    for (final value in <ChannelTab?>[null, ...ChannelTab.values])
                      ChoiceChip(
                        label: Text(value?.label ?? '全部'),
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
        if (posts != null) ..._postSlivers(context, posts) else ..._listingSlivers(context, loader!, tab, searching),
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
          child: ErrorBanner(empty ? '无法加载：$error' : '加载更多失败：$error', onRetry: () => loader.loadMore(retry: true)),
        )),
      if (empty && !loader.loading && error == null)
        SliverFillRemaining(hasScrollBody: false, child: searching
            ? const StatusView(icon: Icons.search_off_rounded, title: '频道里没有找到相关内容', message: '换个关键词试试。')
            : StatusView(icon: Icons.video_library_outlined, title: '这个频道没有${tab.label}')),
    ];
  }

  List<Widget> _postSlivers(BuildContext context, PostsLoader loader) {
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
              child: PostCard(post: posts[i], channel: controller.channel!, onPlay: (video) => controller.play(video), onComments: () => showPostComments(context, controller, posts[i])),
            ),
          ),
        ),
      ),
      if (loader.loading)
        const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))),
      if (error != null)
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, AppStyle.cardSpacing, AppStyle.pagePadding, 0),
          child: ErrorBanner(posts.isEmpty ? '无法加载社区帖子：$error' : '加载更多失败：$error', onRetry: () => loader.loadMore(retry: true)),
        )),
      if (posts.isEmpty && !loader.loading && error == null)
        SliverFillRemaining(
          hasScrollBody: false,
          child: controller.channelQuery != null
              ? const StatusView(icon: Icons.search_off_rounded, title: '没有找到相关的社区帖子', message: '只搜索了最近的帖子，换个关键词试试。')
              : const StatusView(icon: Icons.forum_outlined, title: '这个频道还没有社区帖子'),
        ),
    ];
  }
}

/// The comments under [post], in a dialog over the channel page.
Future<void> showPostComments(BuildContext context, AppController controller, CommunityPost post) => showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(children: [
                Expanded(child: Text(post.text.isEmpty ? '帖子评论' : post.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium)),
                IconButton(tooltip: '关闭', icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).pop()),
              ]),
            ),
            Flexible(child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: CommentsSection(controller: controller, postId: post.id),
            )),
          ]),
        ),
      ),
    );

/// One community post: text, images, an attached video or poll, likes.
class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.post, required this.channel, required this.onPlay, this.onComments});
  final CommunityPost post;
  final VoidCallback? onComments;
  final ChannelRef channel;
  final void Function(VideoItem video) onPlay;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final video = post.video;
    return Card(child: Padding(
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
          SelectableText(post.text, style: const TextStyle(height: 1.5)),
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
                child: Image.network(post.images[i], fit: BoxFit.cover, errorBuilder: (context, error, stack) => const SizedBox(width: 240)),
              ),
            ),
          ),
        ],
        if (post.poll.isNotEmpty) ...[
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
          Icon(Icons.thumb_up_outlined, size: 16, color: colors.outline),
          const SizedBox(width: 6),
          Text(post.likes.isEmpty ? '0' : post.likes, style: TextStyle(color: colors.outline, fontSize: 12)),
          const SizedBox(width: 16),
          TextButton.icon(
            onPressed: onComments,
            icon: const Icon(Icons.comment_outlined, size: 16),
            label: Text(post.comments.isEmpty ? '评论' : post.comments, style: const TextStyle(fontSize: 12)),
          ),
          const Spacer(),
          TextButton.icon(onPressed: () => openExternal(post.url), icon: const Icon(Icons.open_in_new_rounded, size: 16), label: const Text('在浏览器中查看')),
        ]),
      ]),
    ));
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
        onSubmitted: (text) => widget.controller.searchChannel(text, within: widget.controller.channelSearchTab),
        decoration: InputDecoration(
          isDense: true,
          hintText: '搜索频道内的视频',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: ListenableBuilder(
            listenable: _text,
            builder: (context, _) => _text.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: '清除',
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
    final name = channel.name.isEmpty ? 'YouTube 频道' : channel.name;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding - 8, 8, AppStyle.pagePadding, 20),
      child: Row(children: [
        if (onBack != null) IconButton(tooltip: '返回 (Alt+←)', onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded)),
        const SizedBox(width: 8),
        ChannelAvatar(name: name, radius: 28),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('YouTube 频道', style: TextStyle(color: colors.onSurfaceVariant)),
        ])),
        FollowButton(controller: controller, channel: channel),
        const SizedBox(width: 8),
        IconButton(tooltip: '在浏览器中打开', onPressed: () => openExternal(channel.url), icon: const Icon(Icons.open_in_new_rounded)),
      ]),
    );
  }
}

/// A round avatar: the channel's picture when a search listed one, else the
/// first letter of its name.
class ChannelAvatar extends StatelessWidget {
  const ChannelAvatar({super.key, required this.name, this.radius = 18, this.image});
  final String name;
  final double radius;
  final String? image;

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
    return ClipOval(child: Image.network(
      url,
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
    final name = ref.name.isEmpty ? 'YouTube 频道' : ref.name;
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
          FollowButton(controller: controller, channel: ref),
        ]),
      ),
    ));
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
      final now = library.toggleFollow(channel);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(now ? '已关注，新视频会出现在“订阅”里' : '已取消关注')));
    }

    return following
        ? FilledButton.tonalIcon(onPressed: toggle, icon: const Icon(Icons.check_rounded), label: const Text('已关注'))
        : FilledButton.icon(onPressed: toggle, icon: const Icon(Icons.add_rounded), label: const Text('关注'));
  }
}
