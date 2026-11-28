import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'emoji_pictures.dart';
import 'live_chat.dart';
import 'native_core.dart';
import 'player_settings.dart';
import 'ui/danmaku_picture.dart';

/// How 弹幕 look: kept with the preferences.
class DanmakuSettings {
  factory DanmakuSettings.fromJson(Object? raw) {
    const d = DanmakuSettings();
    if (raw is! Map) return d;
    double number(String key, double fallback, double min, double max) =>
        raw[key] is num ? (raw[key] as num).toDouble().clamp(min, max) : fallback;
    return DanmakuSettings(
      enabled: raw['enabled'] is bool ? raw['enabled'] as bool : d.enabled,
      opacity: number('opacity', d.opacity, 0.2, 1),
      // Before version 3 the default was 44, which read too small.
      size: (raw['version'] is! int || (raw['version'] as int) < 3) && raw['size'] == 44
          ? d.size
          : number('size', d.size, 24, 96),
      // Before version 2 the default crossed in 8 s, before version 4 in
      // 12 s; both read too fast.
      seconds: raw['version'] is! int ||
              (raw['version'] as int) < 2 ||
              ((raw['version'] as int) < 4 && raw['seconds'] == 12)
          ? d.seconds
          : number('seconds', d.seconds, 4, 20),
      area: number('area', d.area, 0.25, 1),
      paid: raw['paid'] is bool ? raw['paid'] as bool : d.paid,
      comments: raw['comments'] is bool ? raw['comments'] as bool : d.comments,
    );
  }

  const DanmakuSettings(
      {this.enabled = false,
      this.opacity = 0.85,
      this.size = 52,
      this.seconds = 16,
      this.area = 0.5,
      this.paid = true,
      this.comments = true});

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

  DanmakuSettings copyWith(
          {bool? enabled,
          double? opacity,
          double? size,
          double? seconds,
          double? area,
          bool? paid,
          bool? comments}) =>
      DanmakuSettings(
        enabled: enabled ?? this.enabled,
        opacity: opacity ?? this.opacity,
        size: size ?? this.size,
        seconds: seconds ?? this.seconds,
        area: area ?? this.area,
        paid: paid ?? this.paid,
        comments: comments ?? this.comments,
      );

  Map<String, Object> toJson() => {
        'enabled': enabled,
        'opacity': opacity,
        'size': size,
        'seconds': seconds,
        'area': area,
        'paid': paid,
        'comments': comments,
        'version': 4
      };

  /// What the layout in lumtub_core needs.
  String get layoutJson => jsonEncode({
        'font_size': size,
        'duration_ms': seconds * 1000,
        'area': area,
        'opacity': opacity,
        'font': PlayerSettings.fontForThisSystem(PlayerSettings.defaultSubtitleFont)
      });

  @override
  bool operator ==(Object other) =>
      other is DanmakuSettings && jsonEncode(toJson()) == jsonEncode(other.toJson());

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

/// The chat flying over the picture, laid out by lumtub_core and drawn by
/// [DanmakuLayer] at every frame of the display, so it moves smoothly at
/// any refresh rate. A replay's messages fly at their place in the video;
/// a live stream's as they arrive, on a clock that stops while paused.
class DanmakuOverlay extends ChangeNotifier {
  DanmakuOverlay(this.player);

  final Player player;

  /// Bookkeeping: messages given to the layout ahead, old ones forgotten.
  static const _tickEvery = Duration(milliseconds: 250);

  /// Live messages with emoji kept to draw: more than can be on screen.
  static const _keptLive = 500;

  DanmakuPainter? _painter;
  DanmakuPainter? get painter => _painter;
  int _nextPicture = 0;
  final _pictureParts = <int, (List<DanmakuPart>, bool)>{};

  Pointer<Void>? _layout;
  NativeCore? _core;
  DanmakuSettings? _settings;
  DanmakuSettings? get settings => _settings;
  bool _live = false;
  final _liveClock = Stopwatch();
  final _added = <String>{};

  /// The ids a live keeps to tell new messages from those already shown.
  static const _liveIds = 5000;

  /// A replay's messages not given to the layout yet, by start: each is
  /// laid out a little before it flies, not all when danmaku starts.
  final _waiting = <(double, LiveChatMessage)>[];
  var _given = 0;
  static const _ahead = 30000.0;
  var _timing = LiveDanmakuTiming();
  Timer? _timer;

  /// Bumped whenever the layout takes messages: [visibleAt] asks again.
  int _revision = 0;
  int get revision => _revision;

  final _replayClock = ReplayClock();

  bool get running => _layout != null;

