import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../models.dart';
import '../common.dart';
import '../theme.dart';
import '../video_card.dart';

/// A channel's uploads, newest first, with a follow button.
class ChannelPage extends StatelessWidget {
  const ChannelPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final channel = controller.channel;
    final loader = controller.channelVideos;
    if (channel == null || loader == null) {
      return const StatusView(icon: Icons.account_circle_outlined, title: '没有打开的频道');
    }
    final items = loader.items;
    final error = loader.error;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 800) loader.loadMore();
        return false;
      },
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: ChannelHeader(controller: controller, channel: channel, onBack: controller.goBack)),
        if (items.isNotEmpty) SliverVideoGrid(items: items, thumbnails: controller.thumbnailDirectory, onOpen: (item) => controller.play(item, from: items)),
        if (loader.loading) ...[
          if (items.isNotEmpty) const SliverToBoxAdapter(child: SizedBox(height: AppStyle.cardSpacing)),
          SliverSkeletonGrid(rows: items.isEmpty ? 3 : 1),
        ],
        if (error != null)
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, AppStyle.cardSpacing, AppStyle.pagePadding, 0),
            child: ErrorBanner(items.isEmpty ? '无法加载频道视频：$error' : '加载更多失败：$error', onRetry: () => loader.loadMore(retry: true)),
          )),
        if (items.isEmpty && !loader.loading && error == null)
          const SliverFillRemaining(hasScrollBody: false, child: StatusView(icon: Icons.video_library_outlined, title: '这个频道还没有视频')),
        const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
      ]),
    );
  }
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
          Text('最新上传', style: TextStyle(color: colors.onSurfaceVariant)),
        ])),
        FollowButton(controller: controller, channel: channel),
        const SizedBox(width: 8),
        IconButton(tooltip: '在浏览器中打开', onPressed: () => openExternal(channel.url), icon: const Icon(Icons.open_in_new_rounded)),
      ]),
    );
  }
}

/// A round avatar with the first letter of the channel's name; YouTube's
/// avatar images would need an extra request per channel.
class ChannelAvatar extends StatelessWidget {
  const ChannelAvatar({super.key, required this.name, this.radius = 18});
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final letter = name.trim().isEmpty ? '?' : String.fromCharCode(name.trim().runes.first).toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: colors.primaryContainer,
      child: Text(letter, style: TextStyle(fontSize: radius * 0.85, fontWeight: FontWeight.w600, color: colors.onPrimaryContainer)),
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
      final now = library.toggleFollow(channel);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(now ? '已关注，新视频会出现在“订阅”里' : '已取消关注')));
    }

    return following
        ? FilledButton.tonalIcon(onPressed: toggle, icon: const Icon(Icons.check_rounded), label: const Text('已关注'))
        : FilledButton.icon(onPressed: toggle, icon: const Icon(Icons.add_rounded), label: const Text('关注'));
  }
}
