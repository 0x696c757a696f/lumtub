import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'position_ticks.dart';

/// The thin played/buffered line along the bottom edge of the video, shown
/// while the controls are hidden.
class MiniProgressLine extends StatelessWidget {
  const MiniProgressLine({super.key, required this.player, required this.color});
  final Player player;
  final Color color;

  static const height = 2.5;

  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
        stream: coarsePosition(player),
        initialData: player.state.position,
        builder: (context, _) {
          final total = player.state.duration.inMilliseconds;
          double fraction(Duration d) => total <= 0 ? 0 : (d.inMilliseconds / total).clamp(0.0, 1.0);
          return SizedBox(
            height: height,
            child: Stack(fit: StackFit.expand, children: [
              const ColoredBox(color: Color(0x33FFFFFF)),
              FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: fraction(player.state.buffer), child: ColoredBox(color: color.withValues(alpha: 0.4))),
              FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: fraction(player.state.position), child: ColoredBox(color: color)),
            ]),
          );
        },
      );
}
