import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// mpv properties shown in the statistics overlay; the same names appear in
/// standalone mpv's stats page (key i), so the two can be compared directly.
const _properties = [
  'video-codec',
  'hwdec-current',
  'video-params/w',
  'video-params/h',
  'container-fps',
  'estimated-vf-fps',
  'frame-drop-count',
  'decoder-frame-drop-count',
  'video-bitrate',
  'audio-codec-name',
  'audio-bitrate',
  'demuxer-cache-duration',
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
    if (platform is! NativePlayer) return;
    final values = <String, String>{};
    for (final name in _properties) {
      try {
        values[name] = await platform.getProperty(name);
      } catch (_) {
        // Unavailable until the first frame, or for audio-only media.
      }
    }
    if (mounted) setState(() => _values = values);
  }

  @override
  Widget build(BuildContext context) {
    final rows = statsRows(_values);
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
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

  final width = value('video-params/w');
  final height = value('video-params/h');
  final hwdec = value('hwdec-current');
  return [
    ('视频', or(value('video-codec'))),
    ('分辨率', width.isEmpty || height.isEmpty ? '—' : '${width}x$height'),
    ('解码', hwdec.isEmpty || hwdec == 'no' ? '软件解码' : '硬件 $hwdec'),
    ('帧率', '${number('estimated-vf-fps')} / 源 ${number('container-fps', digits: 3)}'),
    ('丢帧', '输出 ${or(value('frame-drop-count'))} · 解码 ${or(value('decoder-frame-drop-count'))}'),
    ('码率', '视频 ${kbps('video-bitrate')} · 音频 ${kbps('audio-bitrate')}'),
    ('音频', or(value('audio-codec-name'))),
    ('缓冲', value('demuxer-cache-duration').isEmpty ? '—' : '${number('demuxer-cache-duration', digits: 1)} 秒'),
  ];
}
