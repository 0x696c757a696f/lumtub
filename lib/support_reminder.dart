import 'dart:convert';
import 'dart:io';

import 'app_directories.dart';

/// When to ask, now and then, whether someone would like to support
/// Lumtub. Kept in `config/support_reminder.json` on this device only.
///
/// The first time comes after Lumtub was used on [_daysUsed] different days
/// and at least [_firstAfter] after the first of them; later ones come
/// [_every] after the last. Turning it off stops it for good.
class SupportReminder {
  SupportReminder(this.file);
  final File file;

  static const _daysUsed = 7;
  static const _firstAfter = Duration(days: 14);
  static const _every = Duration(days: 60);

  DateTime? _first;
  DateTime? _last;
  final _days = <String>{};
  bool _off = false;
  final _writes = WriteQueue();

  bool get enabled => !_off;

  Future<void> load() async {
    if (!await file.exists()) return;
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is! Map) throw const FormatException('Not a JSON object');
      DateTime? time(Object? value) => value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;
      _first = time(data['first']);
      _last = time(data['last']);
      _off = data['off'] == true;
      if (data['days'] case final List days) _days.addAll(days.whereType<String>());
    } catch (e) {
      await setBrokenFileAside(file, e);
    }
  }

  static String _day(DateTime time) => '${time.year}-${time.month}-${time.day}';

  /// Counts [now]'s day as one Lumtub was used on.
  void used(DateTime now) {
    final first = _first == null;
    _first ??= now;
    // Only the count matters, and only up to [_daysUsed].
    if (_days.length >= _daysUsed && !first) return;
    if (_days.add(_day(now)) || first) _save();
  }

  /// Whether to ask at [now].
  bool due(DateTime now) {
    final first = _first;
    if (_off || first == null || _days.length < _daysUsed) return false;
    final last = _last;
    return last == null ? now.difference(first) >= _firstAfter : now.difference(last) >= _every;
  }

  /// Asked at [now]: the next time is [_every] later.
  void asked(DateTime now) {
    _last = now;
    _save();
  }

  set enabled(bool value) {
    if (_off == !value) return;
    _off = !value;
    _save();
  }

  void _save() {
    final text = jsonEncode({
      if (_first case final first?) 'first': first.millisecondsSinceEpoch,
      if (_last case final last?) 'last': last.millisecondsSinceEpoch,
      'days': _days.toList(),
      if (_off) 'off': true,
    });
    _writes.run(() => writeFileAtomic(file, text)).ignore();
  }
}
