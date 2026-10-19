import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/library_controller.dart';
import '../../library_store.dart';
import '../../models.dart';
import '../common.dart';
import '../theme.dart';
import '../video_card.dart';
import 'channel_page.dart';

/// Newest uploads of the channels followed on this computer.
class SubscriptionsPage extends StatelessWidget {
  const SubscriptionsPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final library = controller.library;
    if (library == null) return const SizedBox.shrink();
    final channels = library.channels;
    if (channels.isEmpty) {
      return const StatusView(
        icon: Icons.subscriptions_outlined,
        title: '还没有关注频道',
        message: '在播放页或频道页点“关注”，频道的新视频就会出现在这里。关注列表只保存在本机。',
      );
    }
    final feed = library.feed;
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(child: PageHeader(
        '订阅',
        subtitle: '${channels.length} 个频道 · 仅保存在本机',
        trailing: library.loadingFeed
            ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
            : TextButton.icon(onPressed: () => library.refreshFeed(force: true), icon: const Icon(Icons.refresh_rounded), label: const Text('刷新')),
      )),
      SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, AppStyle.cardSpacing),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final channel in channels)
            ActionChip(
              avatar: ChannelAvatar(name: channel.name, radius: 12),
              label: Text(channel.name.isEmpty ? channel.id : channel.name),
              onPressed: () => controller.openChannel(channel),
            ),
        ]),
      )),
      if (library.feedFailures.isNotEmpty)
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, AppStyle.cardSpacing),
          child: ErrorBanner('这些频道暂时无法加载：${library.feedFailures.join('、')}', onRetry: () => library.refreshFeed(force: true)),
        )),
      if (feed.isNotEmpty)
        SliverVideoGrid(items: feed, thumbnails: controller.thumbnailDirectory, onOpen: (item) => controller.play(item, from: feed))
      else if (library.loadingFeed)
        const SliverSkeletonGrid()
      else
        const SliverFillRemaining(hasScrollBody: false, child: StatusView(icon: Icons.inbox_outlined, title: '暂时没有新视频')),
      const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
    ]);
  }
}

/// Favorites and the local playlists.
class PlaylistsPage extends StatelessWidget {
  const PlaylistsPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final library = controller.library;
    if (library == null) return const SizedBox.shrink();
    final entries = [
      (AppController.favoritesPlaylistId, '收藏', library.favorites, Icons.favorite_rounded),
      for (final playlist in library.playlists) (playlist.id, playlist.name, playlist.items, Icons.playlist_play_rounded),
    ];
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(child: PageHeader(
        '播放列表',
        subtitle: '仅保存在本机',
        trailing: FilledButton.tonalIcon(
          onPressed: () async {
            final name = await promptText(context, title: '新建播放列表', hint: '播放列表名称', confirm: '创建');
            if (name != null) library.createPlaylist(name);
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('新建'),
        ),
      )),
      SliverVideoLayout(
        count: entries.length,
        builder: (context, i) {
          final (id, name, items, icon) = entries[i];
          return _PlaylistCard(
            name: name,
            items: items,
            icon: icon,
            thumbnails: controller.thumbnailDirectory,
            onOpen: () => controller.openPlaylist(id),
          );
        },
      ),
      if (library.playlists.isEmpty)
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.all(AppStyle.pagePadding),
          child: Text('右键点击任意视频，可以收藏或添加到播放列表。', style: TextStyle(color: context.colors.onSurfaceVariant)),
        )),
      const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
    ]);
  }
}

/// A grid laid out like the video grid, for cards other than videos.
class SliverVideoLayout extends StatelessWidget {
  const SliverVideoLayout({super.key, required this.count, required this.builder});
  final int count;
  final IndexedWidgetBuilder builder;

