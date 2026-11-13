import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../../app/app_controller.dart';
import '../../app/library_controller.dart';
import '../../library_store.dart';
import '../../models.dart';
import '../../youtube_tv_feed.dart';
import '../common.dart';
import '../playlist_length.dart';
import '../theme.dart';
import '../playlist_order_button.dart';
import '../video_card.dart';
import 'channel_page.dart';
import 'subscription_import_dialog.dart';
import 'explore_page.dart';
import '../../l10n/l10n.dart';
import '../app_icons.dart';

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
  /// The 订阅分组 shown, or null for every channel.
  ChannelGroup? _group;
  double _railWidth = _ChannelStrip.railWidth;

  AppController get controller => widget.controller;

  void _select(ChannelRef? channel) => setState(() => _selected = channel == _selected ? null : channel);

  @override
  Widget build(BuildContext context) {
    final library = controller.library;
    if (library == null) return const SizedBox.shrink();
    final channels = library.channels;
    if (channels.isEmpty) {
      return StatusView(
        icon: AppIcons.stack,
        title: tr('No followed channels yet'),
        message: tr('Tap "Follow" on a player or channel page, and the channel\'s new videos will show up here. You can also import your follow list from a NewPipe, FreeTube or Google Takeout file, or sign in with Google to import your YouTube subscriptions. Your follow list is stored only on this device.'),
        action: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
          FilledButton.icon(onPressed: () => importSubscriptionsFromFile(context, library), icon: Icon(AppIcons.downloadSimple), label: Text(tr('Import from file'))),
          if (!(controller.account?.signedIn ?? false))
            FilledButton.tonalIcon(onPressed: () => controller.navigate(PageMode.settings), icon: Icon(AppIcons.signIn), label: Text(tr('Sign in and import subscriptions'))),
        ]),
      );
    }
    final group = library.channelGroups.contains(_group) ? _group : null;
    final inGroup = group == null ? channels : [for (final c in channels) if (group.channels.contains(c.id)) c];
    final selected = inGroup.contains(_selected) ? _selected : null;
    final all = controller.visible(library.feed, subscriptions: true);
    final chosen = selected != null
        ? [for (final item in all) if (item.channelId == selected.id) item]
        : group != null
            ? [for (final item in all) if (group.channels.contains(item.channelId)) item]
            : all;
    // Streams that are on now come first.
    final feed = [for (final item in chosen) if (item.isLive) item, for (final item in chosen) if (!item.isLive) item];
    Widget strip({bool vertical = false}) => _ChannelStrip(
          vertical: vertical,
          itemWidth: vertical ? _railWidth - 12 : 72,
          channels: inGroup,
          feed: library.feed,
          live: library.liveChannels,
          selected: selected,
          thumbnails: controller.thumbnailDirectory,
          onSelect: _select,
          onShowAll: () => showDialog<void>(
            context: context,
            builder: (_) => _AllChannels(channels: inGroup, thumbnails: controller.thumbnailDirectory, onSelect: _select, onOpen: controller.openChannel),
          ),
        );
    // A wide window lists the channels down the left, as Bilibili's 动态 does.
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= ExplorePage.wideLayout;
      final page = _page(context, library, channels, selected, feed, wide ? null : strip(), group);
      if (!wide) return page;
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: _railWidth, child: strip(vertical: true)),
        _RailResizeHandle(onDrag: (delta) => setState(() => _railWidth = (_railWidth + delta).clamp(_ChannelStrip.railWidth, 360).toDouble())),
        Expanded(child: page),
      ]);
    });
  }

  Widget _page(BuildContext context, LibraryController library, List<ChannelRef> channels, ChannelRef? selected, List<VideoItem> feed, Widget? strip, ChannelGroup? group) {
    return CustomScrollView(key: const PageStorageKey('list'), slivers: [
      SliverToBoxAdapter(child: PageHeader(
        tr('Subscriptions'),
        subtitle: tr('{0} channels · Saved on this device only', [channels.length]),
        trailing: library.loadingFeed
            ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
            : Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(onPressed: () => importSubscriptionsFromFile(context, library), icon: Icon(AppIcons.downloadSimple), tooltip: tr('Import from file')),
                IconButton(onPressed: () => exportSubscriptionsToFile(context, library), icon: Icon(AppIcons.fileArrowUp), tooltip: tr('Export subscriptions')),
                TextButton.icon(onPressed: () => library.refreshFeed(force: true), icon: Icon(AppIcons.arrowsClockwise), label: Text(tr('Refresh'))),
              ]),
      )),
      SliverToBoxAdapter(child: _GroupChips(
        groups: library.channelGroups,
        selected: group,
        onSelect: (g) => setState(() {
          _group = g;
          _selected = null;
        }),
        onManage: () => showDialog<void>(context: context, builder: (_) => _ManageGroups(library: library, channels: channels)),
      )),
      if (strip != null) SliverToBoxAdapter(child: strip),
      if (selected != null)
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, AppStyle.cardSpacing),
          child: Row(children: [
            Expanded(child: Text(
              tr('New from {0}', [selected.name.isEmpty ? selected.id : selected.name]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            )),
            TextButton(onPressed: () => _select(null), child: Text(tr('Show all'))),
            FilledButton.tonalIcon(
              onPressed: () => controller.openChannel(selected),
              icon: Icon(AppIcons.caretRight),
              label: Text(tr('Open channel')),
            ),
          ]),
        )),
      if (library.feedFailures.isNotEmpty && selected == null)
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, AppStyle.cardSpacing),
          child: ErrorBanner(
            library.feedFailures.length > 5
                ? tr('{0} and others, {1} channels in all, could not be loaded', [library.feedFailures.take(5).join(tr(', ')), library.feedFailures.length])
                : tr("Couldn't load these channels right now: {0}", [library.feedFailures.join(tr(', '))]),
            onRetry: () => library.refreshFeed(force: true),
          ),
        )),
      if (feed.isNotEmpty)
        SliverVideoGrid(items: feed, thumbnails: controller.thumbnailDirectory, onOpen: (item) => controller.play(item, from: feed))
      else if (library.loadingFeed)
        const SliverSkeletonGrid()
      else if (group != null && group.channels.isEmpty)
        SliverFillRemaining(hasScrollBody: false, child: StatusView(
          icon: AppIcons.folderOpen,
          title: tr('This group has no channels yet'),
          action: FilledButton.tonal(onPressed: () => showDialog<void>(context: context, builder: (_) => _GroupChannels(library: library, group: group, channels: channels)), child: Text(tr('Choose channels'))),
        ))
      else if (selected != null)
        SliverFillRemaining(hasScrollBody: false, child: StatusView(
          icon: AppIcons.tray,
          title: tr('No recent videos from this channel'),
          action: FilledButton.tonal(onPressed: () => controller.openChannel(selected), child: Text(tr('Open the channel for all its videos'))),
        ))
      else
        SliverFillRemaining(hasScrollBody: false, child: StatusView(icon: AppIcons.tray, title: tr('No new videos yet'))),
      const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
    ]);
  }
}

