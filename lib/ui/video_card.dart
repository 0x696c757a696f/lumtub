import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../appearance_settings.dart';
import '../library_store.dart';
import '../models.dart';
import '../thumbnail_cache.dart';
import 'common.dart';
import 'skeleton.dart';
import 'theme.dart';

/// Height of the text below a card's thumbnail: two title lines and one
/// channel line.
const _cardInfoHeight = 82.0;

ImageProvider thumbnailFor(VideoItem item, Directory? thumbnails, {int width = 480}) => ResizeImage.resizeIfNeeded(
      width,
      null,
      thumbnails == null ? NetworkImage(item.thumbnail) : CachedThumbnail(item.thumbnail, CachedThumbnail.fileFor(thumbnails, item.id, VideoItem.thumbnailFile)),
    );

/// Column count and card height for a grid [width] wide.
({int columns, double itemHeight}) gridLayoutFor(double width) {
  final columns = max(1, ((width + AppStyle.cardSpacing) / (videoCardMinWidth + AppStyle.cardSpacing)).floor());
  final itemWidth = (width - AppStyle.cardSpacing * (columns - 1)) / columns;
  return (columns: columns, itemHeight: itemWidth * 9 / 16 + _cardInfoHeight);
}

/// Makes the app's library actions (favorites, playlists, channels, watch
/// progress) available to every card below it without passing them down.
class VideoActions extends InheritedWidget {
  const VideoActions({super.key, required this.controller, required super.child});
  final AppController controller;

  static AppController? of(BuildContext context) => context.getInheritedWidgetOfExactType<VideoActions>()?.controller;

  // Cards rebuild with their pages whenever the controller notifies.
  @override
  bool updateShouldNotify(VideoActions oldWidget) => false;
}

/// A lazily built grid of video cards as a sliver, so pages can put headers
/// above it in the same scroll view.
class SliverVideoGrid extends StatelessWidget {
  const SliverVideoGrid({super.key, required this.items, required this.onOpen, this.thumbnails, this.onRemove});
  final List<VideoItem> items;
  final void Function(VideoItem item) onOpen;
  final Directory? thumbnails;
  /// Adds a "remove" entry to each card's menu, for playlists.
  final void Function(VideoItem item)? onRemove;

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
            delegate: SliverChildBuilderDelegate(
              (context, i) => VideoCard(item: items[i], thumbnails: thumbnails, onOpen: () => onOpen(items[i]), onRemove: onRemove == null ? null : () => onRemove!(items[i])),
              childCount: items.length,
            ),
          );
        }),
      );
}

/// Placeholder cards shown while results load.
class SliverSkeletonGrid extends StatelessWidget {
  const SliverSkeletonGrid({super.key, this.rows = 3});
  final int rows;

  @override
  Widget build(BuildContext context) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppStyle.pagePadding),
        sliver: SliverLayoutBuilder(builder: (context, constraints) {
          final layout = gridLayoutFor(constraints.crossAxisExtent);
          final width = constraints.crossAxisExtent;
          return SliverToBoxAdapter(child: Skeleton(child: SizedBox(
            width: width,
            child: Wrap(
              spacing: AppStyle.cardSpacing,
              runSpacing: AppStyle.cardSpacing,
              children: List.generate(layout.columns * rows, (_) => SizedBox(
                width: (width - AppStyle.cardSpacing * (layout.columns - 1)) / layout.columns - 0.01,
                height: layout.itemHeight,
                child: const _CardSkeleton(),
              )),
            ),
          )));
        }),
      );
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
        AspectRatio(aspectRatio: 16 / 9, child: SkeletonBox(radius: AppStyle.radius)),
        SizedBox(height: 12),
        SkeletonBox(height: 14),
        SizedBox(height: 8),
        FractionallySizedBox(widthFactor: 0.6, child: SkeletonBox(height: 14)),
        SizedBox(height: 10),
        FractionallySizedBox(widthFactor: 0.4, child: SkeletonBox(height: 11)),
      ]);
}

/// Thumbnail-on-top video card with hover zoom and a right-click menu.
class VideoCard extends StatefulWidget {
  const VideoCard({super.key, required this.item, required this.onOpen, this.thumbnails, this.onRemove});
  final VideoItem item;
  final VoidCallback onOpen;
  final Directory? thumbnails;
  final VoidCallback? onRemove;

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  bool _hovered = false;
  Timer? _prefetch;

  /// A pointer resting on a card starts resolving the video, so a click
  /// that follows starts playback sooner.
  void _hover(bool value) {
    setState(() => _hovered = value);
    _prefetch?.cancel();
    if (value) _prefetch = Timer(const Duration(milliseconds: 400), () => VideoActions.of(context)?.prefetch(widget.item));
  }

  @override
  void dispose() {
    _prefetch?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final colors = context.colors;
    final meta = [
      if (item.channel.isNotEmpty) item.channel,
      if (item.viewCount != null) '${formatCount(item.viewCount!)}次观看',
    ].join(' · ');
    return Card(
      child: InkWell(
        onTap: widget.onOpen,
        onHover: _hover,
        onSecondaryTapUp: (details) => showVideoMenu(context, item, details.globalPosition, onOpen: widget.onOpen, onRemove: widget.onRemove),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: AppStyle.thumbnailRadius,
              child: Stack(fit: StackFit.expand, children: [
                AnimatedScale(
                  scale: _hovered ? 1.04 : 1,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: Image(
                    image: thumbnailFor(item, widget.thumbnails),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    frameBuilder: (context, child, frame, sync) => sync || frame != null ? child : ColoredBox(color: colors.surfaceContainerHighest),
                    errorBuilder: (context, _, __) => ColoredBox(color: colors.surfaceContainerHighest, child: Icon(Icons.ondemand_video_rounded, size: 40, color: colors.outline)),
                  ),
                ),
                if (item.durationLabel.isNotEmpty) Positioned(right: 8, bottom: 8, child: DurationBadge(item.durationLabel)),
                _ProgressBar(item: item),
              ]),
            ),
          ),
          Expanded(child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, height: 1.38, fontWeight: FontWeight.w500, color: colors.onSurface))),
              Text(meta.isEmpty ? 'YouTube' : meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: colors.outline)),
            ]),
          )),
        ]),
      ),
    );
  }
}

