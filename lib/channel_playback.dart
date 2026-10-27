import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// The speed and volume last chosen on each channel's videos, kept in
/// `data/channel_playback.json` on this computer and used again the next
/// time that channel plays.
class ChannelPlayback {
  ChannelPlayback(this.file);
  final File file;

  static const _most = 1000;

  // Insertion order is age order: the channel used longest ago goes first.
  final _entries = <String, ({double? rate, int? volume})>{};
  Timer? _save;

  /// The key of [item]'s channel: its id, or its name when it has none.
  static String? keyOf(VideoItem item) {
    final id = item.channelId;
    if (id != null && id.isNotEmpty) return id;
    return item.channel.isEmpty ? null : 'name:${item.channel}';
  }

  Future<void> load() async {
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is! Map) return;
      for (final MapEntry(:key, :value) in data.entries) {
        if (value is! Map) continue;
        final rate = value['rate'];
        final volume = value['volume'];
        _entries['$key'] = (
          rate: rate is num && rate > 0 && rate <= 16 ? rate.toDouble() : null,
          volume: volume is num && volume > 0 && volume <= 1000 ? volume.round() : null,
        );
      }
    } catch (_) {
      // None yet, or damaged: start empty.
    }
  }

  ({double? rate, int? volume})? of(String key) => _entries[key];

  /// Remembers [rate] or [volume] for [key]; a null field keeps what was
  /// there, [forgetRate] drops the speed (back to the default).
  void remember(String key, {double? rate, int? volume, bool forgetRate = false}) {
    final old = _entries.remove(key);
    final next = (rate: forgetRate ? null : rate ?? old?.rate, volume: volume ?? old?.volume);
    if (next.rate != null || next.volume != null) _entries[key] = next;
    while (_entries.length > _most) {
      _entries.remove(_entries.keys.first);
    }
    _save?.cancel();
    _save = Timer(const Duration(seconds: 2), () => unawaited(save()));
  }

  void clear() {
    _entries.clear();
    _save?.cancel();
    unawaited(save());
  }

  int get length => _entries.length;

  Future<void> save() async {
    _save?.cancel();
    try {
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode({
        for (final MapEntry(:key, :value) in _entries.entries)
          key: {if (value.rate != null) 'rate': value.rate, if (value.volume != null) 'volume': value.volume},
      }), flush: true);
      await temp.rename(file.path);
    } catch (_) {}
  }
}
