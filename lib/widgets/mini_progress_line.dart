import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'position_ticks.dart';

/// The thin played/buffered line along the bottom edge of the video, shown
/// while the controls are hidden.
class MiniProgressLine extends StatefulWidget {
  const MiniProgressLine({super.key, required this.player, required this.color});
  final Player player;
  final Color color;

  static const height = 2.5;

  @override
  State<MiniProgressLine> createState() => _MiniProgressLineState();
}

class _MiniProgressLineState extends State<MiniProgressLine> {
  // Made once per player, so a rebuild keeps the same subscription.
  late Stream<Duration> _position = coarsePosition(widget.player);

  @override
  void didUpdateWidget(MiniProgressLine old) {
    super.didUpdateWidget(old);
    if (old.player != widget.player) _position = coarsePosition(widget.player);
  }

  Player get player => widget.player;
  Color get color => widget.color;

  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
        stream: _position,
        initialData: player.state.position,
        builder: (context, _) {
          final total = player.state.duration.inMilliseconds;
          double fraction(Duration d) =>
              total <= 0 ? 0 : (d.inMilliseconds / total).clamp(0.0, 1.0);
          return SizedBox(
            height: MiniProgressLine.height,
            child: Stack(fit: StackFit.expand, children: [
              const ColoredBox(color: Color(0x33FFFFFF)),
              FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction(player.state.buffer),
                  child: ColoredBox(color: color.withValues(alpha: 0.4))),
              FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction(player.state.position),
                  child: ColoredBox(color: color)),
            ]),
          );
        },
      );
}