  @override
  Widget build(BuildContext context) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppStyle.pagePadding),
        sliver: SliverLayoutBuilder(builder: (context, constraints) {
          final layout = gridLayoutFor(constraints.crossAxisExtent);
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: layout.columns,
              mainAxisSpacing: AppStyle.cardSpacing,
              crossAxisSpacing: AppStyle.cardSpacing,
              mainAxisExtent: layout.itemHeight,
            ),
            delegate: SliverChildBuilderDelegate(builder, childCount: count),
          );
        }),
      );
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.name, required this.items, required this.icon, required this.thumbnails, required this.onOpen});
  final String name;
  final List<VideoItem> items;
  final IconData icon;
  final Directory? thumbnails;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Card(
      child: InkWell(
        onTap: onOpen,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: AppStyle.thumbnailRadius,
              child: Stack(fit: StackFit.expand, children: [
                if (items.isEmpty)
                  ColoredBox(color: colors.surfaceContainerHighest, child: Icon(icon, size: 40, color: colors.outline))
                else
                  Image(
                    image: thumbnailFor(items.first, thumbnails),
                    fit: BoxFit.cover,
                    errorBuilder: (context, _, __) => ColoredBox(color: colors.surfaceContainerHighest),
                  ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 96,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.62),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(icon, color: Colors.white),
                      const SizedBox(height: 4),
                      Text('${items.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
          Expanded(child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.onSurface))),
              Text('${items.length} 个视频', style: TextStyle(fontSize: 12, color: colors.outline)),
            ]),
          )),
        ]),
      ),
    );
  }
}

/// One playlist, or the favorites, with play-all, rename and delete.
class PlaylistDetailPage extends StatelessWidget {
  const PlaylistDetailPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final library = controller.library;
    final id = controller.openPlaylistId;
    if (library == null || id == null) return const SizedBox.shrink();
    final favorites = id == AppController.favoritesPlaylistId;
    final playlist = favorites ? null : library.playlist(id);
    if (!favorites && playlist == null) {
      return StatusView(
        icon: Icons.playlist_remove_rounded,
        title: '播放列表已删除',
        action: FilledButton.tonal(onPressed: controller.goBack, child: const Text('返回')),
      );
    }
    final items = List<VideoItem>.of(favorites ? library.favorites : playlist!.items);
    final name = favorites ? '收藏' : playlist!.name;
    void remove(VideoItem item) => favorites ? library.toggleFavorite(item) : library.removeFromPlaylist(playlist!, item);
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding - 8, 8, AppStyle.pagePadding, 16),
        child: Row(children: [
          IconButton(tooltip: '返回 (Alt+←)', onPressed: controller.goBack, icon: const Icon(Icons.arrow_back_rounded)),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            Text('${items.length} 个视频 · 仅保存在本机', style: TextStyle(color: context.colors.onSurfaceVariant)),
          ])),
          FilledButton.icon(
            onPressed: items.isEmpty ? null : () => controller.play(items.first, from: items),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('播放全部'),
          ),
          if (playlist != null) ...[
            const SizedBox(width: 4),
            IconButton(tooltip: '重命名', onPressed: () => _rename(context, library, playlist), icon: const Icon(Icons.edit_outlined)),
            IconButton(tooltip: '删除播放列表', onPressed: () => _delete(context, library, playlist), icon: const Icon(Icons.delete_outline_rounded)),
          ],
        ]),
      )),
      if (items.isEmpty)
        SliverFillRemaining(hasScrollBody: false, child: StatusView(
          icon: favorites ? Icons.favorite_border_rounded : Icons.playlist_add_rounded,
          title: favorites ? '还没有收藏视频' : '这个播放列表是空的',
          message: '右键点击任意视频，或在播放页点按钮，就能添加到这里。',
        ))
      else
        SliverVideoGrid(items: items, thumbnails: controller.thumbnailDirectory, onOpen: (item) => controller.play(item, from: items), onRemove: remove),
      const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
    ]);
  }

  Future<void> _rename(BuildContext context, LibraryController library, LocalPlaylist playlist) async {
    final name = await promptText(context, title: '重命名播放列表', hint: '播放列表名称', confirm: '保存', initial: playlist.name);
    if (name != null) library.renamePlaylist(playlist, name);
  }

  Future<void> _delete(BuildContext context, LibraryController library, LocalPlaylist playlist) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text('删除“${playlist.name}”？'),
      content: const Text('只删除这个播放列表，视频和观看记录不受影响。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
      ],
    ));
    if (confirmed == true) {
      library.deletePlaylist(playlist);
      controller.goBack();
    }
  }
}
