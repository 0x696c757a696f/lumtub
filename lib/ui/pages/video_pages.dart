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
import '../app_icons.dart';

/// Home: a search prompt and the most recently watched videos.
class HomeFeedPage extends StatelessWidget {
  const HomeFeedPage({super.key, required this.controller, required this.onFocusSearch});
  final AppController controller;
  final VoidCallback onFocusSearch;

  @override
  Widget build(BuildContext context) {
    final prefs = controller.preferences;
    if (prefs.focusHideHome) return _FocusHome(controller: controller, onFocusSearch: onFocusSearch);
    final feed = prefs.homeShowRecommended ? controller.homeFeed : null;
    final showFeed = feed != null && (feed.items.isNotEmpty || feed.loading || feed.error != null);
    // With the feed below, the history only needs a short row.
    final recent = prefs.homeShowRecent ? controller.history.take(showFeed ? 6 : 12).toList() : const <VideoItem>[];
    final library = controller.library;
    final unfinished = library == null || !prefs.homeShowContinue
        ? const <VideoItem>[]
        : controller.history.where((item) => library.progressOf(item.id)?.resumable ?? false).take(showFeed ? 4 : 8).toList();
    final watched = watchedLabels(controller.watchedTimes);
    return NearEndListener(
      // The feed goes on: the next page loads before the end is reached.
      enabled: showFeed,
      onNearEnd: controller.loadMoreHomeFeed,
      child: CustomScrollView(key: const PageStorageKey('list'), slivers: [
        // The search box is at the top already; the prompt greets a first start.
        if (recent.isEmpty && unfinished.isEmpty && !showFeed) SliverToBoxAdapter(child: _Welcome(onFocusSearch: onFocusSearch)),
        if (unfinished.isNotEmpty) ...[
          SliverToBoxAdapter(child: PageHeader(tr('Continue watching'), subtitle: tr('Pick up where you left off'))),
          SliverVideoGrid(items: unfinished, thumbnails: controller.thumbnailDirectory, onOpen: (item) => controller.play(item, from: unfinished), watched: watched),
          const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
        ],
        if (recent.isNotEmpty) ...[
          SliverToBoxAdapter(child: PageHeader(
            tr('Recently watched'),
            subtitle: tr('From your watch history on this device'),
            trailing: TextButton(onPressed: () => controller.navigate(PageMode.history), child: Text(tr('View all'))),
          )),
          SliverVideoGrid(items: recent, thumbnails: controller.thumbnailDirectory, onOpen: (item) => controller.play(item, from: recent), watched: watched),
          const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
        ],
        if (showFeed) ...[
          SliverToBoxAdapter(child: PageHeader(
            tr('For you'),
            subtitle: feed.loading && feed.items.isEmpty ? tr('Picking from your watch history…') : touchFirst ? null : tr('Picked on this device from what you watch; right-click a video for "Not interested"'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton.icon(onPressed: feed.items.isEmpty ? null : controller.shuffleHomeFeed, icon: Icon(AppIcons.shuffle, size: 18), label: Text(tr('Shuffle'))),
              IconButton(
                tooltip: tr('Pick again'),
                onPressed: feed.loading ? null : () => controller.refreshHomeFeed(force: true),
                icon: Icon(AppIcons.arrowsClockwise),
              ),
            ]),
          )),
          if (feed.items.isNotEmpty)
            SliverVideoGrid(
              items: feed.items,
              thumbnails: controller.thumbnailDirectory,
              onOpen: (item) => controller.play(item, from: feed.items),
              onRemove: controller.dismissRecommendation,
              removeLabel: tr('Not interested'),
              reasons: feed.reasons,
            ),
          if (feed.loading || feed.loadingMore) ...[
            if (feed.items.isNotEmpty) const SliverToBoxAdapter(child: SizedBox(height: AppStyle.cardSpacing)),
            SliverSkeletonGrid(rows: feed.items.isEmpty ? 2 : 1),
          ] else if (feed.error case final error? when feed.items.isEmpty)
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppStyle.pagePadding),
              child: ErrorBanner(tr("Couldn't load recommendations: {0}", [error]), onRetry: () => controller.refreshHomeFeed(force: true)),
            )),
        ],
        if (recent.isEmpty && !showFeed)
          SliverFillRemaining(hasScrollBody: false, child: StatusView(
            icon: AppIcons.playCircle,
            title: tr('No watch history yet'),
            message: tr("Search or paste a YouTube link to start watching. Videos you've watched will appear here."),
          )),
        const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
      ]),
    );
  }
}

