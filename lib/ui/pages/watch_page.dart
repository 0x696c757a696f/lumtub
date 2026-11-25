import 'dart:async';
import 'dart:io' show Platform;

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show DeviceOrientation, SystemChrome, SystemUiMode;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit/media_kit.dart' show Player;

import '../../device.dart';
import '../../libass_layout.dart' show LibassLook;
import '../../live_chat.dart' show LiveChatMessage;
import '../window_chrome.dart';
import '../../app/app_controller.dart';
import '../../learning/word_token.dart';
import '../../learning/known_words.dart';
import '../../learning/learning.dart';
import '../learning/ruby_line.dart';
import '../learning/word_card.dart';
import '../../appearance_settings.dart' show blankFont, bundledFont, cjkFormOf, downloadedScriptFamilies, languageStyle;
import '../../models.dart';
import '../../player_settings.dart';
import '../../timestamp_link.dart';
import '../../youtube_account.dart' show VideoRating;
import '../comments_view.dart';
import '../cast_ui.dart';
import '../common.dart';
import '../fill_icon.dart';
import '../fitting_tab_bar.dart';
import '../haptics.dart';
import '../reveal.dart';
import '../key_scroll.dart';
import '../lights_off.dart';
import '../live_chat_rows.dart';
import '../linked_text.dart';
import '../player_controls.dart';
import '../player_shortcuts.dart';
import '../screenshot_action.dart';
import '../summary_dialog.dart';
import '../subtitle_list_panel.dart';
import '../study_bar.dart';
import '../animated_visibility.dart';
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
/// windows the list and the comments share a side panel as
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

  /// Whether this full screen comes from turning the phone: only while the
  /// screen is sideways. A turn that never reached full screen (the page
  /// was busy, the phone was turned back at once) must not leave the
  /// fullscreen button holding an upright screen with the sideways layout.
  bool _enteredByRotation() {
    final view = View.maybeOf(context);
    if (view == null || view.physicalSize.width <= view.physicalSize.height) _byRotation = false;
    return _byRotation;
  }

  void _leftFullscreen() {
    _byRotation = false;
    final view = View.maybeOf(context);
    _waitUpright = view != null && view.physicalSize.width > view.physicalSize.height;
  }

  /// Enters fullscreen once per video when 自动全屏 is on, and always on a TV.
  void _autoFullscreen(AppController controller) {
    final id = controller.playing?.id;
    // A TV plays full screen, as TV video apps do; back shows the page.
    if (id == null || id == _fullscreenFor || !(controller.preferences.autoFullscreen || Device.tv)) return;
    _fullscreenFor = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = _video.currentState;
      if (mounted && state != null && !state.isFullscreen()) {
        fillingWindow.value = false;
        state.enterFullscreen();
      }
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
          final theater = theaterMode.value;
          // A phone keeps the player at the top and the rest in tabs under
          // it, as phone video apps do.
          final phone = watchesLikePhone(context);
          final item = controller.playing;
          final hasChat = item?.isLive == true || item?.liveStatus == 'was_live';
          // 剧场模式 in a wide window keeps comments, up next and the chat
          // in a column beside the video, which can be folded away.
          final sidePanel = theater && outer.maxWidth >= 900;
          subtitleListBeside = sidePanel || (!theater && outer.maxWidth >= 1080);
          theaterPanelBeside = sidePanel;
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
                  creator: controller.playingChannel,
                  onSeek: (position) => controller.seek(position),
                  scrollable: wide || panelOpen || phone,
                  sliver: !wide && !panelOpen && !phone,
                  padding: wide ? const EdgeInsets.fromLTRB(4, 0, 4, AppStyle.pagePadding) : EdgeInsets.zero,
                );
          final replayChat = hasChat ? _ReplayChatPanel(controller: controller, shrinkWrap: !wide && !panelOpen && !phone) : null;
          if (phone) {
            return Column(children: [
              _Player(controller: controller, videoKey: _video, byRotation: _enteredByRotation, onExit: _leftFullscreen),
              CastBar(controller: controller),
              Padding(padding: const EdgeInsets.symmetric(horizontal: AppStyle.pagePadding), child: StudyBar(controller: controller)),
              Expanded(
                child: _SidePanel(
                  controller: controller,
                  comments: comments,
                  replayChat: replayChat,
                  chatFirst: item?.isLive == true,
                  // As phone video apps lay it out: the channel, the
                  // title with its description folded under it, a row of
                  // the main actions, then what plays next.
                  intro: CustomScrollView(slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 4, AppStyle.pagePadding, 0),
                      sliver: SliverList.list(children: [
                        _PhoneDetails(key: ValueKey('details:${item?.id}'), controller: controller),
                        const SizedBox(height: 12),
                        _PhoneActions(controller: controller),
                        if (controller.playbackError != null && !controller.waitingForStart) ...[
                          const SizedBox(height: 12),
                          ErrorBanner(tr('Playback failed: {0}', [controller.playbackError]), onRetry: controller.retryPlayback),
                        ],
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 12),
                      ]),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 0, AppStyle.pagePadding, AppStyle.pagePadding),
                      sliver: SliverMainAxisGroup(slivers: _UpNext(controller: controller, shrinkWrap: true).slivers(context)),
                    ),
                  ]),
                ),
              ),
            ]);
          }
          final main = <Widget>[
            if (!theater) _BackRow(onBack: controller.goBack),
            Center(child: SizedBox(width: playerWidth, child: _Player(controller: controller, videoKey: _video, byRotation: _enteredByRotation, onExit: _leftFullscreen))),
            CastBar(controller: controller),
            StudyBar(controller: controller),
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
              // In 剧场模式 the player spans the whole width, black either
              // side of a picture narrower than the window, as on YouTube.
              // Sized by the room it has as that changes, so the player
              // follows the side rail and the side panel as they slide.
              if (theater)
                SliverLayoutBuilder(builder: (context, box) {
                  final width = min(box.crossAxisExtent, max(320.0, (constraints.maxHeight - 8) * 16 / 9));
                  return SliverToBoxAdapter(child: _Player(controller: controller, videoKey: _video, byRotation: _enteredByRotation, onExit: _leftFullscreen, height: width * 9 / 16));
                }),
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
            // Folded, the player's own button unfolds it again.
            return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: page),
              AnimatedVisibility.side(
                visible: panelOpen,
                child: SizedBox(
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
  const _RatingButtons({required this.controller, this.stacked = false});
  final AppController controller;
  /// Each an icon over its count, sharing the row's width.
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    // Built once more while the video closes, when nothing plays.
    final item = controller.playing;
    if (item == null) return const SizedBox.shrink();
    final account = controller.account;
    final signedIn = account?.active ?? false;
    final colors = context.colors;
    final likes = controller.details?.likeCount ?? controller.dislikes?.likes;
    final dislikes = controller.dislikes?.dislikes;
    Widget button(VideoRating rating, IconData icon, IconData selectedIcon, String label, int? count, {String? note}) {
      final selected = signedIn && account!.ratingOf(item.id) == rating;
      final off = signedIn && account!.ratingOff(item.id);
      final shown = count == null || !signedIn ? count : (count + account!.ratingChange(item.id, rating)).clamp(0, 1 << 62);
      final onPressed = off
          ? null
          : signedIn
          ? () => account!.rate(item, rating)
          : () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Sign in to YouTube to {0}', [label]))));
      if (stacked) return Expanded(child: _StackedAction(icon: icon, fill: selectedIcon, label: shown == null ? label : formatCount(shown), selected: selected, onPressed: onPressed));
      return Tooltip(
        message: [
          if (!signedIn) tr('Sign in to YouTube to {0}', [label]) else if (off) tr('The uploader turned off likes and dislikes for this video') else if (selected) tr('Cancel {0}', [label]) else label,
          if (note != null) note,
        ].join('\n'),
        child: TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: selected ? colors.primary : colors.onSurface,
            backgroundColor: colors.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          onPressed: onPressed,
          icon: IconTheme.merge(data: const IconThemeData(size: 20), child: FillIcon(icon, selectedIcon, selected: selected)),
          label: Text(shown == null ? label : formatCount(shown)),
        ),
      );
    }

    return Row(mainAxisSize: stacked ? MainAxisSize.max : MainAxisSize.min, children: [
      button(VideoRating.like, AppIcons.thumbsUp, AppIcons.thumbsUpFill, tr('Like'), likes),
      if (!stacked) const SizedBox(width: 4),
      button(VideoRating.dislike, AppIcons.thumbsDown, AppIcons.thumbsDownFill, tr('Dislike'), dislikes,
          note: dislikes == null ? null : tr("The dislike count is Return YouTube Dislike's estimate")),
    ]);
  }
}

