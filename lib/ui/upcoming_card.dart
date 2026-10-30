import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'common.dart';
import 'app_icons.dart';

/// How long until a stream starts, as the card's headline.
String startsIn(Duration? left) {
  if (left == null || left < const Duration(seconds: 1)) return tr('即将开始');
  final days = left.inDays;
  final hours = left.inHours.remainder(24);
  final minutes = left.inMinutes.remainder(60);
  final seconds = left.inSeconds.remainder(60);
  if (days > 0) return tr('{0} 天 {1} 小时后开始', [days, hours]);
  if (left.inHours > 0) return tr('{0} 小时 {1} 分后开始', [left.inHours, minutes]);
  if (minutes > 0) return tr('{0} 分 {1} 秒后开始', [minutes, seconds]);
  return tr('{0} 秒后开始', [seconds]);
}

/// Covers the player while a live stream or premiere has not started: its
/// thumbnail, when it starts and a countdown. Lumtub opens it by itself.
class UpcomingCard extends StatefulWidget {
  const UpcomingCard({super.key, required this.thumbnail, required this.start, required this.onRetry});
  final ImageProvider thumbnail;
  /// When it is scheduled to start, when known.
  final DateTime? start;
  final VoidCallback onRetry;

  @override
  State<UpcomingCard> createState() => _UpcomingCardState();
}

class _UpcomingCardState extends State<UpcomingCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.start;
    final left = start?.difference(DateTime.now());
    final late = left != null && left < -const Duration(minutes: 1);
    const white = Colors.white;
    return Stack(fit: StackFit.expand, children: [
      // The blur stays in its own layer, so the spinner and the countdown
      // ticking above it do not blur the picture again every frame.
      RepaintBoundary(
        child: Stack(fit: StackFit.expand, children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 16, sigmaY: 16, tileMode: TileMode.decal),
            child: Image(
              image: widget.thumbnail,
              fit: BoxFit.cover,
              errorBuilder: (context, _, __) => const SizedBox.shrink(),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x99000000), Color(0xCC000000)]),
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFE53935), borderRadius: BorderRadius.circular(999)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(AppIcons.broadcast, size: 16, color: white),
                  const SizedBox(width: 4),
                  Text(tr('直播预告'), style: const TextStyle(color: white, fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
              const SizedBox(height: 16),
              Text(
                late ? tr('即将开始') : startsIn(left),
                style: const TextStyle(color: white, fontSize: 30, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
              ),
              if (start != null) ...[
                const SizedBox(height: 8),
                Text(
                  late ? tr('原定 {0} 开始，等待主播开播', [formatScheduledStart(start)]) : tr('开始于 {0}', [formatScheduledStart(start)]),
                  style: const TextStyle(color: Color(0xDDFFFFFF), fontSize: 14),
                ),
              ],
              const SizedBox(height: 24),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const RepaintBoundary(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xAAFFFFFF)))),
                const SizedBox(width: 8),
                Text(tr('开始后会自动播放'), style: const TextStyle(color: Color(0xAAFFFFFF), fontSize: 12)),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: widget.onRetry,
                  style: TextButton.styleFrom(foregroundColor: white),
                  child: Text(tr('现在重试')),
                ),
              ]),
            ]),
          ),
        ),
      ),
    ]);
  }
}
