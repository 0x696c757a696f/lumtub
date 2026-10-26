// Player controls adapted from PiliNara (lib/plugin/pl_player/view/view.dart,
// widgets/bottom_control.dart, app_bar_ani.dart, play_pause_btn.dart,
// common_btn.dart, models/video_fit_type.dart and
// lib/pages/video/widgets/header_control.dart).
//
// PiliNara: https://github.com/Starfallan/PiliNara
// Copyright (C) PiliNara contributors.
// Adapted for Lumtub under the GNU General Public License, version 3 or
// later. Changes: the controls drive media_kit through Lumtub's
// AppController instead of PiliNara's PlPlayerController and GetX; touch
// gestures, danmaku and Bilibili-only buttons are left out, and desktop
// mouse handling (hover to show, wheel for volume) is kept.

import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../app/app_controller.dart';
import '../heatmap.dart';
import '../keep_awake.dart';
import '../picture_transform.dart';
import '../storyboard.dart';
import '../models.dart' show Chapter;
import '../format_policy.dart';
import '../player_settings.dart';
import '../widgets/mini_progress_line.dart';
import '../widgets/video_progress_bar.dart';
import 'cast_ui.dart';
import 'common.dart';
import 'format_policy_dialogs.dart';
import 'pages/settings_sections.dart' show trimSpeed, qualityLabel;
import 'pages/settings_subpages.dart';
import 'player_shortcuts.dart';
import 'player_panel.dart';
import 'subtitle_panel.dart';
import 'player_stats.dart';
import 'screenshot_action.dart';
import 'storyboard_preview.dart';
import 'theater_mode.dart';
import 'video_box.dart';
import 'video_aspect.dart';
import '../l10n/l10n.dart';

/// Picture sizing, from PiliNara's `VideoFitType`.
enum VideoFit {
  contain('自动', BoxFit.contain),
  fill('拉伸', BoxFit.fill),
  cover('裁剪', BoxFit.cover),
  fitWidth('等宽', BoxFit.fitWidth),
  fitHeight('等高', BoxFit.fitHeight),
  none('原始', BoxFit.none),
  ratio4x3('4:3', BoxFit.fill, 4 / 3),
  ratio16x9('16:9', BoxFit.fill, 16 / 9);

  const VideoFit(this._label, this.fit, [this.aspectRatio]);
  final String _label;
  String get label => tr(_label);
  final BoxFit fit;
  final double? aspectRatio;
}

/// The chosen [VideoFit]; kept for the session like PiliNara keeps it per
/// player.
final videoFit = ValueNotifier(VideoFit.contain);

/// Colours of the SponsorBlock categories on the progress bar, as the
/// SponsorBlock extension draws them.
const _segmentColors = {
  'sponsor': Color(0xFF00D400),
  'selfpromo': Color(0xFFFFFF00),
  'interaction': Color(0xFFCC00FF),
  'intro': Color(0xFF00FFFF),
  'outro': Color(0xFF0202ED),
  'preview': Color(0xFF008FD6),
  'music_offtopic': Color(0xFFFF9900),
  'filler': Color(0xFF7300FF),
};

const _menuText = TextStyle(color: Colors.white, fontSize: 13);

/// PiliNara's control layer over the video: a title bar and a bottom bar
/// that slide in on hover, with the progress bar, play, time, fit,
/// subtitle, speed, quality and fullscreen buttons.
class PlayerControls extends StatefulWidget {
  const PlayerControls({super.key, required this.player, required this.state, required this.controller});
  final Player player;
  /// The video these controls sit on; null in tests, where there is no
  /// video surface.
  final VideoState? state;
  final AppController controller;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(vsync: this, duration: const Duration(milliseconds: 200), value: 1);
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _focus = FocusNode(debugLabel: 'player controls');
  Timer? _hideTimer;
  Timer? _feedbackTimer;
  (IconData, String)? _feedback;
  int _menus = 0;
  bool _hoveringBars = false;
  late final _transform = PictureTransform(_player);
  // What yt-dlp's extraction of the playing video offers for the bar.
  String? _infoFor;
  bool _infoBusy = false;
  String? _infoRead;
  Heatmap? _heatmap;
  ProgressPreview? _preview;

  AppController get _controller => widget.controller;
  Player get _player => widget.player;