/// 全部 and each 订阅分组 as chips, with the button that edits them.
class _GroupChips extends StatelessWidget {
  const _GroupChips({required this.groups, required this.selected, required this.onSelect, required this.onManage});
  final List<ChannelGroup> groups;
  final ChannelGroup? selected;
  final ValueChanged<ChannelGroup?> onSelect;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, 8),
        child: FilterFlow(children: [
          if (groups.isNotEmpty) ...[
            ChoiceChip(label: Text(tr('All')), selected: selected == null, onSelected: (_) => onSelect(null)),
            for (final group in groups)
              ChoiceChip(label: Text('${group.name} · ${group.channels.length}'), selected: selected == group, onSelected: (_) => onSelect(selected == group ? null : group)),
          ],
          TextButton.icon(
            onPressed: onManage,
            icon: Icon(groups.isEmpty ? AppIcons.folderPlus : AppIcons.pencilSimple, size: 18),
            label: Text(groups.isEmpty ? tr('New group') : tr('Manage groups')),
          ),
        ]),
      );
}

/// Adds, renames and removes 订阅分组 and picks each one's channels.
class _ManageGroups extends StatelessWidget {
  const _ManageGroups({required this.library, required this.channels});
  final LibraryController library;
  final List<ChannelRef> channels;

  Future<String?> _askName(BuildContext context, {String initial = ''}) {
    final text = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(initial.isEmpty ? tr('New group') : tr('Rename group')),
        content: TextField(
          controller: text,
          autofocus: true,
          decoration: InputDecoration(labelText: tr('Group name')),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
          TextButton(onPressed: () => Navigator.pop(context, text.text), child: Text(tr('Confirm'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: library,
        builder: (context, _) => AlertDialog(
          title: Text(tr('Subscription groups')),
          content: SizedBox(
            width: dialogWidth(context, 420),
            child: library.channelGroups.isEmpty
                ? Text(tr("Sort the channels you follow into groups, such as “Learning” or “Music”, and see one group's new videos at a time on the Subscriptions page."), style: TextStyle(color: context.colors.outline, height: 1.5))
                : ListView(shrinkWrap: true, children: [
                    for (final group in library.channelGroups)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(AppIcons.folder),
                        title: Text(group.name),
                        subtitle: Text(tr('{0} channels', [group.channels.length])),
                        onTap: () => showDialog<void>(context: context, builder: (_) => _GroupChannels(library: library, group: group, channels: channels)),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            tooltip: tr('Rename'),
                            icon: Icon(AppIcons.pencilLine),
                            onPressed: () async {
                              final name = await _askName(context, initial: group.name);
                              if (name != null && name.trim().isNotEmpty) library.renameGroup(group, name);
                            },
                          ),
                          IconButton(tooltip: tr('Delete group'), icon: Icon(AppIcons.trash), onPressed: () => library.removeGroup(group)),
                        ]),
                      ),
                  ]),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                final name = await _askName(context);
                if (name == null || name.trim().isEmpty || !context.mounted) return;
                final group = library.addGroup(name);
                await showDialog<void>(context: context, builder: (_) => _GroupChannels(library: library, group: group, channels: channels));
              },
              icon: Icon(AppIcons.plus),
              label: Text(tr('New group')),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Done'))),
          ],
        ),
      );
}