/// Whether [player] has played past its first second; one stream per
/// player, so a rebuild keeps its subscription.
Stream<bool> _startedOf(Player player) => _started[player] ??= player.stream.position.map((p) => p.inSeconds > 0).distinct();
final _started = Expando<Stream<bool>>();

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    // Built once more while the video closes, when nothing plays.
    final item = controller.playing;
    if (item == null) return const SizedBox.shrink();
    final settings = controller.settings;
    final decoded = controller.currentCodec != tr('No video played yet');
    final library = controller.library;
    final favorite = library?.isFavorite(item.id) ?? false;
    final later = library?.isWatchLater(item.id) ?? false;
    final phone = watchesLikePhone(context);
    // A phone's buttons go in one row that scrolls sideways, each with its
    // name, as phone video apps lay them out.
    Widget layout(List<Widget> children) => phone
        ? SingleChildScrollView(
            key: const PageStorageKey('actions'),
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
              icon: IconTheme.merge(data: IconThemeData(color: favorite ? context.colors.primary : null), child: FillIcon(AppIcons.heart, AppIcons.heartFill, selected: favorite)),
              onPressed: () => library.toggleFavorite(item),
            ),
            _ActionButton(
              tooltip: later ? tr('Remove from Watch later') : tr('Watch later'),
              label: tr('Watch later'),
              icon: IconTheme.merge(data: IconThemeData(color: later ? context.colors.primary : null), child: FillIcon(AppIcons.clock, AppIcons.clockFill, selected: later)),
              onPressed: () => library.toggleWatchLater(item),
            ),
            _ActionButton(tooltip: tr('Add to playlist'), icon: Icon(AppIcons.listPlus), onPressed: () => showAddToPlaylist(context, controller, item)),
            if (controller.account?.active ?? false)
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
              stream: _startedOf(controller.player!),
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
          if (!Platform.isAndroid && !Platform.isIOS)
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

