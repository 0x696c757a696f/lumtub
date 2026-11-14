// Adapted from prism_ui (FlClash), GPL-3.0.
// Changes: follows Lumtub's reduced motion and easing, and can be told to
// switch at once, as while a video shows.

import 'dart:ui' as ui show Image;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'motion.dart';

/// Switches the theme in one frame and fades a picture of the frame before
/// it out on top, instead of blending [ThemeData] and building every widget
/// that reads it again on each frame of the change.
///
/// The change is instant on the first frame, with animations reduced,
/// while the window is hidden, and while [instant] says so. The picture
/// takes no pointer events: they reach the new frame under it.
class ThemeCrossFade extends StatefulWidget {
  const ThemeCrossFade({super.key, this.duration = ThemeCrossFade.standard, this.instant, required this.child});
  final Duration duration;
  /// Whether to switch at once for now; asked on each change.
  final bool Function()? instant;
  final Widget child;

  static const standard = Duration(milliseconds: 250);

  /// Whether the cross-fade built at [element] still draws the old frame.
  @visibleForTesting
  static bool fadingAt(Element element) => element is StatefulElement && element.state is _ThemeCrossFadeState && (element.state as _ThemeCrossFadeState)._snapshot != null;

  @override
  State<ThemeCrossFade> createState() => _ThemeCrossFadeState();
}

class _ThemeCrossFadeState extends State<ThemeCrossFade> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this)..addStatusListener(_status);
  late final _progress = CurvedAnimation(parent: _controller, curve: Ease.curve);
  final _fadeKey = GlobalKey();
  ThemeData? _theme;
  ui.Image? _snapshot;
  Size? _snapshotSize;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = Theme.of(context);
    final previous = _theme;
    _theme = theme;
    if (previous != null && previous != theme) _capture();
  }

  bool get _instant {
    if (Motion.reduced || (widget.instant?.call() ?? false)) return true;
    return switch (WidgetsBinding.instance.lifecycleState) {
      AppLifecycleState.hidden || AppLifecycleState.paused || AppLifecycleState.detached => true,
      _ => false,
    };
  }

  void _capture() {
    final fade = _fadeKey.currentContext?.findRenderObject();
    final duration = Motion.of(widget.duration);
    final image = fade is _RenderThemeCrossFade && duration > Duration.zero && !_instant ? fade.capture(MediaQuery.devicePixelRatioOf(context)) : null;
    if (fade is! _RenderThemeCrossFade || image == null) {
      // A fade still running from an earlier change ends with this one.
      _controller.stop();
      _drop();
      return;
    }
    _snapshot?.dispose();
    _snapshot = image;
    _snapshotSize = fade.size;
    _controller
      ..duration = duration
      ..forward(from: 0);
  }

  void _status(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) setState(_drop);
  }

  void _drop() {
    _snapshot?.dispose();
    _snapshot = null;
    _snapshotSize = null;
  }

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    _drop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ThemeCrossFadeLayer(
        key: _fadeKey,
        snapshot: _snapshot,
        snapshotSize: _snapshotSize,
        progress: _progress,
        child: RepaintBoundary(child: widget.child),
      );
}

class _ThemeCrossFadeLayer extends SingleChildRenderObjectWidget {
  const _ThemeCrossFadeLayer({super.key, required this.snapshot, required this.snapshotSize, required this.progress, super.child});
  final ui.Image? snapshot;
  final Size? snapshotSize;
  final Animation<double> progress;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderThemeCrossFade(snapshot: snapshot, snapshotSize: snapshotSize, progress: progress);

  @override
  void updateRenderObject(BuildContext context, _RenderThemeCrossFade renderObject) {
    renderObject
      ..snapshot = snapshot
      ..snapshotSize = snapshotSize
      ..progress = progress;
  }
}

class _RenderThemeCrossFade extends RenderProxyBox {
  _RenderThemeCrossFade({ui.Image? snapshot, Size? snapshotSize, required Animation<double> progress})
      : _snapshot = snapshot,
        _snapshotSize = snapshotSize,
        _progress = progress;

  @override
  bool get isRepaintBoundary => true;

  ui.Image? _snapshot;
  set snapshot(ui.Image? value) {
    if (identical(value, _snapshot)) return;
    _snapshot = value;
    markNeedsPaint();
  }

  Size? _snapshotSize;
  set snapshotSize(Size? value) => _snapshotSize = value;

  Animation<double> _progress;
  set progress(Animation<double> value) {
    if (identical(value, _progress)) return;
    if (attached) {
      _progress.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _progress = value;
    markNeedsPaint();
  }

  /// The frame on screen, a fade in progress included. The layer still
  /// holds it while the next frame builds.
  ui.Image? capture(double pixelRatio) {
    final layer = this.layer;
    if (!attached || !hasSize || layer is! OffsetLayer) return null;
    return layer.toImageSync(Offset.zero & size, pixelRatio: pixelRatio);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _progress.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final image = _snapshot;
    final weight = 1 - _progress.value;
    // A window resized meanwhile no longer matches the picture.
    if (image == null || weight <= 0 || _snapshotSize != size) return;
    final rect = offset & size;
    final fade = Color.fromRGBO(0, 0, 0, weight);
    // dstOut then plus mixes premultiplied pixels, so a see-through window
    // keeps its opacity through the fade where srcOver would raise it.
    context.canvas
      ..drawRect(rect, Paint()
        ..blendMode = BlendMode.dstOut
        ..color = fade)
      ..drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        rect,
        Paint()
          ..blendMode = BlendMode.plus
          ..color = fade
          ..filterQuality = FilterQuality.low,
      );
  }
}
