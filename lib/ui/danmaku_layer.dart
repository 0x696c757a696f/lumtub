import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../app_log.dart';
import '../danmaku.dart';

/// Draws the 弹幕 of [overlay] over the picture, moved at every frame of
/// the display so they glide at any refresh rate. Each message is drawn
/// once into an image when it comes on and only moved after that.
class DanmakuLayer extends StatefulWidget {
  const DanmakuLayer({super.key, required this.overlay});

  final ValueListenable<DanmakuOverlay?> overlay;

  @override
  State<DanmakuLayer> createState() => _DanmakuLayerState();
}

class _Sprite {
  _Sprite(this.image, this.pad);
  final ui.Image image;

  /// Room left of the text, for the outline, in image pixels.
  final double pad;
}

class _DanmakuLayerState extends State<DanmakuLayer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_frame);
  final _clock = ValueNotifier<double>(0);
  DanmakuOverlay? _overlay;
  StreamSubscription<Object?>? _playing;
  StreamSubscription<Object?>? _position;

  List<DanmakuItem> _items = const [];
  int _itemsRevision = -1;

  /// The moment the items were asked for: they hold until a little later.
  double? _itemsAt;
  static const _lookAhead = 1500.0;
  static const _reaskAfter = 1000.0;

  final _sprites = <String, _Sprite>{};
  final _drawing = <String>{};
  double _spriteHeight = 0;
  int _generation = 0;
  Size _size = Size.zero;
  double _ratio = 1;
  double? _paintedAt;
  Timer? _idle;

  @override
  void initState() {
    super.initState();
    widget.overlay.addListener(_attach);
    _attach();
  }

  @override
  void didUpdateWidget(DanmakuLayer old) {
    super.didUpdateWidget(old);
    if (old.overlay != widget.overlay) {
      old.overlay.removeListener(_attach);
      widget.overlay.addListener(_attach);
      _attach();
    }
  }

  void _attach() {
    final next = widget.overlay.value;
    if (next == _overlay) return;
    _overlay?.removeListener(_wake);
    unawaited(_playing?.cancel());
    unawaited(_position?.cancel());
    _playing = null;
    _position = null;
    _overlay = next;
    _clear();
    if (next != null) {
      next.addListener(_wake);
      // Playing again, or a seek while paused, moves the clock.
      _playing = next.player.stream.playing.listen((_) => _wake());
      _position = next.player.stream.position.listen((_) {
        if (!_ticker.isActive && !next.player.state.playing) _wake();
      });
    }
    _wake();
  }

  void _clear() {
    _generation++;
    for (final sprite in _sprites.values) {
      sprite.image.dispose();
    }
    _sprites.clear();
    _drawing.clear();
    _items = const [];
    _itemsRevision = -1;
    _itemsAt = null;
    _paintedAt = null;
  }

  void _wake() {
    _idle?.cancel();
    if (!mounted) return;
    final overlay = _overlay;
    if (overlay == null || !overlay.running) {
      if (_ticker.isActive) _ticker.stop();
      if (_items.isNotEmpty || _sprites.isNotEmpty) {
        _clear();
        _clock.value = -1;
      }
      return;
    }
    if (!_ticker.isActive) _ticker.start();
  }

  void _frame(Duration _) {
    final overlay = _overlay;
    if (overlay == null || !overlay.running || _size.isEmpty) {
      _ticker.stop();
      return;
    }
    final now = overlay.now();
    final asked = _itemsAt;
    final changed = overlay.revision != _itemsRevision;
    if (changed || asked == null || now < asked || now > asked + _reaskAfter) {
      _items = overlay.visibleAt(now - overlay.duration, now + _lookAhead);
      _itemsRevision = overlay.revision;
      _itemsAt = now;
      _prepare(overlay);
    }
    if (_items.isEmpty && _drawing.isEmpty) {
      // Nothing to fly: no frames are asked for until a message is near.
      if (_paintedAt != null) {
        _paintedAt = null;
        _clock.value = now;
      }
      _ticker.stop();
      _idle?.cancel();
      _idle = Timer(const Duration(milliseconds: 500), _wake);
      return;
    }
    if (now != _paintedAt || changed) {
      _paintedAt = now;
      _clock.value = now;
    } else if (!overlay.moving && _drawing.isEmpty) {
      // Paused and drawn: nothing moves until played or sought.
      _ticker.stop();
    }
  }

  /// Draws the images of the items about to show and lets go of the rest.
  void _prepare(DanmakuOverlay overlay) {
    final painter = overlay.painter;
    if (painter == null) return;
    final height = _size.height * _ratio;
    if ((height - _spriteHeight).abs() > 1) {
      _clear();
      _spriteHeight = height;
      _items = overlay.visibleAt(overlay.now() - overlay.duration, overlay.now() + _lookAhead);
      _itemsRevision = overlay.revision;
      _itemsAt = overlay.now();
    }
    final wanted = {for (final item in _items) item.key};
    for (final key in _sprites.keys.where((key) => !wanted.contains(key)).toList()) {
      _sprites.remove(key)!.image.dispose();
    }
    final generation = _generation;
    for (final item in _items) {
      if (_sprites.containsKey(item.key) || !_drawing.add(item.key)) continue;
      unawaited(painter.image(item.parts, osdHeight: height, paid: item.paid).then((drawn) {
        if (generation != _generation || !mounted) {
          drawn?.$1.dispose();
          return;
        }
        _drawing.remove(item.key);
        if (drawn == null) return;
        _sprites.remove(item.key)?.image.dispose();
        _sprites[item.key] = _Sprite(drawn.$1, drawn.$2);
        _paintedAt = null;
        _wake();
      }, onError: (Object e) {
        _drawing.remove(item.key);
        logWarn('Could not draw a danmaku message: $e');
      }));
    }
  }

  @override
  void dispose() {
    widget.overlay.removeListener(_attach);
    _overlay?.removeListener(_wake);
    unawaited(_playing?.cancel());
    unawaited(_position?.cancel());
    _idle?.cancel();
    _ticker.dispose();
    _clear();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _ratio = MediaQuery.devicePixelRatioOf(context);
    return IgnorePointer(
      child: RepaintBoundary(
        child: LayoutBuilder(builder: (context, constraints) {
          final size = constraints.biggest;
          if (size.isFinite && size != _size) {
            _size = size;
            final overlay = _overlay;
            if (overlay != null) overlay.box = (width: size.width, height: size.height);
            WidgetsBinding.instance.addPostFrameCallback((_) => _wake());
          }
          return CustomPaint(size: Size.infinite, painter: _DanmakuPainter(this));
        }),
      ),
    );
  }
}

class _DanmakuPainter extends CustomPainter {
  _DanmakuPainter(this.state) : super(repaint: state._clock);

  final _DanmakuLayerState state;
  final _paint = Paint()..filterQuality = FilterQuality.low;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = state._overlay;
    final settings = overlay?.settings;
    if (overlay == null || settings == null || state._clock.value < 0) return;
    final now = state._clock.value;
    final duration = overlay.duration;
    final ratio = state._ratio;
    final across = size.width / 1920;
    final line = settings.size * 1.25 * size.height / 1080;
    for (final item in state._items) {
      if (item.start > now || item.start + duration <= now) continue;
      final sprite = state._sprites[item.key];
      if (sprite == null) continue;
      final image = sprite.image;
      final x = item.x(now, duration) * across - sprite.pad / ratio;
      final width = image.width / ratio;
      if (x >= size.width || x + width <= 0) continue;
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(x, item.lane * line, width, image.height / ratio),
        _paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DanmakuPainter old) => old.state != state;
}
