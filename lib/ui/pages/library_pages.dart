import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../../app/app_controller.dart';
import '../../app/library_controller.dart';
import '../../library_store.dart';
import '../../models.dart';
import '../common.dart';
import '../theme.dart';
import '../video_card.dart';
import 'channel_page.dart';
import 'explore_page.dart';
import '../../l10n/l10n.dart';

/// Newest uploads of the channels followed on this computer, under a row of
/// their avatars, the ones that posted most recently first. Picking an
/// avatar narrows the videos to that channel without leaving the page.
class SubscriptionsPage extends StatefulWidget {
  const SubscriptionsPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  ChannelRef? _selected;

  AppController get controller => widget.controller;

  void _select(ChannelRef? channel) => setState(() => _selected = channel == _selected ? null : channel);

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
    final selected = channels.contains(_selected) ? _selected : null;
    final all = controller.visible(library.feed, subscriptions: true);
    final feed = selected == null ? all : [for (final item in all) if (item.channelId == selected.id) item];
    Widget strip({bool vertical = false}) => _ChannelStrip(
          vertical: vertical,
          channels: channels,
          feed: library.feed,
          selected: selected,
          thumbnails: controller.thumbnailDirectory,
          onSelect: _select,
          onShowAll: () => showDialog<void>(
            context: context,
            builder: (_) => _AllChannels(channels: channels, thumbnails: controller.thumbnailDirectory, onSelect: _select, onOpen: controller.openChannel),
          ),
        );
    // A wide window lists the channels down the left, as Bilibili's 动态 does.
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= ExplorePage.wideLayout;
      final page = _page(context, library, channels, selected, feed, wide ? null : strip());
      if (!wide) return page;
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: _ChannelStrip.railWidth, child: strip(vertical: true)),
        Expanded(child: page),
      ]);
    });
  }

  Widget _page(BuildContext context, LibraryController library, List<ChannelRef> channels, ChannelRef? selected, List<VideoItem> feed, Widget? strip) {
    return CustomScrollView(key: const PageStorageKey('list'), slivers: [
      SliverToBoxAdapter(child: PageHeader(
        tr('订阅'),
        subtitle: tr('{0} 个频道 · 仅保存在本机', [channels.length]),
        trailing: library.loadingFeed
            ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
            : TextButton.icon(onPressed: () => library.refreshFeed(force: true), icon: const Icon(Icons.refresh_rounded), label: Text(tr('刷新'))),
      )),
      if (strip != null) SliverToBoxAdapter(child: strip),
      if (selected != null)
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, AppStyle.cardSpacing),
          child: Row(children: [
            Expanded(child: Text(
              tr('{0} 的新视频', [selected.name.isEmpty ? selected.id : selected.name]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            )),
            TextButton(onPressed: () => _select(null), child: Text(tr('显示全部'))),
            FilledButton.tonalIcon(
              onPressed: () => controller.openChannel(selected),
              icon: const Icon(Icons.chevron_right_rounded),
              label: Text(tr('进入频道')),
            ),
          ]),
        )),
      if (library.feedFailures.isNotEmpty && selected == null)
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
      else if (selected != null)
        SliverFillRemaining(hasScrollBody: false, child: StatusView(
          icon: Icons.inbox_outlined,
          title: tr('这个频道最近没有新视频'),
          action: FilledButton.tonal(onPressed: () => controller.openChannel(selected), child: Text(tr('进入频道看全部视频'))),
        ))
      else
        SliverFillRemaining(hasScrollBody: false, child: StatusView(icon: Icons.inbox_outlined, title: tr('暂时没有新视频'))),
      const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
    ]);
  }
}

File? _avatarFile(Directory? thumbnails, ChannelRef channel) =>
    thumbnails == null || channel.avatar == null ? null : File('${thumbnails.path}${Platform.pathSeparator}avatar_${channel.id}.jpg');

/// The followed channels as a row of avatars with names, scrolled by the
/// mouse wheel too. Those that posted most recently come first, and a dot
/// marks an upload in the last two days.
class _ChannelStrip extends StatefulWidget {
  const _ChannelStrip({this.vertical = false, required this.channels, required this.feed, required this.selected, required this.thumbnails, required this.onSelect, required this.onShowAll});
  final List<ChannelRef> channels;
  final List<VideoItem> feed;
  final ChannelRef? selected;
  final Directory? thumbnails;
  final ValueChanged<ChannelRef?> onSelect;
  final VoidCallback onShowAll;

