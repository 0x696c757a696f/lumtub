import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Keeps libmpv's video texture no larger than the pixels it is shown in.
///
/// media_kit renders each frame at the video's own size, copies it to the
/// UI, and Flutter scales it down; a 1440p60 video in a 1300 px wide player
/// does that work several times over, and on some GPUs the UI then shows
/// black frames. With a smaller texture mpv scales once, with its own scaler.
class VideoTextureSize extends StatefulWidget {
  const VideoTextureSize({super.key, required this.controller, required this.fullscreen, required this.child});

  final VideoController controller;
  /// Whether this is the fullscreen copy of the player. While fullscreen is
  /// open, the player on the page underneath does not size the texture.
  final bool fullscreen;
  final Widget child;

  @override
  State<VideoTextureSize> createState() => _VideoTextureSizeState();
}

class _VideoTextureSizeState extends State<VideoTextureSize> {
  static final _fullscreenOpen = ValueNotifier(false);

  final _subscriptions = <StreamSubscription<Object?>>[];
  Timer? _debounce;
  Size _box = Size.zero;

  @override
  void initState() {
    super.initState();
    if (widget.fullscreen) _fullscreenOpen.value = true;
    _fullscreenOpen.addListener(_schedule);
    final player = widget.controller.player;
    _subscriptions
      ..add(player.stream.width.listen((_) => _schedule()))
      ..add(player.stream.height.listen((_) => _schedule()));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _fullscreenOpen.removeListener(_schedule);
    if (widget.fullscreen) _fullscreenOpen.value = false;
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    // Resizing recreates the texture, so a window being dragged larger
    // does it once, after it stops.
    _debounce = Timer(const Duration(milliseconds: 300), _apply);
  }

  void _apply() {
    if (!mounted || (!widget.fullscreen && _fullscreenOpen.value)) return;
    final player = widget.controller.player;
    final size = textureSizeFor(Size((player.state.width ?? 0).toDouble(), (player.state.height ?? 0).toDouble()), _box);
    unawaited(widget.controller.setSize(width: size?.width.toInt(), height: size?.height.toInt()));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final ratio = MediaQuery.devicePixelRatioOf(context);
        final box = Size(constraints.maxWidth * ratio, constraints.maxHeight * ratio);
        if (box != _box && box.isFinite) {
          _box = box;
          _schedule();
        }
        return widget.child;
      });
}

/// The texture size for a [video] shown in [box] physical pixels: the
/// video's aspect, large enough to cover the box (so zoomed fit modes stay
/// sharp), or null for the video's own size when it is not larger.
@visibleForTesting
Size? textureSizeFor(Size video, Size box) {
  if (video.width <= 0 || video.height <= 0 || box.width <= 0 || box.height <= 0) return null;
  final scale = max(box.width / video.width, box.height / video.height);
  if (scale >= 1) return null;
  // Even sizes: some GPU paths reject odd ones.
  int even(double value) => max(2, (value / 2).ceil() * 2);
  return Size(even(video.width * scale).toDouble(), even(video.height * scale).toDouble());
}
