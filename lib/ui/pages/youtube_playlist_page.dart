import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../common.dart';
import '../theme.dart';
import '../video_card.dart';
import '../../l10n/l10n.dart';

/// A YouTube playlist's videos, with play-all and a link to YouTube.
class YoutubePlaylistPage extends StatelessWidget {
  const YoutubePlaylistPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final playlist = controller.youtubePlaylist;
    final loader = controller.youtubePlaylistVideos;
    if (playlist == null || loader == null) {
      return StatusView(icon: Icons.playlist_play_rounded, title: tr('没有打开的播放列表'));
    }
    final items = controller.visible(loader.items);
    final error = loader.error;
    final colors = context.colors;
    return NearEndListener(
      onNearEnd: loader.loadMore,
      child: CustomScrollView(key: const PageStorageKey('list'), slivers: [
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding - 8, 8, AppStyle.pagePadding, 20),
          child: Row(children: [
            IconButton(tooltip: tr('返回 (Alt+←)'), onPressed: controller.goBack, icon: const Icon(Icons.arrow_back_rounded)),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(playlist.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                [if (playlist.channel.isNotEmpty) playlist.channel, if (playlist.count != null) tr('{0} 个视频', [playlist.count]), tr('YouTube 播放列表')].join(' · '),
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ])),
            FilledButton.icon(
              onPressed: items.isEmpty ? null : () => controller.play(items.first, from: items),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(tr('全部播放')),
            ),
            const SizedBox(width: 8),
            IconButton(tooltip: tr('在浏览器中打开'), onPressed: () => openExternal(playlist.url), icon: const Icon(Icons.open_in_new_rounded)),
          ]),
        )),
        if (items.isNotEmpty) SliverVideoGrid(items: items, thumbnails: controller.thumbnailDirectory, onOpen: (item) => controller.play(item, from: items)),
        if (loader.loading) ...[
          if (items.isNotEmpty) const SliverToBoxAdapter(child: SizedBox(height: AppStyle.cardSpacing)),
          SliverSkeletonGrid(rows: items.isEmpty ? 3 : 1),
        ],
        if (error != null)
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, AppStyle.cardSpacing, AppStyle.pagePadding, 0),
            child: ErrorBanner(items.isEmpty ? tr('无法加载播放列表：{0}', [error]) : tr('加载更多失败：{0}', [error]), onRetry: () => loader.loadMore(retry: true)),
          )),
        if (items.isEmpty && !loader.loading && error == null)
          SliverFillRemaining(hasScrollBody: false, child: StatusView(icon: Icons.playlist_remove_rounded, title: tr('这个播放列表是空的'))),
        const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
      ]),
    );
  }
}
