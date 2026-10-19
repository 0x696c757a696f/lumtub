import 'dart:math';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app/app_controller.dart';
import '../../models.dart';
import '../../widgets/pilinara_playback_controls.dart';
import '../common.dart';
import '../player_shortcuts.dart';
import '../skeleton.dart';
import '../theme.dart';
import '../video_card.dart';
import 'channel_page.dart';

/// Player, video details and the up-next list. Side by side on wide windows,
/// stacked on narrow ones.
class WatchPage extends StatefulWidget {
  const WatchPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<WatchPage> createState() => _WatchPageState();
}

class _WatchPageState extends State<WatchPage> {
  static const _sidePanelWidth = 380.0;
  final _video = GlobalKey<VideoState>();

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final shortcuts = playerShortcuts(controller, _video);
    // The same bindings work anywhere on the page and inside the fullscreen
    // route, where media_kit's controls hold focus.
    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1080;
          final mainWidth = wide ? constraints.maxWidth - _sidePanelWidth - AppStyle.pagePadding * 3 : constraints.maxWidth - AppStyle.pagePadding * 2;
          // Keep the whole player visible: never taller than the window allows.
          final playerWidth = min(mainWidth, max(320.0, (constraints.maxHeight - 120) * 16 / 9));
          final main = <Widget>[
            _BackRow(onBack: controller.stopWatching),
            Center(child: SizedBox(width: playerWidth, child: _Player(controller: controller, videoKey: _video, shortcuts: shortcuts))),
            const SizedBox(height: 12),
            _Toolbar(controller: controller),
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
        }),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final item = controller.playing!;
    final settings = controller.settings;
    final decoded = controller.currentCodec != '尚未播放视频';
    final library = controller.library;
    final favorite = library?.isFavorite(item.id) ?? false;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PiliNaraPlayerToolbar(
        player: controller.player!,
        maxHeight: settings.maxHeight,
        onQualitySelected: controller.setMaxHeight,
        trailing: [
          FilterChip(
            avatar: const Icon(Icons.playlist_play_rounded, size: 18),
            label: const Text('自动连播'),
            selected: settings.autoplayNext,
            showCheckmark: false,
            onSelected: controller.setAutoplayNext,
          ),
          IconButton(tooltip: '下一个 (Shift+N)', icon: const Icon(Icons.skip_next_rounded), onPressed: controller.hasNext ? controller.playNext : null),
          if (library != null) ...[
            IconButton(
              tooltip: favorite ? '取消收藏' : '收藏',
              isSelected: favorite,
              icon: const Icon(Icons.favorite_border_rounded),
              selectedIcon: Icon(Icons.favorite_rounded, color: context.colors.primary),
              onPressed: () => library.toggleFavorite(item),
            ),
            IconButton(tooltip: '添加到播放列表', icon: const Icon(Icons.playlist_add_rounded), onPressed: () => showAddToPlaylist(context, controller, item)),
          ],
          IconButton(tooltip: '复制链接', icon: const Icon(Icons.link_rounded), onPressed: () => copyText(context, item.url, '链接已复制')),
          IconButton(tooltip: '在浏览器中打开', icon: const Icon(Icons.open_in_new_rounded), onPressed: () => openExternal(item.url)),
          IconButton(tooltip: '快捷键', icon: const Icon(Icons.keyboard_outlined), onPressed: () => showShortcutHelp(context)),
        ],
      ),
      if (decoded)
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 4),
          child: Text('解码：${controller.currentCodec} · ${controller.currentHwdec}', style: TextStyle(fontSize: 12, color: context.colors.outline)),
        ),
    ]);
  }
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
  const _Player({required this.controller, required this.videoKey, required this.shortcuts});
  final AppController controller;
  final GlobalKey<VideoState> videoKey;
  final Map<ShortcutActivator, VoidCallback> shortcuts;

  @override
  Widget build(BuildContext context) {
    final controls = MaterialDesktopVideoControlsThemeData(keyboardShortcuts: shortcuts);
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: AppStyle.cardRadius,
        child: ColoredBox(
          color: Colors.black,
          child: MaterialDesktopVideoControlsTheme(
            normal: controls,
            fullscreen: controls,
            child: Video(key: videoKey, controller: controller.videoController!),
          ),
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final item = controller.playing!;
    final details = controller.details;
    final views = details?.viewCount ?? item.viewCount;
    final meta = [
      if (views != null) '${formatCount(views)}次观看',
      if (details?.uploadDate != null) formatDate(details!.uploadDate!),
      if (details?.likeCount != null) '${formatCount(details!.likeCount!)} 赞',
    ].join(' · ');
    final channel = details?.channel.isNotEmpty == true ? details!.channel : item.channel;
    final channelRef = controller.playingChannel;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SelectableText(details?.title.isNotEmpty == true ? details!.title : item.title, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w600, height: 1.3)),
      const SizedBox(height: 12),
      Row(children: [
        ChannelAvatar(name: channel.isEmpty ? 'YouTube' : channel),
        const SizedBox(width: 12),
        Flexible(child: Text(channel.isEmpty ? 'YouTube' : channel, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall)),
        const SizedBox(width: 8),
        if (channelRef != null) ...[
          TextButton(onPressed: () => controller.openChannel(channelRef), child: const Text('查看频道')),
          const Spacer(),
          FollowButton(controller: controller, channel: channelRef),
        ] else if (details?.channelUrl != null)
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
    final related = controller.related;
    final relatedItems = related?.items ?? const <VideoItem>[];
    final children = <Widget>[
      _header(context, '接下来播放', items.isEmpty ? null : '${items.length} 个'),
      if (items.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
          child: Text(
            relatedItems.isEmpty ? '播放队列已经到底了。播放搜索结果、播放列表或观看历史中的视频时，后面的视频会显示在这里。' : '播放队列已经到底了，自动连播会接着播放下面的相关视频。',
            style: TextStyle(color: context.colors.onSurfaceVariant, height: 1.5),
          ),
        )
      else
        for (final item in shrinkWrap ? items.take(20) : items) _tile(item, null),
      if (related != null) ...[
        const SizedBox(height: 16),
        _header(context, '相关视频', '按标题搜索'),
        for (final item in relatedItems) _tile(item, relatedItems),
        if (related.loading && relatedItems.isEmpty)
          const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator())
        else if (related.error != null)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: ErrorBanner('无法加载相关视频', onRetry: () => related.loadMore(retry: true))),
      ],
    ];
    if (shrinkWrap) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);
    return ListView(padding: const EdgeInsets.only(bottom: AppStyle.pagePadding), children: children);
  }

  Widget _header(BuildContext context, String title, String? note) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
        child: Row(children: [
          Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const Spacer(),
          if (note != null) Text(note, style: TextStyle(color: context.colors.outline, fontSize: 12)),
        ]),
      );

  Widget _tile(VideoItem item, List<VideoItem>? list) =>
      CompactVideoTile(item: item, thumbnails: controller.thumbnailDirectory, onOpen: () => controller.play(item, from: list));
}