  @override
  void initState() {
    super.initState();
    videoFit.addListener(_applyFit);
    _controller.coverVideo = videoFit.value != VideoFit.contain;
    _controller.addListener(_syncVideo);
    KeepAwake.hold(this, _player.state.playing && !_controller.audioOnly);
    // Hides the pointer together with the bars.
    _animation.addStatusListener((_) {
      if (mounted) setState(() {});
    });
    _subscriptions.addAll([
      // The next video may have another shape; the ratio set for the last
      // one would stretch it.
      _player.stream.width.listen((_) => _applyFit()),
      _player.stream.height.listen((_) => _applyFit()),
      _player.stream.duration.listen((_) => _syncVideo()),
      _player.stream.playing.listen((playing) {
        KeepAwake.hold(this, playing && !_controller.audioOnly);
        if (!playing) {
          _show();
        } else {
          _scheduleHide();
        }
      }),
      _player.stream.completed.listen((completed) {
        if (!completed || !_controller.preferences.exitFullscreenOnEnd || !mounted) return;
        if (isFullscreen(context) && _controller.stopsAfterEnd) unawaited(widget.state?.exitFullscreen());
      }),
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyFit());
    _scheduleHide();
  }

  @override
  void dispose() {
    videoFit.removeListener(_applyFit);
    _controller.removeListener(_syncVideo);
    KeepAwake.hold(this, false);
    _transform.dispose();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _hideTimer?.cancel();
    _feedbackTimer?.cancel();
    _animation.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Loads the bar's preview frames and replay curve once per video, from
  /// the extraction already made for playback, and resets mirroring and zoom
  /// for a new one. Tried again until the extraction is there.
  void _syncVideo() {
    final id = _controller.playing?.id;
    if (!mounted || id == null) return;
    if (_infoFor != id) {
      _infoFor = id;
      _infoRead = null;
      _heatmap = null;
      _preview = null;
      _transform.reset();
      if (mounted) setState(() {});
    } else if (_infoRead == id) {
      return;
    }
    if (_infoBusy) return;
    _infoBusy = true;
    _controller.playingInfo().then((info) {
      _infoBusy = false;
      if (!mounted || info == null || _controller.playing?.id != id) return;
      // Read once per video, also when it has neither: a live has no heatmap
      // or storyboard, and the controller notifies many times a second.
      _infoRead = id;
      final board = Storyboard.from(info);
      setState(() {
        _heatmap = Heatmap.from(info);
        _preview = board == null ? null : storyboardPreview(board, _controller.storyboardSheets);
      });
    });
  }

  void _applyFit() {
    final fit = videoFit.value;
    _controller.coverVideo = fit != VideoFit.contain;
    // update() cannot clear an aspect ratio, so the automatic modes pass
    // the video's own one.
    final ratio = videoAspectFor(fit.aspectRatio, _player.state.width, _player.state.height);
    widget.state?.update(fit: fit.fit, aspectRatio: ratio);
  }

  void _show() {
    _hideTimer?.cancel();
    if (_animation.status != AnimationStatus.forward && _animation.value < 1) _animation.forward();
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(Duration(seconds: _controller.preferences.controlsHideSeconds), () {
      if (!mounted || !_player.state.playing || _menus > 0 || _hoveringBars) return;
      _animation.reverse();
    });
  }

  /// The rate before a long press sped playback up, while it is held.
  double? _heldRate;

  void _holdSpeed(bool hold) {
    if (hold) {
      if (_heldRate != null || !_player.state.playing) return;
      final rate = _heldRate = _player.state.rate;
      final fast = max(2.0, rate * 2).clamp(0.25, 4.0);
      unawaited(_player.setRate(fast));
      _showFeedback(Icons.fast_forward_rounded, tr('{0}x 倍速中', [_trimRate(fast)]));
    } else if (_heldRate case final rate?) {
      _heldRate = null;
      unawaited(_player.setRate(rate));
    }
  }

  static String _trimRate(double rate) => rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : rate.toString();

  void _showFeedback(IconData icon, String text) {
    _feedbackTimer?.cancel();
    setState(() => _feedback = (icon, text));
    _feedbackTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _feedback = null);
    });
  }

  void _onScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final step = _controller.preferences.volumeStep.toDouble();
    unawaited(_controller.changeVolume(event.scrollDelta.dy < 0 ? step : -step).then((_) {
      final volume = _player.state.volume.round();
      _showFeedback(volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded, '$volume%');
    }));
  }

  /// Keeps the bars up while one of their menus is open.
  void _menuOpened() {
    _menus++;
    _show();
  }

  void _menuClosed() {
    if (_menus > 0) _menus--;
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final fullscreen = isFullscreen(context);
    final shortcuts = playerShortcuts(_controller, () => widget.state, onFeedback: _showFeedback, onScreenshot: () => unawaited(captureScreenshot(context, _controller, onFeedback: _showFeedback)));
    final controls = _controls(fullscreen, shortcuts);
    return VideoBox(controller: _controller, child: controls);
  }

  Widget _controls(bool fullscreen, Map<ShortcutActivator, VoidCallback> shortcuts) {
    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => MouseRegion(
            onHover: (_) => _show(),
            cursor: _animation.value == 0 ? SystemMouseCursors.none : MouseCursor.defer,
            child: Listener(
              onPointerSignal: _onScroll,
              child: Stack(fit: StackFit.expand, children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _focus.requestFocus();
                    unawaited(_player.playOrPause());
                    _show();
                  },
                  onDoubleTap: () => unawaited(widget.state?.toggleFullscreen()),
                  // Hold for 2x, as on YouTube and in PiliNara.
                  onLongPressStart: (_) => _holdSpeed(true),
                  onLongPressEnd: (_) => _holdSpeed(false),
                  onLongPressCancel: () => _holdSpeed(false),
                ),
                _buffering(),
                if (_feedback case (final icon, final text)) Center(child: IgnorePointer(child: _FeedbackBubble(icon: icon, text: text))),
                if (_controller.showStats) Positioned(left: 12, top: fullscreen ? 64 : 52, child: PlayerStats(player: _player)),
                if (_controller.preferences.progressLine.shows(fullscreen: fullscreen))
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: FadeTransition(
                        opacity: _animation.drive(Tween(begin: 1.0, end: 0.0)),
                        child: MiniProgressLine(player: _player, color: Theme.of(context).colorScheme.inversePrimary),
                      ),
                    ),
                  ),
                Positioned(left: 0, right: 0, top: 0, child: _bar(top: true, child: _topBar(context, fullscreen))),
                Positioned(left: 0, right: 0, bottom: 0, child: _bar(top: false, child: _bottomBar(context, fullscreen))),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  List<Chapter> get _chapters => _controller.details?.chapters ?? const [];

  /// The current chapter's title; opens the chapter list, as on YouTube.
  Widget _chapterMenu() {
    if (_chapters.isEmpty) return const SizedBox.shrink();
    // Rebuilt only when the position enters another chapter.
    int chapterAt(Duration position) {
      final chapters = _chapters;
      final current = Chapter.at(chapters, position);
      return current == null ? -1 : chapters.indexOf(current);
    }

    return StreamBuilder<int>(
        stream: _player.stream.position.map(chapterAt).distinct(),
        initialData: chapterAt(_player.state.position),
        builder: (context, _) {
          final chapters = _chapters;
          final current = Chapter.at(chapters, _player.state.position);
          return _PopupMenu<int>(
            tooltip: tr('章节'),
            value: current == null ? -1 : chapters.indexOf(current),
            items: [for (final (i, c) in chapters.indexed) (i, '${formatPlaybackTime(c.start)}  ${c.title}')],
            onSelected: (i) => unawaited(_player.seek(chapters[i].start)),
            onOpened: _menuOpened,
            onClosed: _menuClosed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Text('·  ${current?.title ?? chapters.first.title}  ›', style: _menuText, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          );
        },
      );
  }

  Widget _buffering() => StreamBuilder<bool>(
        stream: _player.stream.buffering,
        initialData: _player.state.buffering,
        builder: (context, snapshot) => snapshot.data == true
            ? const Center(child: IgnorePointer(child: SizedBox(width: 36, height: 36, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))))
            : const SizedBox.shrink(),
      );

  /// PiliNara's `AppBarAni`: a gradient bar that slides out of the edge.
  Widget _bar({required bool top, required Widget child}) => MouseRegion(
        onEnter: (_) => _hoveringBars = true,
        onExit: (_) {
          _hoveringBars = false;
          _scheduleHide();
        },
        child: SlideTransition(
          position: _animation.drive(Tween(begin: Offset(0, top ? -1 : 1.2), end: Offset.zero)),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: top ? Alignment.bottomCenter : Alignment.topCenter,
                end: top ? Alignment.topCenter : Alignment.bottomCenter,
                colors: const [Colors.transparent, Color(0xBF000000)],
              ),
            ),
            child: child,
          ),
        ),
      );

  /// Laid out as PiliNara's: 返回 and 主页 on the left, the title, then a
  /// row of switches.
  Widget _topBar(BuildContext context, bool fullscreen) {
    final item = _controller.playing;
    final details = _controller.details;
    final title = details?.title.isNotEmpty == true ? details!.title : item?.title ?? '';
    Future<void> leaveFullscreen() async {
      if (fullscreen) await widget.state?.exitFullscreen();
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(fullscreen ? 8 : 6, fullscreen ? 10 : 4, 8, 16),
      child: Row(children: [
        _IconButton(
          tooltip: fullscreen ? tr('退出全屏') : tr('返回'),
          icon: Icons.arrow_back_rounded,
          size: 20,
          onTap: () => fullscreen ? unawaited(leaveFullscreen()) : _controller.goBack(),
        ),
        _IconButton(
          tooltip: tr('主页'),
          icon: Icons.home_rounded,
          size: 20,
          onTap: () async {
            await leaveFullscreen();
            _controller.navigate(PageMode.home);
          },
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: fullscreen ? 16 : 14, fontWeight: FontWeight.w500)),
            if (fullscreen && (details?.channel ?? item?.channel ?? '').isNotEmpty)
              Text(details?.channel ?? item!.channel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),
        // Switches that are on show here, so the state stays visible after
        // they moved into 更多设置.
        for (final (on, icon, tip) in [
          (_controller.pinned, Icons.push_pin_rounded, tr('窗口置顶中')),
          (_controller.audioOnly, Icons.headphones_rounded, tr('听视频中')),
        ])
          if (on) Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Tooltip(message: tip, child: Icon(icon, color: Theme.of(context).colorScheme.inversePrimary, size: 17))),
        if (_controller.sleepAt != null || _controller.sleepAfterCurrent)
          Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Tooltip(message: tr('定时关闭已开启'), child: Icon(Icons.bedtime_outlined, color: Colors.white, size: 18))),
        _IconButton(
          tooltip: tr('投屏'),
          icon: _controller.cast.active ? Icons.cast_connected_rounded : Icons.cast_rounded,
          size: 19,
          active: _controller.cast.active,
          onTap: () => unawaited(showCastDialog(context, _controller)),
        ),
        _IconButton(
          tooltip: tr('画中画'),
          icon: Icons.picture_in_picture_alt_rounded,
          size: 19,
          onTap: () async {
            await leaveFullscreen();
            _controller.setPip(true);
          },
        ),
        _IconButton(tooltip: tr('更多设置'), icon: Icons.tune_rounded, size: 20, onTap: () => _showMore(context)),
      ]),
    );
  }

  Widget _bottomBar(BuildContext context, bool fullscreen) {
    final primary = Theme.of(context).colorScheme.inversePrimary;
    // Built here, once per rebuild of the bar, not on every position event.
    final segments = [
      for (final s in _controller.segments) ProgressSegment(s.start, s.end, _segmentColors[s.category] ?? const Color(0xFF00D400)),
    ];
    final chapterStarts = [for (final c in _chapters) c.start];
    final width = fullscreen ? 42.0 : 35.0;
    // Keep the action cluster anchored to the physical bottom-right edge in
    // fullscreen. The progress and playback information remain on the left.
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(fullscreen ? 18 : 10, 16, fullscreen ? 18 : 10, fullscreen ? 14 : 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: _PositionBuilder(
            player: _player,
            active: !_animation.isDismissed,
            builder: (context) => VideoProgressBar(
              position: _player.state.position,
              buffered: _player.state.buffer,
              total: _player.state.duration,
              color: primary,
              segments: segments,
              chapterStarts: chapterStarts,
              preview: _preview,
              heatmap: _controller.preferences.showHeatmap ? _heatmap?.values : null,
              labelOf: _chapters.isEmpty ? null : (time) => '${formatPlaybackTime(time)} · ${Chapter.at(_chapters, time)?.title ?? ''}',
              onSeek: (time) => unawaited(_player.seek(time)),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Row(children: [
          _PlayPauseButton(player: _player),
          if (_controller.hasNext)
            _IconButton(tooltip: tr('下一个 (Shift+N)'), icon: Icons.skip_next_rounded, size: 22, width: width, onTap: () => unawaited(_controller.playNext())),
          _VolumeButton(player: _player, controller: _controller, onMenuOpened: _menuOpened, onMenuClosed: _menuClosed),
          const SizedBox(width: 6),
          _PositionBuilder(
            player: _player,
            active: !_animation.isDismissed,
            seconds: true,
            builder: (context) => Text(
              '${formatPlaybackTime(_player.state.position)} / ${formatPlaybackTime(_player.state.duration)}',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
          Expanded(child: Align(alignment: Alignment.centerLeft, child: _chapterMenu())),
          _subtitleMenu(width),
          StreamBuilder<double>(
            stream: _player.stream.rate,
            initialData: _player.state.rate,
            builder: (context, _) => _TextMenu<double>(
              tooltip: tr('倍速'),
              label: '${trimSpeed(_player.state.rate)}X',
              value: _player.state.rate,
              values: [for (final speed in _controller.settings.speeds) (speed, '${trimSpeed(speed)}X')],
              onSelected: (speed) => unawaited(_player.setRate(speed)),
              onOpened: _menuOpened,
              onClosed: _menuClosed,
            ),
          ),
          StreamBuilder<int?>(
            stream: _player.stream.height,
            initialData: _player.state.height,
            builder: (context, _) {
              final height = _player.state.height ?? 0;
              final max = _controller.settings.maxHeight;
              final choices = _controller.qualityChoices;
              return _TextMenu<int>(
                tooltip: tr('画质'),
                label: height > 0 ? '${height}P' : (max == 0 ? tr('自动') : '${max}P'),
                // A limit above what this video offers plays its highest.
                value: choices.contains(max) ? max : height,
                values: [for (final h in choices) (h, h == 0 ? tr('自动') : '${h}P')],
                onSelected: (h) => unawaited(_controller.setMaxHeight(h)),
                onOpened: _menuOpened,
                onClosed: _menuClosed,
              );
            },
          ),
          if (!fullscreen)
            ValueListenableBuilder(
              valueListenable: theaterMode,
              builder: (context, theater, _) => _IconButton(
                tooltip: theater ? tr('退出剧场模式 (T)') : tr('剧场模式 (T)'),
                icon: Icons.crop_16_9_rounded,
                size: 22,
                width: width,
                active: theater,
                onTap: () => theaterMode.value = !theater,
              ),
            ),
          _IconButton(
            tooltip: fullscreen ? tr('退出全屏 (F)') : tr('全屏 (F)'),
            icon: fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
            size: 24,
            width: width,
            onTap: () => unawaited(widget.state?.toggleFullscreen()),
          ),
        ]),
        ]),
      ),
    );
  }

  Widget _subtitleMenu(double width) => StreamBuilder<Track>(
        stream: _player.stream.track,
        initialData: _player.state.track,
        builder: (context, _) {
          final current = _player.state.track.subtitle;
          final on = current.id != 'no' && current.id != 'auto';
          final hasTracks = _player.state.tracks.subtitle.any((t) => t.id != 'auto' && t.id != 'no');
          if (!hasTracks && (_controller.details?.subtitles ?? const []).isEmpty) return const SizedBox.shrink();
          return _IconButton(
            tooltip: tr('字幕'),
            width: width,
            icon: on ? Icons.closed_caption_rounded : Icons.closed_caption_off_outlined,
            active: _controller.secondarySubtitle != null,
            onTap: () => unawaited(_openSubtitles(context)),
          );
        },
      );

  Future<void> _openSubtitles(BuildContext context) async {
    _menuOpened();
    await showSubtitlePanel(context, _controller, _player, onSettings: () => openSubtitleSettings(context, _controller));
    _menuClosed();
  }

  /// The 更多 panel: PiliNara's header sheet, as a side panel whose
  /// choices apply at once while it stays open.
  Future<void> _showMore(BuildContext context) async {
    _menuOpened();
    await showPlayerPanel(
      context,
      title: tr('更多设置'),
      builder: (panel) => ListenableBuilder(listenable: Listenable.merge([_controller, _transform]), builder: (panel, _) => _moreItems(context, panel)),
    );
    _menuClosed();
  }

  Widget _moreItems(BuildContext context, BuildContext panel) {
    final settings = _controller.settings;
    final audio = _player.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
    // Steps that open a page or act on the picture close the panel first.
    void closeThen(VoidCallback then) {
      Navigator.of(panel).pop();
      then();
    }

    const sleepOff = -1;
    const sleepAfterCurrent = 0;
    final sleepAt = _controller.sleepAt;
    final sleeping = _controller.sleepAfterCurrent ? sleepAfterCurrent : (sleepAt == null ? sleepOff : null);
    final codecs = FormatPolicy.disabledNames(settings);
    return ListView(padding: const EdgeInsets.only(bottom: 16), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          PanelToggle(label: tr('窗口置顶'), icon: Icons.push_pin_outlined, value: _controller.pinned, onChanged: (_) => _controller.togglePinned()),
          PanelToggle(label: tr('听视频'), icon: Icons.headphones_rounded, value: _controller.audioOnly, onChanged: (_) => unawaited(_controller.toggleAudioOnly())),
          PanelToggle(label: tr('空降助手'), icon: Icons.shield_outlined, value: settings.sponsorBlock, onChanged: (_) => unawaited(_controller.toggleSponsorBlock())),
          PanelToggle(label: tr('播放信息'), icon: Icons.info_outline_rounded, value: _controller.showStats, onChanged: (_) => _controller.toggleStats()),
          PanelToggle(label: tr('镜像翻转'), icon: Icons.flip_rounded, value: _transform.mirrored, onChanged: (v) => unawaited(_transform.setMirrored(v))),
          PanelToggle(label: tr('应用内小窗'), icon: Icons.picture_in_picture_rounded, value: false, onChanged: (_) => closeThen(() async {
            if (isFullscreen(context)) await widget.state?.exitFullscreen();
            _controller.enterMini();
          })),
        ]),
      ),
      PanelHeading(tr('画面')),
      PanelChoices<int>(
        label: tr('画质'),
        icon: Icons.high_quality_outlined,
        value: settings.maxHeight,
        values: [for (final h in _controller.qualityChoices) (h, qualityLabel(h))],
        onSelected: _controller.setMaxHeight,
      ),
      ValueListenableBuilder(
        valueListenable: videoFit,
        builder: (context, fit, _) => PanelChoices<VideoFit>(
          label: tr('画面比例'),
          icon: Icons.aspect_ratio_rounded,
          value: fit,
          values: [for (final f in VideoFit.values) (f, f.label)],
          onSelected: (f) => videoFit.value = f,
        ),
      ),
      PanelChoices<double>(
        label: tr('画面缩放'),
        icon: Icons.zoom_in_rounded,
        value: _transform.zoom,
        values: [for (final z in PictureTransform.zoomLevels) (z, z == 1 ? tr('原始大小') : '${trimSpeed(z)}x')],
        onSelected: (z) => unawaited(_transform.setZoom(z)),
      ),
      PanelLink(label: tr('画面与音画同步调节'), icon: Icons.tune_rounded, onTap: () => closeThen(() => openPictureSettings(context, _controller))),
      PanelHeading(tr('声音')),
      PanelChoices<AudioQuality>(
        label: tr('音质'),
        icon: Icons.music_note_outlined,
        value: settings.audioQuality,
        values: [for (final q in AudioQuality.values) (q, q.label)],
        onSelected: (q) => unawaited(_controller.reloadVideo(_controller.settings.copyWith(audioQuality: q))),
      ),
      if (audio.length > 1)
        StreamBuilder<Track>(
          stream: _player.stream.track,
          builder: (context, _) => PanelChoices<String>(
            label: tr('音轨'),
            icon: Icons.audiotrack_rounded,
            value: _player.state.track.audio.id,
            values: [for (final t in audio) (t.id, _trackLabel(t.id, t.title, t.language))],
            onSelected: (id) => unawaited(_player.setAudioTrack(audio.firstWhere((t) => t.id == id))),
          ),
        ),
      PanelHeading(tr('播放')),
      PanelChoices<PlayOrder>(
        label: tr('播放顺序'),
        icon: Icons.repeat_rounded,
        value: settings.playOrder,
        values: [for (final o in PlayOrder.values) (o, o.label)],
        onSelected: _controller.setPlayOrder,
      ),
      PanelChoices<int?>(
        label: sleepAt == null ? tr('定时关闭') : tr('定时关闭（{0} 分钟后暂停）', [sleepAt.difference(DateTime.now()).inMinutes + 1]),
        icon: Icons.bedtime_outlined,
        value: sleeping,
        values: [(sleepOff, tr('不开启')), (sleepAfterCurrent, tr('播完当前视频后')), for (final m in const [15, 30, 45, 60, 90]) (m, tr('{0} 分钟', [m]))],
        onSelected: (minutes) {
          if (minutes == null || minutes == sleepOff) {
            _controller.setSleepTimer(null);
          } else if (minutes == sleepAfterCurrent) {
            _controller.setSleepTimer(null, afterCurrent: true);
          } else {
            _controller.setSleepTimer(Duration(minutes: minutes));
          }
        },
      ),
      PanelChoices<PlaybackStrategy>(
        label: tr('播放策略'),
        icon: Icons.movie_filter_outlined,
        value: settings.strategy,
        values: [for (final v in PlaybackStrategy.values) (v, v.label)],
        onSelected: (v) => unawaited(_controller.reloadVideo(_controller.settings.copyWith(strategy: v))),
      ),
      PanelLink(
        label: tr('禁用视频编码'),
        detail: codecs.isEmpty ? tr('无') : codecs,
        icon: Icons.block_outlined,
        onTap: () => pickDisabledCodecs(context, settings, (v) => _controller.reloadVideo(v)),
      ),
      PanelLink(
        label: tr('字幕'),
        detail: '${settings.subtitleMode.label} · ${settings.subtitleLanguage.label}',
        icon: Icons.subtitles_outlined,
        onTap: () => closeThen(() => unawaited(_openSubtitles(context))),
      ),
      PanelHeading(tr('工具')),
      PanelLink(label: tr('截图 (S)'), detail: tr('保存到“图片\\Lumtub”并复制'), icon: Icons.photo_camera_outlined, opens: false, onTap: () => closeThen(() => unawaited(captureScreenshot(context, _controller, onFeedback: _showFeedback)))),
      PanelLink(label: tr('重载视频'), detail: tr('从当前位置重新加载'), icon: Icons.refresh_rounded, opens: false, onTap: () => closeThen(() => unawaited(_controller.reloadVideo()))),
      PanelLink(label: tr('快捷键'), icon: Icons.keyboard_outlined, onTap: () => showShortcutHelp(context, _controller.preferences)),
    ]);
  }

  static String _trackLabel(String id, String? title, String? language) {
    final parts = [if (title != null && title.isNotEmpty) title, if (language != null && language.isNotEmpty) language];
    return parts.isEmpty ? tr('轨道 {0}', [id]) : parts.join(' · ');
  }
}

