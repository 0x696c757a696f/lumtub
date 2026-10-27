import 'dart:async';
import 'dart:math';
import 'dart:ui';

/// The size libmpv draws the picture at. Without one, media_kit draws every
/// frame at the video's own size and Flutter scales it down afterwards, so a
/// 4K video in a small window renders 8 million pixels a frame to show one.
/// Drawn at the size it is shown, libmpv scales once with its own scaler.
class VideoOutputSize {
  VideoOutputSize(this._apply, {this.delay = const Duration(milliseconds: 250)});

  /// Sets the output size; null and null is the video's own size.
  final Future<void> Function(int? width, int? height) _apply;
  final Duration delay;

  final _boxes = <Object, Size>{};
  Size _video = Size.zero;
  Timer? _timer;
  (int, int)? _applied;
  bool _native = true;

  /// [owner] now shows the video in [box], in physical pixels.
  void show(Object owner, Size box) {
    if (_boxes[owner] == box) return;
    _boxes[owner] = box;
    _schedule();
  }

  /// [owner] no longer shows the video.
  void hide(Object owner) {
    if (_boxes.remove(owner) != null) _schedule();
  }

  /// The video's own size changed.
  set video(Size size) {
    if (size == _video) return;
    _video = size;
    _schedule();
  }

  bool _cover = false;
  bool _hidden = false;

  /// While the window is minimised or in the tray, the picture is drawn
  /// small: it keeps playing, so it is there at once on return, at a
  /// fraction of the GPU work.
  set hidden(bool value) {
    if (value == _hidden) return;
    _hidden = value;
    _timer?.cancel();
    // Back to full size without the usual pause, so the first frames are sharp.
    value ? _schedule() : _update();
  }

  /// The box drawn into while hidden.
  static const hiddenBox = Size(320, 180);

  /// Whether the picture is zoomed or stretched to fill its box, so it is
  /// drawn large enough to cover the box rather than fit inside it.
  set cover(bool value) {
    if (value == _cover) return;
    _cover = value;
    _schedule();
  }

  /// The size to draw at for the video [video] shown in the largest of
  /// [boxes]: the video fitted into that box (covering it with [cover]),
  /// or null for the video's own size when the box is as large or there is
  /// nothing to fit.
  static (int, int)? target(Size video, Iterable<Size> boxes, {bool cover = false}) {
    if (video.isEmpty || boxes.isEmpty) return null;
    final box = boxes.reduce((a, b) => a.width * a.height >= b.width * b.height ? a : b);
    if (box.isEmpty) return null;
    final across = box.width / video.width, down = box.height / video.height;
    final scale = cover ? max(across, down) : min(across, down);
    if (scale >= 1) return null;
    // Even sizes; rounded up when covering, so no edge is left short.
    int even(double v) => max(2, (cover ? (v / 2).ceil() : (v / 2).round()) * 2);
    return (even(video.width * scale), even(video.height * scale));
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(delay, _update);
  }

  /// Whether the picture is in a box on screen now.
  bool get onScreen => _boxes.isNotEmpty && !_hidden;

  /// Registers the picture's texture again at the same size, for a picture
  /// that stopped reaching the screen.
  Future<void> refresh() async {
    final size = _applied ?? (_video.isEmpty ? null : (_video.width.round(), _video.height.round()));
    if (size == null) return;
    await _apply(size.$1, size.$2 + 2);
    final applied = _applied;
    await (applied == null ? _apply(null, null) : _apply(applied.$1, applied.$2));
  }

  void _update() {
    // While a page covers the video, the size stays: drawing it again at
    // another size for nobody to see costs a texture swap twice.
    if (_boxes.isEmpty && !_hidden) return;
    final next = target(_video, _hidden ? const [hiddenBox] : _boxes.values, cover: _cover);
    if (next == null) {
      if (_native) return;
      _native = true;
      _applied = null;
      unawaited(_apply(null, null));
      return;
    }
    if (next == _applied) return;
    _native = false;
    _applied = next;
    unawaited(_apply(next.$1, next.$2));
  }

  void dispose() => _timer?.cancel();
}
