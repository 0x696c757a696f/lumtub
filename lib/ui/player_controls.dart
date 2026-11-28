import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../app/app_controller.dart';
import '../app_preferences.dart' show AppPreferences, rateText;
import '../app_window.dart';
import '../device.dart';
import '../format_policy.dart';
import '../heatmap.dart';
import '../keep_awake.dart';
import '../l10n/l10n.dart';
import '../models.dart';
import '../picture_transform.dart';
import '../player_settings.dart';
import '../right_click.dart';
import '../shadowing.dart';
import '../skins/skin.dart';
import '../stream_resolver.dart';
import '../system_env.dart';
import '../translation.dart';
import '../video_codec.dart';
import '../wheel_gesture.dart';
import '../widgets/mini_progress_line.dart';
import '../widgets/position_ticks.dart';
import '../widgets/video_progress_bar.dart';
import '../window_frame.dart';
import '../youtube_account.dart';
import 'accessibility.dart';
import 'app_icons.dart';
import 'cast_ui.dart';
import 'common.dart';
import 'danmaku_panel.dart';
import 'fill_window.dart';
import 'format_policy_dialogs.dart';
import 'haptics.dart';
import 'learning_drawer.dart' show LearningDrawerHandle;
import 'lights_off.dart';
import 'motion.dart';
import 'pages/settings_sections.dart' show qualityLabel, trimSpeed;
import 'pages/settings_subpages.dart' show openPictureSettings;
import 'player_panel.dart';
import 'player_shortcuts.dart';
import 'player_stats.dart';
import 'screenshot_action.dart';
import 'storyboard_preview.dart';
import 'subtitle_list_panel.dart';
import 'subtitle_panel.dart';
import 'subtitle_style_panel.dart';
import 'theater_mode.dart';
import 'theme.dart';
import 'video_aspect.dart';
import 'video_box.dart';
import 'window_chrome.dart';

part 'player_controls_bottom.dart';
part 'player_controls_panel.dart';
part 'player_controls_widgets.dart';

/// How the picture is fitted into the player.
enum VideoFit {
  contain('Auto', BoxFit.contain),
  fill('Stretch', BoxFit.fill),
  cover('Crop', BoxFit.cover),
  fitWidth('Monospace', BoxFit.fitWidth),
  fitHeight('Equal height', BoxFit.fitHeight),
  none('Original', BoxFit.none),
  ratio4x3('4:3', BoxFit.fill, 4 / 3),
  ratio16x9('16:9', BoxFit.fill, 16 / 9);

  const VideoFit(this._label, this.fit, [this.aspectRatio]);
  final String _label;
  final BoxFit fit;
  final double? aspectRatio;

  String get label => tr(_label);
}

/// The fit chosen for the session, shared by every player.
final videoFit = ValueNotifier(VideoFit.contain);

/// The name of an audio language in a menu: `Spanish (US) (original)`.
String audioLanguageLabel(AudioLanguage language) {
  final parts = language.code.split('-')..remove('desc');
  final name = TranslationLanguage.ofTag(parts.first)?.label ?? language.code;
  final label = parts.length > 1 ? '$name (${parts.skip(1).join('-')})' : name;
  return switch (language.kind) {
    'original' => tr('{0} (original)', [label]),
    'auto' => tr('{0} (automatic dub)', [label]),
    'described' => tr('{0} (audio description)', [label]),
    _ => label,
  };
}

/// The name of an audio track in a menu. yt-dlp names formats like
/// `251-4 - audio only (English (US) original (default), medium)`.
String trackLabel(String id, String? title, String? language) {
  final match = RegExp(r'^(\d+)(-\w+)? - audio only \((.*)\)$').firstMatch(title ?? '');
  if (match != null) {
    final codec = switch (int.parse(match[1]!)) {
      249 || 250 || 251 => 'Opus',
      139 || 140 || 141 => 'AAC',
      _ => null,
    };
    return [
      match[3]!,
      if (codec != null) codec,
      if ((match[2] ?? '').contains('drc')) tr('Volume normalization'),
    ].join(' · ');
  }
  final parts = [
    if (title != null && title.isNotEmpty) title,
    if (language != null && language.isNotEmpty) language,
  ];
  return parts.isEmpty ? tr('Track {0}', [id]) : parts.join(' · ');
}

const _sponsorColors = {
  'sponsor': Color(0xFF00D400),
  'selfpromo': Color(0xFFFFFF00),
  'interaction': Color(0xFFCC00FF),
  'intro': Color(0xFF00FFFF),
  'outro': Color(0xFF0202ED),
  'preview': Color(0xFF008FD6),
  'music_offtopic': Color(0xFFFF9900),
  'filler': Color(0xFF7300FF),
};

bool _isTouch(PointerDeviceKind? kind) => kind == PointerDeviceKind.touch || kind == PointerDeviceKind.stylus || kind == PointerDeviceKind.invertedStylus;