/// PiliNara's `ComBtn`: a bare white icon with a tooltip, with a soft
/// round highlight under the mouse.
class _IconButton extends StatelessWidget {
  const _IconButton({required this.tooltip, required this.icon, required this.onTap, this.size = 22, this.width = 34, this.active = false});
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double width;
  /// A switch that is on, drawn in the theme's color.
  final bool active;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: _Hover(
          onTap: onTap,
          child: SizedBox(width: width, height: 34, child: Icon(icon, size: size, color: active ? Theme.of(context).colorScheme.inversePrimary : Colors.white)),
        ),
      );
}

/// A pressable area of the bars: the click cursor and a translucent
/// rounded highlight while the mouse is over it.
class _Hover extends StatefulWidget {
  const _Hover({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _over = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _over = true),
        onExit: (_) => setState(() => _over = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(color: _over ? Colors.white.withValues(alpha: 0.14) : Colors.transparent, borderRadius: BorderRadius.circular(17)),
            child: widget.child,
          ),
        ),
      );
}

/// PiliNara's `PlayOrPauseButton`, animating between the two icons.
/// Rebuilds [builder] as the playback position moves, only while [active]
/// (the bars are on screen), and with [seconds] only when the whole second
/// changes. mpv reports the position on every frame.
class _PositionBuilder extends StatefulWidget {
  const _PositionBuilder({required this.player, required this.active, required this.builder, this.seconds = false});
  final Player player;
  final bool active;
  final bool seconds;
  final WidgetBuilder builder;

