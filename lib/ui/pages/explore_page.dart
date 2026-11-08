import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../explore_filters.dart';
import '../../explore_topics.dart';
import '../common.dart';
import '../../search_options.dart';
import '../theme.dart';
import '../video_card.dart';
import '../../widgets/pilinara_settings_tiles.dart' show confirmDialog;
import '../../l10n/l10n.dart';
import '../../models.dart';
import '../motion.dart';
import '../app_icons.dart';

/// Explore, in zones as Bilibili's 分区: videos, live streams or the tabs of
/// 宗教与信仰, a zone and one of its sub-categories, how they are picked, and
/// filters.
class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key, required this.controller});
  final AppController controller;

  /// The width from which zones and followed channels move to a left column.
  static const wideLayout = 960.0;

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  double _railWidth = 220;

  AppController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final loader = controller.explore;
    final items = controller.visible(loader?.items ?? const []);
    // The AI filter can hide videos after they were listed: when it hides
    // them all, the next page is read rather than the page left empty.
    if (loader != null && items.isEmpty && loader.items.isNotEmpty && !loader.loading && loader.hasMore && loader.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => loader.loadMore());
    }
    final error = loader?.error;
    final loading = loader == null || loader.loading;
    final section = controller.exploreSection;
    final topic = controller.exploreTopicNow;
    final mode = controller.exploreMode;
    final subNow = controller.exploreSubNow;
    final name = [topic.label, if (subNow != null) subNow.label, if (controller.exploreLeafNow case final leafNow?) leafNow.label].join(' · ');
    final subtitle = switch (mode) {
      ExploreMode.curated => tr('{0} · Relevant full-length videos, less clickbait, up to 3 per channel', [name]),
      ExploreMode.popular when topic.mix => tr('All · most watched {0} across the zones, at most 2 per channel', [controller.explorePeriod.label]),
      ExploreMode.popular => tr('{0} · most watched {1}', [name, controller.explorePeriod.label]),
      ExploreMode.forYou => tr('{0} · Based on your watch history', [name]),
      ExploreMode.gems => tr('{0} · Great videos with under 50K views', [name]),
      ExploreMode.fresh => tr('{0} · New this week, under 5,000 views, from channels you have not watched', [name]),
      ExploreMode.long => tr('{0} · Most watched videos over 20 minutes this year', [name]),
      ExploreMode.latest => tr('{0} · Latest uploads', [name]),
      ExploreMode.liveViewers => tr('{0} live · By viewers', [name]),
      ExploreMode.liveLatest => tr('{0} live · Just started', [name]),
      ExploreMode.liveUpcoming => tr('{0} · Upcoming streams', [name]),
      ExploreMode.liveReplay => tr('{0} · Recent stream replays', [name]),
    };
    // 宗教与信仰 keeps the zones in place, with 宗教信仰 chosen among them;
    // its own traditions are a row above the videos.
    final half = controller.exploreHalf;
    Widget strip({bool vertical = false}) {
      final topics = controller.exploreTopicsFor(half);
      return TopicStrip(
        key: ValueKey((half, vertical)),
        vertical: vertical,
        topics: topics,
        selected: section.isFaith ? topics.indexWhere((t) => t.opens != null) : controller.exploreTopic,
        onSelected: (i) {
          if (section.isFaith && topics[i].opens != null) return;
          controller.setExplore(section: half, topic: i);
        },
        onAdd: () => _addTopic(context, half),
        onManage: () => _manageTopics(context, half),
        onRemove: (topic) => _removeTopic(context, half, topic),
      );
    }

    // A wide window lists the zones down the left, as Bilibili's 分区 does,
    // leaving the full width below the filters to the videos.
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= ExplorePage.wideLayout;
      final page = _page(context, items: items, error: error, loading: loading, subtitle: subtitle, strip: wide ? null : strip());
      if (!wide) return page;
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: _railWidth, child: strip(vertical: true)),
        MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: (details) => setState(() => _railWidth = (_railWidth + details.delta.dx).clamp(TopicStrip.railWidth, 360).toDouble()),
            child: const SizedBox(width: 8),
          ),
        ),
        Expanded(child: page),
      ]);
    });
  }

  Widget _page(BuildContext context, {required List<VideoItem> items, required String? error, required bool loading, required String subtitle, required Widget? strip}) {
    final loader = controller.explore;
    final section = controller.exploreSection;
    final topic = controller.exploreTopicNow;
    final mode = controller.exploreMode;
    final live = section.isLive;
    final sub = controller.exploreSub;
    final subNow = controller.exploreSubNow;
    final leaf = controller.exploreLeaf;
    return NearEndListener(
      onNearEnd: () => loader?.loadMore(),
      child: CustomScrollView(key: const PageStorageKey('list'), slivers: [
        SliverToBoxAdapter(child: PageHeader(
          tr('Explore'),
          subtitle: subtitle,
          trailing: SegmentedButton<ExploreSection>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: ExploreSection.popular, label: Text(ExploreSection.popular.label), icon: const Icon(AppIcons.filmReelFill, size: 18)),
              ButtonSegment(value: ExploreSection.live, label: Text(ExploreSection.live.label), icon: const Icon(AppIcons.broadcast, size: 18)),
            ],
            // 宗教与信仰 shows as part of the half it was opened from.
            selected: {controller.exploreHalf},
            onSelectionChanged: (value) => controller.setExplore(section: value.first),
          ),
        )),
        if (section.isFaith)
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding - 8, 0, AppStyle.pagePadding, 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: SegmentedButton<ExploreSection>(
                  showSelectedIcon: false,
                  segments: [for (final s in ExploreSection.faithTabs) ButtonSegment(value: s, label: Text(s.label))],
                  selected: {section},
                  onSelectionChanged: (value) => controller.setExplore(section: value.first),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  for (final (i, faith) in controller.exploreTopicsFor(section).indexed)
                    GestureDetector(
                      onLongPress: faith.custom ? () => _removeTopic(context, section, faith) : null,
                      onSecondaryTap: faith.custom ? () => _removeTopic(context, section, faith) : null,
                      child: ChoiceChip(
                        avatar: Icon(faith.icon, size: 18),
                        label: Text(faith.label),
                        showCheckmark: false,
                        selected: i == controller.exploreTopic,
                        onSelected: (_) => controller.setExplore(topic: i),
                      ),
                    ),
                  IconButton(tooltip: tr('Add'), icon: const Icon(AppIcons.plus, size: 18), onPressed: () => _addTopic(context, section)),
                  IconButton(tooltip: tr('Manage'), icon: const Icon(AppIcons.slidersHorizontal, size: 18), onPressed: () => _manageTopics(context, section)),
                ]),
              ),
            ]),
          )),
        if (strip != null) SliverToBoxAdapter(child: strip),
        if (topic.subs.isNotEmpty)
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 4, AppStyle.pagePadding, 0),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (i, label) in [tr('All'), for (final s in topic.subs) s.label].indexed)
                ChoiceChip(label: Text(label), selected: sub == i, onSelected: (_) => controller.setExplore(sub: i)),
            ]),
          )),
        if (subNow != null && subNow.subs.isNotEmpty)
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 8, AppStyle.pagePadding, 0),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (i, label) in [tr('All {0}', [subNow.label]), for (final s in subNow.subs) s.label].indexed)
                FilterChip(
                  label: Text(label),
                  visualDensity: VisualDensity.compact,
                  showCheckmark: false,
                  selected: leaf == i,
                  onSelected: (_) => controller.setExplore(leaf: i),
                ),
            ]),
          )),
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 12, AppStyle.pagePadding, 16),
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SegmentedButton<ExploreMode>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [for (final m in ExploreMode.of(section)) ButtonSegment(value: m, label: Text(m.label))],
              selected: {mode},
              onSelectionChanged: (value) => controller.setExplore(mode: value.first),
            ),
            if (mode.hasPeriod)
              OptionChip(
                icon: AppIcons.calendar,
                value: controller.explorePeriod,
                values: explorePeriods,
                label: (v) => v.label,
                item: (v) => v.label,
                changed: false,
                onSelected: (v) => controller.setExplore(period: v),
              ),
            OptionChip(
              icon: AppIcons.shapes,
              value: controller.exploreFormat,
              values: controller.exploreFormats,
              label: (v) => v == controller.exploreFormats.first ? tr('Type') : v.label,
              item: (v) => v.label,
              changed: controller.exploreFormat != controller.exploreFormats.first,
              onSelected: (v) => controller.setExplore(format: v),
            ),
            OptionChip(
              icon: AppIcons.eye,
              value: controller.exploreView,
              values: controller.exploreViews,
              label: (v) => v == controller.exploreViews.first ? tr('Viewpoint') : v.label,
              item: (v) => v.label,
              changed: controller.exploreView != controller.exploreViews.first,
              onSelected: (v) => controller.setExplore(view: v),
            ),
            if (!live && mode != ExploreMode.long)
              OptionChip(
                icon: AppIcons.timer,
                value: controller.exploreDuration,
                values: SearchDuration.values,
                label: (v) => v == SearchDuration.any ? tr('Duration') : v.label,
                item: (v) => v.label,
                changed: controller.exploreDuration != SearchDuration.any,
                onSelected: (v) => controller.setExplore(duration: v),
              ),
            OptionChip(
              icon: AppIcons.globe,
              value: controller.preferences.exploreRegion,
              values: ExploreRegion.values,
              label: (v) => v == ExploreRegion.any ? tr('Region') : v.label,
              item: (v) => v.label,
              changed: controller.preferences.exploreRegion != ExploreRegion.any,
              onSelected: (v) => controller.setExplore(region: v),
            ),
            OptionChip(
              icon: AppIcons.translate,
              value: controller.preferences.exploreLanguage,
              values: ExploreLanguage.values,
              label: (v) => v == ExploreLanguage.any ? tr('Language') : v.label,
              item: (v) => v.label,
              changed: controller.preferences.exploreLanguage != ExploreLanguage.any,
              onSelected: (v) => controller.setExplore(language: v),
            ),
            if (controller.preferences.exploreLanguage != ExploreLanguage.any)
              Tooltip(
                message: tr('Only videos whose original audio track or automatic captions confirm the language, not guessed from the title and description'),
                child: FilterChip(
                  avatar: Icon(AppIcons.ear, size: 18, color: chipForeground(context, controller.preferences.exploreHeardOnly)),
                  label: Text(tr('Confirmed audio only')),
                  selected: controller.preferences.exploreHeardOnly,
                  onSelected: (v) => controller.setExplore(heardOnly: v),
                ),
              ),
            OptionChip(
              icon: AppIcons.highDefinition,
              value: controller.exploreQuality,
              values: SearchQuality.values,
              label: (v) => v == SearchQuality.any ? tr('Quality') : v.label,
              item: (v) => v.label,
              changed: controller.exploreQuality != SearchQuality.any,
              onSelected: (v) => controller.setExplore(quality: v),
            ),
            if (topic.mix)
              ActionChip(
                avatar: const Icon(AppIcons.arrowsClockwise, size: 18),
                label: Text(tr('Shuffle')),
                onPressed: loading ? null : controller.refreshExplore,
              ),
          ]),
        )),
        if (items.isNotEmpty) SliverVideoGrid(items: items, thumbnails: controller.thumbnailDirectory, onOpen: (item) => controller.play(item, from: items)),
        if (loading) ...[
          if (items.isNotEmpty) const SliverToBoxAdapter(child: SizedBox(height: AppStyle.cardSpacing)),
          SliverSkeletonGrid(rows: items.isEmpty ? 3 : 1),
        ],
        if (error != null)
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, AppStyle.cardSpacing, AppStyle.pagePadding, 0),
            child: ErrorBanner(items.isEmpty ? tr("Couldn't load: {0}", [error]) : tr("Couldn't load more: {0}", [error]), onRetry: () => loader?.loadMore(retry: true)),
          )),
        if (items.isEmpty && !loading && error == null)
          if (controller.exploreLanguageCheck case final check? when check.asked > 0)
            SliverFillRemaining(hasScrollBody: false, child: StatusView(
              icon: AppIcons.translate,
              title: tr('Checked {0} videos, none in {1}', [check.asked, controller.preferences.exploreLanguage.label]),
              message: tr('Keep looking further, or try another category or a wider duration and region'),
              action: FilledButton.icon(
                onPressed: controller.searchExploreFurther,
                icon: const Icon(AppIcons.magnifyingGlass),
                label: Text(tr('Keep looking')),
              ),
            ))
          else
            SliverFillRemaining(hasScrollBody: false, child: StatusView(icon: AppIcons.compass, title: switch (mode) {
              ExploreMode.liveUpcoming => tr('No upcoming streams in this category'),
              ExploreMode.liveReplay => tr('No stream replays in this category'),
              _ => live ? tr('No live streams in this category right now') : tr('No videos in this category right now'),
            })),
        const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
      ]),
    );
  }

  Future<void> _addTopic(BuildContext context, ExploreSection section) async {
    final topic = await showDialog<CustomTopic>(context: context, builder: (context) => _AddTopicDialog(section: section));
    if (topic != null) await controller.addExploreTopic(topic);
  }

  Future<void> _removeTopic(BuildContext context, ExploreSection section, ExploreTopic topic) async {
    final ok = await confirmDialog(context, title: tr('Delete category'), content: tr('Delete custom category "{0}"?', [topic.label]), confirm: tr('Delete'));
    if (ok) await controller.removeExploreTopic(section, topic.label);
  }

  Future<void> _manageTopics(BuildContext context, ExploreSection section) async {
    final all = controller.allExploreTopics(section);
    final result = await showDialog<(List<String>, Set<String>)>(
      context: context,
      builder: (context) => _ManageTopicsDialog(
        section: section,
        topics: arrangeTopics(all, controller.preferences.exploreOrder[section.name] ?? const [], const {}),
        hidden: {...?controller.preferences.exploreHidden[section.name]},
        defaults: all,
      ),
    );
    if (result != null) await controller.arrangeExploreTopics(section, result.$1, result.$2);
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
        title: Text(tr('Add category')),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _label,
              autofocus: true,
              maxLength: 8,
              decoration: InputDecoration(labelText: tr('Name'), hintText: tr('e.g. Catholic music')),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            TextField(
              controller: _query,
              decoration: InputDecoration(labelText: tr('Search terms (optional)'), hintText: tr('Leave empty to search by name, e.g. Gregorian chant')),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            SegmentedButton<ExploreSection>(
              showSelectedIcon: false,
              segments: [
                for (final s in widget.section.isFaith ? ExploreSection.faithTabs : const [ExploreSection.popular, ExploreSection.live])
                  ButtonSegment(value: s, label: Text(s.label)),
              ],
              selected: {_section},
              onSelectionChanged: (value) => setState(() => _section = value.first),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
          FilledButton(onPressed: _label.text.trim().isEmpty ? null : _submit, child: Text(tr('Add'))),
        ],
      );
}

