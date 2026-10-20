// "Most replayed": the curve above the progress bar. yt-dlp's `heatmap` is a
// list of {start_time, end_time, value} with value 0..1. YouTube's own player
// draws the same curve; PiliNara has the equivalent for Bilibili's
// "高能进度条" (lib/plugin/pl_player, GPLv3).

import 'dart:math';

class Heatmap {
  const Heatmap(this.values);

  /// Equally spaced samples over the whole video, each 0..1.
  final List<double> values;

  /// yt-dlp's `heatmap` of [info], resampled to [samples] points; null when
  /// the video has none (it is only there for popular videos).
  static Heatmap? from(Map<String, dynamic> info, {int samples = 100}) {
    final raw = info['heatmap'];
    if (raw is! List) return null;
    final bins = <(double, double, double)>[
      for (final b in raw.whereType<Map>())
        if (b['start_time'] is num && b['end_time'] is num && b['value'] is num && (b['end_time'] as num) > (b['start_time'] as num))
          ((b['start_time'] as num).toDouble(), (b['end_time'] as num).toDouble(), (b['value'] as num).toDouble().clamp(0.0, 1.0)),
    ];
    if (bins.length < 2) return null;
    final total = bins.map((b) => b.$2).reduce(max);
    final values = List<double>.filled(samples, 0);
    for (var i = 0; i < samples; i++) {
      final at = (i + 0.5) / samples * total;
      for (final (start, end, value) in bins) {
        if (at >= start && at < end) {
          values[i] = value;
          break;
        }
      }
    }
    return Heatmap(values);
  }
}