  @override
  State<_PositionBuilder> createState() => _PositionBuilderState();
}

class _PositionBuilderState extends State<_PositionBuilder> {
  StreamSubscription<Duration>? _subscription;
  int _shown = -1;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(_PositionBuilder old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active || old.player != widget.player) _listen();
  }

  void _listen() {
    unawaited(_subscription?.cancel());
    _subscription = !widget.active
        ? null
        : widget.player.stream.position.listen((position) {
            final mark = widget.seconds ? position.inSeconds : position.inMilliseconds;
            if (mark == _shown || !mounted) return;
            _shown = mark;
            setState(() {});
          });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

class _PlayPauseButton extends StatefulWidget {
  const _PlayPauseButton({required this.player});
  final Player player;

  @override
  State<_PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<_PlayPauseButton> with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(vsync: this, value: widget.player.state.playing ? 1 : 0, duration: const Duration(milliseconds: 200));
  late final StreamSubscription<bool> _subscription = widget.player.stream.playing.listen((playing) => playing ? _animation.forward() : _animation.reverse());

  @override
  void initState() {
    super.initState();
    _subscription;
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tr('播放/暂停 (空格)'),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(widget.player.playOrPause()),
            child: SizedBox(
              width: 42,
              height: 34,
              child: Center(child: AnimatedIcon(progress: _animation, icon: AnimatedIcons.play_pause, color: Colors.white, size: 20)),
            ),
          ),
        ),
      );
}

