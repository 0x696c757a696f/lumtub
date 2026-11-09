import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'app/app_controller.dart';
import 'app_window.dart';
import 'kwin_keep_above.dart';
import 'l10n/l10n.dart';

/// The runner's side of Windows' media overlay (System Media Transport
/// Controls: media keys, Bluetooth buttons, the volume flyout, the lock
/// screen) and the tray icon, over a method channel. The native half is
/// windows/runner/windows_shell.cpp; on Linux linux/runner/linux_shell.cc
/// answers with MPRIS and a StatusNotifier tray icon. Elsewhere nothing
/// answers and every call is ignored.
class WindowsShell {
  WindowsShell({MethodChannel? channel, this.timelineInterval = const Duration(seconds: 1)})
      : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_onCall);
  }

  static const channelName = 'lumtub/windows_shell';

  /// DirectWrite family names installed for the current Windows user.
  /// A missing or older native runner simply leaves the Settings list empty.
  static Future<List<String>> systemFontFamilies() async {
    try {
      final names = await const MethodChannel(channelName)
          .invokeListMethod<String>('listSystemFonts')
          // Test bindings and an older runner can leave an unimplemented
          // platform call pending. The Settings page must still open.
          .timeout(const Duration(milliseconds: 500), onTimeout: () => const <String>[]);
      return (names ?? const <String>[]).where((name) => name.trim().isNotEmpty).toSet().toList()..sort();
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  final MethodChannel _channel;

  /// The least time between two timeline updates.
  final Duration timelineInterval;

  /// A button of the overlay or tray menu: play, pause, playpause, next,
  /// previous or stop.
  void Function(String button)? onButton;
  void Function(Duration position)? onSeek;
  /// Android's picture in picture began or ended.
  void Function(bool on)? onPip;

  DateTime? _lastTimeline;

  Future<dynamic> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'button':
        onButton?.call(call.arguments as String);
      case 'seek':
        onSeek?.call(Duration(milliseconds: call.arguments as int));
      case 'pip':
        onPip?.call(call.arguments == true);
    }
    return null;
  }

  Future<void> _send(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Not Windows, or an older runner.
    } on PlatformException {
      // The overlay is a convenience; playback does not depend on it.
    }
  }

  /// What the overlay shows; [thumbnail] is an https address, may be empty.
  Future<void> setMetadata({required String title, required String artist, String thumbnail = ''}) =>
      _send('setMetadata', {'title': title, 'artist': artist, 'thumbnail': thumbnail});

  /// [status] is playing, paused or stopped.
  Future<void> setStatus(String status) => _send('setStatus', status);

  Future<void> setButtons({required bool next, required bool previous}) => _send('setButtons', {'next': next, 'previous': previous});

  /// Position and length, at most once per [timelineInterval] unless [force].
  Future<void> setTimeline(Duration position, Duration duration, {bool force = false}) async {
    final now = DateTime.now();
    final last = _lastTimeline;
    if (!force && last != null && now.difference(last) < timelineInterval) return;
    _lastTimeline = now;
    await _send('setTimeline', {'position': position.inMilliseconds, 'duration': duration.inMilliseconds});
  }

  /// With [enabled] the close button, and with [minimize] minimising, hides
  /// the window to a tray icon whose menu has translated labels; off,
  /// closing exits and minimising minimises as usual.
  Future<void> setTray({required bool enabled, bool minimize = false}) => _send('setTray', {
        'enabled': enabled,
        'minimize': minimize,
        'show': tr('Show window'),
        'playPause': tr('Play/Pause'),
        'next': tr('Next'),
        'exit': tr('Exit'),
      });
}

/// Keeps a [WindowsShell] in step with the controller's playback, and turns
/// its buttons into player and queue actions.
class WindowsShellSync {
  WindowsShellSync(this.controller, this.shell) {
    shell
      ..onButton = _button
      ..onSeek = ((position) => unawaited(controller.seek(position)))
      ..onPip = controller.pipChangedBySystem;
    controller.addListener(_changed);
    _changed();
  }

