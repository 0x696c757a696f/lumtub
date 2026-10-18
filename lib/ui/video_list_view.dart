import 'dart:io';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../models.dart';
import '../thumbnail_cache.dart';
import 'common.dart';
import 'theme.dart';

/// Home, explore and history pages: a responsive grid of video cards.
class VideoListView extends StatelessWidget {
  const VideoListView({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final mode = controller.mode;
    final list = mode == PageMode.history ? controller.history : controller.results;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 12, 28, 18),
        child: Row(children: [
          Text(_pageTitle(mode), style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
          const Spacer(),
          if (list.isNotEmpty) Text('共 ${list.length} 项', style: const TextStyle(color: Colors.white38)),
        ]),
      ),
      if (controller.searching) const LinearProgressIndicator(minHeight: 2),
      if (controller.error != null) ErrorBanner(controller.error!),
      Expanded(child: list.isEmpty ? _EmptyView(history: mode == PageMode.history) : LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth > 1320 ? 4 : constraints.maxWidth > 930 ? 3 : constraints.maxWidth > 550 ? 2 : 1;
        final grid = GridView.builder(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, mainAxisSpacing: 19, crossAxisSpacing: 19, childAspectRatio: 1.40),
          itemCount: list.length,
          itemBuilder: (context, i) => VideoCard(item: list[i], thumbnails: controller.thumbnailDirectory, onTap: () => controller.play(list[i])),
        );
        if (mode == PageMode.history) return grid;
        // Fetch the next page shortly before the end of the results is reached.
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.extentAfter < 600) controller.loadMoreResults();
            return false;
          },
          child: grid,
        );
      })),
    ]);
  }

  static String _pageTitle(PageMode mode) => switch (mode) {
        PageMode.home => '首页',
        PageMode.explore => '探索视频',
        PageMode.history => '观看历史',
        _ => '',
      };
}

class VideoCard extends StatelessWidget {
  const VideoCard({super.key, required this.item, required this.onTap, this.thumbnails});
  final VideoItem item;
  final VoidCallback onTap;

  /// The thumbnail cache folder; without it images load from the network only.
  final Directory? thumbnails;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(fit: StackFit.expand, children: [
              Image(
                image: ResizeImage.resizeIfNeeded(520, null, thumbnails == null ? NetworkImage(item.thumbnail) : CachedThumbnail(item.thumbnail, CachedThumbnail.fileFor(thumbnails!, item.id))),
                fit: BoxFit.cover,
                errorBuilder: (context, _, __) => const ColoredBox(color: AppColors.surface, child: Icon(Icons.ondemand_video_outlined, size: 46, color: Colors.white30))),
              if (item.durationLabel.isNotEmpty)
                Positioned(bottom: 8, right: 9, child: DecoratedBox(decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(5)), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3), child: Text(item.durationLabel, style: const TextStyle(fontSize: 11))))),
            ]),
          )),
          const SizedBox(height: 9),
          Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 3),
          Text(item.channel.isEmpty ? 'YouTube' : item.channel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white54)),
        ]),
      );
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.history});
  final bool history;

  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(history ? Icons.history_rounded : Icons.play_circle_outline_rounded, size: 60, color: Colors.white24),
        const SizedBox(height: 16),
        Text(history ? '还没有观看记录' : '搜索你想看的 YouTube 视频', style: const TextStyle(fontSize: 18, color: Colors.white60)),
        const SizedBox(height: 8),
        if (!history) const Text('也可以粘贴 youtube.com 或 youtu.be 链接', style: TextStyle(color: Colors.white38)),
      ]));
}

/// Placeholder for sections whose local storage is not implemented yet.
class PlannedView extends StatelessWidget {
  const PlannedView({super.key, required this.subscriptions});
  final bool subscriptions;

  @override
  Widget build(BuildContext context) => Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(subscriptions ? Icons.subscriptions_outlined : Icons.queue_music_outlined, size: 58, color: Colors.white24),
            const SizedBox(height: 16),
            Text(subscriptions ? '订阅会保存在本机' : '播放列表会保存在本机', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('这个区域已预留在界面中，等本地订阅和播放列表功能完成后显示内容。', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, height: 1.5)),
          ]),
        ),
      ));
}