/// PiliNara's dark popup menu: 0.8 black, 35 high rows, 13px white text.
class _PopupMenu<T> extends StatelessWidget {
  const _PopupMenu({
    required this.tooltip,
    required this.value,
    required this.items,
    required this.onSelected,
    required this.onOpened,
    required this.onClosed,
    required this.child,
  });

  final String tooltip;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onSelected;
  final VoidCallback onOpened;
  final VoidCallback onClosed;
  final Widget child;

  static const _itemHeight = 36.0;
  static const _padding = 6.0;

  /// Opens the list just above the button, as the bars sit at the bottom,
  /// instead of over it.
  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay = Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final rect = Rect.fromPoints(box.localToGlobal(Offset.zero, ancestor: overlay), box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay));
    final height = items.length * _itemHeight + _padding * 2;
    final top = rect.top - height - 6;
    final position = top >= 8
        ? RelativeRect.fromLTRB(rect.left, top, overlay.size.width - rect.right, overlay.size.height - rect.top)
        : RelativeRect.fromRect(rect, Offset.zero & overlay.size);
    onOpened();
    final theme = Theme.of(context);
    final picked = await showMenu<T>(
      context: context,
      position: position,
      color: const Color(0xEB1F1F1F),
      elevation: 6,
      menuPadding: const EdgeInsets.symmetric(vertical: _padding),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      constraints: const BoxConstraints(minWidth: 112),
      items: [
        for (final (item, label) in items)
          PopupMenuItem<T>(
            height: _itemHeight,
            padding: const EdgeInsets.only(left: 12, right: 20),
            value: item,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 22, child: item == value ? Icon(Icons.check_rounded, size: 16, color: theme.colorScheme.inversePrimary) : null),
              Flexible(child: Text(label, style: item == value ? _menuText.copyWith(color: theme.colorScheme.inversePrimary, fontWeight: FontWeight.w600) : _menuText)),
            ]),
          ),
      ],
    );
    onClosed();
    if (picked != null && picked != value) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Builder(builder: (context) => _Hover(onTap: () => unawaited(_open(context)), child: child)),
      );
}

