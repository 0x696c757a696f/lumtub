import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../explore_topics.dart';
import '../common.dart';
import '../theme.dart';
import '../video_card.dart';
import '../../widgets/pilinara_settings_tiles.dart' show confirmDialog;

/// Explore: popular videos by category and period, or what is live now.
class ExplorePage extends StatelessWidget {
  const ExplorePage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final loader = controller.explore;
    final items = controller.visible(loader?.items ?? const []);
    final error = loader?.error;
    final loading = loader == null || loader.loading;
    final section = controller.exploreSection;
    final topic = controller.exploreTopicNow;
    final live = section == ExploreSection.live;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth == 0 && notification.metrics.axis == Axis.vertical && notification.metrics.extentAfter < 800) loader?.loadMore();
        return false;
      },
      child: CustomScrollView(key: const PageStorageKey('list'), slivers: [
        SliverToBoxAdapter(child: PageHeader(
          '探索',
          subtitle: live ? '${topic.label}直播 · 按观看人数排列' : '${topic.label} · ${controller.explorePeriod.label}观看最多',
          trailing: SegmentedButton<ExploreSection>(
            showSelectedIcon: false,
            segments: [
              for (final s in ExploreSection.values)
                ButtonSegment(value: s, label: Text(s.label), icon: Icon(s == ExploreSection.live ? Icons.sensors_rounded : Icons.local_fire_department_rounded, size: 18)),
            ],
            selected: {section},
            onSelectionChanged: (value) => controller.setExplore(section: value.first),
          ),
        )),
        SliverToBoxAdapter(child: TopicStrip(
          key: ValueKey(section),
          topics: controller.exploreTopicsFor(section),
          selected: controller.exploreTopic,
          onSelected: (i) => controller.setExplore(topic: i),
          onAdd: () => _addTopic(context, section),
          onRemove: (topic) => _removeTopic(context, section, topic),
        )),
        if (!live)
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 4, AppStyle.pagePadding, 16),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final period in explorePeriods)
                ChoiceChip(label: Text(period.label), selected: controller.explorePeriod == period, onSelected: (_) => controller.setExplore(period: period)),
            ]),
          ))
        else
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        if (items.isNotEmpty) SliverVideoGrid(items: items, thumbnails: controller.thumbnailDirectory, onOpen: (item) => controller.play(item, from: items)),
        if (loading) ...[
          if (items.isNotEmpty) const SliverToBoxAdapter(child: SizedBox(height: AppStyle.cardSpacing)),
          SliverSkeletonGrid(rows: items.isEmpty ? 3 : 1),
        ],
        if (error != null)
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, AppStyle.cardSpacing, AppStyle.pagePadding, 0),
            child: ErrorBanner(items.isEmpty ? '无法加载：$error' : '加载更多失败：$error', onRetry: () => loader?.loadMore(retry: true)),
          )),
        if (items.isEmpty && !loading && error == null)
          SliverFillRemaining(hasScrollBody: false, child: StatusView(icon: Icons.explore_outlined, title: live ? '这个分类现在没有直播' : '这个分类暂时没有视频')),
        const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
      ]),
    );
  }

  Future<void> _addTopic(BuildContext context, ExploreSection section) async {
    final topic = await showDialog<CustomTopic>(context: context, builder: (context) => _AddTopicDialog(section: section));
    if (topic != null) await controller.addExploreTopic(topic);
  }

  Future<void> _removeTopic(BuildContext context, ExploreSection section, ExploreTopic topic) async {
    final ok = await confirmDialog(context, title: '删除分类', content: '删除自定义分类“${topic.label}”？', confirm: '删除');
    if (ok) await controller.removeExploreTopic(section, topic.label);
  }
}

/// Asks for a category's name and the words to search for.
class _AddTopicDialog extends StatefulWidget {
  const _AddTopicDialog({required this.section});
  final ExploreSection section;

  @override
  State<_AddTopicDialog> createState() => _AddTopicDialogState();
}

class _AddTopicDialogState extends State<_AddTopicDialog> {
  final _label = TextEditingController();
  final _query = TextEditingController();
  late var _section = widget.section;

  @override
  void dispose() {
    _label.dispose();
    _query.dispose();
    super.dispose();
  }