/// The controls over the video: bars, gestures, keys and the panels they open.
class PlayerControls extends StatefulWidget {
  const PlayerControls({super.key, required this.player, required this.state, required this.controller});
  final Player player;
  final VideoState? state;
  final AppController controller;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> with SingleTickerProviderStateMixin {
  late final AnimationController _bars = AnimationController(vsync: this, duration: Motion.of(Ease.fade), value: 1);
  final _focus = FocusNode(debugLabel: 'player controls', skipTraversal: true);
  final _bottomKey = GlobalKey();
  late final PictureTransform _picture = PictureTransform(widget.player);
  final _feedback = ValueNotifier<({IconData icon, String text})?>(null);
  final _subscriptions = <StreamSubscription<Object?>>[];

  Timer? _hideTimer;
  Timer? _feedbackTimer;
  int _menus = 0;
  bool _overBar = false;
  /// Round each bar, to see the focus come into it.
  final _topBarFocus = FocusNode(canRequestFocus: false, skipTraversal: true);
  final _bottomBarFocus = FocusNode(canRequestFocus: false, skipTraversal: true);
  /// The keyboard has moved the focus into the bars, which hold open.
  bool _keysInBars = false;
  final _sinceHover = Stopwatch();
  final _livePositions = KeptPositions(step: const Duration(seconds: 1));
  bool _locked = false;
  bool _orientationLocked = false;
  bool _touched = false;
  bool _lifted = false;
  PointerDeviceKind _lastKind = PointerDeviceKind.mouse;

  String? _videoId;
  String? _infoId;
  bool _reading = false;
  Heatmap? _heat;
  ProgressPreview? _preview;

  double? _heldRate;
  Map<ShortcutActivator, VoidCallback>? _bindings;
  AppPreferences? _bindingsFor;

  final _fingers = <int, Offset>{};
  double _pinchStart = 0;
  double _pinchLast = 0;
  bool _pinching = false;

  double _verticalTotal = 0;
  double _verticalSteps = 0;
  bool _verticalLeft = false;
  double _horizontalTotal = 0;
  Duration? _seekFrom;
  Duration? _seekTo;
  bool _dragLive = false;
  Size _lastBox = Size.zero;

  AppController get _c => widget.controller;
  Player get _player => widget.player;

  bool get _barsShown => _bars.status == AnimationStatus.forward || _bars.status == AnimationStatus.completed;

  @override
  void initState() {
    super.initState();
    _videoId = _c.playing?.id;
    _c.addListener(_onController);
    _c.pictureShapedByPlayer.addListener(_applyFit);
    videoFit.addListener(_applyFit);
    _picture.addListener(_rebuild);
    _bars.addStatusListener(_onBarsStatus);
    final stream = _player.stream;
    _subscriptions.addAll([
      stream.playing.listen(_onPlaying),
      stream.completed.listen(_onCompleted),
      stream.width.listen((_) => _applyFit()),
      stream.height.listen((_) => _applyFit()),
      stream.duration.listen((_) {
        if (_heat == null && _preview == null) _infoId = null;
        unawaited(_readInfo());
      }),
    ]);
    _restartHide();
    _keepAwake();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyFit();
      unawaited(_readInfo());
      _updateLift();
    });
  }

  @override
  void didUpdateWidget(PlayerControls old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onController);
      old.controller.pictureShapedByPlayer.removeListener(_applyFit);
      widget.controller.addListener(_onController);
      widget.controller.pictureShapedByPlayer.addListener(_applyFit);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _feedbackTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _c.removeListener(_onController);
    _c.pictureShapedByPlayer.removeListener(_applyFit);
    videoFit.removeListener(_applyFit);
    _picture.removeListener(_rebuild);
    _picture.dispose();
    _releaseHold();
    KeepAwake.hold(this, false);
    if (_lifted) _c.liftSubtitles(0);
    if (_orientationLocked) unawaited(SystemChrome.setPreferredOrientations(const []));
    _bars.dispose();
    _focus.dispose();
    _topBarFocus.dispose();
    _bottomBarFocus.dispose();
    _feedback.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void _onController() {
    final id = _c.playing?.id;
    if (id != _videoId) {
      _videoId = id;
      _heat = null;
      _preview = null;
      _infoId = null;
      _picture.reset();
      _releaseHold();
    }
    unawaited(_readInfo());
    _keepAwake();
    _rebuild();
  }

  void _onPlaying(bool playing) {
    _keepAwake();
    if (playing) {
      _restartHide();
    } else {
      _showBars();
    }
  }

  void _onCompleted(bool completed) {
    if (!completed || !mounted) return;
    if (_c.preferences.exitFullscreenOnEnd && isFullscreen(context) && _c.stopsAfterEnd) {
      unawaited(widget.state?.exitFullscreen());
    }
  }

  void _keepAwake() => KeepAwake.hold(this, _player.state.playing && !_c.audioOnly);

  Future<void> _readInfo() async {
    final id = _c.playing?.id;
    if (id == null || _infoId == id || _reading) return;
    _reading = true;
    ResolvedVideo? video;
    try {
      video = await _c.playingVideo();
    } finally {
      _reading = false;
    }
    if (!mounted || _c.playing?.id != id || video == null) return;
    _infoId = id;
    final board = video.storyboard;
    final heat = video.heatmap;
    setState(() {
      _heat = heat;
      _preview = board == null ? null : storyboardPreview(board, _c.storyboardSheets);
    });
  }

  void _applyFit() {
    if (!mounted) return;
    final fit = videoFit.value;
    _c.coverVideo = fit != VideoFit.contain;
    final shaped = fit == VideoFit.contain && _c.pictureShapedByPlayer.value;
    final state = _player.state;
    final ratio = shaped ? 0.0 : videoAspectFor(fit.aspectRatio, state.width, state.height);
    widget.state?.update(fit: fit.fit, aspectRatio: ratio);
  }

  void _showFeedback(IconData icon, String text) {
    if (!mounted) return;
    _feedback.value = (icon: icon, text: text);
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(milliseconds: 700), () => _feedback.value = null);
  }

  // Bars

  void _showBars() {
    if (!mounted) return;
    _bars.duration = Motion.of(Ease.fade);
    _bars.forward();
    _restartHide();
  }

  void _restartHide() {
    _hideTimer?.cancel();
    final seconds = _c.preferences.controlsHideSeconds;
    if (seconds > 0) _hideTimer = Timer(Duration(seconds: seconds), _autoHide);
  }

  void _autoHide() {
    // A screen reader finds buttons by moving through them: bars that
    // slip away under it leave nothing to find.
    if (!mounted || !_player.state.playing || _menus > 0 || _overBar || _keysInBars || Accessibility.screenReader(context)) return;
    _bars.duration = Motion.of(Ease.fade);
    _bars.reverse();
    _leaveBars();
    if (isFullscreen(context) && WindowFrame.supported && !Device.tv) {
      final box = context.findRenderObject();
      if (box is RenderBox && box.hasSize) unawaited(WindowFrame.hidePointer(box.localToGlobal(Offset.zero) & box.size));
    }
  }

  void _hideNow() {
    _hideTimer?.cancel();
    _bars.duration = Motion.of(Ease.fade);
    _bars.reverse();
    _leaveBars();
  }

  /// Hidden bars keep no focus, so Enter cannot press a button not seen.
  void _leaveBars() {
    if (_topBarFocus.hasFocus || _bottomBarFocus.hasFocus) _focus.requestFocus();
  }

  /// Tab into the bars shows them and holds them open while the focus
  /// stays; a click that leaves the focus in a bar does not hold them.
  void _barFocusChanged(bool _) {
    if (!mounted) return;
    final inBars = _topBarFocus.hasFocus || _bottomBarFocus.hasFocus;
    if (!inBars) {
      if (_keysInBars) {
        _keysInBars = false;
        _restartHide();
      }
    } else if (!_keysInBars && !Device.tv && HardwareKeyboard.instance.logicalKeysPressed.isNotEmpty) {
      _keysInBars = true;
      _showBars();
      _hideTimer?.cancel();
    }
  }

  void _menuOpened() {
    _menus++;
    _hideTimer?.cancel();
  }

  void _menuClosed() {
    if (_menus > 0) _menus--;
    if (_menus == 0) _restartHide();
  }

  void _onBarsStatus(AnimationStatus status) => _updateLift();

  /// Raises mpv's subtitles above the bottom bar while the bars show.
  void _updateLift() {
    if (!mounted) return;
    final shown = _barsShown;
    final bar = _bottomKey.currentContext?.size?.height ?? 0;
    final box = _lastBox;
    var amount = 0.0;
    var percent = 0;
    if (shown && bar > 0 && box.height > 0) {
      final state = _player.state;
      final ratio = videoAspectFor(null, state.width, state.height);
      final picture = math.min(box.height, box.width / ratio);
      amount = picture > 360 ? math.min(bar, picture * 0.15) : bar;
      percent = (amount / picture * 100).ceil();
    }
    _lifted = percent > 0;
    _c.liftSubtitles(percent);
    widget.state?.setSubtitleViewPadding(EdgeInsets.only(bottom: amount));
  }

  // Touch and mouse

  void _onTapUp(TapUpDetails details) {
    _focus.requestFocus();
    if (_locked) return _showBars();
    if (_isTouch(details.kind)) {
      if (_barsShown) {
        _hideNow();
      } else {
        _showBars();
      }
    } else {
      unawaited(_player.playOrPause());
      _showBars();
    }
  }

  void _onDoubleTap() {
    if (_locked) return;
    if (_isTouch(_lastKind)) {
      Haptics.select();
      unawaited(_player.playOrPause().then((_) {
        final playing = _player.state.playing;
        _showFeedback(playing ? AppIcons.pauseFill : AppIcons.playFill, playing ? tr('Pause') : tr('Play'));
      }));
    } else {
      unawaited(toggleFullscreenFrom(widget.state));
    }
  }

  void _onSecondaryTap() {
    if (_locked) return;
    switch (_c.preferences.rightClick) {
      case RightClick.off:
        break;
      case RightClick.back:
        if (isFullscreen(context)) {
          unawaited(widget.state?.exitFullscreen());
        } else {
          _c.goBack();
        }
      case RightClick.fillWindow:
        unawaited(toggleFillWindow(widget.state));
    }
  }

  /// A middle click: what the middle-click setting (鼠标中键) asks for.
  void _onTertiaryTapUp(TapUpDetails details) {
    if (_locked) return;
    switch (_c.preferences.middleClick) {
      case MiddleClick.off:
        break;
      case MiddleClick.playPause:
        unawaited(_player.playOrPause());
        _showBars();
      case MiddleClick.mute:
        unawaited(_c.toggleMute().then((_) {
          if (!mounted) return;
          final muted = _player.state.volume == 0;
          _showFeedback(muted ? AppIcons.speakerSlash : AppIcons.speakerHighFill, muted ? tr('Mute') : '${_player.state.volume.round()}%');
        }));
      case MiddleClick.fillWindow:
        unawaited(toggleFillWindow(widget.state));
      case MiddleClick.pip:
        unawaited(() async {
          if (_c.pip) return _c.setPip(false);
          if (isFullscreen(context)) await widget.state?.exitFullscreen();
          _c.setPip(true);
        }());
    }
  }

  void _holdStart() {
    if (_locked || _heldRate != null || !_player.state.playing) return;
    final rate = _player.state.rate;
    final speed = math.max(2.0, rate * 2).clamp(0.25, 4.0);
    _heldRate = rate;
    if (touchFirst && !Device.tv) unawaited(HapticFeedback.lightImpact());
    unawaited(_player.setRate(speed));
    _showFeedback(AppIcons.fastForwardFill, tr('Playing at {0}x', [rateText(speed)]));
  }

  void _releaseHold() {
    final rate = _heldRate;
    if (rate == null) return;
    _heldRate = null;
    unawaited(_player.setRate(rate));
  }

  void _onPointerDown(PointerDownEvent event) {
    _lastKind = event.kind;
    final touch = _isTouch(event.kind);
    if (touch != _touched) setState(() => _touched = touch);
    if (event.kind == PointerDeviceKind.touch) {
      _fingers[event.pointer] = event.position;
      if (_fingers.length == 2) {
        _pinching = true;
        _pinchStart = _pinchLast = _spread();
      }
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_fingers.containsKey(event.pointer)) return;
    _fingers[event.pointer] = event.position;
    if (_fingers.length == 2) _pinchLast = _spread();
  }

  void _onPointerEnd(PointerEvent event) {
    if (!_fingers.containsKey(event.pointer)) return;
    final both = _fingers.length == 2;
    _fingers.remove(event.pointer);
    if (both && _pinchStart > 0 && event is PointerUpEvent) _finishPinch();
    if (_fingers.isEmpty) _pinching = false;
  }

  double _spread() {
    final points = _fingers.values.toList();
    return points.length < 2 ? 0 : (points[0] - points[1]).distance;
  }

  void _finishPinch() {
    final ratio = _pinchStart > 0 ? _pinchLast / _pinchStart : 1.0;
    _pinchStart = 0;
    if (_locked || !isFullscreen(context)) return;
    if (ratio > 1.2 && videoFit.value != VideoFit.cover) {
      videoFit.value = VideoFit.cover;
      _showFeedback(AppIcons.cornersOut, VideoFit.cover.label);
    } else if (ratio < 0.83 && videoFit.value != VideoFit.contain) {
      videoFit.value = VideoFit.contain;
      _showFeedback(AppIcons.cornersIn, VideoFit.contain.label);
    }
  }

  void _onVerticalStart(DragStartDetails details) {
    _dragLive = !_locked && !_pinching;
    _verticalTotal = 0;
    _verticalSteps = 0;
    _verticalLeft = details.localPosition.dx < _lastBox.width / 2;
  }

  void _onVerticalUpdate(DragUpdateDetails details) {
    if (!_dragLive || _pinching) return;
    final dy = details.primaryDelta ?? 0;
    _verticalTotal += dy;
    if (isPhone(context) && !isFullscreen(context)) return;
    final height = _lastBox.height;
    if (height <= 0) return;
    final range = _verticalLeft ? 2 * pictureLimit('brightness') : 100;
    _verticalSteps -= dy * range / height;
    final whole = _verticalSteps.truncate();
    if (whole == 0) return;
    _verticalSteps -= whole;
    if (_verticalLeft) {
      unawaited(_stepBrightness(whole));
    } else {
      unawaited(_stepVolume(whole.toDouble()));
    }
  }

  void _onVerticalEnd(DragEndDetails details) {
    if (!_dragLive) return;
    _dragLive = false;
    if (!(isPhone(context) && !isFullscreen(context))) return;
    final velocity = details.primaryVelocity ?? 0;
    if (_verticalTotal < -48 || velocity < -400) {
      unawaited(widget.state?.enterFullscreen());
    } else if (_verticalTotal > 48 || velocity > 400) {
      _c.goBack();
    }
  }

  void _onHorizontalStart(DragStartDetails details) {
    final duration = _player.state.duration;
    _dragLive = !_locked && !_pinching && duration > Duration.zero;
    _horizontalTotal = 0;
    _seekFrom = _player.state.position;
    _seekTo = null;
  }

  void _onHorizontalUpdate(DragUpdateDetails details) {
    final from = _seekFrom;
    final duration = _player.state.duration;
    if (!_dragLive || _pinching || from == null || duration <= Duration.zero || _lastBox.width <= 0) return;
    _horizontalTotal += details.primaryDelta ?? 0;
    final span = duration < const Duration(minutes: 3) ? duration : const Duration(minutes: 3);
    final raw = from + span * (_horizontalTotal / _lastBox.width);
    final target = raw < Duration.zero ? Duration.zero : raw > duration ? duration : raw;
    _seekTo = target;
    _showFeedback(_horizontalTotal >= 0 ? AppIcons.fastForwardFill : AppIcons.rewindFill, '${formatPlaybackTime(target)} / ${formatPlaybackTime(duration)}');
  }

  void _onHorizontalEnd(DragEndDetails details) {
    final target = _seekTo;
    final live = _dragLive;
    _dragLive = false;
    _seekTo = null;
    if (live && target != null) unawaited(_c.seek(target));
  }

  void _onHorizontalCancel() {
    _dragLive = false;
    _seekTo = null;
  }

  Future<void> _stepVolume(double delta) async {
    await _c.changeVolume(delta);
    final volume = _player.state.volume.round();
    _showFeedback(volume == 0 ? AppIcons.speakerSlash : AppIcons.speakerHighFill, '$volume%');
  }

  Future<void> _stepBrightness(int delta) async {
    final value = await _c.changeBrightness(delta);
    _showFeedback(value < 0 ? AppIcons.sunDim : AppIcons.sun, tr('Brightness {0}', [value > 0 ? '+$value' : '$value']));
  }

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _locked) return;
    final keyboard = HardwareKeyboard.instance;
    final modifier = keyboard.isControlPressed || (Platform.isMacOS && keyboard.isMetaPressed);
    final mode = _c.preferences.wheelGesture;
    if (!modifier && mode == WheelGesture.off) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) => _scroll(resolved as PointerScrollEvent, modifier));
  }

  void _scroll(PointerScrollEvent event, bool modifier) {
    final up = event.scrollDelta.dy < 0;
    if (modifier) {
      final speed = nextSpeed(_c.settings.speeds, _player.state.rate, up ? 1 : -1);
      if (speed == null) return;
      unawaited(_player.setRate(speed));
      _showFeedback(up ? AppIcons.fastForwardFill : AppIcons.speedometer, '${trimSpeed(speed)}X');
      return;
    }
    final left = event.localPosition.dx < _lastBox.width / 2;
    final useBrightness = switch (_c.preferences.wheelGesture) {
      WheelGesture.brightness => true,
      WheelGesture.split => left,
      _ => false,
    };
    if (useBrightness) {
      unawaited(_stepBrightness(up ? 5 : -5));
    } else {
      final step = _c.preferences.volumeStep.toDouble();
      unawaited(_stepVolume(up ? step : -step));
    }
  }

  // Keys

  Map<ShortcutActivator, VoidCallback> _shortcuts() {
    final prefs = _c.preferences;
    if (_bindings == null || !identical(_bindingsFor, prefs)) {
      _bindingsFor = prefs;
      _bindings = playerShortcuts(_c, () => widget.state, onFeedback: _showFeedback, onScreenshot: _screenshot);
    }
    return _bindings!;
  }

  void _screenshot() => unawaited(captureScreenshot(context, _c, onFeedback: _showFeedback));

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!Device.tv || event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final ok = key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter || key == LogicalKeyboardKey.gameButtonA;
    final direction = switch (key) {
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
      LogicalKeyboardKey.arrowRight => TraversalDirection.right,
      _ => null,
    };
    if (!ok && direction == null) return KeyEventResult.ignored;
    if (!_barsShown) _focus.requestFocus();
    if (FocusManager.instance.primaryFocus == _focus) {
      _showBars();
      if (ok) {
        unawaited(_player.playOrPause());
        return KeyEventResult.handled;
      }
      if (direction == TraversalDirection.up || direction == TraversalDirection.down) {
        _focusBottomBar();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    _showBars();
    if (direction != null) {
      FocusManager.instance.primaryFocus?.focusInDirection(direction);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _focusBottomBar() {
    final nodes = [
      for (final node in _focus.descendants)
        if (node is! FocusScopeNode && node.canRequestFocus && !node.skipTraversal && node.context != null && node.context!.mounted) node,
    ];
    if (nodes.isEmpty) return;
    final lowest = nodes.map((n) => n.rect.bottom).reduce(math.max);
    final row = nodes.where((n) => n.rect.bottom >= lowest - 4).toList()..sort((a, b) => a.rect.left.compareTo(b.rect.left));
    row.first.requestFocus();
  }

  // Look

  /// The played colour and gradient of the progress bar, from the skin.
  (Color, Gradient?) _progressStyle(BuildContext context) {
    final fallback = Theme.of(context).colorScheme.inversePrimary;
    final paints = context.skin?.player.progress;
    if (paints == null || paints.isEmpty) return (fallback, null);
    return switch (paints.last) {
      SolidPaint(:final color) => (color, null),
      final LinearPaint paint when paint.colors.isNotEmpty => (paint.colors.last, paint.gradient),
      RadialPaint(:final colors, :final stops) when colors.isNotEmpty => (colors.last, LinearGradient(colors: colors, stops: stops)),
      _ => (fallback, null),
    };
  }

  ({double side, double above}) _letterbox(Size box) {
    final fit = videoFit.value;
    if (fit != VideoFit.contain && fit.aspectRatio == null || box.isEmpty) return (side: 0, above: 0);
    final state = _player.state;
    final ratio = videoAspectFor(fit.aspectRatio, state.width, state.height);
    var width = box.width;
    var height = box.height;
    if (width / height > ratio) {
      width = height * ratio;
    } else {
      height = width / ratio;
    }
    return (side: (box.width - width) / 2, above: (box.height - height) / 2);
  }

  @override
  Widget build(BuildContext context) {
    final fullscreen = isFullscreen(context);
    final phone = isPhone(context);
    final padding = MediaQuery.paddingOf(context);
    final locked = _locked;
    final showLock = locked || fullscreen || (_touched && !phone);
    final (color, gradient) = _progressStyle(context);
    final line = _c.preferences.progressLine.shows(fullscreen: fullscreen);
    return VideoBox(
      controller: _c,
      danmakuOver: false,
      child: CallbackShortcuts(
        bindings: _shortcuts(),
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: LayoutBuilder(builder: (context, constraints) {
            final box = constraints.biggest;
            if (box != _lastBox) {
              _lastBox = box;
              WidgetsBinding.instance.addPostFrameCallback((_) => _updateLift());
            }
            final letter = _letterbox(box);
            final extra = fullscreen ? math.max(0.0, letter.side - math.max(padding.left, padding.right)) : 0.0;
            return AnimatedBuilder(
              animation: _bars,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerEnd,
                onPointerCancel: _onPointerEnd,
                onPointerSignal: _onSignal,
                child: Stack(fit: StackFit.expand, children: [
                  Positioned.fill(child: _surface()),
                  const PositionedDirectional(start: 0, top: 0, child: SpokenLine()),
                  _Buffering(player: _player, c: _c),
                  IgnorePointer(child: _FeedbackBubble(feedback: _feedback)),
                  if (_c.showStats) _statsOverlay(box, letter, fullscreen, padding),
                  if (line)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: FadeTransition(
                          opacity: ReverseAnimation(_bars),
                          child: MiniProgressLine(player: _player, color: Theme.of(context).colorScheme.inversePrimary),
                        ),
                      ),
                    ),
                  if (!locked) ...[
                    Positioned(left: 0, right: 0, top: 0, child: _bar(top: true, child: _topBar(context, fullscreen, phone, extra, box))),
                    Positioned(left: 0, right: 0, bottom: 0, child: _bar(top: false, child: _bottomBar(context, fullscreen, phone, extra, color, gradient, box))),
                  ],
                  if (!locked && _c.playing != null)
                    PositionedDirectional(
                      end: 0,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: MouseRegion(
                          onEnter: (_) {
                            _overBar = true;
                            _hideTimer?.cancel();
                          },
                          onExit: (_) {
                            _overBar = false;
                            _restartHide();
                          },
                          child: AnimatedBuilder(
                            animation: _bars,
                            child: LearningDrawerHandle(controller: _c),
                            builder: (context, child) => IgnorePointer(
                              ignoring: _bars.value < 0.5,
                              child: FractionalTranslation(translation: Offset(1 - Ease.out.transform(_bars.value), 0), child: child),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (showLock) _lockColumn(context, fullscreen, phone, extra),
                ]),
              ),
              builder: (context, child) => MouseRegion(
                cursor: _bars.value == 0 ? SystemMouseCursors.none : MouseCursor.defer,
                onHover: (event) {
                  if (event.kind != PointerDeviceKind.mouse) return;
                  // A moving mouse sends many events; the hide timer needs
                  // starting again only now and then.
                  if (_barsShown && _sinceHover.isRunning && _sinceHover.elapsedMilliseconds < 250) return;
                  _sinceHover
                    ..reset()
                    ..start();
                  _showBars();
                },
                child: child,
              ),
            );
          }),
        ),
      ),
    );
  }

  /// Whether a mouse drag on the picture moves the window: only while the
  /// video fills the window, not in fullscreen.
  bool get _movesWindow => WindowFrame.supported && fillingWindow.value && !WindowChrome.fullscreen.value && !_c.pip;

  Widget _surface() => RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            TapGestureRecognizer.new,
            (recognizer) => recognizer
              ..onTapUp = _onTapUp
              ..onSecondaryTap = _onSecondaryTap
              ..onTertiaryTapUp = _onTertiaryTapUp,
          ),
          DoubleTapGestureRecognizer: GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
            DoubleTapGestureRecognizer.new,
            (recognizer) => recognizer.onDoubleTap = _onDoubleTap,
          ),
          LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            LongPressGestureRecognizer.new,
            (recognizer) => recognizer
              ..onLongPressStart = ((_) => _holdStart())
              ..onLongPressEnd = ((_) => _releaseHold())
              ..onLongPressCancel = _releaseHold,
          ),
          // With the video filling the window there is no title bar to
          // hold, so the picture itself moves the window.
          if (_movesWindow)
            PanGestureRecognizer: GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
              () => PanGestureRecognizer(supportedDevices: const {PointerDeviceKind.mouse}, allowedButtonsFilter: (buttons) => buttons == kPrimaryButton),
              (recognizer) => recognizer.onStart = (_) {
                if (_movesWindow) AppWindow.startDrag();
              },
            ),
          if (!_locked) ...{
            VerticalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
              () => VerticalDragGestureRecognizer(supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus}),
              (recognizer) => recognizer
                ..onStart = _onVerticalStart
                ..onUpdate = _onVerticalUpdate
                ..onEnd = _onVerticalEnd,
            ),
            HorizontalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
              () => HorizontalDragGestureRecognizer(supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus}),
              (recognizer) => recognizer
                ..onStart = _onHorizontalStart
                ..onUpdate = _onHorizontalUpdate
                ..onEnd = _onHorizontalEnd
                ..onCancel = _onHorizontalCancel,
            ),
          },
        },
        child: const SizedBox.expand(),
      );

  Widget _bar({required bool top, required Widget child}) {
    const black = Color(0xBF000000);
    return MouseRegion(
      onEnter: (_) {
        _overBar = true;
        _hideTimer?.cancel();
      },
      onExit: (_) {
        _overBar = false;
        _restartHide();
      },
      child: AnimatedBuilder(
        animation: _bars,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.bottomCenter : Alignment.topCenter,
              end: top ? Alignment.topCenter : Alignment.bottomCenter,
              colors: const [Colors.transparent, black],
            ),
          ),
          child: Focus(
            focusNode: top ? _topBarFocus : _bottomBarFocus,
            onFocusChange: _barFocusChanged,
            child: top ? child : KeyedSubtree(key: _bottomKey, child: child),
          ),
        ),
        builder: (context, child) {
          final hidden = 1 - Ease.out.transform(_bars.value);
          return FractionalTranslation(translation: Offset(0, top ? -hidden : 1.2 * hidden), child: child);
        },
      ),
    );
  }

  Widget _statsOverlay(Size box, ({double side, double above}) letter, bool fullscreen, EdgeInsets padding) {
    final start = math.max(letter.side, padding.left) + 12;
    final top = math.max(letter.above + 8, math.max(fullscreen ? padding.top : 0.0, fullscreen ? 64.0 : 52.0));
    final maxWidth = math.max(0.0, box.width - start - math.max(letter.side, 12));
    final maxHeight = math.max(0.0, box.height - top - math.max(letter.above, 8));
    return Positioned(
      left: start,
      top: top,
      child: IgnorePointer(
        child: StreamBuilder<int?>(
          stream: _player.stream.width,
          initialData: _player.state.width,
          builder: (context, _) => ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
            child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topLeft, child: PlayerStats(player: _player)),
          ),
        ),
      ),
    );
  }

  // Top bar

  Widget _topBar(BuildContext context, bool fullscreen, bool phone, double extra, Size box) {
    final c = _c;
    final details = c.details;
    final item = c.playing;
    final title = details != null && details.title.isNotEmpty ? details.title : item?.title ?? '';
    final channel = details != null && details.channel.isNotEmpty ? details.channel : item?.channel ?? '';
    final accent = Theme.of(context).colorScheme.inversePrimary;
    final narrow = box.width < 600;
    final row = Padding(
      padding: EdgeInsetsDirectional.fromSTEB((fullscreen ? 8 : 4) + extra, fullscreen ? 8 : 4, 8 + extra, 16),
      child: Row(children: [
        _IconBtn(
          icon: AppIcons.arrowLeft,
          size: 20,
          tooltip: fullscreen ? tr('Exit fullscreen') : tr('Back'),
          onTap: () {
            _showBars();
            if (fullscreen) {
              unawaited(widget.state?.exitFullscreen());
            } else {
              c.goBack();
            }
          },
        ),
        if (!phone || fullscreen)
          _IconBtn(
            icon: AppIcons.houseFill,
            size: 20,
            tooltip: tr('Home'),
            onTap: () async {
              if (fullscreen) await widget.state?.exitFullscreen();
              c.navigate(PageMode.home);
            },
          ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: fullscreen ? 16 : 14, fontWeight: FontWeight.w500)),
            if (fullscreen && channel.isNotEmpty)
              Text(channel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),
        if (phone && fullscreen && item != null && !narrow) ...[..._countButtons(accent), const SizedBox(width: 8)],
        if (c.pinned) _status(AppIcons.pushPinFill, tr('Window pinned on top'), accent),
        if (c.audioOnly) _status(AppIcons.headphonesFill, tr('Playing audio only'), accent),
        if (c.sleepAt != null || c.sleepAfterCurrent) _status(AppIcons.moonStars, tr('Sleep timer on'), Colors.white, size: 18),
        if (!fullscreen && !phone)
          ValueListenableBuilder<bool>(
            valueListenable: lightsOff,
            builder: (context, off, _) => _IconBtn(
              icon: off ? AppIcons.lightbulbFill : AppIcons.lightbulb,
              size: 19,
              active: off,
              tooltip: off ? tr('Lights on (B)') : tr('Lights off (B)'),
              onTap: () {
                _showBars();
                lightsOff.value = !lightsOff.value;
              },
            ),
          ),
        ListenableBuilder(
          listenable: c.cast,
          builder: (context, _) => _IconBtn(
            icon: c.cast.active ? AppIcons.airplay : AppIcons.screencast,
            size: 19,
            active: c.cast.active,
            tooltip: tr('Cast'),
            onTap: () {
              _showBars();
              unawaited(showCastDialog(context, c));
            },
          ),
        ),
        if (!phone || fullscreen)
          _IconBtn(
            icon: AppIcons.browsers,
            size: 19,
            tooltip: tr('Picture in picture'),
            onTap: () async {
              if (fullscreen) await widget.state?.exitFullscreen();
              c.setPip(true);
            },
          ),
        _IconBtn(icon: AppIcons.slidersHorizontal, size: 20, tooltip: tr('More settings'), onTap: () => _openMore(context)),
      ]),
    );
    return fullscreen ? SafeArea(bottom: false, child: row) : row;
  }

  Widget _status(IconData icon, String tooltip, Color color, {double size = 17}) => Tooltip(
        message: tooltip,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Icon(icon, size: size, color: color)),
      );

  List<Widget> _countButtons(Color accent) {
    final c = _c;
    final item = c.playing;
    if (item == null) return const [];
    final account = c.account;
    final liked = account?.ratingOf(item.id) == VideoRating.like;
    final base = c.details?.likeCount ?? c.dislikes?.likes;
    final likes = base == null ? null : math.max(0, base + (account?.ratingChange(item.id, VideoRating.like) ?? 0));
    final library = c.library;
    final favorite = library?.isFavorite(item.id) ?? false;
    return [
      _CountButton(
        icon: liked ? AppIcons.thumbsUpFill : AppIcons.thumbsUp,
        tooltip: tr('Like'),
        count: likes,
        active: liked,
        onTap: () {
          _showBars();
          if (account != null && account.active && !account.ratingOff(item.id)) {
            unawaited(account.rate(item, VideoRating.like));
          } else if (account != null && account.active) {
            _showFeedback(AppIcons.thumbsUp, tr('The uploader turned off likes and dislikes for this video'));
          } else {
            _showFeedback(AppIcons.thumbsUp, tr('Sign in to YouTube to {0}', [tr('Like')]));
          }
        },
      ),
      if (!_c.preferences.focusHideComments)
        _CountButton(
          icon: AppIcons.chatCircle,
          tooltip: tr('Comments'),
          onTap: () async {
            await widget.state?.exitFullscreen();
            sidePanelTab.value = null;
            sidePanelTab.value = 'comments';
          },
        ),
      if (library != null)
        _CountButton(
          icon: favorite ? AppIcons.heartFill : AppIcons.heart,
          tooltip: tr('Favorites'),
          active: favorite,
          onTap: () {
            _showBars();
            library.toggleFavorite(item);
            _rebuild();
          },
        ),
      _CountButton(
        icon: AppIcons.share,
        tooltip: tr('Share'),
        onTap: () async {
          _showBars();
          if (!await shareText(item.url)) {
            await Clipboard.setData(ClipboardData(text: item.url));
            _showFeedback(AppIcons.link, tr('Link copied'));
          }
        },
      ),
    ];
  }

  // Lock

  Widget _lockColumn(BuildContext context, bool fullscreen, bool phone, double extra) {
    final accent = Theme.of(context).colorScheme.inversePrimary;
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _bars,
        builder: (context, child) => IgnorePointer(ignoring: _bars.value == 0, child: child),
        child: FadeTransition(
          opacity: _bars,
          child: SafeArea(
            right: false,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: EdgeInsetsDirectional.only(start: 12 + extra),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _CircleButton(
                    icon: _locked ? AppIcons.lock : AppIcons.lockOpen,
                    tooltip: _locked ? tr('Unlock') : tr('Lock'),
                    onTap: () {
                      setState(() => _locked = !_locked);
                      _showFeedback(_locked ? AppIcons.lock : AppIcons.lockOpen, _locked ? tr('Locked') : tr('Unlocked'));
                      _showBars();
                    },
                  ),
                  if (phone && !_locked && !Device.tv) ...[
                    const SizedBox(height: 12),
                    _CircleButton(
                      icon: _orientationLocked ? AppIcons.lockSimple : AppIcons.deviceRotate,
                      tooltip: _orientationLocked ? tr('Rotate with the phone') : tr('Lock screen rotation'),
                      active: _orientationLocked,
                      accent: accent,
                      onTap: () => _toggleOrientation(context),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _toggleOrientation(BuildContext context) {
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    setState(() => _orientationLocked = !_orientationLocked);
    _showBars();
    if (_orientationLocked) {
      unawaited(SystemChrome.setPreferredOrientations(landscape ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight] : const [DeviceOrientation.portraitUp]));
      _showFeedback(AppIcons.deviceRotate, landscape ? tr('Locked to landscape') : tr('Locked to portrait'));
    } else {
      unawaited(SystemChrome.setPreferredOrientations(const []));
      _showFeedback(AppIcons.deviceRotate, tr('Rotate with the phone'));
    }
  }

  // Menus

  /// A choice among [rows]: a sheet on a phone, else a dark popup over or
  /// above the button whose [anchor] context is given.
  Future<void> _pick<T>(BuildContext anchor, {required String title, required List<(T, String)> rows, required T? current, required void Function(T value) onSelected}) async {
    _menuOpened();
    try {
      T? picked;
      if (isPhone(anchor)) {
        picked = await pickFromSheet<T>(
          anchor,
          [for (final (value, label) in rows) (value: value, icon: null, label: label, selected: value == current)],
          title: title,
        );
      } else {
        final box = anchor.findRenderObject()! as RenderBox;
        final origin = box.localToGlobal(Offset.zero);
        final touch = touchFirst;
        final height = rows.length * (touch ? 48.0 : 36.0) + 12;
        final above = origin.dy - 6 - height;
        final top = above >= 8 ? above : origin.dy;
        final size = MediaQuery.sizeOf(anchor);
        final accent = Theme.of(anchor).colorScheme.inversePrimary;
        picked = await showMenu<T>(
          context: anchor,
          useRootNavigator: true,
          position: RelativeRect.fromLTRB(origin.dx, top, size.width - origin.dx - box.size.width, size.height - top),
          color: const Color(0xEB1F1F1F),
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          constraints: const BoxConstraints(minWidth: 112),
          menuPadding: const EdgeInsets.symmetric(vertical: 6),
          items: [
            for (final (value, label) in rows)
              PopupMenuItem<T>(
                value: value,
                height: touch ? 48 : 36,
                padding: const EdgeInsets.only(left: 12, right: 16),
                child: Row(children: [
                  SizedBox(width: 22, child: value == current ? Icon(AppIcons.check, size: 16, color: accent) : null),
                  Flexible(child: Text(label, style: TextStyle(color: value == current ? accent : Colors.white, fontSize: 12, fontWeight: value == current ? FontWeight.w600 : FontWeight.normal))),
                ]),
              ),
          ],
        );
      }
      if (picked != null && picked != current) onSelected(picked);
    } finally {
      _menuClosed();
    }
  }

  void _openSubtitles(BuildContext context) {
    _showBars();
    _menuOpened();
    unawaited(showSubtitlePanel(
      context,
      _c,
      _player,
      onSettings: () => unawaited(showSubtitleStylePanel(context, _c)),
      onList: () => _openSubtitleList(context),
    ).whenComplete(_menuClosed));
  }

  void _openSubtitleList(BuildContext context) {
    if (subtitleListBeside && !isFullscreen(context)) {
      if (theaterMode.value) theaterChatOpen.value = true;
      sidePanelTab.value = null;
      sidePanelTab.value = 'subtitles';
    } else {
      _menuOpened();
      unawaited(showSubtitleList(context, _c, _player).whenComplete(_menuClosed));
    }
  }
}