/// The followed channels with a tick for those in [group].
class _GroupChannels extends StatefulWidget {
  const _GroupChannels({required this.library, required this.group, required this.channels});
  final LibraryController library;
  final ChannelGroup group;
  final List<ChannelRef> channels;

  @override
  State<_GroupChannels> createState() => _GroupChannelsState();
}

class _GroupChannelsState extends State<_GroupChannels> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final filter = _filter.toLowerCase();
    final shown = [for (final c in widget.channels) if (filter.isEmpty || c.name.toLowerCase().contains(filter)) c];
    return ListenableBuilder(
      listenable: widget.library,
      builder: (context, _) => AlertDialog(
        title: Text(tr('Channels in “{0}”', [group.name])),
        content: SizedBox(
          width: dialogWidth(context, 420),
          height: 480,
          child: Column(children: [
            TextField(
              decoration: InputDecoration(isDense: true, prefixIcon: Icon(AppIcons.magnifyingGlass, size: 20), hintText: tr('Filter channels'), border: const OutlineInputBorder()),
              onChanged: (v) => setState(() => _filter = v.trim()),
            ),
            const SizedBox(height: 8),
            Expanded(child: ListView.builder(
              itemCount: shown.length,
              itemBuilder: (context, index) {
                final channel = shown[index];
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: group.channels.contains(channel.id),
                  title: Text(channel.name.isEmpty ? channel.id : channel.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onChanged: (v) => widget.library.setInGroup(group, channel.id, v ?? false),
                );
              },
            )),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Done')))],
      ),
    );
  }
}

File? _avatarFile(Directory? thumbnails, ChannelRef channel) =>
    thumbnails == null || channel.avatar == null ? null : File('${thumbnails.path}${Platform.pathSeparator}avatar_${channel.id}.jpg');

/// The followed channels as a row of avatars with names, scrolled by the
/// mouse wheel too. Those that posted most recently come first, and a dot
/// marks an upload in the last two days.
class _ChannelStrip extends StatefulWidget {
  const _ChannelStrip({this.vertical = false, this.itemWidth = 72, required this.channels, required this.feed, required this.live, required this.selected, required this.thumbnails, required this.onSelect, required this.onShowAll});
  final List<ChannelRef> channels;
  final List<VideoItem> feed;
  /// Channels streaming now.
  final Set<String> live;
  final ChannelRef? selected;
  final Directory? thumbnails;
  final ValueChanged<ChannelRef?> onSelect;
  final VoidCallback onShowAll;

  /// A column down the left of a wide page instead of a row.
  final bool vertical;
  final double itemWidth;
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
    final live = widget.live;
    final rank = {for (final (i, id) in latest.keys.indexed) id: i};
    // Channels streaming now first, then by their newest video.
    int order(ChannelRef channel) => (live.contains(channel.id) ? -latest.length - 1 : 0) + (rank[channel.id] ?? latest.length);
    final ordered = [...widget.channels]..sort((a, b) => order(a).compareTo(order(b)));
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
      label: tr('Show all {0}', [widget.channels.length]),
      width: widget.itemWidth,
      selected: false,
      onTap: widget.onShowAll,
      avatar: (radius) => CircleAvatar(radius: radius, child: Icon(AppIcons.listMagnifyingGlass, size: radius)),
    );
    if (widget.vertical) {
      // The full list stays in reach at the bottom, however long the column.
      return Column(children: [
        Expanded(child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.only(top: 8),
          children: _items(ordered, selected, latest, fresh, live),
        )),
        const Divider(height: 1, indent: 16, endIndent: 16),
        SizedBox(height: 88, child: showAll),
      ]);
    }
    // The full list stays in reach at the right, however long the row.
    return Row(children: [
      Expanded(child: _row(ordered, selected, latest, fresh, live)),
      Padding(
        padding: const EdgeInsetsDirectional.only(end: AppStyle.pagePadding - 4),
        child: showAll,
      ),
    ]);
  }

  List<Widget> _items(List<ChannelRef> ordered, ChannelRef? selected, Map<String, DateTime?> latest, DateTime fresh, Set<String> live) => [
        _StripItem(
          label: tr('All'),
          width: widget.itemWidth,
          selected: selected == null,
          onTap: () => widget.onSelect(null),
          avatar: (radius) => CircleAvatar(radius: radius, child: Icon(AppIcons.stackSimpleFill, size: radius)),
        ),
        for (final channel in ordered.take(_ChannelStrip.shown))
          _StripItem(
            label: channel.name.isEmpty ? channel.id : channel.name,
            width: widget.itemWidth,
            selected: channel == selected,
            fresh: latest[channel.id]?.isAfter(fresh) ?? false,
            live: live.contains(channel.id),
            onTap: () => widget.onSelect(channel),
            avatar: (radius) => ChannelAvatar(name: channel.name, radius: radius, image: channel.avatar, cacheFile: _avatarFile(widget.thumbnails, channel), channelId: channel.id),
          ),
      ];

  Widget _row(List<ChannelRef> ordered, ChannelRef? selected, Map<String, DateTime?> latest, DateTime fresh, Set<String> live) {
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
            padding: const EdgeInsetsDirectional.only(start: AppStyle.pagePadding - 4),
            children: _items(ordered, selected, latest, fresh, live),
          ),
        ),
      ),
    );
  }
}

