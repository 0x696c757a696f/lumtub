import 'dart:async';

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app/app_controller.dart';
import '../../appearance_settings.dart' show bundledFont;
import '../../models.dart';
import '../../live_chat.dart';
import '../../player_settings.dart';
import '../../youtube_account.dart' show VideoRating;
import '../comments_view.dart';
import '../cast_ui.dart';
import '../common.dart';
import '../lights_off.dart';
import '../linked_text.dart';
import '../player_controls.dart';
import '../player_shortcuts.dart';
import '../screenshot_action.dart';
import '../summary_dialog.dart';
import '../theater_mode.dart';
import '../skeleton.dart';
import '../theme.dart';
import '../translatable.dart';
import '../play_queue_panel.dart';
import '../video_card.dart';
import '../upcoming_card.dart';
import 'channel_page.dart';
import 'downloads_page.dart';
import '../../dearrow.dart';
import '../video_box.dart';
import '../../l10n/l10n.dart';
import '../motion.dart';

/// Player, video details, the up-next list and the comments. On wide
/// windows the list and the comments share a side panel, as PiliNara's
/// 简介/评论 tabs; on narrow ones everything is stacked.
class WatchPage extends StatefulWidget {
  const WatchPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<WatchPage> createState() => _WatchPageState();
}

class _WatchPageState extends State<WatchPage> {
  static const _sidePanelWidth = 400.0;
  final _video = GlobalKey<VideoState>();
  String? _fullscreenFor;
  StreamSubscription<bool>? _playing;

  @override
  void initState() {
    super.initState();
    final player = widget.controller.player;
    _playing = player?.stream.playing.listen(_autoLights);
    // The shell above is building now, so its 关灯 layer changes after.
    if (player != null) WidgetsBinding.instance.addPostFrameCallback((_) => _autoLights(player.state.playing));
  }

  @override
  void dispose() {
    unawaited(_playing?.cancel());
    super.dispose();
  }

  /// 播放时自动关灯: dark while the video plays, lit while it is paused.
  void _autoLights(bool playing) {
    if (mounted && widget.controller.preferences.autoLightsOff) lightsOff.value = playing;
  }

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

  Object? _darkKey;
  ThemeData? _dark;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final appearance = controller.appearance;
    final page = _page(context, controller);
    if (!appearance.darkWatchPage || Theme.of(context).brightness == Brightness.dark) return page;
    // ColorScheme.fromSeed is costly and the page rebuilds on every notify.
    final key = appearance.themeKey(controller.accentColor);
    if (key != _darkKey) {
      _darkKey = key;
      _dark = buildAppTheme(controller.accentColor, Brightness.dark, variant: appearance.schemeVariant, pureBlack: appearance.pureBlack, fontFamily: appearance.fontFamily);
    }
    final dark = _dark!;
    return Theme(data: dark, child: Material(color: dark.colorScheme.surface, child: page));
  }

  Widget _page(BuildContext context, AppController controller) {
    _autoFullscreen(controller);
    final shortcuts = playerShortcuts(controller, () => _video.currentState, onScreenshot: () => unawaited(captureScreenshot(context, controller)));
    // The same bindings work anywhere on the page and inside the fullscreen
    // route, where media_kit's controls hold focus.
    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        autofocus: true,
        child: ValueListenableBuilder(valueListenable: theaterMode, builder: (context, theater, _) => LayoutBuilder(builder: (context, constraints) {
          // 剧场模式 gives the video the whole width and stacks the panels below.
          final wide = !theater && constraints.maxWidth >= 1080;
          final mainWidth = wide ? constraints.maxWidth - _sidePanelWidth - AppStyle.pagePadding * 3 : constraints.maxWidth - AppStyle.pagePadding * 2;
          // Keep the whole player visible: never taller than the window allows.
          final playerWidth = theater ? min(constraints.maxWidth, max(320.0, (constraints.maxHeight - 8) * 16 / 9)) : min(mainWidth, max(320.0, (constraints.maxHeight - 120) * 16 / 9));
          final item = controller.playing;
          // In the side panel the comments scroll by themselves and build
          // only what is on screen.
          // 专注模式 can leave the comments out; then they are not loaded.
          final comments = item == null || controller.preferences.focusHideComments
              ? null
              : CommentsSection(
                  key: ValueKey('comments:${item.id}'),
                  controller: controller,
                  videoId: item.id,
                  onSeek: (position) => controller.player?.seek(position),
                  scrollable: wide,
                  sliver: !wide,
                  padding: wide ? const EdgeInsets.fromLTRB(4, 0, 4, AppStyle.pagePadding) : EdgeInsets.zero,
                );
          final replayChat = item?.isLive == true || item?.liveStatus == 'was_live' ? _ReplayChatPanel(controller: controller, shrinkWrap: !wide) : null;
          final main = <Widget>[
            if (!theater) _BackRow(onBack: controller.goBack),
            Center(child: SizedBox(width: playerWidth, child: _Player(controller: controller, videoKey: _video))),
            CastBar(controller: controller),
            if (!theater) const SizedBox(height: 12),
            _Toolbar(controller: controller),
            if (controller.playbackError != null && !controller.waitingForStart) ...[
              const SizedBox(height: 12),
              ErrorBanner(tr('播放失败：{0}', [controller.playbackError]), onRetry: controller.retryPlayback),
            ],
            const SizedBox(height: 16),
            _Details(controller: controller),
          ];
          if (!wide) {
            // One scroll view of slivers, so the comments below the details
            // are built as they scroll into view, not all at once.
            const margin = AppStyle.pagePadding;
            final rest = [
              if (replayChat != null) ...[const SizedBox(height: 24), replayChat],
              const SizedBox(height: 24),
              _UpNext(controller: controller, shrinkWrap: true),
            ];
            return CustomScrollView(slivers: [
              // In 剧场模式 the player goes edge to edge.
              if (theater) SliverToBoxAdapter(child: Center(child: SizedBox(width: playerWidth, child: _Player(controller: controller, videoKey: _video)))),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(margin, theater ? 12 : 0, margin, 0),
                sliver: SliverList.list(children: theater ? main.skip(1).toList() : main),
              ),
              if (comments != null) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
                SliverPadding(padding: const EdgeInsets.symmetric(horizontal: margin), sliver: comments),
              ],
              SliverPadding(padding: const EdgeInsets.fromLTRB(margin, 0, margin, margin), sliver: SliverList.list(children: rest)),
            ]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, AppStyle.pagePadding), children: main)),
            SizedBox(width: _sidePanelWidth, child: Padding(
              padding: const EdgeInsets.only(right: AppStyle.pagePadding, top: 8),
              child: _SidePanel(controller: controller, comments: comments, replayChat: replayChat),
            )),
          ]);
        })),
      ),
    );
  }
}

