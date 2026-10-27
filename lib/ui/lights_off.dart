import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'motion.dart';
import 'theme.dart';

/// 关灯: everything but the video goes dark, like Enhancer for YouTube's
/// cinema mode. Kept for the session, like 剧场模式; with 播放时自动关灯 it
/// follows playing and paused.
final lightsOff = ValueNotifier(false);

/// The watch page's player: the part [LightsOffLayer] leaves lit.
final lightsOffHole = GlobalKey(debugLabel: 'lightsOffHole');

/// Darkens what is under it except [lightsOffHole]. A click on the dark
/// part turns the lights back on; the player stays usable through the hole.
class LightsOffLayer extends StatefulWidget {
  const LightsOffLayer({super.key, required this.dim, this.radius = AppStyle.cardRadius});

  /// How dark, from 0 to 1.
  final double dim;
  final BorderRadius radius;

  @override
  State<LightsOffLayer> createState() => _LightsOffLayerState();
}

class _LightsOffLayerState extends State<LightsOffLayer> with SingleTickerProviderStateMixin {
  late final _fade = AnimationController(vsync: this, duration: Motion.of(const Duration(milliseconds: 250)))..forward();
  Rect? _hole;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_measure);
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  /// Follows the player after every frame, so scrolling, 剧场模式 and
  /// window resizes move the hole with it. Only a change repaints.
  void _measure(Duration _) {
    if (!mounted) return;
    final hole = holeRect(lightsOffHole, context.findRenderObject());
    if (hole != _hole) setState(() => _hole = hole);
    WidgetsBinding.instance.addPostFrameCallback(_measure);
  }

  @override
  Widget build(BuildContext context) {
    final hole = _hole;
    if (hole == null) return const SizedBox.shrink();
    // Its own layer: the fade and a moving hole repaint the dark layer
    // only, not the page under it.
    return _HoleHitTest(
      hole: hole,
      child: RepaintBoundary(child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => lightsOff.value = false,
        child: AnimatedBuilder(
          animation: _fade,
          builder: (context, _) => CustomPaint(
            size: Size.infinite,
            painter: _DarkPainter(hole: widget.radius.toRRect(hole), color: Colors.black.withValues(alpha: widget.dim * _fade.value)),
          ),
        ),
      )),
    );
  }
}

/// Where [key]'s box is inside [layer], or null when either is not laid out.
Rect? holeRect(GlobalKey key, RenderObject? layer) {
  final target = key.currentContext?.findRenderObject();
  if (target is! RenderBox || layer is! RenderBox || !target.attached || !layer.attached || !target.hasSize || !layer.hasSize) return null;
  final topLeft = layer.globalToLocal(target.localToGlobal(Offset.zero));
  return topLeft & target.size;
}

class _DarkPainter extends CustomPainter {
  const _DarkPainter({required this.hole, required this.color});
  final RRect hole;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(hole);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_DarkPainter old) => old.hole != hole || old.color != color;
}

/// Lets pointers inside [hole] through to the player below.
class _HoleHitTest extends SingleChildRenderObjectWidget {
  const _HoleHitTest({required this.hole, super.child});
  final Rect hole;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHoleHitTest(hole);

  @override
  void updateRenderObject(BuildContext context, _RenderHoleHitTest renderObject) => renderObject.hole = hole;
}

class _RenderHoleHitTest extends RenderProxyBox {
  _RenderHoleHitTest(this.hole);
  Rect hole;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) => !hole.contains(position) && super.hitTest(result, position: position);
}