/// Puts the zones in order, pins them to the front or hides them.
class _ManageTopicsDialog extends StatefulWidget {
  const _ManageTopicsDialog({required this.section, required this.topics, required this.hidden, required this.defaults});
  final ExploreSection section;
  final List<ExploreTopic> topics;
  final Set<String> hidden;
  /// The zones in their built-in order, for 恢复默认.
  final List<ExploreTopic> defaults;

  @override
  State<_ManageTopicsDialog> createState() => _ManageTopicsDialogState();
}

class _ManageTopicsDialogState extends State<_ManageTopicsDialog> {
  late final _topics = [...widget.topics];
  late final _hidden = {...widget.hidden};

  bool _lastShown(ExploreTopic topic) => !_hidden.contains(topic.key) && _topics.where((t) => !_hidden.contains(t.key)).length == 1;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr('Manage {0} categories', [widget.section.label])),
        content: SizedBox(
          width: 420,
          height: 480,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Drag to reorder, pin to move to the top, turn off the switch to hide.'), style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 8),
            Expanded(child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: _topics.length,
              onReorderItem: (from, to) => setState(() => _topics.insert(to, _topics.removeAt(from))),
              itemBuilder: (context, i) {
                final topic = _topics[i];
                final shown = !_hidden.contains(topic.key);
                return ListTile(
                  key: ValueKey(topic.key),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.all(4), child: Icon(AppIcons.dotsSixVertical))),
                  title: Row(children: [
                    Icon(topic.icon, size: 20, color: shown ? null : context.colors.outline),
                    const SizedBox(width: 8),
                    Flexible(child: Text(topic.label, overflow: TextOverflow.ellipsis, style: TextStyle(color: shown ? null : context.colors.outline))),
                  ]),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: tr('Pinned'),
                      icon: const Icon(AppIcons.alignTop),
                      onPressed: i == 0 ? null : () => setState(() => _topics.insert(0, _topics.removeAt(i))),
                    ),
                    Switch(
                      value: shown,
                      onChanged: _lastShown(topic) ? null : (on) => setState(() => on ? _hidden.remove(topic.key) : _hidden.add(topic.key)),
                    ),
                  ]),
                );
              },
            )),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              _topics
                ..clear()
                ..addAll(widget.defaults);
              _hidden.clear();
            }),
            child: Text(tr('Restore default')),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, ([for (final t in _topics) t.key], _hidden)), child: Text(tr('Save'))),
        ],
      );
}

