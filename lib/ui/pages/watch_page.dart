import 'dart:async';

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app/app_controller.dart';
import '../../models.dart';
import '../../player_settings.dart';
import '../../youtube_account.dart' show VideoRating;
import '../comments_view.dart';
import '../common.dart';
import '../linked_text.dart';
import '../player_controls.dart';
import '../player_shortcuts.dart';
import '../skeleton.dart';
import '../theme.dart';
import '../video_card.dart';
import 'channel_page.dart';
import '../../l10n/l10n.dart';

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
  String? _fullscreenFor;

  /// Enters fullscreen once per video when 自动全屏 is on.
  void _autoFullscreen(AppController controller) {
    final id = controller.playing?.id;
    if (id == null || id == _fullscreenFor || !controller.preferences.autoFullscreen) return;
    _fullscreenFor = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = _video.currentState;
      if (mounted && state != null && !state.isFullscreen()) state.enterFullscreen();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final appearance = controller.appearance;
    final page = _page(context, controller);
    if (!appearance.darkWatchPage || Theme.of(context).brightness == Brightness.dark) return page;
    final dark = buildAppTheme(controller.accentColor, Brightness.dark, variant: appearance.schemeVariant, pureBlack: appearance.pureBlack, fontFamily: appearance.fontFamily);
    return Theme(data: dark, child: Material(color: dark.colorScheme.surface, child: page));
  }

  Widget _page(BuildContext context, AppController controller) {
    _autoFullscreen(controller);
    final shortcuts = playerShortcuts(controller, () => _video.currentState);
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
            _BackRow(onBack: controller.goBack),
            Center(child: SizedBox(width: playerWidth, child: _Player(controller: controller, videoKey: _video))),
            const SizedBox(height: 12),
            _Toolbar(controller: controller),
            if (controller.playbackError != null) ...[
              const SizedBox(height: 12),
              ErrorBanner(tr('播放失败：{0}', [controller.playbackError]), onRetry: controller.retryPlayback),
            ],
            const SizedBox(height: 16),
            _Details(controller: controller),
            if (controller.playing case final item?) ...[
              const SizedBox(height: 24),
              CommentsSection(key: ValueKey('comments:${item.id}'), controller: controller, videoId: item.id, onSeek: (position) => controller.player?.seek(position)),
            ],
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
    final decoded = controller.currentCodec != tr('尚未播放视频');
    final library = controller.library;
    final favorite = library?.isFavorite(item.id) ?? false;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          PopupMenuButton<PlayOrder>(
            tooltip: tr('播放顺序'),
            initialValue: settings.playOrder,
            onSelected: controller.setPlayOrder,
            itemBuilder: (context) => [
              for (final order in PlayOrder.values) CheckedPopupMenuItem(value: order, checked: order == settings.playOrder, child: Text(order.label)),
            ],
            child: Chip(avatar: const Icon(Icons.repeat_rounded, size: 18), label: Text(settings.playOrder.label)),
          ),
          if (controller.account case final account? when account.signedIn) ...[
            for (final (rating, icon, selectedIcon, label) in [
              (VideoRating.like, Icons.thumb_up_outlined, Icons.thumb_up_rounded, tr('赞')),
              (VideoRating.dislike, Icons.thumb_down_outlined, Icons.thumb_down_rounded, tr('踩')),
            ])
              IconButton(
                tooltip: account.ratingOf(item.id) == rating ? tr('取消{0}', [label]) : label,
                isSelected: account.ratingOf(item.id) == rating,
                icon: Icon(icon),
                selectedIcon: Icon(selectedIcon, color: context.colors.primary),
                onPressed: () => account.rate(item, rating),
              ),
          ],
          if (library != null) ...[
            IconButton(
              tooltip: favorite ? tr('取消收藏') : tr('收藏'),
              isSelected: favorite,
              icon: const Icon(Icons.favorite_border_rounded),
              selectedIcon: Icon(Icons.favorite_rounded, color: context.colors.primary),
              onPressed: () => library.toggleFavorite(item),
            ),
            IconButton(tooltip: tr('添加到播放列表'), icon: const Icon(Icons.playlist_add_rounded), onPressed: () => showAddToPlaylist(context, controller, item)),
            if (controller.account?.signedIn ?? false)
              IconButton(tooltip: tr('保存到 YouTube 播放列表'), icon: const Icon(Icons.video_library_outlined), onPressed: () => showSaveToYoutube(context, controller, item)),
          ],
          IconButton(tooltip: tr('复制链接'), icon: const Icon(Icons.link_rounded), onPressed: () => copyText(context, item.url, tr('链接已复制'))),
          IconButton(tooltip: tr('在浏览器中打开'), icon: const Icon(Icons.open_in_new_rounded), onPressed: () => openExternal(item.url)),
          IconButton(tooltip: tr('快捷键'), icon: const Icon(Icons.keyboard_outlined), onPressed: () => showShortcutHelp(context, controller.preferences)),
        ],
      ),
      if (decoded)
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 4),
          child: Text(tr('解码：{0} · {1}', [controller.currentCodec, controller.currentHwdec]), style: TextStyle(fontSize: 12, color: context.colors.outline)),
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
          child: TextButton.icon(onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded), label: Text(tr('返回'))),
        ),
      );
}

