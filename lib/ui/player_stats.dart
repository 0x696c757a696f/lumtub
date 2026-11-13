import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../l10n/l10n.dart';

/// mpv properties shown in the statistics overlay; the same names appear in
/// standalone mpv's stats page (key i), so the two can be compared directly.
const _properties = [
  'video-codec',
  // Newer libmpv, as on Android, has no video-codec; these name it instead.
  'video-format',
  'current-tracks/video/codec',
  'hwdec-current',
  'video-params/w',
  'video-params/h',
  'container-fps',
  'estimated-vf-fps',
  'frame-drop-count',
  'decoder-frame-drop-count',
  'vo-delayed-frame-count',
  'avsync',
  'display-fps',
  'video-bitrate',
  'audio-codec-name',
  'audio-bitrate',
  'demuxer-cache-duration',
  'cache-speed',
];

/// Live decoder and network figures over the video, refreshed every second.
class PlayerStats extends StatefulWidget {
  const PlayerStats({super.key, required this.player});
  final Player player;

  @override
  State<PlayerStats> createState() => _PlayerStatsState();
}

class _PlayerStatsState extends State<PlayerStats> {
  Map<String, String> _values = const {};
  Timer? _timer;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_read()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    final platform = widget.player.platform;
    // A slow player is not asked again before it has answered.
    if (platform is! NativePlayer || _reading) return;
    _reading = true;
    final values = <String, String>{};
    try {
      for (final name in _properties) {
        if (!mounted) return;
        try {
          values[name] = await platform.getProperty(name);
        } catch (_) {
          // Unavailable until the first frame, or for audio-only media.
        }
      }
    } finally {
      _reading = false;
    }
    if (mounted) setState(() => _values = values);
  }

  @override
  Widget build(BuildContext context) {
    final screen = View.of(context).display.refreshRate;
    final rows = statsRows({
      ..._values,
      // The Android video output does not know the screen's refresh rate.
      if (double.tryParse(_values['display-fps'] ?? '') case null || 0) 'display-fps': '$screen',
    });
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.68), borderRadius: BorderRadius.circular(8)),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.45, fontFeatures: [FontFeature.tabularFigures()]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            for (final (label, value) in rows)
              Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 64, child: Text(label, style: const TextStyle(color: Colors.white70))),
                Text(value),
              ]),
          ]),
        ),
      ),
    );
  }
}

/// Turns raw mpv values into labelled rows; missing values show as "—".
List<(String, String)> statsRows(Map<String, String> v) {
  String value(String name) => (v[name] ?? '').trim();
  String or(String text) => text.isEmpty ? '—' : text;
  String number(String name, {int digits = 2}) {
    final parsed = double.tryParse(value(name));
    return parsed == null ? '—' : parsed.toStringAsFixed(digits);
  }

  String kbps(String name) {
    final bits = double.tryParse(value(name));
    return bits == null || bits <= 0 ? '—' : '${(bits / 1000).round()} kbps';
  }

  String speed(String raw) {
    final bytes = double.tryParse(raw);
    if (bytes == null) return '—';
    return bytes >= 1 << 20 ? '${(bytes / (1 << 20)).toStringAsFixed(1)} MB/s' : '${(bytes / 1024).round()} KB/s';
  }

  final width = value('video-params/w');
  final height = value('video-params/h');
  final hwdec = value('hwdec-current');
  return [
    (tr('Videos'), or([value('video-codec'), value('video-format'), value('current-tracks/video/codec')].firstWhere((name) => name.isNotEmpty, orElse: () => ''))),
    (tr('Resolution'), width.isEmpty || height.isEmpty ? '—' : '${width}x$height'),
    (tr('Decoding'), hwdec.isEmpty || hwdec == 'no' ? tr('Software decoding') : tr('Hardware {0}', [hwdec])),
    (tr('Frame rate'), tr('{0} / source {1}', [number('estimated-vf-fps'), number('container-fps', digits: 3)])),
    (tr('Dropped frames'), tr('Output {0} · Decode {1} · Delay {2}', [or(value('frame-drop-count')), or(value('decoder-frame-drop-count')), or(value('vo-delayed-frame-count'))])),
    (tr('A/V offset'), value('avsync').isEmpty ? '—' : tr('{0} ms · display {1} Hz', [((double.tryParse(value('avsync')) ?? 0) * 1000).round(), number('display-fps', digits: 0)])),
    (tr('Bitrate'), tr('Video {0} · Audio {1}', [kbps('video-bitrate'), kbps('audio-bitrate')])),
    (tr('Audio'), or(value('audio-codec-name'))),
    (tr('Buffering'), value('demuxer-cache-duration').isEmpty ? '—' : tr('{0} s', [number('demuxer-cache-duration', digits: 1)])),
    (tr('Download speed'), speed(value('cache-speed'))),
  ];
}