  /// A column down the left of a wide page instead of a row.
  final bool vertical;
  static const railWidth = 92.0;

  /// How many avatars the row holds; the rest are in the full list.
  static const shown = 60;

  @override
  State<_ChannelStrip> createState() => _ChannelStripState();
}

class _ChannelStripState extends State<_ChannelStrip> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final latest = <String, DateTime?>{};
    for (final item in widget.feed) {
      final id = item.channelId;
      if (id != null && !latest.containsKey(id)) latest[id] = item.published;
    }
    final rank = {for (final (i, id) in latest.keys.indexed) id: i};
    final ordered = [...widget.channels]..sort((a, b) => (rank[a.id] ?? latest.length).compareTo(rank[b.id] ?? latest.length));
    final selected = widget.selected;
    // A channel picked from the full list shows up front, so the row says
    // what the videos below are narrowed to.
    if (selected != null && ordered.indexOf(selected) >= _ChannelStrip.shown) {
      ordered
        ..remove(selected)
        ..insert(0, selected);
    }
    final fresh = DateTime.now().subtract(const Duration(days: 2));
    final showAll = _StripItem(
      label: tr('全部 {0} 个', [widget.channels.length]),
      selected: false,
      onTap: widget.onShowAll,
      avatar: (radius) => CircleAvatar(radius: radius, child: Icon(Icons.manage_search_rounded, size: radius)),
    );
    if (widget.vertical) {
      // The full list stays in reach at the bottom, however long the column.
      return Column(children: [
        Expanded(child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.only(top: 8),
          children: _items(ordered, selected, latest, fresh),
        )),
        const Divider(height: 1, indent: 16, endIndent: 16),
        SizedBox(height: 88, child: showAll),
      ]);
    }
    // The full list stays in reach at the right, however long the row.
    return Row(children: [
      Expanded(child: _row(ordered, selected, latest, fresh)),
      Padding(
        padding: const EdgeInsets.only(right: AppStyle.pagePadding - 6),
        child: showAll,
      ),
    ]);
  }

  List<Widget> _items(List<ChannelRef> ordered, ChannelRef? selected, Map<String, DateTime?> latest, DateTime fresh) => [
        _StripItem(
          label: tr('全部'),
          selected: selected == null,
          onTap: () => widget.onSelect(null),
          avatar: (radius) => CircleAvatar(radius: radius, child: Icon(Icons.dynamic_feed_rounded, size: radius)),
        ),
        for (final channel in ordered.take(_ChannelStrip.shown))
          _StripItem(
            label: channel.name.isEmpty ? channel.id : channel.name,
            selected: channel == selected,
            fresh: latest[channel.id]?.isAfter(fresh) ?? false,
            onTap: () => widget.onSelect(channel),
            avatar: (radius) => ChannelAvatar(name: channel.name, radius: radius, image: channel.avatar, cacheFile: _avatarFile(widget.thumbnails, channel)),
          ),
      ];

  Widget _row(List<ChannelRef> ordered, ChannelRef? selected, Map<String, DateTime?> latest, DateTime fresh) {
    return Listener(
      // A mouse wheel turns vertically; the row moves sideways with it.
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent || !_scroll.hasClients || event.scrollDelta.dy == 0) return;
        final position = _scroll.position;
        if (position.maxScrollExtent <= 0) return;
        GestureBinding.instance.pointerSignalResolver.register(event, (_) {
          _scroll.jumpTo((position.pixels + event.scrollDelta.dy).clamp(0, position.maxScrollExtent));
        });
      },
      child: SizedBox(
        height: 96,
        child: Scrollbar(
          controller: _scroll,
          child: ListView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: AppStyle.pagePadding - 6),
            children: _items(ordered, selected, latest, fresh),
          ),
        ),
      ),
    );
  }
}

