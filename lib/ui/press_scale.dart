import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'motion.dart';

/// A card that sinks a little while a finger or the mouse button holds it,
/// and springs back when let go. It only watches the pointer, so the card's
/// own taps, long presses, hover and menus work as before; a press that
/// turns into a scroll lets go at once. Only the transform animates: the
/// card itself is not built again. With animations reduced it stays still.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child});
  final Widget child;

  static const scale = 0.97;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;
  int? _pointer;
  Offset _down = Offset.zero;

  void _press(PointerDownEvent event) {
    if (Motion.reduced || _pointer != null) return;
    if (event.kind == PointerDeviceKind.mouse && event.buttons != kPrimaryMouseButton) return;
    _pointer = event.pointer;
    _down = event.position;
    setState(() => _pressed = true);
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer == _pointer && (event.position - _down).distance > computeHitSlop(event.kind, MediaQuery.maybeGestureSettingsOf(context))) _let(event);
  }

  void _let(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    if (mounted) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: _press,
        onPointerMove: _move,
        onPointerUp: _let,
        onPointerCancel: _let,
        child: AnimatedScale(
          scale: _pressed ? PressScale.scale : 1,
          duration: Ease.press,
          curve: Ease.out,
          child: widget.child,
        ),
      );
}
