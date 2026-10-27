import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../l10n/l10n.dart';
import '../../models.dart';
import '../common.dart';
import '../theme.dart';
import '../video_card.dart';
import 'watch_stats_page.dart';

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

  AppController get controller => widget.controller;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = controller.history;
    if (all.isEmpty) {
      return StatusView(icon: Icons.history_rounded, title: tr('还没有观看记录'), message: tr('播放过的视频会保存在本机，最多保留 60 条。'));
    }
    final items = filterHistory(all, _query);
    _selected.removeWhere((id) => !all.any((item) => item.id == id));
    final allSelected = items.isNotEmpty && items.every((item) => _selected.contains(item.id));
    return CustomScrollView(key: const PageStorageKey('list'), slivers: [
      SliverToBoxAdapter(child: PageHeader(
        tr('观看历史'),
        subtitle: _selecting ? tr('已选 {0} 个', [_selected.length]) : tr('{0} 个视频 · 仅保存在本机', [all.length]),
        trailing: _selecting
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                TextButton(
                  onPressed: items.isEmpty ? null : () => setState(() => allSelected ? _selected.clear() : _selected.addAll(items.map((item) => item.id))),
                  child: Text(allSelected ? tr('取消全选') : tr('全选')),
                ),
                const SizedBox(width: 4),
                FilledButton.icon(onPressed: _selected.isEmpty ? null : _deleteSelected, icon: const Icon(Icons.delete_outline_rounded), label: Text(tr('删除所选'))),
                const SizedBox(width: 4),
                TextButton(onPressed: _stopSelecting, child: Text(tr('完成'))),
              ])
            : Row(mainAxisSize: MainAxisSize.min, children: [
                TextButton.icon(onPressed: () => openWatchStats(context, widget.controller), icon: const Icon(Icons.insights_rounded), label: Text(tr('观看统计'))),
                TextButton.icon(onPressed: () => setState(() => _selecting = true), icon: const Icon(Icons.checklist_rounded), label: Text(tr('选择'))),
                TextButton.icon(onPressed: () => _confirmClear(context), icon: const Icon(Icons.delete_sweep_outlined), label: Text(tr('清空'))),
              ]),
      )),
      SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, 16),
        child: Align(alignment: Alignment.centerLeft, child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: tr('搜索历史标题或频道'),
              isDense: true,
              suffixIcon: _query.isEmpty ? null : IconButton(tooltip: tr('清除'), icon: const Icon(Icons.close_rounded), onPressed: () => setState(() {
                    _search.clear();
                    _query = '';
                  })),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        )),
      )),
      if (items.isEmpty)
        SliverFillRemaining(hasScrollBody: false, child: StatusView(icon: Icons.search_off_rounded, title: tr('没有匹配的历史记录'), message: tr('换个关键词试试。')))
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
          removeLabel: tr('从历史记录中删除'),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
    ]);
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
      title: Text(tr('清空观看历史？')),
      content: Text(tr('本机保存的全部观看记录都会被删除，无法恢复。')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('取消'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('清空'))),
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
