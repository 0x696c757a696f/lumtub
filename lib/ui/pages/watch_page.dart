import 'dart:async';
import 'dart:io' show Platform;

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;
import 'package:media_kit_video/media_kit_video.dart';

import '../window_chrome.dart';
import '../../app/app_controller.dart';
import '../../appearance_settings.dart' show bundledFont;
import '../../models.dart';
import '../../player_settings.dart';
import '../../timestamp_link.dart';
import '../../youtube_account.dart' show VideoRating;
import '../comments_view.dart';
import '../cast_ui.dart';
import '../common.dart';
import '../lights_off.dart';
import '../live_chat_rows.dart';
import '../linked_text.dart';
import '../player_controls.dart';
import '../player_shortcuts.dart';
import '../screenshot_action.dart';
import '../summary_dialog.dart';
import '../subtitle_list_panel.dart';
import '../theater_mode.dart';
import '../skeleton.dart';
import '../theme.dart';
import '../skin_deck.dart';
import '../skin_lcd.dart';
import '../skin_paint.dart';
import '../warm_layer.dart';
import '../translatable.dart';
import '../play_queue_panel.dart';
import '../playing_list_panel.dart';
import '../video_card.dart';
import '../upcoming_card.dart';
import 'channel_page.dart';
import 'downloads_page.dart';
import '../../dearrow.dart';
import '../video_box.dart';
import '../../l10n/l10n.dart';
import '../motion.dart';
import '../app_icons.dart';
import '../palettes.dart';
import '../live_chat_input.dart';
import '../live_chat_list.dart';

/// Player, video details, the up-next list and the comments. On wide
/// windows the list and the comments share a side panel, as PiliNara's
/// 简介/评论 tabs; on narrow ones everything is stacked.
class WatchPage extends StatefulWidget {
  const WatchPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<WatchPage> createState() => _WatchPageState();
}