/// 专注模式's home page: no videos to be drawn into, only the search and
/// the user's own lists.
class _FocusHome extends StatelessWidget {
  const _FocusHome({required this.controller, required this.onFocusSearch});
  final AppController controller;
  final VoidCallback onFocusSearch;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(AppStyle.pagePadding),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(AppIcons.personSimpleTaiChi, size: 48, color: colors.primary),
            const SizedBox(height: 16),
            Text(tr('Focus mode'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(tr('No videos on the home page. Search for what you want to watch, or open Subscriptions and Watch later.'), textAlign: TextAlign.center, style: TextStyle(color: colors.outline, height: 1.5)),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onFocusSearch, icon: Icon(AppIcons.magnifyingGlass), label: Text(touchFirst ? tr('Search') : keyNames(tr('Search (Ctrl+K)')))),
            const SizedBox(height: 8),
            Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
              TextButton(onPressed: () => controller.navigate(PageMode.subscriptions), child: Text(tr('Subscriptions'))),
              TextButton(onPressed: () => controller.navigate(PageMode.playlists), child: Text(tr('Watch later and playlists'))),
              TextButton(onPressed: () => controller.savePreferences(controller.preferences.copyWith(focusHideHome: false)), child: Text(tr('Show the home page'))),
            ]),
          ]),
        ),
      ),
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
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: AppStyle.cardRadius, side: BorderSide(color: colors.outlineVariant)),
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          onTap: onFocusSearch,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('What do you want to watch?'), style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: colors.onSurface)),
                const SizedBox(height: 4),
                Text(touchFirst ? tr('Search YouTube, or paste a video link') : keyNames(tr('Search YouTube, or paste a video link to play it. Press Ctrl+K to search anytime.')), style: TextStyle(color: colors.onSurfaceVariant)),
              ])),
              const SizedBox(width: 16),
              Icon(AppIcons.magnifyingGlass, size: 40, color: colors.onSurfaceVariant),
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
        icon: AppIcons.compass,
        title: tr('Search YouTube'),
        message: tr('Enter keywords, or paste a youtube.com / youtu.be link.'),
        action: FilledButton.tonalIcon(onPressed: onFocusSearch, icon: Icon(AppIcons.magnifyingGlass), label: Text(tr('Start searching'))),
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
        icon: AppIcons.cloudSlash,
        error: true,
        title: tr('Search failed'),
        message: error,
        action: FilledButton.tonalIcon(onPressed: controller.retrySearch, icon: Icon(AppIcons.arrowsClockwise), label: Text(tr('Retry'))),
      );
    } else if (empty && !controller.searching) {
      status = StatusView(icon: AppIcons.magnifyingGlassMinus, title: filter == SearchFilter.all ? tr('Nothing found') : tr('No {0} found', [filter.label]), message: tr('Try other keywords.'));
    }
    final count = [
      if (results.isNotEmpty) tr('{0} videos', [results.length]),
      if (channels.isNotEmpty) tr('{0} channels', [channels.length]),
      if (playlists.isNotEmpty) tr('{0} playlists', [playlists.length]),
    ].join(tr(', '));
    return NearEndListener(
      // Fetch the next page shortly before the end of the results is reached.
      onNearEnd: controller.loadMoreResults,
      child: CustomScrollView(key: const PageStorageKey('list'), slivers: [
        SliverToBoxAdapter(child: PageHeader(
          '“$query”',
          subtitle: controller.searching ? tr('Searching…') : (count.isEmpty ? null : count),
          trailing: IconButton(tooltip: keyNames(tr('Back (Alt+←)')), onPressed: controller.goBack, icon: Icon(AppIcons.arrowLeft)),
        )),
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, 16),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final value in SearchFilter.values)
              ChoiceChip(label: Text(value.label), selected: filter == value, onSelected: (_) => controller.setSearchFilter(value)),
            const SizedBox(width: 8),
            OptionChip(
              icon: AppIcons.sortDescending,
              value: controller.searchSort,
              values: SearchSort.values,
              label: (v) => v == SearchSort.relevance ? tr('Sort') : tr('By {0}', [v.label]),
              item: (v) => tr('By {0}', [v.label]),
              changed: controller.searchSort != SearchSort.relevance,
              onSelected: (v) => controller.setSearchOptions(sort: v),
            ),
            OptionChip(
              icon: AppIcons.calendar,
              value: controller.searchDate,
              values: SearchUploadDate.values,
              label: (v) => v == SearchUploadDate.any ? tr('Upload time') : v.label,
              item: (v) => v.label,
              changed: controller.searchDate != SearchUploadDate.any,
              onSelected: (v) => controller.setSearchOptions(date: v),
            ),
            OptionChip(
              icon: AppIcons.timer,
              value: controller.searchDuration,
              values: SearchDuration.values,
              label: (v) => v == SearchDuration.any ? tr('Duration') : v.label,
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
              child: ErrorBanner(tr("Couldn't load more: {0}", [error]), onRetry: () => controller.loadMoreResults(retry: true)),
            )),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
      ]),
    );
  }
}
