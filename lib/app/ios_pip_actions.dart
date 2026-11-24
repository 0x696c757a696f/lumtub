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
    // The window shows the picture's own shape: subtitles are wrapped for it.
    _queueLibassLook();
    _iosPipSubtitles(settings.pipSubtitles);
    _sendPipSubtitles();
    if (IosVideoLayer.active.value || !_windowHidden) return;
    final restored = _iosPip?.restoredAt;
    if (restored != null && DateTime.now().difference(restored) < const Duration(seconds: 3)) return;
    unawaited(setBackgroundAudioOnly(true));
  }

  /// 画中画显示字幕 off: the window shows the picture without subtitles.
  void _iosPipSubtitles(bool shown) {
    if (!Platform.isIOS) return;
    subtitlesOffIn(_iosPipOwner, IosVideoLayer.active.value && !shown);
  }

  /// The window shows only what goes into the frames: libmpv's subtitles
  /// go in by themselves, while those Flutter draws (where libmpv has no
  /// font for a line) are drawn here into a picture for it. Only while the
  /// window is open and Flutter draws, and only when the lines change.
  void _sendPipSubtitles([List<String>? lines]) {
    if (!Platform.isIOS) return;
    final player = this.player;
    final wanted = player != null && IosVideoLayer.active.value && !libassDraws && !subtitlesOff && settings.pipSubtitles;
    final shown = lines ?? player?.state.subtitle ?? const [];
    final main = wanted && shown.isNotEmpty ? shown.first.trim() : '';
    final second = wanted && shown.length > 1 && secondarySubtitle != null ? shown[1].trim() : '';
    final aspect = _videoAspect;
    final s = settings;
    final key = main.isEmpty && second.isEmpty
        ? ''
        : [main, second, aspect, s.subtitleFont, s.subtitleScale, s.subtitleColor, s.subtitleOpacity, s.secondaryFont, s.secondaryScale, s.secondaryColor, s.secondaryOpacity, s.subtitleBold, s.subtitleBackground, s.subtitleBorder, s.subtitlePosition].join('|');
    if (key == _pipSubtitlesSent) return;
    _pipSubtitlesSent = key;
    final serial = ++_pipSubtitlesSerial;
    if (key.isEmpty) {
      unawaited(IosVideoLayer.setSubtitles(null).catchError((Object e) => logDebug(() => 'Could not clear the picture-in-picture subtitles: $e')));
      return;
    }
    // At the height the window's frames are made (720 lines), in the
    // picture's shape, sized by height as the phone's player sizes them.
    final canvas = Size(720 * aspect.clamp(0.3, 4.0), 720);
    PipSubtitleStyle look(String font, double scale, int color, double opacity, String language) {
      final style = languageStyle(language);
      return pipSubtitleStyle(
        font: font,
        scale: scale,
        color: color,
        opacity: opacity,
        bold: s.subtitleBold,
        box: s.subtitleBackground,
        outline: LibassLook.outlineFor(s.subtitleBorder),
        fallback: style?.fontFamilyFallback ?? [bundledFont, ...downloadedScriptFamilies, blankFont],
        locale: style?.locale,
      );
    }

    unawaited(() async {
      try {
        final picture = await drawPipSubtitles(
          main: main,
          second: second,
          mainStyle: look(s.subtitleFont, s.subtitleScale, s.subtitleColor, s.subtitleOpacity, mainSubtitleLanguage),
          secondStyle: look(s.secondaryFont, s.secondaryScale, s.secondaryColor, s.secondaryOpacity, secondSubtitleLanguage),
          canvas: canvas,
          scale: max(12.0, min(canvas.height, canvas.width * 0.75) * 0.0533) / 32,
          position: s.subtitlePosition,
        );
        if (serial != _pipSubtitlesSerial) return;
        if (picture == null) {
          await IosVideoLayer.setSubtitles(null);
          return;
        }
        await IosVideoLayer.setSubtitles(picture.pixels,
            width: picture.width, height: picture.height, x: picture.x, y: picture.y, canvasWidth: canvas.width, canvasHeight: canvas.height);
      } catch (e) {
        logDebug(() => 'Could not draw the picture-in-picture subtitles: $e');
      }
    }());
  }
}
