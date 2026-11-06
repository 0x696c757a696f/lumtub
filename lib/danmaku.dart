import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:media_kit/media_kit.dart';

import 'app_log.dart';
import 'live_chat.dart';
import 'native_core.dart';
import 'player_settings.dart';

/// How 弹幕 look: kept with the preferences.
class DanmakuSettings {
  const DanmakuSettings({this.enabled = false, this.opacity = 0.85, this.size = 52, this.seconds = 12, this.area = 0.5, this.paid = true});

  /// The chat flies across the picture.
  final bool enabled;
  /// 0.2 to 1.
  final double opacity;
  /// Text height for a 1080-line picture.
  final double size;
  /// How long a message takes to cross: the speed.
  final double seconds;
  /// The share of the picture from the top: 0.25, 0.5 or 1.
  final double area;
  /// Super Chats, stickers and memberships too.
  final bool paid;

  static const areas = [0.25, 0.5, 1.0];

  DanmakuSettings copyWith({bool? enabled, double? opacity, double? size, double? seconds, double? area, bool? paid}) => DanmakuSettings(
        enabled: enabled ?? this.enabled,
        opacity: opacity ?? this.opacity,
        size: size ?? this.size,
        seconds: seconds ?? this.seconds,
        area: area ?? this.area,
        paid: paid ?? this.paid,
      );

  Map<String, Object> toJson() => {'enabled': enabled, 'opacity': opacity, 'size': size, 'seconds': seconds, 'area': area, 'paid': paid, 'version': 3};

  factory DanmakuSettings.fromJson(Object? raw) {
    const d = DanmakuSettings();
    if (raw is! Map) return d;
    double number(String key, double fallback, double min, double max) => raw[key] is num ? (raw[key] as num).toDouble().clamp(min, max) : fallback;
    return DanmakuSettings(
      enabled: raw['enabled'] is bool ? raw['enabled'] as bool : d.enabled,
      opacity: number('opacity', d.opacity, 0.2, 1),
      // Before version 3 the default was 44, which read too small.
      size: (raw['version'] is! int || (raw['version'] as int) < 3) && raw['size'] == 44 ? d.size : number('size', d.size, 24, 96),
      // Before version 2 the default crossed in 8 s, which read too fast.
      seconds: raw['version'] is int && (raw['version'] as int) >= 2 ? number('seconds', d.seconds, 4, 20) : d.seconds,
      area: number('area', d.area, 0.25, 1),
      paid: raw['paid'] is bool ? raw['paid'] as bool : d.paid,
    );
  }

  /// What the layout in lumtub_core needs.
  String get layoutJson => jsonEncode({'font_size': size, 'duration_ms': seconds * 1000, 'area': area, 'opacity': opacity, 'font': PlayerSettings.fontForThisSystem(PlayerSettings.defaultSubtitleFont)});