  final AppController controller;
  final WindowsShell shell;
  Player? _player;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  String? _videoId;
  bool? _hasNext, _hasPrevious;
  bool _autoPip = false;
  (bool, bool)? _tray;
  Duration _duration = Duration.zero;
  /// The playing video's frame rate as mpv reads it, and the one the
  /// screen was last asked to fit (0: its own choice).
  double _fps = 0, _fitted = 0;

  void _button(String button) {
    final player = controller.player;
    switch (button) {
      case 'play':
        unawaited(player?.play());
      case 'pause' || 'stop':
        unawaited(player?.pause());
      case 'playpause':
        unawaited(player?.playOrPause());
      case 'next':
        if (controller.hasNext) unawaited(controller.playNext());
      case 'previous':
        unawaited(controller.playPrevious());
    }
  }

  void _changed() {
    final player = controller.player;
    if (player != null && player != _player) _attach(player);
    final tray = (controller.preferences.closeToTray, controller.preferences.minimizeToTray);
    if (tray != _tray) {
      _tray = tray;
      unawaited(shell.setTray(enabled: tray.$1, minimize: tray.$2));
      if (AppWindow.onWayland) unawaited(KWinMinimizeWatch.set(tray.$2));
    }
    final video = controller.playing;
    if (video?.id != _videoId) {
      _videoId = video?.id;
      if (video == null) {
        unawaited(shell.setStatus('stopped'));
      } else {
        unawaited(shell.setMetadata(title: video.title, artist: controller.playingChannel?.name ?? video.channel, thumbnail: video.thumbnail));
        _hasNext = _hasPrevious = null;
        _status(player?.state.playing ?? false);
      }
    }
    // Android: going home while a video plays on the watch page keeps it
    // in picture in picture.
    final autoPip = Platform.isAndroid && video != null && controller.onWatchPage && !controller.mini && (player?.state.playing ?? false);
    if (autoPip != _autoPip) {
      _autoPip = autoPip;
      AppWindow.setAutoPip(autoPip);
    }
    if (Platform.isAndroid) _fitFrameRate();
    final hasNext = video != null && controller.hasNext, hasPrevious = controller.hasPrevious;
    if (hasNext != _hasNext || hasPrevious != _hasPrevious) {
      _hasNext = hasNext;
      _hasPrevious = hasPrevious;
      unawaited(shell.setButtons(next: hasNext, previous: hasPrevious));
    }
  }

  /// Android: a screen that offers several refresh rates switches to one
  /// the video's frame rate divides, while a video plays.
  void _fitFrameRate() {
    final want = controller.preferences.matchFrameRate && controller.playing != null ? _fps : 0.0;
    if ((want - _fitted).abs() < 0.01) return;
    _fitted = want;
    unawaited(const MethodChannel('lumtub/windows_shell').invokeMethod<void>('setFrameRate', want).catchError((Object _) {}));
  }

  void _status(bool playing) {
    if (Platform.isAndroid) _changed();
    if (_videoId == null) return;
    unawaited(shell.setStatus(playing ? 'playing' : 'paused'));
    unawaited(shell.setTimeline(_player?.state.position ?? Duration.zero, _duration, force: true));
  }

  void _attach(Player player) {
    _player = player;
    final platform = player.platform;
    if (Platform.isAndroid && platform is NativePlayer) {
      // Only noted here: awaiting the player in mpv's callback stalls it.
      unawaited(platform.observeProperty('container-fps', (value) async {
        _fps = double.tryParse(value) ?? 0;
        _fitFrameRate();
      }).catchError((Object _) {}));
    }
    _duration = player.state.duration;
    _subscriptions.addAll([
      player.stream.playing.listen(_status),
      player.stream.duration.listen((d) {
        _duration = d;
        if (_videoId != null) unawaited(shell.setTimeline(player.state.position, d, force: true));
      }),
      player.stream.position.listen((p) {
        if (_videoId != null && _duration > Duration.zero) unawaited(shell.setTimeline(p, _duration));
      }),
    ]);
  }

  void dispose() {
    controller.removeListener(_changed);
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
  }
}