class _WatchPageState extends State<WatchPage> with WidgetsBindingObserver {
  static const _sidePanelWidth = 400.0;
  final _video = GlobalKey<VideoState>();
  String? _fullscreenFor;
  StreamSubscription<bool>? _playing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final player = widget.controller.player;
    _playing = player?.stream.playing.listen(_autoLights);
    // The shell above is building now, so its 关灯 layer changes after.
    if (player != null) WidgetsBinding.instance.addPostFrameCallback((_) => _autoLights(player.state.playing));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_playing?.cancel());
    subtitleListBeside = false;
    super.dispose();
  }

  /// 播放时自动关灯: dark while the video plays, lit while it is paused.
  void _autoLights(bool playing) {
    if (mounted && widget.controller.preferences.autoLightsOff) lightsOff.value = playing;
  }

  /// Whether full screen came from turning the phone sideways, so turning
  /// it back leaves it, as phone video apps do. Full screen from the button
  /// holds the screen sideways instead.
  bool _byRotation = false;
  /// Left full screen while sideways: it is not entered again until the
  /// phone has been upright once.
  bool _waitUpright = false;

  @override
  void didChangeMetrics() {
    final view = View.maybeOf(context);
    final state = _video.currentState;
    if (!touchFirst || view == null || state == null || !state.mounted) return;
    final size = view.physicalSize / view.devicePixelRatio;
    if (size.shortestSide >= 600 || size.isEmpty) return;
    final sideways = size.width > size.height;
    if (!sideways) _waitUpright = false;
    if (sideways && !_waitUpright && !state.isFullscreen() && widget.controller.playing != null) {
      _byRotation = true;
      unawaited(state.enterFullscreen());
    } else if (!sideways && _byRotation && state.isFullscreen()) {
      unawaited(state.exitFullscreen());
    }
  }

  void _leftFullscreen() {
    _byRotation = false;
    final view = View.maybeOf(context);
    _waitUpright = view != null && view.physicalSize.width > view.physicalSize.height;
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
    final warmth = context.tones.warmth;
    final key = (appearance.themeKey(controller.accentColor), warmth);
    if (key != _darkKey) {
      _darkKey = key;
      _dark = buildAppTheme(controller.accentColor, Brightness.dark, variant: appearance.schemeVariant, pureBlack: appearance.pureBlack, fontFamily: appearance.font, palette: paletteOf(appearance.palette), warmth: warmth);
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
        child: ListenableBuilder(listenable: Listenable.merge([theaterMode, theaterChatOpen]), builder: (context, _) => LayoutBuilder(builder: (context, outer) {
          // A phone lays the page out as 剧场模式 does: the player edge to
          // edge at the top, nothing above it.
          final theater = theaterMode.value || isPhone(context);
          final item = controller.playing;
          final hasChat = item?.isLive == true || item?.liveStatus == 'was_live';
          // 剧场模式 in a wide window keeps comments, up next and the chat
          // in a column beside the video, which can be folded away.
          final sidePanel = theater && outer.maxWidth >= 900;
          subtitleListBeside = sidePanel || (!theater && outer.maxWidth >= 1080);
          final panelOpen = sidePanel && theaterChatOpen.value;
          final constraints = panelOpen ? outer.copyWith(maxWidth: outer.maxWidth - _theaterChatWidth) : outer;
          // 剧场模式 gives the video the whole width and stacks the panels below.
          final wide = !theater && constraints.maxWidth >= 1080;
          final mainWidth = wide ? constraints.maxWidth - _sidePanelWidth - AppStyle.pagePadding * 3 : constraints.maxWidth - AppStyle.pagePadding * 2;
          // Keep the whole player visible: never taller than the window allows.
          final playerWidth = theater ? min(constraints.maxWidth, max(320.0, (constraints.maxHeight - 8) * 16 / 9)) : min(mainWidth, max(320.0, (constraints.maxHeight - 120) * 16 / 9));
          // In the side panel the comments scroll by themselves and build
          // only what is on screen.
          // 专注模式 can leave the comments out; then they are not loaded.
          final comments = item == null || controller.preferences.focusHideComments
              ? null
              : CommentsSection(
                  key: ValueKey('comments:${item.id}'),
                  controller: controller,
                  videoId: item.id,
                  onSeek: (position) => controller.seek(position),
                  scrollable: wide || panelOpen,
                  sliver: !wide && !panelOpen,
                  padding: wide ? const EdgeInsets.fromLTRB(4, 0, 4, AppStyle.pagePadding) : EdgeInsets.zero,
                );
          final replayChat = hasChat ? _ReplayChatPanel(controller: controller, shrinkWrap: !wide && !panelOpen) : null;
          final main = <Widget>[
            if (!theater) _BackRow(onBack: controller.goBack),
            Center(child: SizedBox(width: playerWidth, child: _Player(controller: controller, videoKey: _video, byRotation: () => _byRotation, onExit: _leftFullscreen))),
            CastBar(controller: controller),
            if (!theater) const SizedBox(height: 12),
            _Toolbar(controller: controller),
            if (controller.playbackError != null && !controller.waitingForStart) ...[
              const SizedBox(height: 12),
              ErrorBanner(tr('Playback failed: {0}', [controller.playbackError]), onRetry: controller.retryPlayback),
            ],
            const SizedBox(height: 16),
            _Details(controller: controller),
          ];
          if (!wide) {
            // One scroll view of slivers, so the comments below the details
            // are built as they scroll into view, not all at once.
            const margin = AppStyle.pagePadding;
            final rest = [
              if (!panelOpen) ...[
                if (replayChat != null) ...[const SizedBox(height: 24), replayChat],
                const SizedBox(height: 24),
              ],
            ];
            final page = CustomScrollView(slivers: [
              // In 剧场模式 the player goes edge to edge.
              if (theater) SliverToBoxAdapter(child: Center(child: SizedBox(width: playerWidth, child: _Player(controller: controller, videoKey: _video, byRotation: () => _byRotation, onExit: _leftFullscreen)))),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(margin, theater ? 12 : 0, margin, 0),
                sliver: SliverList.list(children: theater ? main.skip(1).toList() : main),
              ),
              if (comments != null && !panelOpen) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
                SliverPadding(padding: const EdgeInsets.symmetric(horizontal: margin), sliver: comments),
              ],
              SliverPadding(padding: const EdgeInsets.fromLTRB(margin, 0, margin, margin), sliver: SliverMainAxisGroup(slivers: [
                SliverList.list(children: rest),
                if (!panelOpen) ..._UpNext(controller: controller, shrinkWrap: true).slivers(context),
              ])),
            ]);
            if (!sidePanel) return page;
            return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: page),
              if (panelOpen)
                SizedBox(
                  width: _theaterChatWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(border: Border(left: BorderSide(color: context.colors.outlineVariant))),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      // The fold button sits in the tab row, so the panel
                      // starts as high as the video.
                      child: _SidePanel(
                        controller: controller,
                        comments: comments,
                        replayChat: replayChat,
                        chatFirst: true,
                        trailing: IconButton(tooltip: tr('Collapse'), icon: Icon(AppIcons.caretRight, size: 18), onPressed: () => theaterChatOpen.value = false),
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: 4, end: 4),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: IconButton(tooltip: tr('Expand'), icon: Icon(AppIcons.sidebar, size: 20), onPressed: () => theaterChatOpen.value = true),
                  ),
                ),
            ]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, AppStyle.pagePadding), children: main)),
            SizedBox(width: _sidePanelWidth, child: Padding(
              padding: const EdgeInsetsDirectional.only(end: AppStyle.pagePadding, top: 8),
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
      final off = signedIn && account!.ratingOff(item.id);
      final shown = count == null || !signedIn ? count : (count + account!.ratingChange(item.id, rating)).clamp(0, 1 << 62);
      return Tooltip(
        message: [
          if (!signedIn) tr('Sign in to Google to {0}', [label]) else if (off) tr('The uploader turned off likes and dislikes for this video') else if (selected) tr('Cancel {0}', [label]) else label,
          if (note != null) note,
        ].join('\n'),
        child: TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: selected ? colors.primary : colors.onSurface,
            backgroundColor: colors.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          onPressed: off
              ? null
              : signedIn
              ? () => account!.rate(item, rating)
              : () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Sign in to Google to {0}', [label])))),
          icon: Icon(selected ? selectedIcon : icon, size: 20),
          label: Text(shown == null ? label : formatCount(shown)),
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      button(VideoRating.like, AppIcons.thumbsUp, AppIcons.thumbsUpFill, tr('Like'), likes),
      const SizedBox(width: 4),
      button(VideoRating.dislike, AppIcons.thumbsDown, AppIcons.thumbsDownFill, tr('Dislike'), dislikes,
          note: dislikes == null ? null : tr("The dislike count is Return YouTube Dislike's estimate")),
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
    final decoded = controller.currentCodec != tr('No video played yet');
    final library = controller.library;
    final favorite = library?.isFavorite(item.id) ?? false;
    final later = library?.isWatchLater(item.id) ?? false;
    final phone = isPhone(context);
    // A phone's buttons go in one row that scrolls sideways, each with its
    // name, as phone video apps lay them out.
    Widget layout(List<Widget> children) => phone
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [for (final (i, c) in children.indexed) Padding(padding: EdgeInsetsDirectional.only(start: i == 0 ? 0 : 8), child: c)]),
          )
        : Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: children);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      layout(
        [
          PopupMenuButton<PlayOrder>(
            tooltip: tr('Playback order'),
            initialValue: settings.playOrder,
            onSelected: controller.setPlayOrder,
            itemBuilder: (context) => [
              for (final order in PlayOrder.values) CheckedPopupMenuItem(value: order, checked: order == settings.playOrder, child: Text(order.label)),
            ],
            child: Chip(avatar: Icon(AppIcons.repeat, size: 18), label: Text(settings.playOrder.label)),
          ),
          _RatingButtons(controller: controller),
          if (library != null) ...[
            _ActionButton(
              tooltip: favorite ? tr('Remove from favorites') : tr('Favorites'),
              label: tr('Favorites'),
              icon: Icon(favorite ? AppIcons.heartFill : AppIcons.heart, color: favorite ? context.colors.primary : null),
              onPressed: () => library.toggleFavorite(item),
            ),
            _ActionButton(
              tooltip: later ? tr('Remove from Watch later') : tr('Watch later'),
              label: tr('Watch later'),
              icon: Icon(later ? AppIcons.clockFill : AppIcons.clock, color: later ? context.colors.primary : null),
              onPressed: () => library.toggleWatchLater(item),
            ),
            _ActionButton(tooltip: tr('Add to playlist'), icon: Icon(AppIcons.listPlus), onPressed: () => showAddToPlaylist(context, controller, item)),
            if (controller.account?.signedIn ?? false)
              _ActionButton(tooltip: tr('Save to YouTube playlist'), label: tr('Save'), icon: Icon(AppIcons.filmReel), onPressed: () => showSaveToYoutube(context, controller, item)),
          ],
          if (controller.downloads != null && !item.isLive)
            _ActionButton(tooltip: tr('Downloads'), icon: Icon(AppIcons.downloadSimple), onPressed: () => showDownloadChoice(context, controller, item)),
          if (item.isLive && (controller.downloads?.canRecord ?? false))
            _ActionButton(tooltip: tr('Record the live stream'), icon: Icon(AppIcons.radioButton), onPressed: () => showDownloadChoice(context, controller, item)),
          if (!item.isLive)
            _ActionButton(tooltip: tr('AI summary'), icon: Icon(AppIcons.sparkle), onPressed: () => showVideoSummary(context, controller)),
          _ActionButton(tooltip: tr('Copy link'), icon: Icon(AppIcons.link), onPressed: () => copyText(context, item.url, tr('Link copied'))),
          if (!item.isLive && controller.player != null)
            StreamBuilder<bool>(
              stream: controller.player!.stream.position.map((p) => p.inSeconds > 0).distinct(),
              initialData: controller.player!.state.position.inSeconds > 0,
              builder: (context, started) => started.data != true
                  ? const SizedBox.shrink()
                  : _ActionButton(
                      tooltip: tr('Copy link at current time'),
                      icon: Icon(AppIcons.timer),
                      onPressed: () {
                        final link = timestampLink(item.id, controller.player?.state.position ?? Duration.zero);
                        if (link != null) copyText(context, link, tr('Link copied'));
                      },
                    ),
            ),
          _ActionButton(tooltip: tr('Open in browser'), icon: Icon(AppIcons.arrowSquareOut), onPressed: () => openExternal(item.url)),
          if (!Platform.isAndroid)
            IconButton(tooltip: tr('Keyboard shortcuts'), icon: Icon(AppIcons.keyboard), onPressed: () => showShortcutHelp(context, controller.preferences)),
        ],
      ),
      if (decoded)
        Padding(
          padding: const EdgeInsetsDirectional.only(top: 8, start: 4),
          child: Text(tr('Decoding: {0} · {1}', [controller.currentCodec, controller.currentHwdec]), style: TextStyle(fontSize: 12, color: context.colors.outline)),
        ),
    ]);
  }
}