/// 赞 and 踩 with their counts, as on YouTube. The counts show signed in or
/// not; rating needs the Google account. 踩's count is Return YouTube
/// Dislike's estimate, when that is turned on.
class _RatingButtons extends StatelessWidget {
  const _RatingButtons({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final item = controller.playing!;
    final account = controller.account;
    final signedIn = account?.signedIn ?? false;
    final colors = context.colors;
    final likes = controller.details?.likeCount ?? controller.dislikes?.likes;
    final dislikes = controller.dislikes?.dislikes;
    Widget button(VideoRating rating, IconData icon, IconData selectedIcon, String label, int? count, {String? note}) {
      final selected = signedIn && account!.ratingOf(item.id) == rating;
      return Tooltip(
        message: [
          if (!signedIn) tr('登录 Google 账号后可以{0}', [label]) else if (selected) tr('取消{0}', [label]) else label,
          if (note != null) note,
        ].join('\n'),
        child: TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: selected ? colors.primary : colors.onSurface,
            backgroundColor: colors.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
          onPressed: signedIn
              ? () => account!.rate(item, rating)
              : () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('登录 Google 账号后可以{0}', [label])))),
          icon: Icon(selected ? selectedIcon : icon, size: 20),
          label: Text(count == null ? label : formatCount(count)),
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      button(VideoRating.like, Icons.thumb_up_outlined, Icons.thumb_up_rounded, tr('赞'), likes),
      const SizedBox(width: 4),
      button(VideoRating.dislike, Icons.thumb_down_outlined, Icons.thumb_down_rounded, tr('踩'), dislikes,
          note: dislikes == null ? null : tr('踩数是 Return YouTube Dislike 的估算')),
    ]);
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
    final later = library?.isWatchLater(item.id) ?? false;
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
          _RatingButtons(controller: controller),
          if (library != null) ...[
            IconButton(
              tooltip: favorite ? tr('取消收藏') : tr('收藏'),
              isSelected: favorite,
              icon: const Icon(Icons.favorite_border_rounded),
              selectedIcon: Icon(Icons.favorite_rounded, color: context.colors.primary),
              onPressed: () => library.toggleFavorite(item),
            ),
            IconButton(
              tooltip: later ? tr('从稍后观看移除') : tr('稍后观看'),
              icon: Icon(later ? Icons.watch_later_rounded : Icons.watch_later_outlined, color: later ? context.colors.primary : null),
              onPressed: () => library.toggleWatchLater(item),
            ),
            IconButton(tooltip: tr('添加到播放列表'), icon: const Icon(Icons.playlist_add_rounded), onPressed: () => showAddToPlaylist(context, controller, item)),
            if (controller.account?.signedIn ?? false)
              IconButton(tooltip: tr('保存到 YouTube 播放列表'), icon: const Icon(Icons.video_library_outlined), onPressed: () => showSaveToYoutube(context, controller, item)),
          ],
          if (controller.downloads != null && !item.isLive)
            IconButton(tooltip: tr('下载'), icon: const Icon(Icons.download_rounded), onPressed: () => showDownloadChoice(context, controller, item)),
          if (!item.isLive)
            IconButton(tooltip: tr('AI 总结'), icon: const Icon(Icons.auto_awesome_outlined), onPressed: () => showVideoSummary(context, controller)),
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
        key: lightsOffHole,
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: AppStyle.cardRadius,
          child: ColoredBox(
            color: Colors.black,
            // As in PiliNara: the video and its controls repaint apart, so
            // pointer movement over the controls does not redraw the video
            // texture, which flashes black on some Windows GPUs.
            child: Stack(fit: StackFit.expand, children: [
              RepaintBoundary(
                child: Video(
                  key: videoKey,
                  controller: controller.videoController!,
                  // The controls cover the video here and in full screen, so
                  // they measure the size it is drawn at.
                  controls: (state) => VideoBox(
                    controller: controller,
                    child: RepaintBoundary(
                      child: PlayerControls(player: state.widget.controller.player, state: state, controller: controller),
                    ),
                  ),
                  subtitleViewConfiguration: subtitleViewFor(controller.settings),
                ),
              ),
              if (controller.waitingForStart && controller.playing != null)
                UpcomingCard(
                  thumbnail: thumbnailFor(controller.playing!, controller.thumbnailDirectory, width: 320, size: 'mqdefault'),
                  start: controller.scheduledStart,
                  onRetry: controller.retryPlayback,
                ),
            ]),
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
      if (item.isUpcoming && item.scheduledStart != null) tr('开始于 {0}', [formatScheduledStart(item.scheduledStart!)]),
      if (views != null) tr('{0}次观看', [formatCount(views)]),
      if (details?.uploadDate != null) formatDate(details!.uploadDate!),
    ].join(' · ');
    final channel = details?.channel.isNotEmpty == true ? details!.channel : item.channel;
    final channelRef = controller.playingChannel;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Translatable(
        controller: controller,
        text: deArrow.titleOf(item.id, details?.title.isNotEmpty == true ? details!.title : item.title),
        builder: (context, title) => SelectableText(title, style: context.text.titleLarge?.copyWith(fontWeight: FontWeight.w600, height: 1.3)),
      ),
      const SizedBox(height: 12),
      Row(children: [
        ChannelAvatar(name: channel.isEmpty ? 'YouTube' : channel),
        const SizedBox(width: 12),
        // The name and its link take the free space, so the follow button
        // and menu sit at the right edge.
        Expanded(child: Row(children: [
          Flexible(child: Text(channel.isEmpty ? 'YouTube' : channel, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall)),
          const SizedBox(width: 8),
          if (channelRef != null)
            TextButton(onPressed: () => controller.openChannel(channelRef), child: Text(tr('查看频道')))
          else if (details?.channelUrl != null)
            TextButton(onPressed: () => openExternal(details!.channelUrl!), child: Text(tr('查看频道'))),
        ])),
        if (channelRef != null) ...[
          FollowButton(controller: controller, channel: channelRef),
          ChannelMenuButton(controller: controller, channel: channelRef),
        ],
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
        // As wide as the title and channel row, not as wide as its text.
        SizedBox(
          width: double.infinity,
          child: _Description(meta: meta, description: details?.description ?? '', expanded: controller.preferences.expandDescription, controller: controller),
        ),
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
              Translatable(
                controller: widget.controller,
                text: widget.description,
                builder: (context, description) => AnimatedSize(
                  duration: Motion.of(const Duration(milliseconds: 180)),
                  alignment: Alignment.topCenter,
                  // Times seek the video and links open in the browser, as in
                  // PiliNara; the expanded text can still be selected.
                  child: _expanded
                      ? SelectionArea(child: LinkedText(description, style: const TextStyle(height: 1.5), onTime: _seek, onLink: openExternal))
                      : LinkedText(description, maxLines: 3, style: const TextStyle(height: 1.5), onTime: _seek, onLink: openExternal),
                ),
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

/// 接下来播放 and 评论 as tabs beside the player. The comments load when
/// their tab is first opened and stay loaded while the video plays.
class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.controller, required this.comments, this.replayChat});
  final AppController controller;
  final Widget? comments;
  final Widget? replayChat;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      (tr('接下来播放'), _UpNext(controller: controller)),
      if (comments case final comments?) (tr('评论'), _KeepAlive(child: comments)),
      if (replayChat case final chat?) (tr('聊天'), _KeepAlive(child: chat)),
    ];
    return DefaultTabController(
      key: ValueKey(tabs.length),
      length: tabs.length,
      child: Column(children: [
        TabBar(dividerColor: Colors.transparent, tabs: [for (final (label, _) in tabs) Tab(height: 40, text: label)]),
        const SizedBox(height: 8),
        Expanded(child: TabBarView(children: [for (final (_, view) in tabs) view])),
      ]),
    );
  }
}

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _ReplayChatPanel extends StatelessWidget {
  const _ReplayChatPanel({required this.controller, this.shrinkWrap = false});
  final AppController controller;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: controller.chatMessages, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final messages = controller.replayChat;
    final live = controller.playing?.isLive ?? false;
    final header = <Widget>[
      Text(tr(live ? '聊天' : '聊天回放'), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      if (controller.loadingReplayChat) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
      if (controller.replayChatError != null) ErrorBanner(tr(live ? '无法加载聊天：{0}' : '无法加载聊天回放：{0}', [controller.replayChatError]), onRetry: controller.retryChat),
      if (!controller.loadingReplayChat && controller.replayChatError == null && messages.isEmpty)
        Padding(padding: const EdgeInsets.all(12), child: Text(tr(live ? '当前直播没有公开聊天' : '这个直播录像没有公开的聊天回放'), style: TextStyle(color: context.colors.onSurfaceVariant))),
    ];
    if (messages.isEmpty) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: header);
    Widget messageAt(int index) {
      final message = messages[index];
      return _ReplayChatMessage(message: message, onSeek: message.offset == null ? null : () => controller.player?.seek(message.offset!));
    }
    if (shrinkWrap) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ...header,
        SizedBox(height: 320, child: ListView.builder(itemCount: messages.length, itemBuilder: (context, index) => messageAt(index))),
      ]);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, AppStyle.pagePadding),
      itemCount: messages.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: header);
        return messageAt(index - 1);
      },
    );
  }
}