class _Player extends StatelessWidget {
  const _Player({required this.controller, required this.videoKey});
  final AppController controller;
  final GlobalKey<VideoState> videoKey;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: AppStyle.cardRadius,
          child: ColoredBox(
            color: Colors.black,
            // As in PiliNara: the video and its controls repaint apart, so
            // pointer movement over the controls does not redraw the video
            // texture, which flashes black on some Windows GPUs.
            child: RepaintBoundary(
              child: Video(
                key: videoKey,
                controller: controller.videoController!,
                controls: (state) => RepaintBoundary(
                  child: PlayerControls(player: state.widget.controller.player, state: state, controller: controller),
                ),
                subtitleViewConfiguration: subtitleViewFor(controller.settings),
              ),
            ),
          ),
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
    final views = details?.viewCount ?? item.viewCount;
    final meta = [
      if (views != null) tr('{0}次观看', [formatCount(views)]),
      if (details?.uploadDate != null) formatDate(details!.uploadDate!),
      if (details?.likeCount != null) tr('{0} 赞', [formatCount(details!.likeCount!)]),
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
          TextButton(onPressed: () => controller.openChannel(channelRef), child: Text(tr('查看频道'))),
          const Spacer(),
          FollowButton(controller: controller, channel: channelRef),
        ] else if (details?.channelUrl != null)
          TextButton(onPressed: () => openExternal(details!.channelUrl!), child: Text(tr('查看频道'))),
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
        _Description(meta: meta, description: details?.description ?? '', expanded: controller.preferences.expandDescription, controller: controller),
    ]);
  }
}

/// Collapsible description card, three lines until expanded.
class _Description extends StatefulWidget {
  const _Description({required this.meta, required this.description, this.expanded = false, required this.controller});
  final AppController controller;
  final String meta;
  final String description;
  /// Whether it starts expanded.
  final bool expanded;

  @override
  State<_Description> createState() => _DescriptionState();
}

class _DescriptionState extends State<_Description> {
  late bool _expanded = widget.expanded;

  void _seek(Duration time) => unawaited(widget.controller.player?.seek(time));

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
                // Times seek the video and links open in the browser, as in
                // PiliNara; the expanded text can still be selected.
                child: _expanded
                    ? SelectionArea(child: LinkedText(widget.description, style: const TextStyle(height: 1.5), onTime: _seek, onLink: openExternal))
                    : LinkedText(widget.description, maxLines: 3, style: const TextStyle(height: 1.5), onTime: _seek, onLink: openExternal),
              ),
              if (hasMore) ...[
                const SizedBox(height: 4),
                Text(_expanded ? tr('收起') : tr('展开'), style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600)),
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
    final relatedItems = controller.relatedItems;
    final children = <Widget>[
      _header(context, tr('接下来播放'), items.isEmpty ? null : tr('{0} 个', [items.length])),
      if (items.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
          child: Text(
            relatedItems.isEmpty ? tr('播放队列已经到底了。播放搜索结果、播放列表或观看历史中的视频时，后面的视频会显示在这里。') : tr('播放队列已经到底了，自动连播会接着播放下面的相关视频。'),
            style: TextStyle(color: context.colors.onSurfaceVariant, height: 1.5),
          ),
        )
      else
        for (final item in shrinkWrap ? items.take(20) : items) _tile(item, null),
      if (related != null) ...[
        const SizedBox(height: 16),
        _header(context, tr('相关视频'), tr('按标题搜索')),
        for (final item in relatedItems) _tile(item, relatedItems),
        if (related.loading && relatedItems.isEmpty)
          const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator())
        else if (related.error != null)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: ErrorBanner(tr('无法加载相关视频'), onRetry: () => related.loadMore(retry: true))),
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

/// Flutter's subtitle view styled from 字幕设置, or hidden when libmpv draws
/// the subtitles (see AppController's player setup).
SubtitleViewConfiguration subtitleViewFor(PlayerSettings settings) {
  if (settings.libassSubtitles) return const SubtitleViewConfiguration(visible: false);
  final border = settings.subtitleBorder;
  return SubtitleViewConfiguration(
    style: TextStyle(
      height: 1.4,
      fontSize: 32 * settings.subtitleScale,
      letterSpacing: 0.0,
      wordSpacing: 0.0,
      color: Colors.white,
      fontWeight: settings.subtitleBold ? FontWeight.w700 : FontWeight.normal,
      backgroundColor: settings.subtitleBackground ? const Color(0xAA000000) : null,
      shadows: settings.subtitleBackground || border == 0
          ? null
          : [for (final (dx, dy) in const [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)]) Shadow(color: Colors.black, offset: Offset(dx * border / 2, dy * border / 2), blurRadius: border / 2)],
    ),
    // sub-pos counts from the top; 100 is the bottom edge.
    padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + (100 - settings.subtitlePosition) * 4.0),
  );
}