/// A button of the watch page's row: an icon with a tooltip, or on a phone
/// a pill with its [label] too.
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.tooltip, required this.icon, required this.onPressed, String? label}) : label = label ?? tooltip;
  final String tooltip;
  final String label;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (!isPhone(context)) return IconButton(tooltip: tooltip, icon: icon, onPressed: onPressed);
    return TextButton.icon(
      style: TextButton.styleFrom(foregroundColor: context.colors.onSurface, backgroundColor: context.colors.surfaceContainerHighest, padding: const EdgeInsets.symmetric(horizontal: 12)),
      onPressed: onPressed,
      icon: IconTheme.merge(data: const IconThemeData(size: 20), child: icon),
      label: Text(label),
    );
  }
}

class _BackRow extends StatelessWidget {
  const _BackRow({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextButton.icon(onPressed: onBack, icon: Icon(AppIcons.arrowLeft), label: Text(tr('Back'))),
        ),
      );
}

class _Player extends StatelessWidget {
  const _Player({required this.controller, required this.videoKey, required this.byRotation, required this.onExit});
  final AppController controller;
  final GlobalKey<VideoState> videoKey;
  /// Whether the phone entering full screen was turned sideways.
  final bool Function() byRotation;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final picture = _picture(context);
    if (skin == null || (skin.player.frame == null && skin.player.style == 'default')) return picture;
    final frame = skin.player.frame;
    final playing = controller.playing;
    return SkinBox(
      surface: frame,
      radius: frame == null ? 0 : context.cardRadius.topLeft.x + 6,
      padding: frame == null ? null : const EdgeInsets.all(10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        picture,
        if (skin.player.style == 'lcd')
          SkinLcd(
            skin: skin,
            player: controller.player,
            title: playing?.title ?? '',
            subtitle: playing?.channel ?? '',
            still: controller.appearance.lowResource,
          ),
        if (skin.player.deck case final deck?)
          SkinDeckView(
            deck: deck,
            player: controller.player,
            title: playing?.title ?? '',
            onSeek: controller.seek,
          ),
      ]),
    );
  }

  Widget _picture(BuildContext context) => AspectRatio(
        key: lightsOffHole,
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: context.cardRadius,
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
                    child: WarmLayer(
                      behind: true,
                      child: RepaintBoundary(
                        child: PlayerControls(player: state.widget.controller.player, state: state, controller: controller),
                      ),
                    ),
                  ),
                  subtitleViewConfiguration: subtitleViewFor(controller.settings, secondary: controller.secondarySubtitle?.label),
                  onEnterFullscreen: () {
                    WindowChrome.fullscreen.value = true;
                    // Turned sideways: the bars hide, and the screen still
                    // turns with the phone, so turning it back leaves.
                    if (byRotation()) return SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky, overlays: []);
                    return defaultEnterNativeFullscreen();
                  },
                  onExitFullscreen: () {
                    WindowChrome.fullscreen.value = false;
                    onExit();
                    return defaultExitNativeFullscreen();
                  },
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
      if (item.isUpcoming && item.scheduledStart != null) tr('Starts {0}', [formatScheduledStart(item.scheduledStart!)]),
      if (item.isLive && item.watching != null) tr('{0} watching', [formatCount(item.watching!)])
      else if (views != null) tr('{0} views', [formatCount(views)]),
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
        ChannelAvatar(name: channel.isEmpty ? tr('YouTube') : channel, image: channelRef?.avatar, channelId: channelRef?.id),
        const SizedBox(width: 12),
        // The name and its link take the free space, so the follow button
        // and menu sit at the right edge.
        Expanded(child: Row(children: [
          Flexible(child: Text(channel.isEmpty ? tr('YouTube') : channel, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall)),
          const SizedBox(width: 8),
          if (channelRef != null)
            TextButton(onPressed: () => controller.openChannel(channelRef), child: Text(tr('View channel')))
          else if (details?.channelUrl != null)
            TextButton(onPressed: () => openExternal(details!.channelUrl!), child: Text(tr('View channel'))),
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
          SizedBox(height: 8),
          SkeletonBox(height: 12),
          SizedBox(height: 4),
          SkeletonBox(height: 12),
          SizedBox(height: 4),
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

  void _seek(Duration time) => unawaited(widget.controller.seek(time));

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
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.meta.isNotEmpty) Text(widget.meta, style: context.text.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
            if (widget.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Translatable(
                controller: widget.controller,
                text: widget.description,
                builder: (context, description) => AnimatedSize(
                  duration: Motion.of(Ease.fade),
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
                Text(_expanded ? tr('Collapse') : tr('Expand'), style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600)),
              ],
            ],
          ]),
        ),
      ),
    );
  }
}