/// A phone's channel, title and description: the title folded to two
/// lines with how often and when it was watched under it; the arrow beside
/// it unfolds the whole title and the description.
class _PhoneDetails extends StatefulWidget {
  const _PhoneDetails({super.key, required this.controller});
  final AppController controller;

  @override
  State<_PhoneDetails> createState() => _PhoneDetailsState();
}

class _PhoneDetailsState extends State<_PhoneDetails> {
  late bool _open = widget.controller.preferences.expandDescription;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    // Built once more while the video closes, when nothing plays.
    final item = controller.playing;
    if (item == null) return const SizedBox.shrink();
    final details = controller.details;
    final colors = context.colors;
    final views = details?.viewCount ?? item.viewCount;
    final meta = [
      if (item.isUpcoming && item.scheduledStart != null) tr('Starts {0}', [formatScheduledStart(item.scheduledStart!)]),
      if (item.isLive && item.watching != null) tr('{0} watching', [formatCount(item.watching!)])
      else if (views != null) tr('{0} views', [formatCount(views)]),
      if (details?.uploadDate != null) formatDate(details!.uploadDate!),
    ].join(' · ');
    final channel = details?.channel.isNotEmpty == true ? details!.channel : item.channel;
    final channelRef = controller.playingChannel;
    final description = details?.description ?? '';
    final name = channel.isEmpty ? tr('YouTube') : channel;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: InkWell(
            borderRadius: AppStyle.cardRadius,
            onTap: channelRef != null ? () => controller.openChannel(channelRef) : details?.channelUrl != null ? () => openExternal(details!.channelUrl!) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                ChannelAvatar(name: name, image: channelRef?.avatar, channelId: channelRef?.id),
                const SizedBox(width: 10),
                Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall)),
              ]),
            ),
          ),
        ),
        if (channelRef != null) ...[
          const SizedBox(width: 8),
          FollowButton(controller: controller, channel: channelRef, compact: MediaQuery.sizeOf(context).width < 600),
          ChannelMenuButton(controller: controller, channel: channelRef),
        ],
      ]),
      const SizedBox(height: 8),
      InkWell(
        borderRadius: AppStyle.cardRadius,
        onTap: () => setState(() => _open = !_open),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Translatable(
              controller: controller,
              text: deArrow.titleOf(item.id, details?.title.isNotEmpty == true ? details!.title : item.title),
              builder: (context, title) => Text(title, maxLines: _open ? null : 2, overflow: _open ? null : TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.35)),
            ),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(meta, style: TextStyle(fontSize: 12, color: colors.outline)),
            ],
          ])),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 8, top: 2),
            child: Icon(_open ? AppIcons.caretUp : AppIcons.caretDown, size: 18, color: colors.outline, semanticLabel: _open ? tr('Collapse') : tr('Expand')),
          ),
        ]),
      ),
      if (controller.loadingDetails && details == null) ...[
        const SizedBox(height: 8),
        const DelayedReveal(child: Skeleton(child: SkeletonBox(width: 180, height: 12))),
      ] else if (_open && description.isNotEmpty) ...[
        const SizedBox(height: 8),
        Reveal(child: Translatable(
          controller: controller,
          text: description,
          builder: (context, text) => SelectionArea(
            child: LinkedText(text, style: TextStyle(height: 1.5, fontSize: 13, color: colors.onSurfaceVariant), onTime: (time) => unawaited(controller.seek(time)), onLink: openExternal),
          ),
        )),
      ],
    ]);
  }
}