class _StripItem extends StatelessWidget {
  const _StripItem({required this.label, required this.selected, required this.onTap, required this.avatar, this.fresh = false});
  final String label;
  final bool selected;
  final bool fresh;
  final VoidCallback onTap;
  final Widget Function(double radius) avatar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 72,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const SizedBox(height: 6),
            Stack(clipBehavior: Clip.none, children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? colors.primary : Colors.transparent, width: 2)),
                child: avatar(22),
              ),
              if (fresh)
                Positioned(right: 2, top: 2, child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle, border: Border.all(color: colors.surface, width: 2)),
                )),
            ]),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: selected ? colors.primary : colors.onSurfaceVariant, fontWeight: selected ? FontWeight.w600 : null),
              ),
            ),
            const SizedBox(height: 6),
          ]),
        ),
      ),
    );
  }
}

/// Every followed channel, in a list that can be searched by name. Picking
/// one narrows the subscriptions page to it; the arrow opens its page.
class _AllChannels extends StatefulWidget {
  const _AllChannels({required this.channels, required this.thumbnails, required this.onSelect, required this.onOpen});
  final List<ChannelRef> channels;
  final Directory? thumbnails;
  final ValueChanged<ChannelRef> onSelect;
  final ValueChanged<ChannelRef> onOpen;

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
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
                        leading: ChannelAvatar(name: channel.name, radius: 18, image: channel.avatar, cacheFile: _avatarFile(widget.thumbnails, channel)),
                        title: Text(channel.name.isEmpty ? channel.id : channel.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          tooltip: tr('进入频道'),
                          icon: const Icon(Icons.open_in_new_rounded),
                          onPressed: () {
                            Navigator.pop(context);
                            widget.onOpen(channel);
                          },
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          widget.onSelect(channel);
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
      (AppController.watchLaterPlaylistId, tr('稍后观看'), library.watchLater, Icons.watch_later_rounded),
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
    final later = id == AppController.watchLaterPlaylistId;
    final playlist = favorites || later ? null : library.playlist(id);
    if (!favorites && !later && playlist == null) {
      return StatusView(
        icon: Icons.playlist_remove_rounded,
        title: tr('播放列表已删除'),
        action: FilledButton.tonal(onPressed: controller.goBack, child: Text(tr('返回'))),
      );
    }
    final items = List<VideoItem>.of(favorites ? library.favorites : later ? library.watchLater : playlist!.items);
    final name = favorites ? tr('收藏') : later ? tr('稍后观看') : playlist!.name;
    void remove(VideoItem item) => favorites
        ? library.toggleFavorite(item)
        : later
            ? library.removeWatchLater(item.id)
            : library.removeFromPlaylist(playlist!, item);
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
          if (later && items.isNotEmpty) ...[
            const SizedBox(width: 4),
            TextButton.icon(onPressed: () => _clearLater(context, library), icon: const Icon(Icons.delete_sweep_outlined), label: Text(tr('清空'))),
          ],
          if (playlist != null) ...[
            const SizedBox(width: 4),
            IconButton(tooltip: tr('重命名'), onPressed: () => _rename(context, library, playlist), icon: const Icon(Icons.edit_outlined)),
            IconButton(tooltip: tr('删除播放列表'), onPressed: () => _delete(context, library, playlist), icon: const Icon(Icons.delete_outline_rounded)),
          ],
        ]),
      )),
      if (items.isEmpty)
        SliverFillRemaining(hasScrollBody: false, child: StatusView(
          icon: favorites ? Icons.favorite_border_rounded : later ? Icons.watch_later_outlined : Icons.playlist_add_rounded,
          title: favorites ? tr('还没有收藏视频') : later ? tr('稍后观看是空的') : tr('这个播放列表是空的'),
          message: later ? tr('右键点击任意视频选“稍后观看”，或在播放页点按钮，想看的视频会先放在这里。') : tr('右键点击任意视频，或在播放页点按钮，就能添加到这里。'),
        ))
      else
        SliverVideoGrid(items: items, thumbnails: controller.thumbnailDirectory, onOpen: (item) => controller.play(item, from: items), onRemove: remove),
      const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
    ]);
  }

  Future<void> _clearLater(BuildContext context, LibraryController library) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(tr('清空稍后观看？')),
      content: Text(tr('只清空这个列表，视频和观看记录不受影响。')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('取消'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('清空'))),
      ],
    ));
    if (confirmed == true) library.clearWatchLater();
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
