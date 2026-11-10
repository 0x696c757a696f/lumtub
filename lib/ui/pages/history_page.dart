import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../l10n/l10n.dart';
import '../../models.dart';
import '../../video_repository.dart' show historyLimit;
import '../common.dart';
import '../theme.dart';
import '../video_card.dart';
import 'watch_stats_page.dart';
import '../app_icons.dart';

/// The watch history, with a search box, single delete from a card's menu,
/// and a 选择 mode to delete several at once (after PiliNara's history and
/// multi-select pages).
/// The history items whose title or channel contain [query].
List<VideoItem> filterHistory(List<VideoItem> items, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return List.of(items);
  return [for (final item in items) if (item.title.toLowerCase().contains(needle) || item.channel.toLowerCase().contains(needle)) item];
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _search = TextEditingController();
  String _query = '';
  bool _selecting = false;
  final _selected = <String>{};
  /// Showing the account's history on YouTube instead of this computer's.
  bool _youtube = false;

  AppController get controller => widget.controller;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = controller.history;
    final signedIn = controller.tvFeed?.available ?? false;
    if (signedIn && _youtube) return _youtubeHistory(context);
    if (all.isEmpty && !signedIn) {
      return StatusView(icon: AppIcons.clockCounterClockwiseFill, title: tr('No watch history yet'), message: tr('Played videos are saved on this device, up to {0} entries.', [historyLimit]));
    }
    final items = filterHistory(all, _query);
    _selected.removeWhere((id) => !all.any((item) => item.id == id));
    final allSelected = items.isNotEmpty && items.every((item) => _selected.contains(item.id));
    return CustomScrollView(key: const PageStorageKey('list'), slivers: [
      SliverToBoxAdapter(child: PageHeader(
        tr('Watch history'),
        subtitle: _selecting ? tr('{0} selected', [_selected.length]) : tr('{0} videos · Saved on this device only', [all.length]),
        trailing: _selecting
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                TextButton(
                  onPressed: items.isEmpty ? null : () => setState(() => allSelected ? _selected.clear() : _selected.addAll(items.map((item) => item.id))),
                  child: Text(allSelected ? tr('Untick all') : tr('Tick all')),
                ),
                const SizedBox(width: 4),
                FilledButton.icon(onPressed: _selected.isEmpty ? null : _deleteSelected, icon: Icon(AppIcons.trash), label: Text(tr('Delete selected'))),
                const SizedBox(width: 4),
                TextButton(onPressed: _stopSelecting, child: Text(tr('Done'))),
              ])
            : Row(mainAxisSize: MainAxisSize.min, children: [
                TextButton.icon(onPressed: () => openWatchStats(context, widget.controller), icon: Icon(AppIcons.chartLineUp), label: Text(tr('Watch statistics'))),
                TextButton.icon(onPressed: () => setState(() => _selecting = true), icon: Icon(AppIcons.listChecks), label: Text(tr('Select'))),
                TextButton.icon(onPressed: () => _confirmClear(context), icon: Icon(AppIcons.trashSimple), label: Text(tr('Clear all'))),
              ]),
      )),
      if (signedIn) SliverToBoxAdapter(child: _sourceChips()),
      SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, 16),
        child: Align(alignment: AlignmentDirectional.centerStart, child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              prefixIcon: Icon(AppIcons.magnifyingGlass),
              hintText: tr('Search history by title or channel'),
              isDense: true,
              suffixIcon: _query.isEmpty ? null : IconButton(tooltip: tr('Clear'), icon: Icon(AppIcons.x), onPressed: () => setState(() {
                    _search.clear();
                    _query = '';
                  })),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        )),
      )),
      if (all.isEmpty)
        SliverFillRemaining(hasScrollBody: false, child: StatusView(icon: AppIcons.clockCounterClockwiseFill, title: tr('No watch history yet'), message: tr('Played videos are saved on this device, up to {0} entries.', [historyLimit])))
      else if (items.isEmpty)
        SliverFillRemaining(hasScrollBody: false, child: StatusView(icon: AppIcons.magnifyingGlassMinus, title: tr('No matching history'), message: tr('Try other keywords.')))
      else if (_selecting)
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppStyle.pagePadding),
          sliver: SliverList.builder(
            itemCount: items.length,
            itemBuilder: (context, i) => _SelectRow(
              item: items[i],
              selected: _selected.contains(items[i].id),
              thumbnails: controller.thumbnailDirectory,
              onToggle: () => setState(() => _selected.contains(items[i].id) ? _selected.remove(items[i].id) : _selected.add(items[i].id)),
            ),
          ),
        )
      else
        SliverVideoGrid(
          items: items,
          thumbnails: controller.thumbnailDirectory,
          onOpen: (item) => controller.play(item, from: items),
          onRemove: (item) => controller.removeFromHistory({item.id}),
          removeLabel: tr('Delete from history'),
          watched: watchedLabels(controller.watchedTimes),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
    ]);
  }

  Widget _sourceChips() => Padding(
        padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, 12),
        child: Wrap(spacing: 8, children: [
          ChoiceChip(label: Text(tr('This computer')), selected: !_youtube, onSelected: (_) => setState(() => _youtube = false)),
          ChoiceChip(label: Text(tr('YouTube account')), selected: _youtube, onSelected: (_) => setState(() {
                _youtube = true;
                _stopSelecting();
              })),
        ]),
      );

  /// The account's history as YouTube keeps it, read with the TV-code
  /// sign-in. Read only: deleting goes through YouTube itself.
  Widget _youtubeHistory(BuildContext context) {
    final loader = controller.youtubeHistory;
    if (loader == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.openYoutubeHistory();
      });
      return CustomScrollView(slivers: [SliverToBoxAdapter(child: PageHeader(tr('Watch history'))), SliverToBoxAdapter(child: _sourceChips()), const SliverSkeletonGrid(rows: 3)]);
    }
    final items = controller.visible(loader.items);
    final error = loader.error;
    return NearEndListener(
      onNearEnd: loader.loadMore,
      child: CustomScrollView(key: const PageStorageKey('youtube-history'), slivers: [
        SliverToBoxAdapter(child: PageHeader(
          tr('Watch history'),
          subtitle: tr('Watch history in your YouTube account'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton.icon(onPressed: () => openExternal('https://www.youtube.com/feed/history'), icon: Icon(AppIcons.arrowSquareOut), label: Text(tr('Manage on YouTube'))),
            TextButton.icon(onPressed: () => controller.openYoutubeHistory(reload: true), icon: Icon(AppIcons.arrowsClockwise), label: Text(tr('Refresh'))),
          ]),
        )),
        SliverToBoxAdapter(child: _sourceChips()),
        if (items.isNotEmpty) SliverVideoGrid(items: items, thumbnails: controller.thumbnailDirectory, onOpen: (item) => controller.play(item, from: items), watched: controller.tvFeed?.historyDays),
        if (loader.loading) ...[
          if (items.isNotEmpty) const SliverToBoxAdapter(child: SizedBox(height: AppStyle.cardSpacing)),
          SliverSkeletonGrid(rows: items.isEmpty ? 3 : 1),
        ] else if (items.isEmpty && error == null)
          SliverFillRemaining(hasScrollBody: false, child: StatusView(icon: AppIcons.clockCounterClockwiseFill, title: tr('No watch history on YouTube yet'))),
        if (error != null)
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, AppStyle.cardSpacing, AppStyle.pagePadding, 0),
            child: ErrorBanner(tr('Could not load the YouTube watch history: {0}', [error]), onRetry: () => loader.loadMore(retry: true)),
          )),
        const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
      ]),
    );
  }

  void _stopSelecting() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  Future<void> _deleteSelected() async {
    final ids = Set.of(_selected);
    _stopSelecting();
    await controller.removeFromHistory(ids);
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(tr('Clear watch history?')),
      content: Text(tr("All watch history saved on this device will be deleted. This can't be undone.")),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Clear all'))),
      ],
    ));
    if (confirmed == true) await controller.clearHistory();
  }
}

/// One history entry in 选择 mode: a checkbox, the thumbnail and the title.
class _SelectRow extends StatelessWidget {
  const _SelectRow({required this.item, required this.selected, required this.thumbnails, required this.onToggle});
  final VideoItem item;
  final bool selected;
  final Directory? thumbnails;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      borderRadius: AppStyle.cardRadius,
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Checkbox(value: selected, onChanged: (_) => onToggle()),
          SizedBox(
            width: 152,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image(
                  color: context.pictureWarmth,
                  colorBlendMode: BlendMode.multiply,
                  image: thumbnailFor(item, thumbnails, width: 320, size: 'mqdefault'),
                  fit: BoxFit.cover,
                  errorBuilder: (context, _, __) => ColoredBox(color: colors.surfaceContainerHighest),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titleFor(item), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.onSurface)),
            const SizedBox(height: 4),
            Text(item.channel.isEmpty ? 'YouTube' : item.channel, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: colors.outline)),
          ])),
        ]),
      ),
    );
  }
}