/// A phone's main actions spread over the width, each an icon over its
/// count or name; the rest are under 更多.
class _PhoneActions extends StatelessWidget {
  const _PhoneActions({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    // Built once more while the video closes, when nothing plays.
    final item = controller.playing;
    if (item == null) return const SizedBox.shrink();
    final library = controller.library;
    final favorite = library?.isFavorite(item.id) ?? false;
    final later = library?.isWatchLater(item.id) ?? false;
    final download = controller.downloads != null && (!item.isLive || controller.downloads!.canRecord);
    return Row(children: [
      Expanded(flex: 2, child: _RatingButtons(controller: controller, stacked: true)),
      if (library != null) ...[
        Expanded(child: _StackedAction(icon: AppIcons.heart, fill: AppIcons.heartFill, label: tr('Favorites'), selected: favorite, onPressed: () => library.toggleFavorite(item))),
        Expanded(child: _StackedAction(icon: AppIcons.clock, fill: AppIcons.clockFill, label: tr('Watch later'), selected: later, onPressed: () => library.toggleWatchLater(item))),
      ],
      if (download) Expanded(child: _StackedAction(icon: item.isLive ? AppIcons.radioButton : AppIcons.downloadSimple, label: tr('Downloads'), onPressed: () => showDownloadChoice(context, controller, item))),
      Expanded(child: _StackedAction(icon: AppIcons.dotsThreeVertical, label: tr('More'), onPressed: () => _more(context))),
    ]);
  }

  Future<void> _more(BuildContext context) async {
    final item = controller.playing;
    if (item == null) return;
    final library = controller.library;
    final settings = controller.settings;
    final position = controller.player?.state.position ?? Duration.zero;
    final picked = await pickFromSheet<String>(context, [
      if (library != null) (value: 'playlist', icon: AppIcons.listPlus, label: tr('Add to playlist'), selected: false),
      if (library != null && (controller.account?.active ?? false)) (value: 'youtube', icon: AppIcons.filmReel, label: tr('Save to YouTube playlist'), selected: false),
      if (!item.isLive) (value: 'summary', icon: AppIcons.sparkle, label: tr('AI summary'), selected: false),
      (value: 'link', icon: AppIcons.link, label: tr('Copy link'), selected: false),
      if (!item.isLive && position.inSeconds > 0) (value: 'time', icon: AppIcons.timer, label: tr('Copy link at current time'), selected: false),
      (value: 'browser', icon: AppIcons.arrowSquareOut, label: tr('Open in browser'), selected: false),
      // 播放顺序, the chosen one ticked.
      (value: null, icon: null, label: null, selected: false),
      for (final order in PlayOrder.values) (value: 'order:${order.name}', icon: null, label: order.label, selected: order == settings.playOrder),
    ]);
    if (picked == null || !context.mounted) return;
    if (picked.startsWith('order:')) {
      final order = PlayOrder.values.byName(picked.substring(6));
      controller.setPlayOrder(order);
      return;
    }
    switch (picked) {
      case 'playlist':
        await showAddToPlaylist(context, controller, item);
      case 'youtube':
        await showSaveToYoutube(context, controller, item);
      case 'summary':
        await showVideoSummary(context, controller);
      case 'link':
        copyText(context, item.url, tr('Link copied'));
      case 'time':
        final link = timestampLink(item.id, position);
        if (link != null) copyText(context, link, tr('Link copied'));
      case 'browser':
        await openExternal(item.url);
    }
  }
}

/// An icon over a short label, as a phone's row of actions has them. With
/// [fill], the icon fills in while [selected].
class _StackedAction extends StatelessWidget {
  const _StackedAction({required this.icon, this.fill, required this.label, required this.onPressed, this.selected = false});
  final IconData icon;
  final IconData? fill;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = onPressed == null ? colors.outline : selected ? colors.primary : colors.onSurfaceVariant;
    return InkWell(
      borderRadius: AppStyle.cardRadius,
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          IconTheme.merge(
            data: IconThemeData(size: 24, color: color),
            child: fill == null ? Icon(icon) : FillIcon(icon, fill!, selected: selected),
          ),
          const SizedBox(height: 4),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: color)),
        ]),
      ),
    );
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
    if (!watchesLikePhone(context)) return IconButton(tooltip: tooltip, icon: icon, onPressed: onPressed);
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
  const _Player({required this.controller, required this.videoKey, required this.byRotation, required this.onExit, this.height});
  final AppController controller;
  /// 剧场模式's height: the player then takes the whole width, square
  /// cornered, rather than a 16:9 box.
  final double? height;
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

  Widget _box({required Widget child}) => height == null
      ? AspectRatio(key: lightsOffHole, aspectRatio: 16 / 9, child: child)
      : SizedBox(key: lightsOffHole, width: double.infinity, height: height, child: child);

  Widget _picture(BuildContext context) => _box(
        child: ClipRRect(
          borderRadius: height == null ? context.cardRadius : BorderRadius.zero,
          child: ColoredBox(
            color: Colors.black,
            // The video and its controls repaint apart, so
            // pointer movement over the controls does not redraw the video
            // texture, which flashes black on some Windows GPUs.
            child: Stack(fit: StackFit.expand, children: [
              RepaintBoundary(
                child: ValueListenableBuilder<int>(
                  valueListenable: controller.learning.viewChanges,
                  builder: (context, learningView, child) => Video(
                  key: videoKey,
                  controller: controller.videoController!,
                  // Background playback is decided in main.dart (onHide), not by the view.
                  pauseUponEnteringBackgroundMode: false,
                  // The controls cover the video here and in full screen, so
                  // they measure the size it is drawn at.
                  controls: (state) => VideoBox(
                    controller: controller,
                    // PlayerControls' own box draws them, under its controls.
                    danmakuOver: null,
                    child: WarmLayer(
                      behind: true,
                      child: RepaintBoundary(
                        child: PlayerControls(player: state.widget.controller.player, state: state, controller: controller),
                      ),
                    ),
                  ),
                  subtitleViewConfiguration: controller.studyHidesSubtitles
                      ? const SubtitleViewConfiguration(visible: false)
                      : subtitleViewFor(
                    controller.settings,
                    secondary: controller.secondarySubtitle?.label,
                    byHeight: Platform.isAndroid || Platform.isIOS,
                    libass: controller.libassDraws,
                    mainLanguage: controller.mainSubtitleLanguage,
                    secondLanguage: controller.secondSubtitleLanguage,
                    reveal: (shown: controller.translationShown, hover: controller.hoverTranslation, tap: controller.toggleTranslation),
                    words: !controller.learningOn
                        ? null
                        : (
                      learning: controller.learning,
                      onWord: (token, line) => unawaited(showWordCard(context, controller, token, sentence: line)),
                      onHover: controller.hoverSubtitle,
                      // A finger swiped across the line; a mouse drags no lines.
                      onSwipe: Platform.isAndroid || Platform.isIOS ? (step) => unawaited(controller.stepLine(step)) : null,
                    ),
                  ),
                  onEnterFullscreen: () {
                    // 铺满窗口 keeps the window as it is.
                    if (fillingWindow.value) return Future.value();
                    WindowChrome.fullscreen.value = true;
                    // Turned sideways: the bars hide, and the screen still
                    // turns with the phone, so turning it back leaves.
                    if (byRotation()) return SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky, overlays: []);
                    // A video taller than wide fills an upright screen best,
                    // so the phone is not turned for it.
                    final width = controller.player?.state.width ?? 0, height = controller.player?.state.height ?? 0;
                    if (touchFirst && width > 0 && height > width) {
                      return Future.wait([
                        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky, overlays: []),
                        SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]),
                      ]);
                    }
                    return defaultEnterNativeFullscreen();
                  },
                  onExitFullscreen: () {
                    WindowChrome.fullscreen.value = false;
                    onExit();
                    if (fillingWindow.value) {
                      fillingWindow.value = false;
                      return Future.value();
                    }
                    return defaultExitNativeFullscreen();
                  },
                ),
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
    // Built once more while the video closes, when nothing plays.
    final item = controller.playing;
    if (item == null) return const SizedBox.shrink();
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
        const DelayedReveal(child: Skeleton(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SkeletonBox(width: 220, height: 14),
          SizedBox(height: 8),
          SkeletonBox(height: 12),
          SizedBox(height: 4),
          SkeletonBox(height: 12),
          SizedBox(height: 4),
          SkeletonBox(width: 260, height: 12),
        ])))
      else if (meta.isNotEmpty || (details?.description.isNotEmpty ?? false))
        // As wide as the title and channel row, not as wide as its text.
        Reveal(child: SizedBox(
          width: double.infinity,
          child: _Description(meta: meta, description: details?.description ?? '', expanded: controller.preferences.expandDescription, controller: controller),
        )),
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
                  curve: Ease.out,
                  alignment: Alignment.topCenter,
                  // Times seek the video and links open in the browser; the
                  // expanded text can still be selected.
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
  const _SidePanel({required this.controller, required this.comments, this.replayChat, this.chatFirst = false, this.trailing, this.intro});
  final AppController controller;
  /// On a phone: the buttons and details, as the first tab.
  final Widget? intro;
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

  /// The tab last settled on, before a tap moves away from it.
  int _settled = 0;
  final _pageKeys = <String, GlobalKey>{};

  /// A tap on the tab already shown takes its list back to the top.
  void _tapped(int index, String id) {
    if (index == _settled) {
      final page = _pageKeys[id]?.currentContext;
      if (page != null) KeyScroll.toTopAt(page);
    }
  }

  TabController _controllerFor(List<String> ids) {
    if (_tabs != null && listEquals(ids, _ids)) return _tabs!;
    final was = _tabs == null ? sidePanelTab.value : _ids[_tabs!.index];
    _tabs?.dispose();
    _ids = ids;
    final tabs = TabController(length: ids.length, vsync: this, initialIndex: max(0, ids.indexOf(was ?? '')));
    tabs.addListener(() {
      if (tabs.indexIsChanging) return;
      sidePanelTab.value = _ids[tabs.index];
      _settled = tabs.index;
    });
    _settled = tabs.index;
    return _tabs = tabs;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final player = controller.player;
    final chat = widget.replayChat == null ? null : ('chat', tr('Chat'), _KeepAlive(child: widget.replayChat!));
    final subtitles = player != null && (controller.details?.subtitles.isNotEmpty == true || controller.secondarySubtitle != null);
    final tabs = [
      if (widget.intro case final intro?) ('intro', tr('Overview'), _KeepAlive(child: intro)),
      if (widget.chatFirst && chat != null) chat,
      // On a phone what plays next is under 简介.
      if (widget.intro == null) ('next', controller.playingList != null ? tr('Playlist') : tr('Up next'), _UpNext(controller: controller)),
      if (widget.comments case final comments?) ('comments', tr('Comments'), _KeepAlive(child: comments)),
      if (!widget.chatFirst && chat != null) chat,
      if (subtitles) ('subtitles', tr('Subtitles'), _KeepAlive(child: Padding(padding: const EdgeInsets.only(top: 4), child: SubtitleList(key: ValueKey('subtitles:${controller.playing?.id}'), controller: controller, player: player)))),
    ];
    final tabController = _controllerFor([for (final (id, _, _) in tabs) id]);
    return Column(children: [
      Row(children: [
        Expanded(child: FittingTabBar(controller: tabController, onTap: (i) => _tapped(i, tabs[i].$1), height: widget.intro != null ? 48 : 40, labels: [for (final (_, label, _) in tabs) label])),
        if (widget.trailing case final trailing?) trailing,
      ]),
      const SizedBox(height: 8),
      Expanded(child: TabBarView(controller: tabController, children: [for (final (id, _, view) in tabs) KeyedSubtree(key: _pageKeys.putIfAbsent(id, GlobalKey.new), child: view)])),
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

(Object, (List<VideoItem>, List<VideoItem>))? _upNextMemo;
(Object, List<(_Related, String, List<VideoItem>)>)? _choicesMemo;

/// Whether the chat holds a Super Chat, kept up as messages arrive: a
/// live chat grows by a few messages a flush, so only those are looked at.
final _superChats = _SuperChatsSeen();

class _SuperChatsSeen {
  List<LiveChatMessage> _list = const [];
  // Messages after the newest coloured one, or -1 for none.
  int _after = -1;

  bool seenIn(List<LiveChatMessage> list) {
    if (!identical(list, _list)) {
      // A flush appends to the last list (dropping the oldest); anything
      // else is looked through whole.
      var added = list.length;
      if (_list.isNotEmpty) {
        final last = _list.last;
        for (var i = list.length - 1; i >= 0; i--) {
          if (identical(list[i], last)) {
            added = list.length - 1 - i;
            break;
          }
        }
      }
      if (added == list.length) {
        _after = -1;
      } else if (_after >= 0) {
        _after += added;
      }
      for (var i = list.length - added; i < list.length; i++) {
        if (list[i].color != null) _after = list.length - 1 - i;
      }
      _list = list;
    }
    return _after >= 0 && _after < list.length;
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
        Flexible(child: Text(tr(live ? 'Chat' : 'Chat replay'), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
        const SizedBox(width: 4),
        Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: ChatViewMenu(controller: controller))),
        if (_superChats.seenIn(messages) || controller.chatTicker.isNotEmpty) SuperChatHighlightSwitch(controller: controller),
        ImmersiveTranslationSwitch(controller: controller),
      ]),
      const SizedBox(height: 8),
      ChatModeStrip(controller: controller),
      if (controller.loadingMoreChat) const Padding(padding: EdgeInsets.only(bottom: 8), child: LinearProgressIndicator(minHeight: 2)),
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

enum _Related { all, live, channel, others, forYou, recent, watched }

/// Which related videos show, for the video it was picked on.
final _relatedFilter = ValueNotifier<(String?, _Related)>((null, _Related.all));

class _UpNext extends StatelessWidget {
  const _UpNext({required this.controller, this.shrinkWrap = false});
  final AppController controller;
  final bool shrinkWrap;

  List<Widget> slivers(BuildContext context) {
    final (items, relatedItems) = _upNextAndRelated();
    final related = controller.related;
    final autoplay = Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(child: Text(tr('Autoplay next'), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12))),
      Transform.scale(
        scale: 0.75,
        child: Switch(value: controller.settings.playOrder == PlayOrder.autoPlayRelated, onChanged: (on) => unawaited(controller.setAutoplayNext(on))),
      ),
    ]);
    final head = <Widget>[
      if (controller.playQueue.isNotEmpty) ...[PlayQueuePanel(controller: controller), const SizedBox(height: 16)],
      if (controller.playingList == null) _header(context, tr('Up next'), items.isEmpty ? null : '${items.length}', trailing: autoplay),
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
      if (controller.playingList != null) ...playingListSlivers(context, controller: controller, trailing: autoplay, shrinkWrap: shrinkWrap),
      if (controller.playingList == null && items.isNotEmpty) SliverList.builder(itemCount: items.length, itemBuilder: (context, i) => _tile(items[i], null)),
      if (related != null) ...[
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(top: 16), child: _header(context, tr('Related videos'), tr('Search by title')))),
        ValueListenableBuilder(
          valueListenable: _relatedFilter,
          builder: (context, picked, _) {
            final playing = controller.playing;
            final choices = _relatedChoices(playing, relatedItems);
            final (_, kind) = picked.$1 == playing?.id && choices.any((c) => c.$1 == picked.$2) ? picked : (playing?.id, _Related.all);
            final shown = choices.firstWhere((c) => c.$1 == kind).$3;
            return SliverMainAxisGroup(slivers: [
              if (choices.length > 1)
                SliverToBoxAdapter(child: SizedBox(
                  height: 40,
                  child: ListView(key: const PageStorageKey('choices'), scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(4, 0, 4, 8), children: [
                    for (final (value, label, _) in choices)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ChoiceChip(label: Text(label), selected: value == kind, onSelected: (_) {
                          if (value != kind) Haptics.select();
                          _relatedFilter.value = (playing?.id, value);
                        }),
                      ),
                  ]),
                )),
              SliverReveal(key: ValueKey(shown.isEmpty), sliver: SliverList.builder(itemCount: shown.length, itemBuilder: (context, i) => _tile(shown[i], shown))),
            ]);
          },
        ),
      ],
      SliverList.list(children: tail),
    ];
  }

  @override
  Widget build(BuildContext context) => CustomScrollView(slivers: [...slivers(context), const SliverPadding(padding: EdgeInsets.only(bottom: AppStyle.pagePadding))]);

  Widget _header(BuildContext context, String title, String? note, {Widget? trailing}) => Padding(
        padding: EdgeInsetsDirectional.fromSTEB(4, 0, trailing == null ? 4 : 0, 8),
        // A long translation puts the switch on a line of its own rather
        // than pushing it out of the panel.
        child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
            if (note != null) ...[const SizedBox(width: 8), Flexible(child: Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.colors.outline, fontSize: 12)))],
          ]),
          if (trailing != null) trailing,
        ]),
      );

  /// 接下来播放 and the related videos it does not already list, worked
  /// out again only when the queue, the video or the related list changes:
  /// the panel rebuilds on every notify.
  (List<VideoItem>, List<VideoItem>) _upNextAndRelated() {
    final key = (controller.queue, controller.playing?.id, controller.relatedItems);
    if (_upNextMemo case (final known, final kept) when known == key) return kept;
    final items = controller.upNext;
    final queued = {for (final item in items) item.id};
    final kept = (items, [for (final item in controller.relatedItems) if (!queued.contains(item.id)) item]);
    _upNextMemo = (key, kept);
    return kept;
  }

  /// The ways the related videos can be narrowed, as YouTube offers them
  /// beside a video, each with what it shows; only those that show
  /// something, after 全部. Kept while what they come from stays.
  List<(_Related, String, List<VideoItem>)> _relatedChoices(VideoItem? playing, List<VideoItem> related) {
    final key = (related, playing, controller.details?.channelId, controller.homeFeed?.items, controller.library?.revision);
    if (_choicesMemo case (final known, final kept) when known == key) return kept;
    final kept = _workOutRelatedChoices(playing, related);
    _choicesMemo = (key, kept);
    return kept;
  }

  List<(_Related, String, List<VideoItem>)> _workOutRelatedChoices(VideoItem? playing, List<VideoItem> related) {
    final channelId = playing?.channelId ?? controller.details?.channelId;
    final channel = playing?.channel ?? '';
    bool own(VideoItem item) => channelId != null && item.channelId != null ? item.channelId == channelId : channel.isNotEmpty && item.channel == channel;
    final library = controller.library;
    final monthAgo = DateTime.now().subtract(const Duration(days: 30));
    final forYou = [for (final item in controller.homeFeed?.items ?? const <VideoItem>[]) if (item.id != playing?.id) item];
    final choices = [
      (_Related.all, tr('All'), related),
      // Watching a live, other lives come next to it.
      if (playing?.isLive ?? false) (_Related.live, tr('Live'), [for (final item in related) if (item.isLive) item]),
      (_Related.channel, tr('From {0}', [channel]), [for (final item in related) if (own(item)) item]),
      (_Related.others, tr('Related content'), [for (final item in related) if (!own(item)) item]),
      (_Related.forYou, tr('For you'), forYou),
      (_Related.recent, tr('Recently uploaded'), [for (final item in related) if (item.published?.isAfter(monthAgo) ?? false) item]),
      (_Related.watched, tr('Watched'), [for (final item in related) if (library?.progressOf(item.id) != null) item]),
      if (!(playing?.isLive ?? false)) (_Related.live, tr('Live'), [for (final item in related) if (item.isLive) item]),
    ];
    return [
      for (final choice in choices)
        if (choice.$1 == _Related.all || (choice.$3.isNotEmpty && choice.$3.length < related.length) || (choice.$1 == _Related.forYou && choice.$3.isNotEmpty))
          if (choice.$1 != _Related.channel || channel.isNotEmpty) choice,
    ];
  }

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

