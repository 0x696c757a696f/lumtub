import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:math' as math;

import 'package:media_kit/media_kit.dart';

import 'app_log.dart';
import 'live_chat.dart';
import 'native_core.dart';
import 'player_settings.dart';
import 'ui/danmaku_picture.dart';

/// How 弹幕 look: kept with the preferences.
class DanmakuSettings {
  const DanmakuSettings({this.enabled = false, this.opacity = 0.85, this.size = 52, this.seconds = 12, this.area = 0.5, this.paid = true, this.comments = true});

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
  /// On a video without a chat, the comments that name a moment of it fly
  /// at that moment.
  final bool comments;

  static const areas = [0.25, 0.5, 1.0];

  DanmakuSettings copyWith({bool? enabled, double? opacity, double? size, double? seconds, double? area, bool? paid, bool? comments}) => DanmakuSettings(
        enabled: enabled ?? this.enabled,
        opacity: opacity ?? this.opacity,
        size: size ?? this.size,
        seconds: seconds ?? this.seconds,
        area: area ?? this.area,
        paid: paid ?? this.paid,
        comments: comments ?? this.comments,
      );

  Map<String, Object> toJson() => {'enabled': enabled, 'opacity': opacity, 'size': size, 'seconds': seconds, 'area': area, 'paid': paid, 'comments': comments, 'version': 3};

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
      comments: raw['comments'] is bool ? raw['comments'] as bool : d.comments,
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
/// Messages with emoji, which libass cannot draw, are drawn by Flutter as
/// pictures and shown with mpv's `overlay-add`.
class DanmakuOverlay {
  DanmakuOverlay(this.player);

  final Player player;
  /// mpv's overlay ids are per client; this one is only the 弹幕's.
  static const _overlay = '47';
  static const _frame = Duration(milliseconds: 33);
  /// mpv takes `overlay-add` ids 0 to 63.
  static const _pictureSlots = 64;
  /// Live messages with emoji kept to draw: more than can be on screen.
  static const _keptLive = 500;

  DanmakuPainter? _painter;
  int _nextPicture = 0;
  int _generation = 0;
  final _pictureParts = <int, (List<DanmakuPart>, bool)>{};
  /// The latest drawing of each picture.
  final _bitmaps = <int, DanmakuBitmap>{};
  final _drawing = <int>{};
  /// The overlay each picture on screen has, and what mpv reads there.
  final _slots = <int, int>{};
  final _onScreen = <int, DanmakuBitmap>{};
  final _freeSlots = [for (var i = _pictureSlots - 1; i >= 0; i--) i];
  String _shownEvents = '';
  double _osdWidth = 1920;
  double _osdHeight = 1080;
  int _ticks = 0;
  /// The time last laid out; while it stays (paused) and nothing new came,
  /// the frame is the same and the core is not asked again.
  double? _laidOut;
  bool _changed = true;

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
    _painter = DanmakuPainter(font: PlayerSettings.fontForThisSystem(PlayerSettings.defaultSubtitleFont), size: settings.size, opacity: settings.opacity);
    _generation++;
    _laidOut = null;
    _changed = true;
    unawaited(_readOsdSize());
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
      final entry = <String, Object>{'start_ms': start, 'text': text, 'paid': paid};
      final parts = danmakuParts(text, message.emojis);
      final painter = _painter;
      if (parts != null && painter != null) {
        final id = _nextPicture++;
        _pictureParts[id] = (parts, paid);
        entry['picture'] = id;
        entry['width'] = painter.measure(parts, _osdWidth, _osdHeight);
      }
      batch.add(entry);
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
    _changed = true;
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
    if (++_ticks % 30 == 0) unawaited(_readOsdSize());
    if (!_changed && now == _laidOut) return;
    _laidOut = now;
    _changed = false;
    final frame = core.take(core.danmakuFrame(layout, now, _live)) ?? '';
    if (frame == _shown) return;
    _shown = frame;
    final events = StringBuffer();
    final pictures = <(int, double, double)>[];
    for (final line in frame.split('\n')) {
      if (line.isEmpty) continue;
      if (line.startsWith('!')) {
        final fields = line.substring(1).split(' ');
        final id = int.tryParse(fields[0]);
        final x = double.tryParse(fields.elementAtOrNull(1) ?? '');
        final y = double.tryParse(fields.elementAtOrNull(2) ?? '');
        if (id != null && x != null && y != null) pictures.add((id, x, y));
      } else {
        events.writeln(line);
      }
    }
    unawaited(_show('$events', pictures));
  }

