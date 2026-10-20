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
import '../../l10n/l10n.dart';

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
      return StatusView(
        icon: Icons.subscriptions_outlined,
        title: tr('还没有关注频道'),
        message: tr('在播放页或频道页点“关注”，频道的新视频就会出现在这里。也可以登录 Google 账号，导入 YouTube 订阅。关注列表只保存在本机。'),
        action: controller.account?.signedIn ?? false
            ? null
            : FilledButton.tonalIcon(onPressed: () => controller.navigate(PageMode.settings), icon: const Icon(Icons.login_rounded), label: Text(tr('登录并导入订阅'))),
      );
    }
    final feed = controller.visible(library.feed, subscriptions: true);
    return CustomScrollView(key: const PageStorageKey('list'), slivers: [
      SliverToBoxAdapter(child: PageHeader(
        tr('订阅'),
        subtitle: tr('{0} 个频道 · 仅保存在本机', [channels.length]),
        trailing: library.loadingFeed
            ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
            : TextButton.icon(onPressed: () => library.refreshFeed(force: true), icon: const Icon(Icons.refresh_rounded), label: Text(tr('刷新'))),
      )),
      SliverToBoxAdapter(child: _ChannelStrip(controller: controller, channels: channels, feed: library.feed)),
      if (library.feedFailures.isNotEmpty)
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, AppStyle.cardSpacing),
          child: ErrorBanner(
            library.feedFailures.length > 5
                ? tr('{0} 等 {1} 个频道暂时无法加载', [library.feedFailures.take(5).join('、'), library.feedFailures.length])
                : tr('这些频道暂时无法加载：{0}', [library.feedFailures.join('、')]),
            onRetry: () => library.refreshFeed(force: true),
          ),
        )),
      if (feed.isNotEmpty)
        SliverVideoGrid(items: feed, thumbnails: controller.thumbnailDirectory, onOpen: (item) => controller.play(item, from: feed))
      else if (library.loadingFeed)
        const SliverSkeletonGrid()
      else
        SliverFillRemaining(hasScrollBody: false, child: StatusView(icon: Icons.inbox_outlined, title: tr('暂时没有新视频'))),
      const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
    ]);
  }
}

/// One scrolling row of the followed channels, the ones that posted most
/// recently first, and a button for the whole list. Hundreds of imported
/// subscriptions would otherwise push the videos off the page.
class _ChannelStrip extends StatelessWidget {
  const _ChannelStrip({required this.controller, required this.channels, required this.feed});
  final AppController controller;
  final List<ChannelRef> channels;
  final List<VideoItem> feed;

  static const shown = 40;