  /// The size the picture is shown at, set by [DanmakuLayer]: pictures are
  /// measured for it.
  ({double width, double height}) box = (width: 1920.0, height: 1080.0);

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
    _painter = DanmakuPainter(
        font: PlayerSettings.fontForThisSystem(PlayerSettings.defaultSubtitleFont),
        size: settings.size,
        opacity: settings.opacity);
    _liveClock
      ..reset()
      ..start();
    _replayClock.reset();
    _timer = Timer.periodic(_tickEvery, (_) => _tick());
    _changed();
  }

  void _changed() {
    _revision++;
    notifyListeners();
  }

  /// Whether the clock moves: playing.
  bool get moving => running && player.state.playing;

  /// The moment shown now, in ms: the live clock, or the video's position
  /// carried on smoothly between mpv's reports.
  double now() {
    final state = player.state;
    if (_live) {
      if (state.playing && !_liveClock.isRunning) _liveClock.start();
      if (!state.playing && _liveClock.isRunning) _liveClock.stop();
      return _liveClock.elapsedMicroseconds / 1000;
    }
    return _replayClock.at(state.position.inMicroseconds / 1000,
        playing: state.playing, rate: state.rate);
  }

  /// How long a message takes to cross, in ms.
  double get duration => (_settings?.seconds ?? 12) * 1000;

  /// The messages on screen at some moment from [from] to [to].
  List<DanmakuItem> visibleAt(double from, double to) {
    final core = _core;
    final layout = _layout;
    if (core == null || layout == null) return const [];
    if (!_live) _giveUpTo(to);
    final json = core.take(core.danmakuVisible(layout, from, to, false));
    if (json == null || json.isEmpty) return const [];
    final items = <DanmakuItem>[];
    for (final row in jsonDecode(json) as List) {
      if (row is! List || row.length < 6) continue;
      final picture = row[5] as int?;
      final paid = row[4] == true;
      final parts = picture == null ? [DanmakuText('${row[3]}')] : _pictureParts[picture]?.$1;
      if (parts == null) continue;
      items.add(DanmakuItem(
          start: (row[0] as num).toDouble(),
          width: (row[1] as num).toDouble(),
          lane: (row[2] as num).toInt(),
          parts: parts,
          paid: paid,
          key: picture == null ? 't${row[0]}:${row[2]}:${row[3]}' : 'p$picture'));
    }
    return items;
  }

  void _tick() {
    final core = _core;
    final layout = _layout;
    if (core == null || layout == null) return;
    final now = this.now();
    if (!_live) {
      _giveUpTo(now);
    } else {
      // A live chat keeps growing: what left the picture is forgotten.
      core.take(core.danmakuVisible(layout, now - duration, now - duration, true));
      if (_pictureParts.length > _keptLive) {
        final old = _pictureParts.keys.take(_pictureParts.length - _keptLive).toList();
        old.forEach(_pictureParts.remove);
      }
    }
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
    final waiting = _waiting.length;
    for (final message in messages) {
      if (!_added.add(message.id)) continue;
      final paid = message.kind != LiveChatKind.message;
      if (message.kind == LiveChatKind.system || (paid && !settings.paid)) continue;
      if (_textOf(message).trim().isEmpty) continue;
      final start = _live ? now : message.offset?.inMilliseconds.toDouble();
      if (start == null) continue;
      if (!_live) {
        _waiting.add((start, message));
        continue;
      }
      batch.add(_entry(start, message));
      sent.add(message.timestampUsec);
    }
    if (_live) _forgetOldIds();
    if (_waiting.length != waiting) {
      _mergeWaiting(waiting);
      _changed();
    }
    _send(batch, sent, now, wall);
  }

  /// Puts the messages added after [from] in order among those waiting.
  /// A replay read answer by answer adds them mostly after the ones before:
  /// only the new ones are sorted, then merged in one pass, instead of
  /// sorting everything still waiting each time.
  void _mergeWaiting(int from) {
    int byStart((double, LiveChatMessage) a, (double, LiveChatMessage) b) => a.$1.compareTo(b.$1);
    final added = _waiting.sublist(from)..sort(byStart);
    // Nothing waiting before them, or all of it earlier.
    if (from <= _given || _waiting[from - 1].$1 <= added.first.$1) {
      _waiting.setRange(from, _waiting.length, added);
      return;
    }
    // Merged from the end, in place: the larger of the two tails goes last.
    var i = from - 1;
    var j = added.length - 1;
    var k = _waiting.length - 1;
    while (j >= 0) {
      if (i >= _given && byStart(_waiting[i], added[j]) > 0) {
        _waiting[k--] = _waiting[i--];
      } else {
        _waiting[k--] = added[j--];
      }
    }
  }

  static String _textOf(LiveChatMessage message) =>
      message.text.trim().isNotEmpty ? message.text : message.amount ?? '';

