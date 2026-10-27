import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'native_core.dart';

/// 观看统计: how long videos played each day, per channel, kept in
/// `data/watch_time.json` on this computer only.
class WatchTime {
  WatchTime(this.file);
  final File file;

  /// Days kept; older ones are dropped.
  static const _keptDays = 400;

  final _days = <String, Map<String, int>>{};
  final _names = <String, String>{};
  Timer? _save;
  bool _dirty = false;

  static String dayOf(DateTime time) => '${time.year.toString().padLeft(4, '0')}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';

  Future<void> load() async {
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is! Map) return;
      for (final MapEntry(:key, :value) in (data['days'] is Map ? data['days'] as Map : const {}).entries) {
        if (value is! Map) continue;
        _days['$key'] = {for (final MapEntry(key: channel, value: seconds) in value.entries) if (seconds is num && seconds > 0) '$channel': seconds.round()};
      }
      for (final MapEntry(:key, :value) in (data['names'] is Map ? data['names'] as Map : const {}).entries) {
        if (value is String) _names['$key'] = value;
      }
    } catch (_) {
      // None yet, or damaged: start empty.
    }
  }

  /// Adds [seconds] of [channel] (named [name]) to the day of [at].
  void add(String channel, String name, int seconds, {DateTime? at}) {
    if (seconds <= 0) return;
    final day = _days.putIfAbsent(dayOf(at ?? DateTime.now()), () => {});
    day[channel] = (day[channel] ?? 0) + seconds;
    if (name.isNotEmpty) _names[channel] = name;
    _dirty = true;
    _save ??= Timer(const Duration(minutes: 1), () => unawaited(save()));
  }

  bool get isEmpty => _days.isEmpty;

  void clear() {
    _days.clear();
    _names.clear();
    _dirty = true;
    unawaited(save());
  }

  Future<void> save() async {
    _save?.cancel();
    _save = null;
    if (!_dirty) return;
    _dirty = false;
    final keep = (_days.keys.toList()..sort()).reversed.take(_keptDays).toSet();
    _days.removeWhere((day, _) => !keep.contains(day));
    final used = {for (final day in _days.values) ...day.keys};
    _names.removeWhere((channel, _) => !used.contains(channel));
    try {
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode({'days': _days, 'names': _names}), flush: true);
      await temp.rename(file.path);
    } catch (_) {}
  }

  /// Totals for 观看统计 over the last [span] days, worked out by
  /// lumtub_core off the UI thread; null without the core.
  Future<WatchStats?> stats({int span = 30, DateTime? today}) async {
    if (NativeCore.instance == null) return null;
    final input = jsonEncode({'days': _days, 'names': _names, 'today': dayOf(today ?? DateTime.now()), 'span': span});
    final answer = await Isolate.run(() {
      final core = NativeCore.instance!;
      final stats = core.library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_watch_stats');
      return core.take(core.withText(input, stats));
    });
    return answer == null ? null : WatchStats.fromJson(jsonDecode(answer));
  }
}

/// What lumtub_core worked out from [WatchTime], in seconds.
class WatchStats {
  const WatchStats({required this.today, required this.week, required this.month, required this.total, required this.average, required this.days, required this.top});
  final int today;
  final int week;
  final int month;
  final int total;
  /// A day's average over the span.
  final int average;
  /// Each day of the span, oldest first.
  final List<(String, int)> days;
  /// The channels watched most in the span: key, name, seconds.
  final List<(String, String, int)> top;

  factory WatchStats.fromJson(Object? raw) {
    final map = raw is Map ? raw : const {};
    int number(String key) => (map[key] as num?)?.toInt() ?? 0;
    return WatchStats(
      today: number('today'),
      week: number('week'),
      month: number('month'),
      total: number('total'),
      average: number('average'),
      days: [for (final d in map['days'] is List ? map['days'] as List : const []) if (d is List && d.length == 2) ('${d[0]}', (d[1] as num).toInt())],
      top: [for (final t in map['top'] is List ? map['top'] as List : const []) if (t is List && t.length == 3) ('${t[0]}', '${t[1]}', (t[2] as num).toInt())],
    );
  }
}