  @override
  bool operator ==(Object other) => other is DanmakuSettings && jsonEncode(toJson()) == jsonEncode(other.toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// When a live message flies: at its own time, so a batch fetched at once
/// keeps the gaps it was sent with. Messages reach the app late by up to one
/// fetch, and the computer's clock may differ from YouTube's, so the least
/// lateness seen counts as on time and the chat runs behind by the most
/// lateness seen past that.
class LiveDanmakuTiming {
  double? _onTime;
  double _delay = 0;
  /// Later than this past on time, a message flies at once.
  static const mostBehind = 15000.0;

  /// The clock times, in ms, for a batch of messages sent at [sentUsec]
  /// that arrived when the clock read [now] and the wall clock [wall] (ms).
  List<double> starts(List<int?> sentUsec, double now, double wall) {
    for (final sent in sentUsec) {
      if (sent == null) continue;
      final late = wall - sent / 1000;
      if (_onTime == null || late < _onTime!) _onTime = late;
    }
    return [
      for (final sent in sentUsec)
        if (sent == null) now else _start(wall - sent / 1000 - _onTime!, now),
    ];
  }

  double _start(double behind, double now) {
    if (behind > mostBehind) return now;
    if (behind > _delay) _delay = behind;
    return now - behind + _delay;
  }
}

/// Draws the chat over the picture through mpv's `osd-overlay`, laid out
/// by lumtub_core. A replay's messages fly at their place in the video; a
/// live stream's as they arrive, on a clock that stops while paused.
class DanmakuOverlay {
  DanmakuOverlay(this.player);

  final Player player;
  /// mpv's overlay ids are per client; this one is only the 弹幕's.
  static const _overlay = '47';
  static const _frame = Duration(milliseconds: 33);

  Pointer<Void>? _layout;
  NativeCore? _core;
  DanmakuSettings? _settings;
  bool _live = false;
  final _liveClock = Stopwatch();
  final _added = <String>{};
  var _timing = LiveDanmakuTiming();
  Timer? _timer;
  String _shown = '';
  bool _sending = false;

  bool get running => _layout != null;

  /// Starts over for a video: [live] follows messages as they arrive,
  /// otherwise each flies at its offset.
  void start(DanmakuSettings settings, {required bool live}) {
    stop();
    final core = NativeCore.instance;
    if (core == null) return;
    _core = core;
    _settings = settings;
    _live = live;
    _layout = core.withText(settings.layoutJson, core.danmakuNew);
    _liveClock
      ..reset()
      ..start();
    _timer = Timer.periodic(_frame, (_) => _tick());
  }

  /// Adds the messages not added yet: a replay's all at once, in order;
  /// a live stream's newest as they come.
  void add(List<LiveChatMessage> messages) {
    final core = _core;
    final layout = _layout;
    final settings = _settings;
    if (core == null || layout == null || settings == null) return;
    final now = _liveClock.elapsedMilliseconds.toDouble();
    final wall = DateTime.now().microsecondsSinceEpoch / 1000;
    final batch = <Map<String, Object>>[];
    final sent = <int?>[];
    for (final message in messages) {
      if (!_added.add(message.id)) continue;
      final paid = message.kind != LiveChatKind.message;
      if (message.kind == LiveChatKind.system || (paid && !settings.paid)) continue;
      final text = message.text.trim().isNotEmpty ? message.text : message.amount ?? '';
      if (text.trim().isEmpty) continue;
      final start = _live ? now : message.offset?.inMilliseconds.toDouble();
      if (start == null) continue;
      batch.add({'start_ms': start, 'text': text, 'paid': paid});
      sent.add(message.timestampUsec);
    }
    if (batch.isEmpty) return;
    if (_live) {
      final starts = _timing.starts(sent, now, wall);
      for (var i = 0; i < batch.length; i++) {
        batch[i]['start_ms'] = starts[i];
      }
    }
    batch.sort((a, b) => (a['start_ms'] as double).compareTo(b['start_ms'] as double));
    core.withText(jsonEncode(batch), (bytes, length) => core.danmakuAdd(layout, bytes, length));
  }

  /// Marks [messages] as shown without flying them.
  void skip(List<LiveChatMessage> messages) {
    for (final message in messages) {
      _added.add(message.id);
    }
  }

  void _tick() {
    final core = _core;
    final layout = _layout;
    if (core == null || layout == null || _sending) return;
    final playing = player.state.playing;
    if (_live) {
      if (playing && !_liveClock.isRunning) _liveClock.start();
      if (!playing && _liveClock.isRunning) _liveClock.stop();
    }
    final now = _live ? _liveClock.elapsedMilliseconds.toDouble() : player.state.position.inMilliseconds.toDouble();
    final events = core.take(core.danmakuFrame(layout, now, _live)) ?? '';
    if (events == _shown) return;
    _shown = events;
    unawaited(_show(events));
  }

  Future<void> _show(String events) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    _sending = true;
    try {
      if (events.isEmpty) {
        await platform.command(['osd-overlay', _overlay, 'none', '']);
      } else {
        await platform.command(['osd-overlay', _overlay, 'ass-events', events, '1920', '1080', '0', 'no', 'no']);
      }
    } catch (e) {
      logWarn('Could not draw the danmaku: $e');
      stop();
    } finally {
      _sending = false;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    final layout = _layout;
    if (layout != null) _core?.danmakuFree(layout);
    _layout = null;
    _added.clear();
    _timing = LiveDanmakuTiming();
    _liveClock.stop();
    if (_shown.isNotEmpty) {
      _shown = '';
      unawaited(_show(''));
    }
  }
}