  Map<String, Object> _entry(double start, LiveChatMessage message) {
    final paid = message.kind != LiveChatKind.message;
    final text = _textOf(message);
    final entry = <String, Object>{'start_ms': start, 'text': text, 'paid': paid};
    final parts = danmakuParts(text, EmojiPictures.fill(text, message.emojis));
    final painter = _painter;
    if (parts != null && painter != null) {
      final id = _nextPicture++;
      _pictureParts[id] = (parts, paid);
      entry['picture'] = id;
      entry['width'] = painter.measure(parts, box.width, box.height);
    }
    return entry;
  }

  void _forgetOldIds() {
    if (_added.length <= _liveIds) return;
    final old = _added.take(_added.length - _liveIds).toList();
    _added.removeAll(old);
  }

  /// Gives the layout the replay's messages that fly before [now] and a
  /// little after, in order.
  void _giveUpTo(double now) {
    final batch = <Map<String, Object>>[];
    while (_given < _waiting.length && _waiting[_given].$1 <= now + _ahead) {
      final (start, message) = _waiting[_given++];
      batch.add(_entry(start, message));
    }
    _send(batch, const [], now, 0);
  }

  void _send(List<Map<String, Object>> batch, List<int?> sent, double now, double wall) {
    final core = _core;
    final layout = _layout;
    if (batch.isEmpty || core == null || layout == null) return;
    if (_live) {
      final starts = _timing.starts(sent, now, wall);
      for (var i = 0; i < batch.length; i++) {
        batch[i]['start_ms'] = starts[i];
      }
    }
    batch.sort((a, b) => (a['start_ms']! as double).compareTo(b['start_ms']! as double));
    core.withText(jsonEncode(batch), (bytes, length) => core.danmakuAdd(layout, bytes, length));
    _changed();
  }

  /// Marks [messages] as shown without flying them.
  void skip(List<LiveChatMessage> messages) {
    for (final message in messages) {
      _added.add(message.id);
    }
    if (_live) _forgetOldIds();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    final layout = _layout;
    if (layout != null) _core?.danmakuFree(layout);
    _layout = null;
    _added.clear();
    _waiting.clear();
    _given = 0;
    _timing = LiveDanmakuTiming();
    _liveClock.stop();
    _replayClock.reset();
    _painter = null;
    _pictureParts.clear();
    _changed();
  }
}

/// The moment of a replay shown at each frame. mpv reports the position
/// in steps, so between reports it is carried on by a stopwatch, and a
/// small difference is caught up over half a second instead of with a jump,
/// so the 弹幕 neither stutter nor step back.
class ReplayClock {
  ReplayClock({double Function()? elapsedMs}) : _elapsed = elapsedMs;

  final double Function()? _elapsed;
  final _watch = Stopwatch();
  double _elapsedAtBase = 0;
  double _anchor = 0;
  double _catchUp = 0;
  double? _lastReported;
  bool _running = false;

  double get _now => _elapsed?.call() ?? _watch.elapsedMicroseconds / 1000;

  void reset() {
    _running = false;
    _lastReported = null;
    _catchUp = 0;
    _watch
      ..stop()
      ..reset();
  }

  /// The moment to show, given the position mpv last [reported], in ms.
  double at(double reported, {required bool playing, required double rate}) {
    if (rate <= 0) rate = 1;
    if (!playing) {
      _anchor = reported;
      _catchUp = 0;
      _lastReported = reported;
      _running = false;
      _watch.stop();
      return reported;
    }
    if (!_running) {
      _running = true;
      _watch.start();
      _elapsedAtBase = _now;
      if (_lastReported != reported) _anchor = reported;
      _lastReported = reported;
    }
    final now = _now;
    var shown = _anchor + (now - _elapsedAtBase) * (rate + _catchUp);
    if (reported != _lastReported) {
      _lastReported = reported;
      final behind = reported - shown;
      if (behind.abs() > 300) {
        // A seek, or a stall: go there at once.
        shown = reported;
        _catchUp = 0;
      } else {
        // Caught up over the next half second, never going backwards.
        _catchUp = (behind / 500).clamp(-0.5 * rate, 0.5 * rate);
      }
      _anchor = shown;
      _elapsedAtBase = now;
    }
    return shown;
  }
}

/// A message on screen: [start] is when it came in at the right edge, at
/// the top of [lane], [width] wide in a 1920-wide picture.
class DanmakuItem {
  const DanmakuItem(
      {required this.start,
      required this.width,
      required this.lane,
      required this.parts,
      required this.paid,
      required this.key});
  final double start;
  final double width;
  final int lane;
  final List<DanmakuPart> parts;
  final bool paid;
  final String key;

  /// Where its left edge is at [now], for a 1920-wide picture.
  double x(double now, double duration) => 1920 - (now - start) * (1920 + width) / duration;
}