/// A menu shown as its current value in text, like PiliNara's speed, fit
/// and quality buttons.
class _TextMenu<T> extends StatelessWidget {
  const _TextMenu({
    required this.tooltip,
    required this.label,
    required this.value,
    required this.values,
    required this.onSelected,
    required this.onOpened,
    required this.onClosed,
  });

  final String tooltip;
  final String label;
  final T value;
  final List<(T, String)> values;
  final ValueChanged<T> onSelected;
  final VoidCallback onOpened;
  final VoidCallback onClosed;

  @override
  Widget build(BuildContext context) => _PopupMenu<T>(
        tooltip: tooltip,
        value: value,
        items: values,
        onSelected: onSelected,
        onOpened: onOpened,
        onClosed: onClosed,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), child: Text(label, style: _menuText)),
      );
}

/// Volume icon that mutes on click and shows a slider on hover.
class _VolumeButton extends StatefulWidget {
  const _VolumeButton({required this.player, required this.controller, required this.onMenuOpened, required this.onMenuClosed});
  final Player player;
  final AppController controller;
  final VoidCallback onMenuOpened;
  final VoidCallback onMenuClosed;

  @override
  State<_VolumeButton> createState() => _VolumeButtonState();
}

class _VolumeButtonState extends State<_VolumeButton> {
  bool _open = false;