/// A row of category icons that scrolls sideways, with the mouse wheel or
/// the arrows at its ends.
class TopicStrip extends StatefulWidget {
  const TopicStrip({super.key, required this.topics, required this.selected, required this.onSelected, this.onAdd, this.onManage, this.onRemove, this.vertical = false});
  /// A column down the left of a wide page instead of a row across the top.
  final bool vertical;
  static const railWidth = 128.0;
  final List<ExploreTopic> topics;
  final int selected;
  final ValueChanged<int> onSelected;
  /// Adds a category of the user's own, from a tile after the others.
  final VoidCallback? onAdd;
  /// Opens the order and hidden zones, from the last tile.
  final VoidCallback? onManage;
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

  List<(ExploreTopic, VoidCallback)> get _extras => [
        if (widget.onAdd case final add?) (ExploreTopic(tr('Add'), AppIcons.plus, ''), add),
        if (widget.onManage case final manage?) (ExploreTopic(tr('Manage'), AppIcons.slidersHorizontal, ''), manage),
      ];

  bool _extent(bool Function(ScrollPosition position) test) =>
      _scroll.hasClients && _scroll.position.hasContentDimensions && test(_scroll.position);

  void _by(double delta) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final target = (position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent);
    unawaited(Motion.scrollTo(_scroll, target));
  }

  Widget _rail(BuildContext context) {
    final remove = widget.onRemove;
    // Adding and managing stay in reach below the list, however long it is.
    return Column(children: [
      Expanded(child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(8, 12, 4, 8),
        children: [
          for (final (i, topic) in widget.topics.indexed)
            _RailTile(
              topic: topic,
              selected: i == widget.selected,
              onTap: () => widget.onSelected(i),
              onRemove: topic.custom && remove != null ? () => remove(topic) : null,
            ),
        ],
      )),
      if (_extras.isNotEmpty) ...[
        const Divider(height: 1, indent: 12, endIndent: 12),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 4, 8),
          child: Column(children: [for (final (topic, onTap) in _extras) _RailTile(topic: topic, selected: false, onTap: onTap, quiet: true)]),
        ),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) => widget.vertical ? _rail(context) : SizedBox(
        height: 84,
        child: Row(children: [
          const SizedBox(width: AppStyle.pagePadding - 12),
          _Arrow(icon: AppIcons.caretLeft, onTap: _extent((p) => p.pixels > p.minScrollExtent) ? () => _by(-_tileWidth * 4) : null),
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
              itemCount: widget.topics.length + _extras.length,
              itemExtent: _tileWidth,
              itemBuilder: (context, i) {
                if (i >= widget.topics.length) {
                  final (topic, onTap) = _extras[i - widget.topics.length];
                  return _TopicTile(topic: topic, selected: false, onTap: onTap);
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
          _Arrow(icon: AppIcons.caretRight, onTap: _extent((p) => p.pixels < p.maxScrollExtent) ? () => _by(_tileWidth * 4) : null),
          const SizedBox(width: AppStyle.pagePadding - 12),
        ]),
      );
}

/// One zone in the left column: a bar marks the one shown.
class _RailTile extends StatelessWidget {
  const _RailTile({required this.topic, required this.selected, required this.onTap, this.onRemove, this.quiet = false});
  final ExploreTopic topic;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  /// Add and manage, drawn fainter than the zones.
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = selected ? colors.primary : quiet ? colors.onSurfaceVariant : colors.onSurface;
    return Tooltip(
      message: onRemove == null ? topic.label : tr('{0} (right-click or long-press to delete)', [topic.label]),
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        onLongPress: onRemove,
        onSecondaryTap: onRemove,
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            color: selected ? colors.primary.withValues(alpha: 0.10) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            AnimatedContainer(
              duration: Motion.of(Ease.fade),
              width: 3,
              height: selected ? 20 : 0,
              decoration: BoxDecoration(color: colors.primary, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 8),
            Icon(topic.icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(
              topic.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: color, fontWeight: selected ? FontWeight.w600 : null),
            )),
          ]),
        ),
      ),
    );
  }
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
      message: onRemove == null ? topic.label : tr('{0} (right-click or long-press to delete)', [topic.label]),
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        onLongPress: onRemove,
        onSecondaryTap: onRemove,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedContainer(
            duration: Motion.of(Ease.fade),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: selected ? colors.primary : colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(topic.icon, size: 22, color: selected ? colors.onPrimary : colors.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
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
