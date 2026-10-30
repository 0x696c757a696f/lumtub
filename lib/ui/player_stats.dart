import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../l10n/l10n.dart';

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
    (tr('视频'), or(value('video-codec'))),
    (tr('分辨率'), width.isEmpty || height.isEmpty ? '—' : '${width}x$height'),
    (tr('解码'), hwdec.isEmpty || hwdec == 'no' ? tr('软件解码') : tr('硬件 {0}', [hwdec])),
    (tr('帧率'), tr('{0} / 源 {1}', [number('estimated-vf-fps'), number('container-fps', digits: 3)])),
    (tr('丢帧'), tr('输出 {0} · 解码 {1} · 延迟 {2}', [or(value('frame-drop-count')), or(value('decoder-frame-drop-count')), or(value('vo-delayed-frame-count'))])),
    (tr('音画偏差'), value('avsync').isEmpty ? '—' : tr('{0} ms · 显示 {1} Hz', [((double.tryParse(value('avsync')) ?? 0) * 1000).round(), number('display-fps', digits: 0)])),
    (tr('码率'), tr('视频 {0} · 音频 {1}', [kbps('video-bitrate'), kbps('audio-bitrate')])),
    (tr('音频'), or(value('audio-codec-name'))),
    (tr('缓冲'), value('demuxer-cache-duration').isEmpty ? '—' : tr('{0} 秒', [number('demuxer-cache-duration', digits: 1)])),
    (tr('下载速度'), speed(value('cache-speed'))),
  ];
}