class _StripItem extends StatelessWidget {
  const _StripItem({required this.label, required this.width, required this.selected, required this.onTap, required this.avatar, this.fresh = false, this.live = false});
  final String label;
  final double width;
  final bool selected;
  final bool fresh;
  /// Streaming now: a red ring and a 直播 tag, as YouTube shows it.
  final bool live;
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
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: width,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const SizedBox(height: 4),
            Stack(clipBehavior: Clip.none, children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? colors.primary : live ? _liveRed : Colors.transparent, width: 2)),
                child: avatar(22),
              ),
              if (live)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: -6,
                  child: Center(child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: _liveRed, borderRadius: BorderRadius.circular(4), border: Border.all(color: colors.surface, width: 1.5)),
                    child: Text(tr('Live'), style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700, height: 1.2)),
                  )),
                )
              else if (fresh)
                PositionedDirectional(end: 2, top: 2, child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle, border: Border.all(color: colors.surface, width: 2)),
                )),
            ]),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                maxLines: width > 100 ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: selected ? colors.primary : colors.onSurfaceVariant, fontWeight: selected ? FontWeight.w600 : null),
              ),
            ),
            const SizedBox(height: 4),
          ]),
        ),
      ),
    );
  }
}

const _liveRed = Color(0xFFCC0000);

