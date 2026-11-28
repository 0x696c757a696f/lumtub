import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import 'motion.dart';

/// Applies a new theme in a single frame and fades the old look out over
/// it: when the ambient [ThemeData] changes, a picture of the frame on
/// screen is kept above the page and faded away, instead of every colour
/// being interpolated and the whole tree rebuilt on each frame.
class ThemeCrossFade extends StatefulWidget {
  const ThemeCrossFade(
      {required this.child, super.key, this.duration = ThemeCrossFade.standard, this.instant});
  final Duration duration;

  /// Asked at each change: whether to switch without a fade.
  final bool Function()? instant;
  final Widget child;

  static const standard = Duration(milliseconds: 250);

  @visibleForTesting
  static bool fadingAt(Element element) =>
      element is StatefulElement &&
      element.state is _ThemeCrossFadeState &&
      (element.state as _ThemeCrossFadeState)._old != null;

  @override
  State<ThemeCrossFade> createState() => _ThemeCrossFadeState();
}

class _ThemeCrossFadeState extends State<ThemeCrossFade> with SingleTickerProviderStateMixin {
  final _boundary = GlobalKey();
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addStatusListener(_statusChanged);
  ThemeData? _seen;
  ui.Image? _old;
  Size? _oldSize;
  Size? _captureSize;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = Theme.of(context);
    final before = _seen;
    _seen = theme;
    if (before == null || before == theme) return;
    final duration = Motion.of(widget.duration);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final hidden = lifecycle == AppLifecycleState.hidden ||
        lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.detached;
    final snapshot =
        Motion.reduced || hidden || duration == Duration.zero || (widget.instant?.call() ?? false)
            ? null
            : _capture();
    if (snapshot == null) return _drop();
    _drop();
    _old = snapshot;
    _oldSize = _captureSize;
    _controller.duration = duration;
    _controller.forward(from: 0);
  }

  ui.Image? _capture() {
    final box = _boundary.currentContext?.findRenderObject();
    if (box is! RenderRepaintBoundary || !box.hasSize) return null;
    try {
      final image = box.toImageSync(pixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1);
      _captureSize = box.size;
      return image;
    } catch (_) {
      return null;
    }
  }

  void _drop() {
    _controller.stop();
    _old?.dispose();
    _old = null;
    _oldSize = null;
  }

  void _statusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _drop();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    _old?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final old = _old;
    return RepaintBoundary(
      key: _boundary,
      child: Stack(fit: StackFit.passthrough, children: [
        RepaintBoundary(child: widget.child),
        if (old != null)
          Positioned.fill(
            child: IgnorePointer(
                child: RepaintBoundary(
                    child: CustomPaint(painter: _OldFrame(old, _oldSize!, _controller)))),
          ),
      ]),
    );
  }
}

/// The previous frame at weight 1 - progress. The page beneath is scaled by
/// the rest and the picture added, so a window that is see-through keeps
/// its opacity all along; a plain source-over would not.
class _OldFrame extends CustomPainter {
  _OldFrame(this.image, this.captured, this.progress) : super(repaint: progress);
  final ui.Image image;
  final Size captured;
  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size != captured) return;
    final weight = 1 - Ease.curve.transform(progress.value.clamp(0.0, 1.0));
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, weight)
          ..blendMode = BlendMode.dstOut);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, weight)
        ..blendMode = BlendMode.plus
        ..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_OldFrame old) => old.image != image || old.captured != captured;
}