class DurationBadge extends StatelessWidget {
  const DurationBadge(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(4)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500, fontFeatures: [FontFeature.tabularFigures()])),
        ),
      );
}

/// Compact horizontal card for the up-next list on the watch page.
class CompactVideoTile extends StatelessWidget {
  const CompactVideoTile({super.key, required this.item, required this.onOpen, this.thumbnails});
  final VideoItem item;
  final VoidCallback onOpen;
  final Directory? thumbnails;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      borderRadius: AppStyle.cardRadius,
      onTap: onOpen,
      onSecondaryTapUp: (details) => showVideoMenu(context, item, details.globalPosition, onOpen: onOpen),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 152,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(fit: StackFit.expand, children: [
                  Image(
                    image: thumbnailFor(item, thumbnails, width: 320),
                    fit: BoxFit.cover,
                    errorBuilder: (context, _, __) => ColoredBox(color: colors.surfaceContainerHighest),
                  ),
                  if (item.durationLabel.isNotEmpty) Positioned(right: 4, bottom: 4, child: DurationBadge(item.durationLabel)),
                  _ProgressBar(item: item),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, height: 1.35, fontWeight: FontWeight.w500, color: colors.onSurface)),
            const SizedBox(height: 4),
            Text(item.channel.isEmpty ? 'YouTube' : item.channel, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: colors.outline)),
          ])),
        ]),
      ),
    );
  }
}

/// How much of [item] was watched, as a bar along the thumbnail's bottom.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.item});
  final VideoItem item;

  @override
  Widget build(BuildContext context) {
    final progress = VideoActions.of(context)?.library?.progressOf(item.id);
    if (progress == null || progress.fraction < 0.02) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: LinearProgressIndicator(value: progress.fraction, minHeight: 3, backgroundColor: Colors.black45, color: context.colors.primary),
    );
  }
}

Future<void> showVideoMenu(BuildContext context, VideoItem item, Offset position, {required VoidCallback onOpen, VoidCallback? onRemove}) async {
  final controller = VideoActions.of(context);
  final library = controller?.library;
  final channel = item.channelRef;
  final favorite = library?.isFavorite(item.id) ?? false;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  PopupMenuItem<String> entry(String value, IconData icon, String label) =>
      PopupMenuItem(value: value, child: ListTile(dense: true, leading: Icon(icon), title: Text(label)));
  final choice = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size),
    items: [
      entry('play', Icons.play_arrow_rounded, '播放'),
      if (library != null) ...[
        entry('favorite', favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, favorite ? '取消收藏' : '收藏'),
        entry('playlist', Icons.playlist_add_rounded, '添加到播放列表…'),
      ],
      if (controller != null && channel != null) ...[
        entry('channel', Icons.account_circle_outlined, '查看频道'),
        entry('block', Icons.block_rounded, '屏蔽此频道'),
      ],
      if (onRemove != null) entry('remove', Icons.remove_circle_outline_rounded, '从此列表移除'),
      const PopupMenuDivider(),
      entry('copy', Icons.link_rounded, '复制链接'),
      entry('browser', Icons.open_in_new_rounded, '在浏览器中打开'),
    ],
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'play':
      onOpen();
    case 'favorite':
      final added = library!.toggleFavorite(item);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(added ? '已收藏' : '已取消收藏')));
    case 'playlist':
      await showAddToPlaylist(context, controller!, item);
    case 'channel':
      controller!.openChannel(channel!);
    case 'block':
      controller!.blockChannel(channel!);
    case 'remove':
      onRemove!();
    case 'copy':
      await copyText(context, item.url, '链接已复制');
    case 'browser':
      await openExternal(item.url);
  }
}

/// Lets the user pick a playlist for [item], or create one.
Future<void> showAddToPlaylist(BuildContext context, AppController controller, VideoItem item) async {
  final library = controller.library;
  if (library == null) return;
  const create = '\u0000new';
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('添加到播放列表'),
      children: [
        for (final playlist in library.playlists)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, playlist.id),
            child: ListTile(leading: const Icon(Icons.playlist_play_rounded), title: Text(playlist.name), subtitle: Text('${playlist.items.length} 个视频')),
          ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, create),
          child: const ListTile(leading: Icon(Icons.add_rounded), title: Text('新建播放列表')),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  final playlist = choice == create ? await _createPlaylist(context, controller) : library.playlist(choice);
  if (playlist == null || !context.mounted) return;
  final added = library.addToPlaylist(playlist, item);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(added ? '已添加到“${playlist.name}”' : '“${playlist.name}”里已经有这个视频')));
}

Future<LocalPlaylist?> _createPlaylist(BuildContext context, AppController controller) async {
  final name = await promptText(context, title: '新建播放列表', hint: '播放列表名称', confirm: '创建');
  return name == null ? null : controller.library?.createPlaylist(name);
}

/// Asks for one line of text; null when cancelled.
Future<String?> promptText(BuildContext context, {required String title, required String hint, required String confirm, String initial = ''}) {
  final text = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: text,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, text.text), child: Text(confirm)),
      ],
    ),
  ).whenComplete(text.dispose);
}
