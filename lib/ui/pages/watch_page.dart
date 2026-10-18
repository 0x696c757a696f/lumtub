import 'dart:math';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app/app_controller.dart';
import '../../models.dart';
import '../../widgets/pilinara_playback_controls.dart';
import '../common.dart';
import '../skeleton.dart';
import '../theme.dart';
import '../video_card.dart';

/// Player, video details and the up-next list. Side by side on wide windows,
/// stacked on narrow ones.
class WatchPage extends StatelessWidget {
  const WatchPage({super.key, required this.controller});
  final AppController controller;

  static const _sidePanelWidth = 380.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1080;
        final mainWidth = wide ? constraints.maxWidth - _sidePanelWidth - AppStyle.pagePadding * 3 : constraints.maxWidth - AppStyle.pagePadding * 2;
        // Keep the whole player visible: never taller than the window allows.
        final playerWidth = min(mainWidth, max(320.0, (constraints.maxHeight - 120) * 16 / 9));
        final main = <Widget>[
          _BackRow(onBack: controller.stopWatching),
          Center(child: SizedBox(width: playerWidth, child: _Player(controller: controller))),
          const SizedBox(height: 12),
          PiliNaraPlayerToolbar(player: controller.player!, trailing: [
            IconButton(tooltip: '复制链接', icon: const Icon(Icons.link_rounded), onPressed: () => copyText(context, controller.playing!.url, '链接已复制')),
            IconButton(tooltip: '在浏览器中打开', icon: const Icon(Icons.open_in_new_rounded), onPressed: () => openExternal(controller.playing!.url)),
          ]),
          if (controller.playbackError != null) ...[
            const SizedBox(height: 12),
            ErrorBanner('播放失败：${controller.playbackError}', onRetry: controller.retryPlayback),
          ],
          const SizedBox(height: 16),
          _Details(controller: controller),
        ];
        if (!wide) {
          return ListView(padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, AppStyle.pagePadding), children: [
            ...main,
            const SizedBox(height: 24),
            _UpNext(controller: controller, shrinkWrap: true),
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, AppStyle.pagePadding), children: main)),
          SizedBox(width: _sidePanelWidth, child: Padding(
            padding: const EdgeInsets.only(right: AppStyle.pagePadding, top: 48),
            child: _UpNext(controller: controller),
          )),
        ]);
      });
}

class _BackRow extends StatelessWidget {
  const _BackRow({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextButton.icon(onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded), label: const Text('返回')),
        ),
      );
}

class _Player extends StatelessWidget {
  const _Player({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: AppStyle.cardRadius,
          child: ColoredBox(color: Colors.black, child: Video(controller: controller.videoController!)),
        ),
      );
}

class _Details extends StatelessWidget {
  const _Details({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final item = controller.playing!;
    final details = controller.details;
    final colors = context.colors;
    final views = details?.viewCount ?? item.viewCount;
    final meta = [
      if (views != null) '${formatCount(views)}次观看',
      if (details?.uploadDate != null) formatDate(details!.uploadDate!),
      if (details?.likeCount != null) '${formatCount(details!.likeCount!)} 赞',
    ].join(' · ');
    final channel = details?.channel.isNotEmpty == true ? details!.channel : item.channel;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SelectableText(details?.title.isNotEmpty == true ? details!.title : item.title, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w600, height: 1.3)),
      const SizedBox(height: 12),
      Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: colors.primaryContainer,
          child: Text(channel.isEmpty ? 'Y' : channel.characters.first.toUpperCase(), style: TextStyle(color: colors.onPrimaryContainer, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(channel.isEmpty ? 'YouTube' : channel, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall)),
        if (details?.channelUrl != null)
          TextButton(onPressed: () => openExternal(details!.channelUrl!), child: const Text('查看频道')),
      ]),
      const SizedBox(height: 12),
      if (controller.loadingDetails && details == null)
        const Skeleton(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SkeletonBox(width: 220, height: 14),
          SizedBox(height: 10),
          SkeletonBox(height: 12),
          SizedBox(height: 6),
          SkeletonBox(height: 12),
          SizedBox(height: 6),
          SkeletonBox(width: 260, height: 12),
        ]))
      else if (meta.isNotEmpty || (details?.description.isNotEmpty ?? false))
        _Description(meta: meta, description: details?.description ?? ''),
    ]);
  }
}

/// Collapsible description card, three lines until expanded.
class _Description extends StatefulWidget {
  const _Description({required this.meta, required this.description});
  final String meta;
  final String description;

  @override
  State<_Description> createState() => _DescriptionState();
}

class _DescriptionState extends State<_Description> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasMore = widget.description.split('\n').length > 3 || widget.description.length > 240;
    return Material(
      color: colors.surfaceContainerHigh,
      borderRadius: AppStyle.cardRadius,
      child: InkWell(
        borderRadius: AppStyle.cardRadius,
        onTap: hasMore ? () => setState(() => _expanded = !_expanded) : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.meta.isNotEmpty) Text(widget.meta, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
            if (widget.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.topCenter,
                child: _expanded
                    ? SelectableText(widget.description, style: const TextStyle(height: 1.5))
                    : Text(widget.description, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.5)),
              ),
              if (hasMore) ...[
                const SizedBox(height: 4),
                Text(_expanded ? '收起' : '展开', style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600)),
              ],
            ],
          ]),
        ),
      ),
    );
  }
}

class _UpNext extends StatelessWidget {
  const _UpNext({required this.controller, this.shrinkWrap = false});
  final AppController controller;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final items = controller.upNext;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
      child: Row(children: [
        Text('接下来播放', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const Spacer(),
        if (items.isNotEmpty) Text('${items.length} 个', style: TextStyle(color: context.colors.outline, fontSize: 12)),
      ]),
    );
    if (items.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        header,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text('播放队列已经到底了。播放搜索结果或观看历史中的视频时，后面的视频会显示在这里。', style: TextStyle(color: context.colors.onSurfaceVariant, height: 1.5)),
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max, children: [
      header,
      if (shrinkWrap)
        for (final item in items.take(20)) _tile(item)
      else
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.only(bottom: AppStyle.pagePadding),
          itemCount: items.length,
          itemBuilder: (context, i) => _tile(items[i]),
        )),
    ]);
  }

  Widget _tile(VideoItem item) => CompactVideoTile(item: item, thumbnails: controller.thumbnailDirectory, onOpen: () => controller.play(item));
}