/// The text scale for subtitles on Android in a player [size] tall, as
/// ExoPlayer and YouTube's app size them on phones, tablets and TVs: 5.33%
/// of the player's height times the caption size from Android's settings
/// ([system]), never under 12 px. Scaling by area against 1080p would leave
/// a phone's upright player with 9 px text. A [small] window (picture in
/// picture, the mini player) keeps the same share of its height down to
/// 6 px, as ExoPlayer does there, so a line does not cover the picture.
/// A player taller than wide (full screen upright, for a portrait video)
/// counts no more than three quarters of its width: by its height the
/// letters were so large that a line held a few words.
double androidSubtitleScale(Size size, [double system = 1, bool small = false]) => max(small ? 6.0 : 12.0, min(size.height, size.width * 0.75) * 0.0533 * system) / 32;

/// What 模糊翻译 needs from the player: whether the second subtitle shows
/// plainly now, and what hovering and tapping it do.
typedef TranslationRevealing = ({ValueListenable<bool> shown, ValueChanged<bool> hover, VoidCallback tap});

/// What the learning pack needs from the player: the dictionary, and what
/// tapping a word of the main line does.
typedef SubtitleWords = ({Learning learning, void Function(WordToken token, String line) onWord, void Function(bool over)? onHover, void Function(int step)? onSwipe});