  void _setOpen(bool open) {
    if (open == _open) return;
    setState(() => _open = open);
    open ? widget.onMenuOpened() : widget.onMenuClosed();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => _setOpen(true),
        onExit: (_) => _setOpen(false),
        child: StreamBuilder<double>(
          stream: widget.player.stream.volume,
          initialData: widget.player.state.volume,
          builder: (context, _) {
            final volume = widget.player.state.volume;
            final max = widget.controller.settings.volumeMax.toDouble();
            return Row(mainAxisSize: MainAxisSize.min, children: [
              _IconButton(
                tooltip: volume == 0 ? tr('取消静音 (M)') : tr('静音 (M)'),
                icon: volume == 0 ? Icons.volume_off_rounded : (volume < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
                onTap: () => unawaited(widget.controller.toggleMute()),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 150),
                child: _open
                    ? SizedBox(
                        width: 96,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: SliderComponentShape.noOverlay,
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white30,
                            thumbColor: Colors.white,
                          ),
                          child: Slider(value: volume.clamp(0, max), max: max, onChanged: (v) => unawaited(widget.player.setVolume(v))),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ]);
          },
        ),
      );
}

/// The seek, volume and mute indicator in the middle of the video.
class _FeedbackBubble extends StatelessWidget {
  const _FeedbackBubble({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: const Color(0x88000000), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 13)),
        ]),
      );
}
