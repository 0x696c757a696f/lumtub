import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models.dart';
import '../thumbnail_cache.dart';
import 'common.dart';
import 'skeleton.dart';
import 'theme.dart';

/// Height of the text below a card's thumbnail: two title lines and one
/// channel line.
const _cardInfoHeight = 82.0;
const _minCardWidth = 250.0;

ImageProvider thumbnailFor(VideoItem item, Directory? thumbnails, {int width = 480}) => ResizeImage.resizeIfNeeded(
      width,
      null,
      thumbnails == null ? NetworkImage(item.thumbnail) : CachedThumbnail(item.thumbnail, CachedThumbnail.fileFor(thumbnails, item.id)),
    );

/// Column count and card height for a grid [width] wide.
({int columns, double itemHeight}) gridLayoutFor(double width) {
  final columns = max(1, ((width + AppStyle.cardSpacing) / (_minCardWidth + AppStyle.cardSpacing)).floor());
  final itemWidth = (width - AppStyle.cardSpacing * (columns - 1)) / columns;
  return (columns: columns, itemHeight: itemWidth * 9 / 16 + _cardInfoHeight);
}

/// A lazily built grid of video cards as a sliver, so pages can put headers
/// above it in the same scroll view.
class SliverVideoGrid extends StatelessWidget {
  const SliverVideoGrid({super.key, required this.items, required this.onOpen, this.thumbnails});
  final List<VideoItem> items;
  final void Function(VideoItem item) onOpen;
  final Directory? thumbnails;

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
              (context, i) => VideoCard(item: items[i], thumbnails: thumbnails, onOpen: () => onOpen(items[i])),
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
  const VideoCard({super.key, required this.item, required this.onOpen, this.thumbnails});
  final VideoItem item;
  final VoidCallback onOpen;
  final Directory? thumbnails;

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  bool _hovered = false;

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
        onHover: (value) => setState(() => _hovered = value),
        onSecondaryTapUp: (details) => showVideoMenu(context, item, details.globalPosition, onOpen: widget.onOpen),
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

Future<void> showVideoMenu(BuildContext context, VideoItem item, Offset position, {required VoidCallback onOpen}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final choice = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size),
    items: const [
      PopupMenuItem(value: 'play', child: ListTile(dense: true, leading: Icon(Icons.play_arrow_rounded), title: Text('播放'))),
      PopupMenuItem(value: 'copy', child: ListTile(dense: true, leading: Icon(Icons.link_rounded), title: Text('复制链接'))),
      PopupMenuItem(value: 'browser', child: ListTile(dense: true, leading: Icon(Icons.open_in_new_rounded), title: Text('在浏览器中打开'))),
    ],
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'play':
      onOpen();
    case 'copy':
      await copyText(context, item.url, '链接已复制');
    case 'browser':
      await openExternal(item.url);
  }
}