/// 接下来播放, 评论, the chat and the subtitle list as tabs beside the
/// player. The comments load when their tab is first opened and stay
/// loaded while the video plays. The tab chosen is kept for the next video.
class _SidePanel extends StatefulWidget {
  const _SidePanel({required this.controller, required this.comments, this.replayChat, this.chatFirst = false, this.trailing});
  final AppController controller;
  final Widget? comments;
  final Widget? replayChat;
  /// The chat as the first tab, as a live stream in 剧场模式 wants it.
  final bool chatFirst;
  /// At the end of the tab row.
  final Widget? trailing;

  @override
  State<_SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<_SidePanel> with TickerProviderStateMixin {
  TabController? _tabs;
  List<String> _ids = const [];

  @override
  void initState() {
    super.initState();
    sidePanelTab.addListener(_asked);
  }

  @override
  void dispose() {
    sidePanelTab.removeListener(_asked);
    _tabs?.dispose();
    super.dispose();
  }

  /// Another part of the page asked for a tab, such as the player's
  /// subtitle list button.
  void _asked() {
    final index = _ids.indexOf(sidePanelTab.value ?? '');
    final tabs = _tabs;
    if (index >= 0 && tabs != null && tabs.index != index) tabs.animateTo(index);
  }

  TabController _controllerFor(List<String> ids) {
    if (_tabs != null && listEquals(ids, _ids)) return _tabs!;
    final was = _tabs == null ? sidePanelTab.value : _ids[_tabs!.index];
    _tabs?.dispose();
    _ids = ids;
    final tabs = TabController(length: ids.length, vsync: this, initialIndex: max(0, ids.indexOf(was ?? '')));
    tabs.addListener(() {
      if (!tabs.indexIsChanging) sidePanelTab.value = _ids[tabs.index];
    });
    return _tabs = tabs;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final player = controller.player;
    final chat = widget.replayChat == null ? null : ('chat', tr('Chat'), _KeepAlive(child: widget.replayChat!));
    final subtitles = player != null && (controller.details?.subtitles.isNotEmpty == true || controller.secondarySubtitle != null);
    final tabs = [
      if (widget.chatFirst && chat != null) chat,
      ('next', controller.playingList != null ? tr('Playlist') : tr('Up next'), _UpNext(controller: controller)),
      if (widget.comments case final comments?) ('comments', tr('Comments'), _KeepAlive(child: comments)),
      if (!widget.chatFirst && chat != null) chat,
      if (subtitles) ('subtitles', tr('Subtitles'), _KeepAlive(child: Padding(padding: const EdgeInsets.only(top: 4), child: SubtitleList(key: ValueKey('subtitles:${controller.playing?.id}'), controller: controller, player: player)))),
    ];
    final tabController = _controllerFor([for (final (id, _, _) in tabs) id]);
    return Column(children: [
      Row(children: [
        Expanded(child: TabBar(controller: tabController, isScrollable: tabs.length > 3, tabAlignment: tabs.length > 3 ? TabAlignment.start : null, dividerColor: Colors.transparent, tabs: [for (final (_, label, _) in tabs) Tab(height: 40, text: label)])),
        if (widget.trailing case final trailing?) trailing,
      ]),
      const SizedBox(height: 8),
      Expanded(child: TabBarView(controller: tabController, children: [for (final (_, _, view) in tabs) view])),
    ]);
  }
}

const _theaterChatWidth = 360.0;

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
    syncChatTranslation(controller);
    syncSuperChatHighlights(controller);
    final header = <Widget>[
      Row(children: [
        Expanded(child: Text(tr(live ? 'Chat' : 'Chat replay'), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
        if (messages.any((m) => m.color != null) || controller.chatTicker.isNotEmpty) SuperChatHighlightSwitch(controller: controller),
        ImmersiveTranslationSwitch(controller: controller),
      ]),
      const SizedBox(height: 8),
      if (live && controller.chatTicker.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: SuperChatStrip(controller: controller)),
      if (controller.loadingReplayChat) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
      if (controller.replayChatError != null) ErrorBanner(tr(live ? "Couldn't load the chat: {0}" : "Couldn't load chat replay: {0}", [controller.replayChatError]), onRetry: controller.retryChat),
      if (!controller.loadingReplayChat && controller.replayChatError == null && messages.isEmpty)
        Padding(padding: const EdgeInsets.all(12), child: Text(tr(live ? 'This live stream has no public chat' : 'This live replay has no public chat replay'), style: TextStyle(color: context.colors.onSurfaceVariant))),
    ];
    // The box to write in stays under the messages, as on YouTube.
    final input = live && controller.playing != null ? LiveChatInput(controller: controller, videoId: controller.playing!.id) : null;
    if (messages.isEmpty) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...header, if (input != null) input]);
    // The same widget for the same message, so a flush of new messages
    // does not build the ones already shown again.
    Widget messageAt(int index) {
      final message = messages[index];
      return _chatRows[message] ??= ChatMessageRow(controller: controller, message: message, onSeek: message.offset == null ? null : () => controller.seek(message.offset!));
    }
    if (live) {
      // Newest at the bottom; a list built from the bottom stays on the
      // newest messages as they arrive while it is scrolled to the end.
      final list = LiveChatList(messages: messages, messageAt: messageAt);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ...header,
        if (shrinkWrap) SizedBox(height: 320, child: list) else Expanded(child: list),
        if (input != null) Padding(padding: EdgeInsets.only(top: 8, bottom: shrinkWrap ? 0 : AppStyle.pagePadding), child: input),
      ]);
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