class _RailResizeHandle extends StatelessWidget {
  const _RailResizeHandle({required this.onDrag});
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
          child: const SizedBox(width: 8),
        ),
      );
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
                prefixIcon: Icon(AppIcons.magnifyingGlass),
                hintText: tr('Search {0} followed channels', [widget.channels.length]),
              ),
            ),
          ),
          Expanded(
            child: matches.isEmpty
                ? Center(child: Text(tr('No matching channels')))
                : ListView.builder(
                    itemCount: matches.length,
                    itemBuilder: (context, i) {
                      final channel = matches[i];
                      return ListTile(
                        leading: ChannelAvatar(name: channel.name, radius: 18, image: channel.avatar, cacheFile: _avatarFile(widget.thumbnails, channel), channelId: channel.id),
                        title: Text(channel.name.isEmpty ? channel.id : channel.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          tooltip: tr('Open channel'),
                          icon: Icon(AppIcons.arrowSquareOut),
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
      (AppController.favoritesPlaylistId, tr('Favorites'), library.favorites, AppIcons.heartFill),
      (AppController.watchLaterPlaylistId, tr('Watch later'), library.watchLater, AppIcons.clockFill),
      for (final playlist in library.playlists) (playlist.id, playlist.name, playlist.items, LibraryController.isRemote(playlist) ? AppIcons.monitorPlay : AppIcons.playlist),
    ];
    return CustomScrollView(key: const PageStorageKey('list'), slivers: [
      SliverToBoxAdapter(child: PageHeader(
        tr('Playlist'),
        subtitle: tr('Saved on this device only'),
        trailing: FilledButton.tonalIcon(
          onPressed: () async {
            final name = await promptText(context, title: tr('New playlist'), hint: tr('Playlist name'), confirm: tr('Create'));
            if (name != null) library.createPlaylist(name);
          },
          icon: Icon(AppIcons.plus),
          label: Text(tr('New')),
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
          child: Text(tr('Right-click any video to add it to favorites or a playlist.'), style: TextStyle(color: context.colors.onSurfaceVariant)),
        )),
      if (controller.tvFeed?.available ?? false) ..._youtubePlaylists(context),
      const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
    ]);
  }

  /// The account's playlists on YouTube, read with the TV-code sign-in.
  List<Widget> _youtubePlaylists(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.ensureTvPlaylists());
    final lists = [
      PlaylistResult(id: YoutubeTvFeed.watchLaterId, title: tr('Watch later')),
      ...controller.tvPlaylists,
    ];
    return [
      SliverToBoxAdapter(child: PageHeader(
        tr('YouTube account'),
        subtitle: tr('Playlists saved on YouTube'),
        trailing: controller.tvPlaylistsLoading
            ? const Padding(padding: EdgeInsets.all(8), child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)))
            : TextButton.icon(onPressed: controller.loadTvPlaylists, icon: Icon(AppIcons.arrowsClockwise), label: Text(tr('Refresh'))),
      )),
      SliverVideoLayout(
        count: lists.length,
        builder: (context, i) {
          final list = lists[i];
          return _PlaylistCard(
            name: list.title,
            items: const [],
            remote: true,
            count: list.count,
            thumbnailUrl: list.thumbnail,
            icon: list.id == YoutubeTvFeed.watchLaterId ? AppIcons.clockFill : AppIcons.monitorPlay,
            thumbnails: controller.thumbnailDirectory,
            onOpen: () => controller.openYoutubePlaylist(list),
          );
        },
      ),
    ];
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
              mainAxisSpacing: gridGap,
              crossAxisSpacing: gridGap,
              mainAxisExtent: layout.itemHeight,
            ),
            delegate: SliverChildBuilderDelegate(builder, childCount: count),
          );
        }),
      );
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.name, required this.items, required this.icon, required this.thumbnails, required this.onOpen, this.remote = false, this.count, this.thumbnailUrl});
  final String name;
  final List<VideoItem> items;
  /// A playlist kept on YouTube, whose videos are not loaded: [count] is
  /// how many it holds, if known, and [thumbnailUrl] its cover.
  final bool remote;
  final int? count;
  final String? thumbnailUrl;
  final IconData icon;
  final Directory? thumbnails;
  final VoidCallback onOpen;

  int? get _shownCount => remote ? count : items.length;

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
                if (thumbnailUrl case final url? when items.isEmpty)
                  Image(color: context.pictureWarmth, colorBlendMode: BlendMode.multiply, image: ResizeImage.resizeIfNeeded(480, null, NetworkImage(url)), fit: BoxFit.cover, errorBuilder: (context, _, __) => ColoredBox(color: colors.surfaceContainerHighest, child: Icon(icon, size: 40, color: colors.outline)))
                else if (items.isEmpty)
                  ColoredBox(color: colors.surfaceContainerHighest, child: Icon(icon, size: 40, color: colors.outline))
                else
                  Image(
                    color: context.pictureWarmth,
                    colorBlendMode: BlendMode.multiply,
                    image: thumbnailFor(items.first, thumbnails),
                    fit: BoxFit.cover,
                    errorBuilder: (context, _, __) => ColoredBox(color: colors.surfaceContainerHighest),
                  ),
                PositionedDirectional(
                  end: 0,
                  top: 0,
                  bottom: 0,
                  width: 96,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.62),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(icon, color: Colors.white),
                      const SizedBox(height: 4),
                      if (_shownCount case final shown?) Text('$shown', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
          Expanded(child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.onSurface))),
              if (_shownCount case final shown?) Text(tr('{0} videos', [shown]), style: TextStyle(fontSize: 12, color: colors.outline)),
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
        icon: AppIcons.musicNotesMinus,
        title: tr('Playlist deleted'),
        action: FilledButton.tonal(onPressed: controller.goBack, child: Text(tr('Back'))),
      );
    }
    final own = List<VideoItem>.of(favorites ? library.favorites : later ? library.watchLater : playlist!.items);
    final items = controller.isReversed(id) ? own.reversed.toList() : own;
    final name = favorites ? tr('Favorites') : later ? tr('Watch later') : playlist!.name;
    void remove(VideoItem item) => favorites
        ? library.toggleFavorite(item)
        : later
            ? library.removeWatchLater(item.id)
            : library.removeFromPlaylist(playlist!, item);
    return CustomScrollView(key: const PageStorageKey('list'), slivers: [
      SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppStyle.pagePadding - 8, 8, AppStyle.pagePadding, 16),
        child: Row(children: [
          IconButton(tooltip: keyNames(tr('Back (Alt+←)')), onPressed: controller.goBack, icon: Icon(AppIcons.arrowLeft)),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            Text(
              playlist != null && LibraryController.isRemote(playlist) ? tr('{0} videos · From your YouTube account, updated on sync', [items.length]) : tr('{0} videos · Saved on this device only', [items.length]),
              style: TextStyle(color: context.colors.onSurfaceVariant),
            ),
            if (playlistLength(items, progressOf: library.progressOf) case final length?)
              Text(length, style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12)),
          ])),
          if (own.length > 1) ...[PlaylistOrderButton(controller: controller, id: id), const SizedBox(width: 4)],
          FilledButton.icon(
            onPressed: items.isEmpty ? null : () => controller.playList(id, name, own),
            icon: const Icon(AppIcons.playFill),
            label: Text(tr('Play all')),
          ),
          if (later && items.isNotEmpty) ...[
            const SizedBox(width: 4),
            TextButton.icon(onPressed: () => _clearLater(context, library), icon: Icon(AppIcons.trashSimple), label: Text(tr('Clear all'))),
          ],
          if (playlist != null) ...[
            const SizedBox(width: 4),
            IconButton(tooltip: tr('Rename'), onPressed: () => _rename(context, library, playlist), icon: Icon(AppIcons.pencilSimple)),
            IconButton(tooltip: tr('Delete playlist'), onPressed: () => _delete(context, library, playlist), icon: Icon(AppIcons.trash)),
          ],
        ]),
      )),
      if (items.isEmpty)
        SliverFillRemaining(hasScrollBody: false, child: StatusView(
          icon: favorites ? AppIcons.heart : later ? AppIcons.clock : AppIcons.listPlus,
          title: favorites ? tr('No favorite videos yet') : later ? tr('Watch later is empty') : tr('This playlist is empty'),
          message: later ? tr('Right-click any video and choose "Watch later", or use the button on the watch page, to keep videos here for later.') : tr('Right-click any video, or tap the button on the player page, to add it here.'),
        ))
      else
        SliverVideoGrid(items: items, thumbnails: controller.thumbnailDirectory, onOpen: (item) => controller.playList(id, name, own, start: item), onRemove: remove),
      const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
    ]);
  }

  Future<void> _clearLater(BuildContext context, LibraryController library) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(tr('Clear Watch later?')),
      content: Text(tr('Only this list is cleared; videos and watch history are not affected.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Clear all'))),
      ],
    ));
    if (confirmed == true) library.clearWatchLater();
  }

  Future<void> _rename(BuildContext context, LibraryController library, LocalPlaylist playlist) async {
    final name = await promptText(context, title: tr('Rename playlist'), hint: tr('Playlist name'), confirm: tr('Save'), initial: playlist.name);
    if (name != null) library.renamePlaylist(playlist, name);
  }

  Future<void> _delete(BuildContext context, LibraryController library, LocalPlaylist playlist) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(tr('Delete "{0}"?', [playlist.name])),
      content: Text(tr('Only deletes this playlist. Videos and watch history are not affected.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Delete'))),
      ],
    ));
    if (confirmed == true) {
      library.deletePlaylist(playlist);
      controller.goBack();
    }
  }
}
