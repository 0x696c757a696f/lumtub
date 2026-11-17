import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Lumtub: the part of the screen, in global coordinates, that a side
/// panel covers while it is open over the player. Each [Video] draws its
/// picture and subtitles in the room left beside it, so changes made in
/// the panel show on the video instead of under the panel.
final ValueNotifier<Rect?> videoObstruction = ValueNotifier<Rect?>(null);

/// Moves [child] out from under [videoObstruction] when it covers one
/// side of this box and enough of the box is left beside it.
class VideoObstructionAvoider extends StatefulWidget {
  const VideoObstructionAvoider({super.key, required this.child});
  final Widget child;

  /// Less room than this share of the box is too small to watch in; the
  /// picture stays where it is then.
  static const minShare = 0.3;

  /// The insets that keep a box at [box] clear of [covered].
  static EdgeInsets insetsFor(Rect box, Rect? covered) {
    if (covered == null || box.isEmpty) return EdgeInsets.zero;
    final overlap = box.intersect(covered);
    if (overlap.width <= 0 || overlap.height < box.height / 2) return EdgeInsets.zero;
    var left = 0.0, right = 0.0;
    if (covered.right >= box.right && covered.left > box.left) {
      right = box.right - covered.left;
    } else if (covered.left <= box.left && covered.right < box.right) {
      left = covered.right - box.left;
    } else {
      return EdgeInsets.zero;
    }
    if (box.width - left - right < box.width * minShare) return EdgeInsets.zero;
    return EdgeInsets.only(left: math.max(0, left), right: math.max(0, right));
  }

  @override
  State<VideoObstructionAvoider> createState() => _VideoObstructionAvoiderState();
}

class _VideoObstructionAvoiderState extends State<VideoObstructionAvoider> {
  var _insets = EdgeInsets.zero;
  var _scheduled = false;

  @override
  void initState() {
    super.initState();
    videoObstruction.addListener(_schedule);
    if (videoObstruction.value != null) _schedule();
  }

  @override
  void dispose() {
    videoObstruction.removeListener(_schedule);
    super.dispose();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) return;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      final insets = VideoObstructionAvoider.insetsFor(rect, videoObstruction.value);
      if (insets != _insets) setState(() => _insets = insets);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    // A new size or place is measured again after this frame.
    if (videoObstruction.value != null) _schedule();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AnimatedPadding(
      duration: still ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: _insets,
      child: widget.child,
    );
  }
}