  @override
  Widget build(BuildContext context) {
    final recent = <String>{for (final item in feed) if (item.channelId != null) item.channelId!};
    final rank = {for (final (i, id) in recent.indexed) id: i};
    final ordered = [...channels]..sort((a, b) => (rank[a.id] ?? recent.length).compareTo(rank[b.id] ?? recent.length));
    return Padding(
      padding: const EdgeInsets.only(bottom: AppStyle.cardSpacing),
      child: SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppStyle.pagePadding),
          children: [
            ActionChip(
              avatar: const Icon(Icons.list_rounded, size: 18),
              label: Text(tr('全部 {0} 个', [channels.length])),
              onPressed: () => showDialog<void>(context: context, builder: (_) => _AllChannels(controller: controller, channels: channels)),
            ),
            for (final channel in ordered.take(shown))
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: ActionChip(
                  avatar: ChannelAvatar(name: channel.name, radius: 12),
                  label: Text(channel.name.isEmpty ? channel.id : channel.name),
                  onPressed: () => controller.openChannel(channel),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Every followed channel, in a list that can be searched by name.
class _AllChannels extends StatefulWidget {
  const _AllChannels({required this.controller, required this.channels});
  final AppController controller;
  final List<ChannelRef> channels;

  @override
  State<_AllChannels> createState() => _AllChannelsState();
}

class _AllChannelsState extends State<_AllChannels> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final matches = [
      for (final channel in widget.channels)
        if (query.isEmpty || channel.name.toLowerCase().contains(query)) channel,
    ];
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: tr('在 {0} 个关注的频道里搜索', [widget.channels.length]),
              ),
            ),
          ),
          Expanded(
            child: matches.isEmpty
                ? Center(child: Text(tr('没有匹配的频道')))
                : ListView.builder(
                    itemCount: matches.length,
                    itemBuilder: (context, i) {
                      final channel = matches[i];
                      return ListTile(
                        leading: ChannelAvatar(name: channel.name, radius: 16),
                        title: Text(channel.name.isEmpty ? channel.id : channel.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          Navigator.pop(context);
                          widget.controller.openChannel(channel);
                        },
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
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
      (AppController.favoritesPlaylistId, tr('收藏'), library.favorites, Icons.favorite_rounded),
      for (final playlist in library.playlists) (playlist.id, playlist.name, playlist.items, LibraryController.isRemote(playlist) ? Icons.smart_display_outlined : Icons.playlist_play_rounded),
    ];
    return CustomScrollView(key: const PageStorageKey('list'), slivers: [
      SliverToBoxAdapter(child: PageHeader(
        tr('播放列表'),
        subtitle: tr('仅保存在本机'),
        trailing: FilledButton.tonalIcon(
          onPressed: () async {
            final name = await promptText(context, title: tr('新建播放列表'), hint: tr('播放列表名称'), confirm: tr('创建'));
            if (name != null) library.createPlaylist(name);
          },
          icon: const Icon(Icons.add_rounded),
          label: Text(tr('新建')),
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
          child: Text(tr('右键点击任意视频，可以收藏或添加到播放列表。'), style: TextStyle(color: context.colors.onSurfaceVariant)),
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
              Text(tr('{0} 个视频', [items.length]), style: TextStyle(fontSize: 12, color: colors.outline)),
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
        title: tr('播放列表已删除'),
        action: FilledButton.tonal(onPressed: controller.goBack, child: Text(tr('返回'))),
      );
    }
    final items = List<VideoItem>.of(favorites ? library.favorites : playlist!.items);
    final name = favorites ? tr('收藏') : playlist!.name;
    void remove(VideoItem item) => favorites ? library.toggleFavorite(item) : library.removeFromPlaylist(playlist!, item);
    return CustomScrollView(key: const PageStorageKey('list'), slivers: [
      SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding - 8, 8, AppStyle.pagePadding, 16),
        child: Row(children: [
          IconButton(tooltip: tr('返回 (Alt+←)'), onPressed: controller.goBack, icon: const Icon(Icons.arrow_back_rounded)),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            Text(
              playlist != null && LibraryController.isRemote(playlist) ? tr('{0} 个视频 · 来自 YouTube 账号，同步时会更新', [items.length]) : tr('{0} 个视频 · 仅保存在本机', [items.length]),
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
          ])),
          FilledButton.icon(
            onPressed: items.isEmpty ? null : () => controller.play(items.first, from: items),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(tr('播放全部')),
          ),
          if (playlist != null) ...[
            const SizedBox(width: 4),
            IconButton(tooltip: tr('重命名'), onPressed: () => _rename(context, library, playlist), icon: const Icon(Icons.edit_outlined)),
            IconButton(tooltip: tr('删除播放列表'), onPressed: () => _delete(context, library, playlist), icon: const Icon(Icons.delete_outline_rounded)),
          ],
        ]),
      )),
      if (items.isEmpty)
        SliverFillRemaining(hasScrollBody: false, child: StatusView(
          icon: favorites ? Icons.favorite_border_rounded : Icons.playlist_add_rounded,
          title: favorites ? tr('还没有收藏视频') : tr('这个播放列表是空的'),
          message: tr('右键点击任意视频，或在播放页点按钮，就能添加到这里。'),
        ))
      else
        SliverVideoGrid(items: items, thumbnails: controller.thumbnailDirectory, onOpen: (item) => controller.play(item, from: items), onRemove: remove),
      const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
    ]);
  }

  Future<void> _rename(BuildContext context, LibraryController library, LocalPlaylist playlist) async {
    final name = await promptText(context, title: tr('重命名播放列表'), hint: tr('播放列表名称'), confirm: tr('保存'), initial: playlist.name);
    if (name != null) library.renamePlaylist(playlist, name);
  }

  Future<void> _delete(BuildContext context, LibraryController library, LocalPlaylist playlist) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(tr('删除“{0}”？', [playlist.name])),
      content: Text(tr('只删除这个播放列表，视频和观看记录不受影响。')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('取消'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('删除'))),
      ],
    ));
    if (confirmed == true) {
      library.deletePlaylist(playlist);
      controller.goBack();
    }
  }
}