/// The words of the main video's subtitle line, to find the one tapped.
final _videoWords = RubyHits();

/// Amber for words above the learner's level, or light blue where the
/// subtitles are already yellow or orange.
Color _hardColorOn(Color? text) {
  if (text == null) return const Color(0xFFFFC23D);
  final hsv = HSVColor.fromColor(text);
  final yellowish = hsv.saturation > 0.35 && hsv.hue >= 20 && hsv.hue <= 75;
  return yellowish ? const Color(0xFF7FDBFF) : const Color(0xFFFFC23D);
}

SubtitleViewConfiguration subtitleViewFor(PlayerSettings settings, {Size? smallWindow, Object? secondary, bool byHeight = false, bool? libass, TranslationRevealing? reveal, SubtitleWords? words, String mainLanguage = '', String secondLanguage = ''}) {
  // The view scales by area against 1080p, which makes the text tiny in a
  // small window. There a line is about a twentieth of the picture's
  // height, as on a TV, but never under 13 px, which stays readable, nor
  // over the full-size text.
  final textScaler = smallWindow == null || byHeight ? null : TextScaler.linear(smallSubtitleScale(smallWindow));
  final paddingScale = smallWindow == null ? 1.0 : (smallWindow.shortestSide / 720).clamp(0.3, 1.0);
  final ghost = libass ?? settings.libassSubtitles;
  final blur = reveal != null && settings.blurSecondary && secondary != null;
  // libmpv draws, blurred too; the view lays the lines out unseen only
  // for 模糊翻译, which needs the second line's place.
  if (ghost && !blur) return const SubtitleViewConfiguration(visible: false);
  final border = settings.subtitleBorder;
  final lookUp = !ghost && (words?.learning.anyDictionary ?? false);
  // Each line in its own language's character forms: the default font
  // gives way to that language's, and the locale and fallback follow it.
  TextStyle style(String font, double scale, int color, double opacity, String language) => TextStyle(
        height: 1.3,
        fontSize: 32 * scale,
        fontFamily: font.isEmpty
            ? null
            : font == PlayerSettings.defaultSubtitleFont && cjkFormOf(language) != null && !(Platform.isAndroid || Platform.isIOS)
                ? PlayerSettings.fontForThisSystem(font, language: language)
                : font,
        locale: languageStyle(language)?.locale,
        // Where the font is missing (another system), the bundled one.
        fontFamilyFallback: languageStyle(language)?.fontFamilyFallback ?? [bundledFont, ...downloadedScriptFamilies, blankFont],
        letterSpacing: 0.0,
        wordSpacing: 0.0,
        color: Color(0xFF000000 | color).withValues(alpha: opacity),
        fontWeight: settings.subtitleBold ? FontWeight.w700 : FontWeight.normal,
        backgroundColor: settings.subtitleBackground ? Color.fromRGBO(0, 0, 0, 0.67 * opacity) : null,
      );
  return SubtitleViewConfiguration(
    style: style(settings.subtitleFont, settings.subtitleScale, settings.subtitleColor, settings.subtitleOpacity, mainLanguage),
    secondaryStyle: style(settings.secondaryFont, settings.secondaryScale, settings.secondaryColor, settings.secondaryOpacity, secondLanguage),
    // sub-pos counts from the top; 100 is the bottom edge.
    textScaler: textScaler,
    scaleFor: byHeight ? (size) => TextScaler.linear(androidSubtitleScale(size, Device.captionScale, smallWindow != null)) : null,
    spacing: 6,
    // The same solid outline libmpv draws (LibassLook.border), so either
    // drawing them looks alike.
    outline: settings.subtitleBackground ? 0 : LibassLook.outlineFor(border),
    secondaryKey: secondary,
    ghost: ghost,
    blurSecondary: blur,
    secondaryShown: reveal?.shown,
    onSecondaryHover: reveal?.hover,
    onSecondaryTap: reveal?.tap,
    mainLine: !lookUp
        ? null
        : (text, style, scaler, outline) {
            final tokens = words!.learning.wordsOf(text);
            if (tokens == null) return null;
            return LayoutBuilder(
                builder: (context, constraints) => ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.9),
                  child: ValueListenableBuilder(
                    valueListenable: _videoWords.selection,
                    builder: (context, chosen, child) => ChineseRubyLine(
                    tokens: tokens,
                    style: style,
                    textScaler: scaler,
                    outline: outline,
                    alignment: WrapAlignment.center,
                    pinyin: words.learning.showPinyin,
                    hard: words.learning.isHard,
                    hardColor: _hardColorOn(style.color),
                    known: words.learning.book == null || !words.learning.unlocked ? null : knownWordsOf(words.learning.book!).knows,
                    hits: _videoWords,
                  ),
                  ),
                ),
              );
          },
    mainHit: !lookUp ? null : (global) => _videoWords.wordAt(global) != null,
    onMainTap: !lookUp
        ? null
        : (global) {
            final token = _videoWords.wordAt(global);
            if (token != null) words!.onWord(token, _videoWords.line);
          },
    onMainHover: !lookUp ? null : words!.onHover,
    // A press held on a word and drawn to another looks up the words
    // between as one, such as a phrase or a name.
    onMainSelect: !lookUp
        ? null
        : (from, to, done) {
            final token = _videoWords.select(from, to, done: done);
            if (token != null) words!.onWord(token, _videoWords.line);
          },
    onMainSwipe: !lookUp ? null : words!.onSwipe,
    padding: EdgeInsets.fromLTRB(16 * paddingScale, 0, 16 * paddingScale, (24 + (100 - settings.subtitlePosition) * 4.0) * paddingScale),
  );
}

/// A phone's channel, title and action row on their own, for tests.
@visibleForTesting
Widget debugPhoneIntro(AppController controller) => Column(children: [_PhoneDetails(controller: controller), const SizedBox(height: 12), _PhoneActions(controller: controller)]);