class _ReplayChatMessage extends StatelessWidget {
  const _ReplayChatMessage({required this.message, this.onSeek});
  final LiveChatMessage message;
  final VoidCallback? onSeek;

  @override
  Widget build(BuildContext context) {
    final icon = switch (message.kind) {
      LiveChatKind.paidMessage => Icons.volunteer_activism_rounded,
      LiveChatKind.paidSticker => Icons.emoji_emotions_outlined,
      LiveChatKind.membership => Icons.workspace_premium_outlined,
      LiveChatKind.system => Icons.info_outline_rounded,
      LiveChatKind.message => Icons.chat_bubble_outline_rounded,
    };
    final time = message.offset == null ? '' : _chatClock(message.offset!);
    return InkWell(
      onTap: onSeek,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: context.colors.outline),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(message.author.isEmpty ? tr('系统消息') : message.author, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (message.amount != null) Text(message.amount!, style: TextStyle(color: context.colors.primary, fontWeight: FontWeight.w700)),
              if (time.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 8), child: Text(time, style: TextStyle(color: context.colors.outline, fontSize: 12))),
            ]),
            if (message.text.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(message.text)),
            if (message.stickerUrl != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Image.network(
                  message.stickerUrl!,
                  height: 56,
                  cacheHeight: (56 * MediaQuery.of(context).devicePixelRatio).round(),
                  errorBuilder: (context, error, stack) => const SizedBox.shrink(),
                ),
              ),
          ])),
        ]),
      ),
    );
  }
}

