import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../models.dart';
import '../../search_options.dart';
import '../../video_repository.dart';
import '../common.dart';
import '../theme.dart';
import '../video_card.dart';
import 'channel_page.dart';

/// Home: a search prompt and the most recently watched videos.
class HomeFeedPage extends StatelessWidget {
  const HomeFeedPage({super.key, required this.controller, required this.onFocusSearch});
  final AppController controller;
  final VoidCallback onFocusSearch;

  @override
  Widget build(BuildContext context) {
    final prefs = controller.preferences;
    final feed = prefs.homeShowRecommended ? controller.homeFeed : null;
    final showFeed = feed != null && (feed.items.isNotEmpty || feed.loading || feed.error != null);
    // With the feed below, the history only needs a short row.
    final recent = prefs.homeShowRecent ? controller.history.take(showFeed ? 6 : 12).toList() : const <VideoItem>[];
    final library = controller.library;
    final unfinished = library == null || !prefs.homeShowContinue
        ? const <VideoItem>[]
        : controller.history.where((item) => library.progressOf(item.id)?.resumable ?? false).take(showFeed ? 4 : 8).toList();
    return NotificationListener<ScrollNotification>(
      // The feed goes on: the next page loads before the end is reached.
      onNotification: (notification) {
        if (showFeed && notification.metrics.axis == Axis.vertical && notification.metrics.extentAfter < 1200) controller.loadMoreHomeFeed();
        return false;
      },
      child: CustomScrollView(key: const PageStorageKey('list'), slivers: [
        SliverToBoxAdapter(child: _Welcome(onFocusSearch: onFocusSearch)),
        if (unfinished.isNotEmpty) ...[
          const SliverToBoxAdapter(child: PageHeader('继续观看', subtitle: '从上次停下的地方接着看')),
          SliverVideoGrid(items: unfinished, thumbnails: controller.thumbnailDirectory, onOpen: (item) => controller.play(item, from: unfinished)),
          const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
        ],
        if (recent.isNotEmpty) ...[
          SliverToBoxAdapter(child: PageHeader(
            '最近观看',
            subtitle: '来自本机观看历史',
            trailing: TextButton(onPressed: () => controller.navigate(PageMode.history), child: const Text('查看全部')),
          )),
          SliverVideoGrid(items: recent, thumbnails: controller.thumbnailDirectory, onOpen: (item) => controller.play(item, from: recent)),
          const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
        ],
        if (showFeed) ...[
          SliverToBoxAdapter(child: PageHeader(
            '为你推荐',
            subtitle: feed.loading && feed.items.isEmpty ? '正在根据观看记录挑选…' : '长期兴趣、近期兴趣、探索和热门新视频混合，在本机挑选；右键可选“不感兴趣”',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton.icon(onPressed: feed.items.isEmpty ? null : controller.shuffleHomeFeed, icon: const Icon(Icons.shuffle_rounded, size: 18), label: const Text('换一批')),
              IconButton(
                tooltip: '重新挑选',
                onPressed: feed.loading ? null : () => controller.refreshHomeFeed(force: true),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ]),
          )),
          if (feed.items.isNotEmpty)
            SliverVideoGrid(
              items: feed.items,
              thumbnails: controller.thumbnailDirectory,
              onOpen: (item) => controller.play(item, from: feed.items),
              onRemove: controller.dismissRecommendation,
              removeLabel: '不感兴趣',
              reasons: feed.reasons,
            ),
          if (feed.loading || feed.loadingMore) ...[
            if (feed.items.isNotEmpty) const SliverToBoxAdapter(child: SizedBox(height: AppStyle.cardSpacing)),
            SliverSkeletonGrid(rows: feed.items.isEmpty ? 2 : 1),
          ] else if (feed.error case final error? when feed.items.isEmpty)
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppStyle.pagePadding),
              child: ErrorBanner('无法加载推荐：$error', onRetry: () => controller.refreshHomeFeed(force: true)),
            )),
        ],
        if (recent.isEmpty && !showFeed)
          const SliverFillRemaining(hasScrollBody: false, child: StatusView(
            icon: Icons.play_circle_outline_rounded,
            title: '还没有观看记录',
            message: '搜索或粘贴 YouTube 链接开始观看，看过的视频会出现在这里。',
          )),
        const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
      ]),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onFocusSearch});
  final VoidCallback onFocusSearch;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 8, AppStyle.pagePadding, 8),
      child: Material(
        color: colors.primaryContainer,
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          onTap: onFocusSearch,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('想看点什么？', style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: colors.onPrimaryContainer)),
                const SizedBox(height: 6),
                Text('搜索 YouTube，或直接粘贴视频链接播放。按 Ctrl+K 随时搜索。', style: TextStyle(color: colors.onPrimaryContainer.withValues(alpha: 0.8))),
              ])),
              const SizedBox(width: 16),
              Icon(Icons.search_rounded, size: 40, color: colors.onPrimaryContainer.withValues(alpha: 0.6)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Search results with kind filters, channels, skeletons, error and empty
/// states, and paging.
class SearchResultsPage extends StatelessWidget {
  const SearchResultsPage({super.key, required this.controller, required this.onFocusSearch});
  final AppController controller;
  final VoidCallback onFocusSearch;

  @override
  Widget build(BuildContext context) {
    final query = controller.query;
    if (query == null) {
      return StatusView(
        icon: Icons.explore_outlined,
        title: '搜索 YouTube',
        message: '输入关键词，或粘贴 youtube.com / youtu.be 链接。',
        action: FilledButton.tonalIcon(onPressed: onFocusSearch, icon: const Icon(Icons.search_rounded), label: const Text('开始搜索')),
      );
    }
    final results = controller.visible(controller.results);
    final channels = controller.channelResults;
    final playlists = controller.playlistResults;
    final error = controller.searchError;
    final filter = controller.searchFilter;
    final empty = results.isEmpty && channels.isEmpty && playlists.isEmpty;
    Widget? status;
    if (empty && error != null && !controller.searching) {
      status = StatusView(
        icon: Icons.cloud_off_rounded,
        error: true,
        title: '搜索失败',
        message: error,
        action: FilledButton.tonalIcon(onPressed: controller.retrySearch, icon: const Icon(Icons.refresh_rounded), label: const Text('重试')),
      );
    } else if (empty && !controller.searching) {
      status = StatusView(icon: Icons.search_off_rounded, title: filter == SearchFilter.all ? '没有找到相关内容' : '没有找到相关${filter.label}', message: '换个关键词试试。');
    }
    final count = [
      if (results.isNotEmpty) '${results.length} 个视频',
      if (channels.isNotEmpty) '${channels.length} 个频道',
      if (playlists.isNotEmpty) '${playlists.length} 个播放列表',
    ].join('，');
    return NotificationListener<ScrollNotification>(
      // Fetch the next page shortly before the end of the results is reached.
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 800) controller.loadMoreResults();
        return false;
      },
      child: CustomScrollView(key: const PageStorageKey('list'), slivers: [
        SliverToBoxAdapter(child: PageHeader(
          '“$query”',
          subtitle: controller.searching ? '正在搜索…' : (count.isEmpty ? null : count),
          trailing: IconButton(tooltip: '返回 (Alt+←)', onPressed: controller.goBack, icon: const Icon(Icons.arrow_back_rounded)),
        )),
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, 16),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final value in SearchFilter.values)
              ChoiceChip(label: Text(value.label), selected: filter == value, onSelected: (_) => controller.setSearchFilter(value)),
            const SizedBox(width: 8),
            _OptionChip(
              icon: Icons.sort_rounded,
              value: controller.searchSort,
              values: SearchSort.values,
              label: (v) => v == SearchSort.relevance ? '排序' : '按${v.label}',
              item: (v) => '按${v.label}',
              changed: controller.searchSort != SearchSort.relevance,
              onSelected: (v) => controller.setSearchOptions(sort: v),
            ),
            _OptionChip(
              icon: Icons.event_rounded,
              value: controller.searchDate,
              values: SearchUploadDate.values,
              label: (v) => v == SearchUploadDate.any ? '上传时间' : v.label,
              item: (v) => v.label,
              changed: controller.searchDate != SearchUploadDate.any,
              onSelected: (v) => controller.setSearchOptions(date: v),
            ),
            _OptionChip(
              icon: Icons.timer_outlined,
              value: controller.searchDuration,
              values: SearchDuration.values,
              label: (v) => v == SearchDuration.any ? '时长' : v.label,
              item: (v) => v.label,
              changed: controller.searchDuration != SearchDuration.any,
              onSelected: (v) => controller.setSearchOptions(duration: v),
            ),
          ]),
        )),
        if (status != null)
          SliverFillRemaining(hasScrollBody: false, child: status)
        else ...[
          if (channels.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, AppStyle.cardSpacing),
              sliver: SliverList.separated(
                itemCount: channels.length,
                separatorBuilder: (context, i) => const SizedBox(height: 8),
                itemBuilder: (context, i) => ChannelResultTile(controller: controller, result: channels[i]),
              ),
            ),
          if (playlists.isNotEmpty) ...[
            SliverPlaylistGrid(items: playlists, onOpen: controller.openYoutubePlaylist),
            const SliverToBoxAdapter(child: SizedBox(height: AppStyle.cardSpacing)),
          ],
          if (results.isNotEmpty) SliverVideoGrid(items: results, thumbnails: controller.thumbnailDirectory, onOpen: (item) => controller.play(item, from: results)),
          if (controller.searching) ...[
            if (!empty) const SliverToBoxAdapter(child: SizedBox(height: AppStyle.cardSpacing)),
            SliverSkeletonGrid(rows: empty ? 3 : 1),
          ],
          if (error != null && !empty)
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, AppStyle.cardSpacing, AppStyle.pagePadding, 0),
              child: ErrorBanner('加载更多失败：$error', onRetry: () => controller.loadMoreResults(retry: true)),
            )),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
      ]),
    );
  }
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.history;
    if (items.isEmpty) {
      return const StatusView(icon: Icons.history_rounded, title: '还没有观看记录', message: '播放过的视频会保存在本机，最多保留 60 条。');
    }
    final snapshot = List<VideoItem>.of(items);
    return CustomScrollView(key: const PageStorageKey('list'), slivers: [
      SliverToBoxAdapter(child: PageHeader(
        '观看历史',
        subtitle: '${items.length} 个视频 · 仅保存在本机',
        trailing: TextButton.icon(onPressed: () => _confirmClear(context), icon: const Icon(Icons.delete_sweep_outlined), label: const Text('清空')),
      )),
      SliverVideoGrid(items: snapshot, thumbnails: controller.thumbnailDirectory, onOpen: (item) => controller.play(item, from: snapshot)),
      const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
    ]);
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('清空观看历史？'),
      content: const Text('本机保存的全部观看记录都会被删除，无法恢复。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('清空')),
      ],
    ));
    if (confirmed == true) await controller.clearHistory();
  }
}

/// A search option chip that opens a menu of its values.
class _OptionChip<T> extends StatelessWidget {
  const _OptionChip({required this.icon, required this.value, required this.values, required this.label, required this.item, required this.changed, required this.onSelected});
  final IconData icon;
  final T value;
  final List<T> values;
  final String Function(T value) label;
  final String Function(T value) item;
  final bool changed;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => MenuAnchor(
        menuChildren: [
          for (final v in values)
            MenuItemButton(
              leadingIcon: Icon(v == value ? Icons.check_rounded : null, size: 18),
              onPressed: v == value ? null : () => onSelected(v),
              child: Text(item(v)),
            ),
        ],
        builder: (context, menu, _) => FilterChip(
          avatar: Icon(icon, size: 18),
          label: Row(mainAxisSize: MainAxisSize.min, children: [Text(label(value)), const Icon(Icons.arrow_drop_down_rounded, size: 18)]),
          selected: changed,
          showCheckmark: false,
          onSelected: (_) => menu.isOpen ? menu.close() : menu.open(),
        ),
      );
}