  Future<void> _readOsdSize() async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    try {
      final width = double.tryParse(await platform.getProperty('osd-width')) ?? 0;
      final height = double.tryParse(await platform.getProperty('osd-height')) ?? 0;
      if (width > 0 && height > 0) {
        if (width != _osdWidth || height != _osdHeight) _changed = true;
        _osdWidth = width;
        _osdHeight = height;
      }
    } catch (_) {}
  }

  Future<void> _show(String events, List<(int, double, double)> pictures) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    _sending = true;
    try {
      final sent = <Future<void>>[];
      if (events != _shownEvents) {
        _shownEvents = events;
        if (events.isEmpty) {
          sent.add(platform.command(['osd-overlay', _overlay, 'none', '']));
        } else {
          sent.add(platform.command(['osd-overlay', _overlay, 'ass-events', events, '1920', '1080', '0', 'no', 'no']));
        }
      }
      sent.addAll(_placePictures(platform, pictures));
      await Future.wait(sent);
    } catch (e) {
      logWarn('Could not draw the danmaku: $e');
      stop();
    } finally {
      _sending = false;
    }
  }

  /// Moves each picture on screen to where the layout puts it, cut at the
  /// edges of the OSD, and takes the ones gone off it.
  List<Future<void>> _placePictures(NativePlayer platform, List<(int, double, double)> pictures) {
    final sent = <Future<void>>[];
    final placed = <int>{};
    final osdWidth = _osdWidth.floor();
    for (final (id, x, y) in pictures) {
      final bitmap = _bitmaps[id];
      if (bitmap == null || (bitmap.scale - _osdHeight).abs() > 2) _draw(id);
      if (bitmap == null) continue;
      final left = (x * _osdWidth / 1920 - bitmap.left).round();
      final top = (y * _osdHeight / 1080).round();
      final cut = math.max(0, -left);
      final width = math.min(bitmap.width - cut, osdWidth - math.max(0, left));
      if (width <= 0 || top < 0) continue;
      final slot = _slots[id] ?? (_freeSlots.isEmpty ? null : _freeSlots.removeLast());
      if (slot == null) continue;
      _slots[id] = slot;
      placed.add(id);
      final before = _onScreen[slot];
      _onScreen[slot] = bitmap;
      sent.add(platform.command([
        'overlay-add', '$slot', '${math.max(0, left)}', '$top', '&${bitmap.pixels.address + cut * 4}', '0', 'bgra', '$width', '${bitmap.height}', '${bitmap.stride}',
      ]).then((_) {
        if (before != null && before != bitmap) _release(before);
      }));
    }
    for (final id in _slots.keys.where((id) => !placed.contains(id)).toList()) {
      final slot = _slots.remove(id)!;
      sent.add(platform.command(['overlay-remove', '$slot']).then((_) {
        final shown = _onScreen.remove(slot);
        _freeSlots.add(slot);
        if (shown != null) _release(shown);
      }));
    }
    final visible = {for (final (id, _, _) in pictures) id};
    for (final id in _bitmaps.keys.where((id) => !visible.contains(id)).toList()) {
      _release(_bitmaps.remove(id)!);
    }
    // A live message is gone for good once it has left the picture; a
    // replay may come back to one.
    if (_live && _pictureParts.length > _keptLive) {
      final old = _pictureParts.keys.where((id) => !visible.contains(id)).take(_pictureParts.length - _keptLive).toList();
      old.forEach(_pictureParts.remove);
    }
    return sent;
  }

  void _draw(int id) {
    final painter = _painter;
    final parts = _pictureParts[id];
    if (painter == null || parts == null || !_drawing.add(id)) return;
    final generation = _generation;
    painter.draw(parts.$1, osdHeight: _osdHeight, paid: parts.$2).then((bitmap) {
      _drawing.remove(id);
      if (bitmap == null) return;
      if (generation != _generation) {
        bitmap.free();
        return;
      }
      final before = _bitmaps[id];
      _bitmaps[id] = bitmap;
      if (before != null) _release(before);
      // Shown at the next frame even while paused.
      _shown = '';
      _changed = true;
    }, onError: (Object e) {
      _drawing.remove(id);
      logWarn('Could not draw a danmaku picture: $e');
    });
  }

  /// Frees [bitmap] once nothing shows it, a moment later so a frame mpv
  /// is drawing just then still reads it.
  void _release(DanmakuBitmap bitmap) {
    if (_bitmaps.containsValue(bitmap) || _onScreen.containsValue(bitmap)) return;
    Timer(const Duration(milliseconds: 500), bitmap.free);
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
    _generation++;
    _painter = null;
    _pictureParts.clear();
    if (_shown.isNotEmpty || _slots.isNotEmpty) {
      _shown = '';
      unawaited(_show('', const []));
    }
  }
}