String _chatClock(Duration value) {
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return value.inHours > 0 ? '${value.inHours}:${value.inMinutes.remainder(60).toString().padLeft(2, '0')}:$seconds' : '${value.inMinutes}:$seconds';
}

class _UpNext extends StatelessWidget {
  const _UpNext({required this.controller, this.shrinkWrap = false});
  final AppController controller;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final items = controller.upNext;
    final related = controller.related;
    // What 接下来播放 already lists is not repeated under 相关视频.
    final queued = {for (final item in items) item.id};
    final relatedItems = [for (final item in controller.relatedItems) if (!queued.contains(item.id)) item];
    final children = <Widget>[
      if (controller.playQueue.isNotEmpty) ...[PlayQueuePanel(controller: controller), const SizedBox(height: 16)],
      _header(context, tr('接下来播放'), items.isEmpty ? null : tr('{0} 个', [items.length]), trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(tr('自动连播'), style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12)),
        Transform.scale(
          scale: 0.75,
          child: Switch(value: controller.settings.playOrder == PlayOrder.autoPlayRelated, onChanged: (on) => unawaited(controller.setAutoplayNext(on))),
        ),
      ])),
      if (items.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
          child: Text(
            relatedItems.isEmpty ? tr('播放队列已经到底了。播放搜索结果、播放列表或观看历史中的视频时，后面的视频会显示在这里。') : controller.settings.autoplayNext ? tr('播放队列已经到底了，自动连播会接着播放下面的相关视频。') : tr('播放队列已经到底了。打开自动连播后，会接着播放下面的相关视频。'),
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

  Widget _header(BuildContext context, String title, String? note, {Widget? trailing}) => Padding(
        padding: EdgeInsets.fromLTRB(6, 0, trailing == null ? 6 : 0, 8),
        child: Row(children: [
          Text(title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          if (note != null) ...[const SizedBox(width: 8), Text(note, style: TextStyle(color: context.colors.outline, fontSize: 12))],
          const Spacer(),
          if (trailing != null) trailing,
        ]),
      );

  Widget _tile(VideoItem item, List<VideoItem>? list) =>
      CompactVideoTile(item: item, thumbnails: controller.thumbnailDirectory, onOpen: () => controller.play(item, from: list));
}

/// Flutter's subtitle view styled from 字幕设置, or hidden when libmpv draws
/// the subtitles (see AppController's player setup). The text follows the
/// size of the video; a small window, such as picture in picture, passes
/// [smallWindow] with its size, which keeps the text readable and shrinks
/// the gap below it.
SubtitleViewConfiguration subtitleViewFor(PlayerSettings settings, {Size? smallWindow}) {
  // The view scales by area against 1080p, which makes the text tiny in a
  // small window; there it goes by the short side, and no smaller than
  // three fifths.
  final textScaler = smallWindow == null ? null : TextScaler.linear((smallWindow.shortestSide / 720).clamp(0.6, 1.0));
  final paddingScale = smallWindow == null ? 1.0 : (smallWindow.shortestSide / 720).clamp(0.3, 1.0);
  if (settings.libassSubtitles) return const SubtitleViewConfiguration(visible: false);
  final border = settings.subtitleBorder;
  TextStyle style(String font, double scale, int color, double opacity) => TextStyle(
        height: 1.4,
        fontSize: 32 * scale,
        fontFamily: font.isEmpty ? null : font,
        // Where the font is missing (another system), the bundled one.
        fontFamilyFallback: const [bundledFont],
        letterSpacing: 0.0,
        wordSpacing: 0.0,
        color: Color(0xFF000000 | color).withValues(alpha: opacity),
        fontWeight: settings.subtitleBold ? FontWeight.w700 : FontWeight.normal,
        backgroundColor: settings.subtitleBackground ? Color.fromRGBO(0, 0, 0, 0.67 * opacity) : null,
        shadows: settings.subtitleBackground || border == 0
            ? null
            : [
                for (final (dx, dy) in const [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)])
                  Shadow(color: Colors.black.withValues(alpha: opacity), offset: Offset(dx * border / 2, dy * border / 2), blurRadius: border / 2),
              ],
      );
  return SubtitleViewConfiguration(
    style: style(settings.subtitleFont, settings.subtitleScale, settings.subtitleColor, settings.subtitleOpacity),
    secondaryStyle: style(settings.secondaryFont, settings.secondaryScale, settings.secondaryColor, settings.secondaryOpacity),
    // sub-pos counts from the top; 100 is the bottom edge.
    textScaler: textScaler,
    padding: EdgeInsets.fromLTRB(16 * paddingScale, 0, 16 * paddingScale, (24 + (100 - settings.subtitlePosition) * 4.0) * paddingScale),
  );
}
