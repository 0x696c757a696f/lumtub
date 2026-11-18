part of 'app_controller.dart';

/// Picture in picture on iPhone and iPad: iOS's own floating window, showing
/// the layer libmpv draws into (IosVideoLayer). Its play, pause and skip
/// buttons drive the player; the player's position, speed and length go to
/// the window's progress bar.
class _IosPipSync {
  final List<StreamSubscription<Object?>> subscriptions = [];

  /// What the window was last told, to send only what it can't work out:
  /// a jump, a pause, another speed or length.
  Duration position = Duration.zero;
  DateTime sentAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool playing = false;
  double rate = 1;
  Duration duration = Duration.zero;
  bool live = false;

  /// When the window's button back to the app was pressed: the window
  /// closing then is no reason to turn the picture off.
  DateTime? restoredAt;
}

extension IosPipActions on AppController {
  /// Starts following [player] for the picture-in-picture window, once.
  void _watchIosPip(Player player) {
    if (!Platform.isIOS || _iosPip != null) return;
    final sync = _iosPip = _IosPipSync();
    IosVideoLayer.onEvent = _onIosPipEvent;
    IosVideoLayer.active.addListener(_iosPipActiveChanged);
    void send({bool force = false}) => unawaited(_sendIosPipState(player, sync, force: force));
    sync.subscriptions.addAll([
      player.stream.playing.listen((_) => send(force: true)),
      player.stream.rate.listen((_) => send(force: true)),
      player.stream.duration.listen((_) => send(force: true)),
      player.stream.position.listen((_) => send()),
    ]);
  }

  Future<void> _sendIosPipState(Player player, _IosPipSync sync, {bool force = false}) async {
    final state = player.state;
    final live = playing?.isLive ?? false;
    final rate = state.rate;
    if (!force && state.playing == sync.playing && rate == sync.rate && state.duration == sync.duration && live == sync.live) {
      // The window's clock runs on by itself: only a jump needs telling.
      final elapsed = DateTime.now().difference(sync.sentAt);
      final expected = sync.position + (sync.playing ? elapsed * rate : Duration.zero);
      if ((state.position - expected).abs() < const Duration(milliseconds: 750)) return;
    }
    sync
      ..position = state.position
      ..sentAt = DateTime.now()
      ..playing = state.playing
      ..rate = rate
      ..duration = state.duration
      ..live = live;
    try {
      await IosVideoLayer.update(position: state.position, duration: state.duration, playing: state.playing, rate: rate, live: live);
    } catch (e) {
      logDebug(() => 'Could not update picture in picture: $e');
    }
  }

  /// Whether going home now opens picture in picture (离开 App 时进入画中画,
  /// while a video plays on the watch page).
  void setIosAutoPip(bool on) {
    _iosAutoPip = on;
    unawaited(IosVideoLayer.setAuto(on).catchError((Object e) => logDebug(() => 'Could not arm picture in picture: $e')));
  }

  /// The 画中画 button: iOS's floating window.
  Future<void> _startIosPip() async {
    if (playing == null || player == null) return;
    // The picture must be on: the window shows what the layer gets.
    if (_backgroundAudioOnly) await setBackgroundAudioOnly(false);
    bool ok;
    try {
      ok = await IosVideoLayer.start();
    } catch (e) {
      logWarn('Could not start picture in picture: $e');
      ok = false;
    }
    if (!ok) _notice(tr('Could not open picture in picture'));
  }

  void _onIosPipEvent(IosPipEvent event, double? seconds, String? error) {
    final player = this.player;
    logInfo('Picture in picture: ${event.name}${seconds == null ? '' : ' ${seconds.toStringAsFixed(0)} s'}${error == null ? '' : ' ($error)'}');
    if (player == null) return;
    switch (event) {
      case IosPipEvent.play:
        unawaited(player.play());
      case IosPipEvent.pause:
        unawaited(player.pause());
      case IosPipEvent.skip:
        if (seconds != null) unawaited(seekBy(Duration(milliseconds: (seconds * 1000).round())));
      case IosPipEvent.restore:
        _iosPip?.restoredAt = DateTime.now();
      case IosPipEvent.failed:
        if (!_windowHidden) _notice(tr('Could not open picture in picture'));
      default:
    }
  }

  /// The window closed while Lumtub is in the background: from then on only
  /// the sound plays there, as without picture in picture.
  void _iosPipActiveChanged() {
    unawaited(_setPipLibass(IosVideoLayer.active.value));
    if (IosVideoLayer.active.value || !_windowHidden) return;
    final restored = _iosPip?.restoredAt;
    if (restored != null && DateTime.now().difference(restored) < const Duration(seconds: 3)) return;
    unawaited(setBackgroundAudioOnly(true));
  }

  /// The window shows the video layer alone, so the subtitles must be drawn
  /// into the frames: mpv draws them (both, in Lumtub's look) while it is
  /// open, and the Flutter view takes over again after. Only in memory: the
  /// saved settings stay as they are.
  Future<void> _setPipLibass(bool open) async {
    final player = this.player;
    if (player == null) return;
    final on = open && settings.pipSubtitles && !settings.libassSubtitles;
    if (on == _pipLibass) return;
    _pipLibass = on;
    final next = settings.copyWith(libassSubtitles: on);
    try {
      await PlayerOptionApplicator.apply(player, next, previous: _applied ?? settings);
    } catch (e) {
      logDebug(() => 'Could not switch the subtitles for picture in picture: $e');
    }
    _applied = next;
    _update(() => settings = next);
    _optionsApplied(player);
    logInfo(on ? 'Subtitles drawn by mpv for picture in picture' : 'Subtitles drawn by Lumtub again');
  }
}
