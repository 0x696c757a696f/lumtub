import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../models.dart';
import '../../search_options.dart';
import '../../video_repository.dart';
import '../common.dart';
import '../theme.dart';
import '../video_card.dart';
import 'channel_page.dart';
export 'history_page.dart';
import '../../l10n/l10n.dart';

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
    return NearEndListener(
      // The feed goes on: the next page loads before the end is reached.
      enabled: showFeed,
      onNearEnd: controller.loadMoreHomeFeed,
      child: CustomScrollView(key: const PageStorageKey('list'), slivers: [
        // The search box is at the top already; the prompt greets a first start.
        if (recent.isEmpty && unfinished.isEmpty && !showFeed) SliverToBoxAdapter(child: _Welcome(onFocusSearch: onFocusSearch)),
        if (unfinished.isNotEmpty) ...[
          SliverToBoxAdapter(child: PageHeader(tr('继续观看'), subtitle: tr('从上次停下的地方接着看'))),
          SliverVideoGrid(items: unfinished, thumbnails: controller.thumbnailDirectory, onOpen: (item) => controller.play(item, from: unfinished)),
          const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
        ],
        if (recent.isNotEmpty) ...[
          SliverToBoxAdapter(child: PageHeader(
            tr('最近观看'),
            subtitle: tr('来自本机观看历史'),
            trailing: TextButton(onPressed: () => controller.navigate(PageMode.history), child: Text(tr('查看全部'))),
          )),
          SliverVideoGrid(items: recent, thumbnails: controller.thumbnailDirectory, onOpen: (item) => controller.play(item, from: recent)),
          const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
        ],
        if (showFeed) ...[
          SliverToBoxAdapter(child: PageHeader(
            tr('为你推荐'),
            subtitle: feed.loading && feed.items.isEmpty ? tr('正在根据观看记录挑选…') : tr('按你的观看兴趣在本机挑选，右键可选“不感兴趣”'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton.icon(onPressed: feed.items.isEmpty ? null : controller.shuffleHomeFeed, icon: const Icon(Icons.shuffle_rounded, size: 18), label: Text(tr('换一批'))),
              IconButton(
                tooltip: tr('重新挑选'),
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
              removeLabel: tr('不感兴趣'),
              reasons: feed.reasons,
            ),
          if (feed.loading || feed.loadingMore) ...[
            if (feed.items.isNotEmpty) const SliverToBoxAdapter(child: SizedBox(height: AppStyle.cardSpacing)),
            SliverSkeletonGrid(rows: feed.items.isEmpty ? 2 : 1),
          ] else if (feed.error case final error? when feed.items.isEmpty)
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppStyle.pagePadding),
              child: ErrorBanner(tr('无法加载推荐：{0}', [error]), onRetry: () => controller.refreshHomeFeed(force: true)),
            )),
        ],
        if (recent.isEmpty && !showFeed)
          SliverFillRemaining(hasScrollBody: false, child: StatusView(
            icon: Icons.play_circle_outline_rounded,
            title: tr('还没有观看记录'),
            message: tr('搜索或粘贴 YouTube 链接开始观看，看过的视频会出现在这里。'),
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
                Text(tr('想看点什么？'), style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: colors.onPrimaryContainer)),
                const SizedBox(height: 6),
                Text(tr('搜索 YouTube，或直接粘贴视频链接播放。按 Ctrl+K 随时搜索。'), style: TextStyle(color: colors.onPrimaryContainer.withValues(alpha: 0.8))),
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
        title: tr('搜索 YouTube'),
        message: tr('输入关键词，或粘贴 youtube.com / youtu.be 链接。'),
        action: FilledButton.tonalIcon(onPressed: onFocusSearch, icon: const Icon(Icons.search_rounded), label: Text(tr('开始搜索'))),
      );
    }
    final results = controller.visible(controller.results, search: true);
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
        title: tr('搜索失败'),
        message: error,
        action: FilledButton.tonalIcon(onPressed: controller.retrySearch, icon: const Icon(Icons.refresh_rounded), label: Text(tr('重试'))),
      );
    } else if (empty && !controller.searching) {
      status = StatusView(icon: Icons.search_off_rounded, title: filter == SearchFilter.all ? tr('没有找到相关内容') : tr('没有找到相关{0}', [filter.label]), message: tr('换个关键词试试。'));
    }
    final count = [
      if (results.isNotEmpty) tr('{0} 个视频', [results.length]),
      if (channels.isNotEmpty) tr('{0} 个频道', [channels.length]),
      if (playlists.isNotEmpty) tr('{0} 个播放列表', [playlists.length]),
    ].join('，');
    return NearEndListener(
      // Fetch the next page shortly before the end of the results is reached.
      onNearEnd: controller.loadMoreResults,
      child: CustomScrollView(key: const PageStorageKey('list'), slivers: [
        SliverToBoxAdapter(child: PageHeader(
          '“$query”',
          subtitle: controller.searching ? tr('正在搜索…') : (count.isEmpty ? null : count),
          trailing: IconButton(tooltip: tr('返回 (Alt+←)'), onPressed: controller.goBack, icon: const Icon(Icons.arrow_back_rounded)),
        )),
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, 16),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final value in SearchFilter.values)
              ChoiceChip(label: Text(value.label), selected: filter == value, onSelected: (_) => controller.setSearchFilter(value)),
            const SizedBox(width: 8),
            OptionChip(
              icon: Icons.sort_rounded,
              value: controller.searchSort,
              values: SearchSort.values,
              label: (v) => v == SearchSort.relevance ? tr('排序') : tr('按{0}', [v.label]),
              item: (v) => tr('按{0}', [v.label]),
              changed: controller.searchSort != SearchSort.relevance,
              onSelected: (v) => controller.setSearchOptions(sort: v),
            ),
            OptionChip(
              icon: Icons.event_rounded,
              value: controller.searchDate,
              values: SearchUploadDate.values,
              label: (v) => v == SearchUploadDate.any ? tr('上传时间') : v.label,
              item: (v) => v.label,
              changed: controller.searchDate != SearchUploadDate.any,
              onSelected: (v) => controller.setSearchOptions(date: v),
            ),
            OptionChip(
              icon: Icons.timer_outlined,
              value: controller.searchDuration,
              values: SearchDuration.values,
              label: (v) => v == SearchDuration.any ? tr('时长') : v.label,
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
              child: ErrorBanner(tr('加载更多失败：{0}', [error]), onRetry: () => controller.loadMoreResults(retry: true)),
            )),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
      ]),
    );
  }
}
