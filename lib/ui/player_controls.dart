// Player controls adapted from PiliNara (lib/plugin/pl_player/view/view.dart,
// widgets/bottom_control.dart, app_bar_ani.dart, play_pause_btn.dart,
// common_btn.dart, models/video_fit_type.dart and
// lib/pages/video/widgets/header_control.dart).
//
// PiliNara: https://github.com/Starfallan/PiliNara
// Copyright (C) PiliNara contributors.
// Adapted for YTPlus under the GNU General Public License, version 3 or
// later. Changes: the controls drive media_kit through YTPlus's
// AppController instead of PiliNara's PlPlayerController and GetX; touch
// gestures, danmaku and Bilibili-only buttons are left out, and desktop
// mouse handling (hover to show, wheel for volume) is kept.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../app/app_controller.dart';
import '../models.dart' show Chapter;
import '../player_settings.dart';
import '../widgets/pilinara_settings_tiles.dart';
import '../widgets/video_progress_bar.dart';
import 'common.dart';
import 'pages/settings_sections.dart' show trimSpeed, qualityLabel;
import 'pages/settings_subpages.dart';
import 'player_shortcuts.dart';
import 'player_stats.dart';
import 'video_texture_size.dart';

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

  const VideoFit(this.label, this.fit, [this.aspectRatio]);
  final String label;
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

  AppController get _controller => widget.controller;
  Player get _player => widget.player;

  @override
  void initState() {
    super.initState();
    videoFit.addListener(_applyFit);
    // Hides the pointer together with the bars.
    _animation.addStatusListener((_) {
      if (mounted) setState(() {});
    });
    _subscriptions.addAll([
      _player.stream.playing.listen((playing) {
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
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _hideTimer?.cancel();
    _feedbackTimer?.cancel();
    _animation.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _applyFit() {
    final fit = videoFit.value;
    final width = _player.state.width ?? 0;
    final height = _player.state.height ?? 0;
    // update() cannot clear an aspect ratio, so the automatic modes pass
    // the video's own one.
    final ratio = fit.aspectRatio ?? (width > 0 && height > 0 ? width / height : 16 / 9);
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
    final shortcuts = playerShortcuts(_controller, () => widget.state, onFeedback: _showFeedback);
    final controls = _controls(fullscreen, shortcuts);
    final video = _controller.videoController;
    return video == null ? controls : VideoTextureSize(controller: video, fullscreen: fullscreen, child: controls);
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
                ),
                _buffering(),
                if (_feedback case (final icon, final text)) Center(child: IgnorePointer(child: _FeedbackBubble(icon: icon, text: text))),
                if (_controller.showStats) Positioned(left: 12, top: fullscreen ? 64 : 52, child: PlayerStats(player: _player)),
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
  Widget _chapterMenu() => StreamBuilder<Duration>(
        stream: _player.stream.position,
        initialData: _player.state.position,
        builder: (context, _) {
          final chapters = _chapters;
          final current = Chapter.at(chapters, _player.state.position);
          return _PopupMenu<int>(
            tooltip: '章节',
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

  Widget _topBar(BuildContext context, bool fullscreen) {
    final item = _controller.playing;
    final details = _controller.details;
    final title = details?.title.isNotEmpty == true ? details!.title : item?.title ?? '';
    return Padding(
      padding: EdgeInsets.fromLTRB(fullscreen ? 8 : 12, fullscreen ? 10 : 4, 8, 16),
      child: Row(children: [
        if (fullscreen)
          _IconButton(tooltip: '返回', icon: Icons.arrow_back_ios_new_rounded, size: 18, onTap: () => unawaited(widget.state?.exitFullscreen())),
        if (fullscreen) const SizedBox(width: 6),
        Expanded(
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: fullscreen ? 16 : 14)),
        ),
        if (_controller.sleepAt != null || _controller.sleepAfterCurrent)
          const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Tooltip(message: '定时关闭已开启', child: Icon(Icons.bedtime_outlined, color: Colors.white, size: 18))),
        _IconButton(tooltip: '播放信息 (I)', icon: Icons.info_outline_rounded, size: 19, onTap: _controller.toggleStats),
        _IconButton(tooltip: '更多设置', icon: Icons.more_vert_rounded, size: 20, onTap: () => _showMore(context)),
      ]),
    );
  }

  Widget _bottomBar(BuildContext context, bool fullscreen) {
    final primary = Theme.of(context).colorScheme.inversePrimary;
    final width = fullscreen ? 42.0 : 35.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: StreamBuilder<Duration>(
            stream: _player.stream.position,
            initialData: _player.state.position,
            builder: (context, _) => VideoProgressBar(
              position: _player.state.position,
              buffered: _player.state.buffer,
              total: _player.state.duration,
              color: primary,
              segments: [
                for (final s in _controller.segments) ProgressSegment(s.start, s.end, _segmentColors[s.category] ?? const Color(0xFF00D400)),
              ],
              chapterStarts: [for (final c in _chapters) c.start],
              labelOf: _chapters.isEmpty ? null : (time) => '${formatPlaybackTime(time)} · ${Chapter.at(_chapters, time)?.title ?? ''}',
              onSeek: (time) => unawaited(_player.seek(time)),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Row(children: [
          _PlayPauseButton(player: _player),
          if (_controller.hasNext)
            _IconButton(tooltip: '下一个 (Shift+N)', icon: Icons.skip_next_rounded, size: 22, width: width, onTap: () => unawaited(_controller.playNext())),
          const SizedBox(width: 4),
          StreamBuilder<Duration>(
            stream: _player.stream.position,
            initialData: _player.state.position,
            builder: (context, _) => Text(
              '${formatPlaybackTime(_player.state.position)} / ${formatPlaybackTime(_player.state.duration)}',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
          if (_chapters.isNotEmpty) Flexible(child: _chapterMenu()),
          const Spacer(),
          _VolumeButton(player: _player, controller: _controller, onMenuOpened: _menuOpened, onMenuClosed: _menuClosed),
          ValueListenableBuilder(
            valueListenable: videoFit,
            builder: (context, fit, _) => _TextMenu<VideoFit>(
              tooltip: '画面比例',
              label: fit.label,
              value: fit,
              values: [for (final f in VideoFit.values) (f, f.label)],
              onSelected: (f) => videoFit.value = f,
              onOpened: _menuOpened,
              onClosed: _menuClosed,
            ),
          ),
          _subtitleMenu(width),
          StreamBuilder<double>(
            stream: _player.stream.rate,
            initialData: _player.state.rate,
            builder: (context, _) => _TextMenu<double>(
              tooltip: '倍速',
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
              return _TextMenu<int>(
                tooltip: '画质',
                label: height > 0 ? '${height}P' : (max == 0 ? '自动' : '${max}P'),
                value: max,
                values: [for (final h in _controller.qualityChoices) (h, h == 0 ? '自动' : '${h}P')],
                onSelected: (h) => unawaited(_controller.setMaxHeight(h)),
                onOpened: _menuOpened,
                onClosed: _menuClosed,
              );
            },
          ),
          _IconButton(
            tooltip: fullscreen ? '退出全屏 (F)' : '全屏 (F)',
            icon: fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
            size: 24,
            width: width,
            onTap: () => unawaited(widget.state?.toggleFullscreen()),
          ),
        ]),
      ]),
    );
  }

  Widget _subtitleMenu(double width) => StreamBuilder<Track>(
        stream: _player.stream.track,
        initialData: _player.state.track,
        builder: (context, _) {
          final tracks = _player.state.tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
          final current = _player.state.track.subtitle;
          final on = current.id != 'no' && current.id != 'auto';
          if (tracks.isEmpty) return const SizedBox.shrink();
          return _PopupMenu<String>(
            tooltip: '字幕',
            value: current.id,
            items: [('no', '关闭字幕'), for (final t in tracks) (t.id, _trackLabel(t.id, t.title, t.language))],
            onSelected: (id) => unawaited(_player.setSubtitleTrack(id == 'no' ? SubtitleTrack.no() : tracks.firstWhere((t) => t.id == id))),
            onOpened: _menuOpened,
            onClosed: _menuClosed,
            child: SizedBox(
              width: width,
              height: 30,
              child: Icon(on ? Icons.closed_caption_rounded : Icons.closed_caption_off_outlined, size: 22, color: Colors.white),
            ),
          );
        },
      );

  /// PiliNara's header "更多" sheet: format, order, subtitles, sleep timer,
  /// playback info and reload.
  Future<void> _showMore(BuildContext context) async {
    _menuOpened();
    final settings = _controller.settings;
    final audio = _player.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
    String sleepLabel() {
      if (_controller.sleepAfterCurrent) return '播完当前视频后暂停';
      final at = _controller.sleepAt;
      if (at == null) return '未开启';
      final left = at.difference(DateTime.now());
      return '${left.inMinutes + 1} 分钟后暂停';
    }

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (sheet) {
        Widget item(IconData icon, String title, String? subtitle, VoidCallback onTap) => ListTile(
              dense: true,
              leading: Icon(icon, size: 20),
              title: Text(title),
              subtitle: subtitle == null ? null : Text(subtitle, style: TextStyle(color: Theme.of(sheet).colorScheme.outline, fontSize: 12)),
              onTap: () {
                Navigator.pop(sheet);
                onTap();
              },
            );
        return SafeArea(
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 12), children: [
            item(Icons.high_quality_outlined, '选择画质', qualityLabel(settings.maxHeight), () {
              pickFromDialog<int>(context, title: '选择画质', value: settings.maxHeight, values: [for (final h in _controller.qualityChoices) (h, qualityLabel(h))], onSelected: _controller.setMaxHeight);
            }),
            item(Icons.music_note_outlined, '选择音质', settings.audioQuality.label, () {
              pickFromDialog<AudioQuality>(
                context,
                title: '选择音质',
                value: settings.audioQuality,
                values: [for (final q in AudioQuality.values) (q, q.label)],
                onSelected: (q) => _controller.reloadVideo(_controller.settings.copyWith(audioQuality: q)),
              );
            }),
            item(Icons.movie_filter_outlined, '解码格式', settings.codec.label, () {
              pickFromDialog<CodecPreference>(
                context,
                title: '解码格式',
                value: settings.codec,
                values: [for (final c in CodecPreference.values) (c, c.label)],
                onSelected: (c) => _controller.reloadVideo(_controller.settings.copyWith(codec: c)),
              );
            }),
            if (audio.length > 1)
              item(Icons.audiotrack_rounded, '选择音轨', _trackLabel(_player.state.track.audio.id, _player.state.track.audio.title, _player.state.track.audio.language), () {
                pickFromDialog<String>(
                  context,
                  title: '选择音轨',
                  value: _player.state.track.audio.id,
                  values: [for (final t in audio) (t.id, _trackLabel(t.id, t.title, t.language))],
                  onSelected: (id) => _player.setAudioTrack(audio.firstWhere((t) => t.id == id)),
                );
              }),
            item(Icons.repeat_rounded, '播放顺序', settings.playOrder.label, () {
              pickFromDialog<PlayOrder>(context, title: '播放顺序', value: settings.playOrder, values: [for (final o in PlayOrder.values) (o, o.label)], onSelected: _controller.setPlayOrder);
            }),
            item(Icons.subtitles_outlined, '字幕设置', '${settings.subtitleMode.label} · ${settings.subtitleLanguage.label}', () => openSubtitleSettings(context, _controller)),
            item(Icons.tune_rounded, '画面与音画同步调节', null, () => openPictureSettings(context, _controller)),
            item(Icons.bedtime_outlined, '定时关闭', sleepLabel(), () => _pickSleepTimer(context)),
            item(Icons.info_outline_rounded, '播放信息', _controller.showStats ? '显示中' : null, _controller.toggleStats),
            item(Icons.refresh_rounded, '重载视频', '从当前位置重新加载', () => unawaited(_controller.reloadVideo())),
            item(Icons.keyboard_outlined, '快捷键', null, () => showShortcutHelp(context, _controller.preferences)),
          ]),
        );
      },
    );
    _menuClosed();
  }

  Future<void> _pickSleepTimer(BuildContext context) async {
    const off = -1;
    const afterCurrent = 0;
    final current = _controller.sleepAfterCurrent ? afterCurrent : (_controller.sleepAt == null ? off : null);
    await pickFromDialog<int?>(
      context,
      title: '定时关闭',
      value: current,
      values: const [(off, '不开启'), (afterCurrent, '播完当前视频后'), (15, '15 分钟'), (30, '30 分钟'), (45, '45 分钟'), (60, '60 分钟'), (90, '90 分钟')],
      onSelected: (minutes) {
        if (minutes == null || minutes == off) {
          _controller.setSleepTimer(null);
        } else if (minutes == afterCurrent) {
          _controller.setSleepTimer(null, afterCurrent: true);
        } else {
          _controller.setSleepTimer(Duration(minutes: minutes));
        }
      },
    );
  }

  static String _trackLabel(String id, String? title, String? language) {
    final parts = [if (title != null && title.isNotEmpty) title, if (language != null && language.isNotEmpty) language];
    return parts.isEmpty ? '轨道 $id' : parts.join(' · ');
  }
}

/// PiliNara's `ComBtn`: a bare white icon with a tooltip.
class _IconButton extends StatelessWidget {
  const _IconButton({required this.tooltip, required this.icon, required this.onTap, this.size = 22, this.width = 34});
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double width;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox(width: width, height: 34, child: Icon(icon, size: size, color: Colors.white)),
          ),
        ),
      );
}

/// PiliNara's `PlayOrPauseButton`, animating between the two icons.
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
        message: '播放/暂停 (空格)',
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

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
        tooltip: tooltip,
        requestFocus: false,
        initialValue: value,
        color: Colors.black.withValues(alpha: 0.8),
        menuPadding: EdgeInsets.zero,
        position: PopupMenuPosition.over,
        onOpened: onOpened,
        onCanceled: onClosed,
        onSelected: (v) {
          onClosed();
          onSelected(v);
        },
        itemBuilder: (context) => [
          for (final (item, label) in items)
            PopupMenuItem<T>(
              height: 35,
              padding: const EdgeInsets.only(left: 30, right: 30),
              value: item,
              child: Text(label, style: item == value ? _menuText.copyWith(color: Theme.of(context).colorScheme.inversePrimary) : _menuText),
            ),
        ],
        child: child,
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
                tooltip: volume == 0 ? '取消静音 (M)' : '静音 (M)',
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