  void _submit() {
    final label = _label.text.trim();
    final query = _query.text.trim().isEmpty ? label : _query.text.trim();
    if (label.isEmpty) return;
    Navigator.pop(context, CustomTopic(label, query, _section));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('添加分类'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _label,
              autofocus: true,
              maxLength: 8,
              decoration: const InputDecoration(labelText: '名称', hintText: '例如：天主教音乐'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            TextField(
              controller: _query,
              decoration: const InputDecoration(labelText: '搜索词（可选）', hintText: '留空则用名称搜索，例如：Gregorian chant 额我略圣歌'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            SegmentedButton<ExploreSection>(
              showSelectedIcon: false,
              segments: [for (final s in ExploreSection.values) ButtonSegment(value: s, label: Text(s.label))],
              selected: {_section},
              onSelectionChanged: (value) => setState(() => _section = value.first),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: _label.text.trim().isEmpty ? null : _submit, child: const Text('添加')),
        ],
      );
}

/// A row of category icons that scrolls sideways, with the mouse wheel or
/// the arrows at its ends.
class TopicStrip extends StatefulWidget {
  const TopicStrip({super.key, required this.topics, required this.selected, required this.onSelected, this.onAdd, this.onRemove});
  final List<ExploreTopic> topics;
  final int selected;
  final ValueChanged<int> onSelected;
  /// Adds a category of the user's own, from a tile after the others.
  final VoidCallback? onAdd;
  /// Removes a category the user added, on right-click or long press.
  final ValueChanged<ExploreTopic>? onRemove;

  @override
  State<TopicStrip> createState() => _TopicStripState();
}

class _TopicStripState extends State<TopicStrip> {
  static const _tileWidth = 84.0;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // The arrows need the row's width, known after the first layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool _extent(bool Function(ScrollPosition position) test) =>
      _scroll.hasClients && _scroll.position.hasContentDimensions && test(_scroll.position);

  void _by(double delta) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final target = (position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent);
    _scroll.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 84,
        child: Row(children: [
          const SizedBox(width: AppStyle.pagePadding - 12),
          _Arrow(icon: Icons.chevron_left_rounded, onTap: _extent((p) => p.pixels > p.minScrollExtent) ? () => _by(-_tileWidth * 4) : null),
          Expanded(child: Listener(
            // A vertical wheel turn scrolls the row.
            onPointerSignal: (event) {
              if (event is PointerScrollEvent && _scroll.hasClients && _scroll.position.maxScrollExtent > 0) {
                GestureBinding.instance.pointerSignalResolver.register(event, (event) {
                  final scroll = event as PointerScrollEvent;
                  final delta = scroll.scrollDelta.dy.abs() > scroll.scrollDelta.dx.abs() ? scroll.scrollDelta.dy : scroll.scrollDelta.dx;
                  final position = _scroll.position;
                  _scroll.jumpTo((position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent));
                });
              }
            },
            child: NotificationListener<Notification>(
              // Show or hide the arrows as the row scrolls or resizes.
              onNotification: (notification) {
                if (notification is ScrollMetricsNotification || notification is ScrollEndNotification) setState(() {});
                return false;
              },
              child: ListView.builder(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              itemCount: widget.topics.length + (widget.onAdd == null ? 0 : 1),
              itemExtent: _tileWidth,
              itemBuilder: (context, i) {
                if (i == widget.topics.length) {
                  return _TopicTile(topic: const ExploreTopic('添加', Icons.add_rounded, ''), selected: false, onTap: widget.onAdd!);
                }
                final topic = widget.topics[i];
                final remove = widget.onRemove;
                return _TopicTile(
                  topic: topic,
                  selected: i == widget.selected,
                  onTap: () => widget.onSelected(i),
                  onRemove: topic.custom && remove != null ? () => remove(topic) : null,
                );
              },
              ),
            ),
          )),
          _Arrow(icon: Icons.chevron_right_rounded, onTap: _extent((p) => p.pixels < p.maxScrollExtent) ? () => _by(_tileWidth * 4) : null),
          const SizedBox(width: AppStyle.pagePadding - 12),
        ]),
      );
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 32,
        child: onTap == null ? null : IconButton(padding: EdgeInsets.zero, iconSize: 22, onPressed: onTap, icon: Icon(icon)),
      );
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({required this.topic, required this.selected, required this.onTap, this.onRemove});
  final ExploreTopic topic;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: onRemove == null ? topic.label : '${topic.label}（右键或长按删除）',
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onRemove,
        onSecondaryTap: onRemove,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: selected ? colors.primary : colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(topic.icon, size: 22, color: selected ? colors.onPrimary : colors.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            topic.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w600 : null, color: selected ? colors.primary : null),
          ),
        ]),
      ),
    );
  }
}
