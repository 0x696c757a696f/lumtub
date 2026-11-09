import 'package:flutter/material.dart';

/// Ink for a press with no ripple: the whole control darkens at once while
/// it is held, and fades back when let go, so a click is felt more than a
/// hover.
class FlatPress extends InteractiveInkFeature {
  FlatPress({
    required super.controller,
    required super.referenceBox,
    required super.color,
    required TextDirection textDirection,
    ShapeBorder? customBorder,
    BorderRadius? borderRadius,
    RectCallback? rectCallback,
    super.onRemoved,
  })  : _textDirection = textDirection,
        _customBorder = customBorder,
        _borderRadius = borderRadius ?? BorderRadius.zero,
        _rectCallback = rectCallback {
    _alpha = AnimationController(duration: const Duration(milliseconds: 40), vsync: controller.vsync)
      ..addListener(controller.markNeedsPaint)
      ..addStatusListener((status) {
        if (status == AnimationStatus.dismissed) dispose();
      })
      ..forward();
    controller.addInkFeature(this);
  }

  static const InteractiveInkFeatureFactory splashFactory = _FlatPressFactory();

  final TextDirection _textDirection;
  final ShapeBorder? _customBorder;
  final BorderRadius _borderRadius;
  final RectCallback? _rectCallback;
  late final AnimationController _alpha;
  bool _released = false;

  void _release() {
    if (_released) return;
    _released = true;
    // A quick click still shows: the wash finishes coming in, then fades.
    _alpha.duration = const Duration(milliseconds: 260);
    _alpha.reverse(from: 1);
  }

  @override
  void confirm() => _release();

  @override
  void cancel() => _release();

  @override
  void dispose() {
    _alpha.dispose();
    super.dispose();
  }

  @override
  void paintFeature(Canvas canvas, Matrix4 transform) {
    final paint = Paint()..color = color.withValues(alpha: color.a * Curves.easeOut.transform(_alpha.value));
    final rect = _rectCallback?.call() ?? Offset.zero & referenceBox.size;
    canvas.save();
    canvas.transform(transform.storage);
    if (_customBorder case final border?) {
      canvas.drawPath(border.getOuterPath(rect, textDirection: _textDirection), paint);
    } else {
      canvas.drawRRect(_borderRadius.resolve(_textDirection).toRRect(rect), paint);
    }
    canvas.restore();
  }
}

class _FlatPressFactory extends InteractiveInkFeatureFactory {
  const _FlatPressFactory();

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) =>
      FlatPress(
        controller: controller,
        referenceBox: referenceBox,
        color: color,
        textDirection: textDirection,
        customBorder: customBorder,
        borderRadius: borderRadius,
        rectCallback: rectCallback,
        onRemoved: onRemoved,
      );
}