final _chatRows = Expando<Widget>();

@visibleForTesting
Widget upNextForTest(AppController controller) => _UpNext(controller: controller);

class _UpNext extends StatelessWidget {
  const _UpNext({required this.controller, this.shrinkWrap = false});
  final AppController controller;
  final bool shrinkWrap;

  List<Widget> slivers(BuildContext context) {
    final items = controller.upNext;
    final related = controller.related;
    // What 接下来播放 already lists is not repeated under 相关视频.
    final queued = {for (final item in items) item.id};
    final relatedItems = [for (final item in controller.relatedItems) if (!queued.contains(item.id)) item];
    final autoplay = Row(mainAxisSize: MainAxisSize.min, children: [
      Text(tr('Autoplay next'), style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12)),
      Transform.scale(
        scale: 0.75,
        child: Switch(value: controller.settings.playOrder == PlayOrder.autoPlayRelated, onChanged: (on) => unawaited(controller.setAutoplayNext(on))),
      ),
    ]);
    final head = <Widget>[
      if (controller.playQueue.isNotEmpty) ...[PlayQueuePanel(controller: controller), const SizedBox(height: 16)],
      if (controller.playingList != null)
        PlayingListPanel(controller: controller, trailing: autoplay, shrinkWrap: shrinkWrap)
      else
        _header(context, tr('Up next'), items.isEmpty ? null : '${items.length}', trailing: autoplay),
      if (controller.playingList == null && items.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            relatedItems.isEmpty ? tr("You've reached the end of the queue. When playing videos from search results, playlists or watch history, the following videos appear here.") : controller.settings.autoplayNext ? tr("You've reached the end of the queue. Autoplay will continue with the related videos below.") : tr("You've reached the end of the queue. Turn on Autoplay to play the related videos below next."),
            style: TextStyle(color: context.colors.onSurfaceVariant, height: 1.5),
          ),
        ),
    ];
    final tail = <Widget>[
      if (related != null) ...[
        if (related.loading && relatedItems.isEmpty)
          const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator())
        else if (related.error != null)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ErrorBanner(tr("Couldn't load related videos"), onRetry: () => related.loadMore(retry: true))),
      ],
    ];
    // Slivers, so a long list builds only the tiles on screen.
    return [
      SliverList.list(children: head),
      if (controller.playingList == null && items.isNotEmpty) SliverList.builder(itemCount: items.length, itemBuilder: (context, i) => _tile(items[i], null)),
      if (related != null) ...[
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(top: 16), child: _header(context, tr('Related videos'), tr('Search by title')))),
        SliverList.builder(itemCount: relatedItems.length, itemBuilder: (context, i) => _tile(relatedItems[i], relatedItems)),
      ],
      SliverList.list(children: tail),
    ];
  }

  @override
  Widget build(BuildContext context) => CustomScrollView(slivers: [...slivers(context), const SliverPadding(padding: EdgeInsets.only(bottom: AppStyle.pagePadding))]);

  Widget _header(BuildContext context, String title, String? note, {Widget? trailing}) => Padding(
        padding: EdgeInsetsDirectional.fromSTEB(4, 0, trailing == null ? 4 : 0, 8),
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
/// The text scale for subtitles in a window of [size]: the 32 px base
/// becomes 5.5% of the short side, between 13 and 32 px.
double smallSubtitleScale(Size size) => (size.shortestSide * 0.055).clamp(13.0, 32.0) / 32;

SubtitleViewConfiguration subtitleViewFor(PlayerSettings settings, {Size? smallWindow, Object? secondary}) {
  // The view scales by area against 1080p, which makes the text tiny in a
  // small window. There a line is about a twentieth of the picture's
  // height, as on a TV, but never under 13 px, which stays readable, nor
  // over the full-size text.
  final textScaler = smallWindow == null ? null : TextScaler.linear(smallSubtitleScale(smallWindow));
  final paddingScale = smallWindow == null ? 1.0 : (smallWindow.shortestSide / 720).clamp(0.3, 1.0);
  if (settings.libassSubtitles) return const SubtitleViewConfiguration(visible: false);
  final border = settings.subtitleBorder;
  TextStyle style(String font, double scale, int color, double opacity) => TextStyle(
        height: 1.3,
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
    spacing: 6,
    secondaryKey: secondary,
    padding: EdgeInsets.fromLTRB(16 * paddingScale, 0, 16 * paddingScale, (24 + (100 - settings.subtitlePosition) * 4.0) * paddingScale),
  );
}
