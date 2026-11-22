/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:async';
import 'dart:math';
import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:media_kit_video/src/video_controller/video_controller.dart';

/// {@template subtitle_view}
///
/// SubtitleView
/// ------------
///
/// [SubtitleView] widget is used to display the subtitles on top of the [Video].
///
/// {@endtemplate}
class SubtitleView extends StatefulWidget {
  /// The [VideoController] reference to control this [SubtitleView] output.
  final VideoController controller;

  /// The configuration to be used for the subtitles.
  final SubtitleViewConfiguration configuration;

  /// {@macro subtitle_view}
  const SubtitleView({
    super.key,
    required this.controller,
    required this.configuration,
  });

  @override
  SubtitleViewState createState() => SubtitleViewState();
}

class SubtitleViewState extends State<SubtitleView> {
  late List<String> subtitle = widget.controller.player.state.subtitle;
  late EdgeInsets padding = widget.configuration.padding;
  late Duration duration = const Duration(milliseconds: 100);

  // The [StreamSubscription] to listen to the subtitle changes.
  StreamSubscription<List<String>>? subscription;

  // Lumtub: the secondary line shown when the secondary subtitle changed,
  // kept hidden until mpv sends another. Turned off, mpv reports the text
  // as unavailable, which media_kit ignores, so the old line would stay.
  String? staleSecondary;

  // The reference width for calculating the visible text scale factor.
  static const kTextScaleFactorReferenceWidth = 1920.0;
  // The reference height for calculating the visible text scale factor.
  static const kTextScaleFactorReferenceHeight = 1080.0;

  // Lumtub: the secondary line on screen, for [secondaryRect].
  final _secondaryKey = GlobalKey();

  /// Lumtub: where the secondary line is on screen now, in global
  /// coordinates; null while none shows.
  Rect? secondaryRect() {
    final box = _secondaryKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  void initState() {
    subscription = widget.controller.player.stream.subtitle.listen((value) {
      setState(() {
        subtitle = value;
        if (value.length < 2 || value[1] != staleSecondary) staleSecondary = null;
      });
    });
    super.initState();
  }

  @override
  void didUpdateWidget(SubtitleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.configuration.secondaryKey != oldWidget.configuration.secondaryKey && subtitle.length > 1 && subtitle[1].isNotEmpty) {
      staleSecondary = subtitle[1];
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  /// Sets the padding to be used for the subtitles.
  ///
  /// The [duration] argument may be specified to set the duration of the animation.
  void setPadding(
    EdgeInsets padding, {
    Duration duration = const Duration(milliseconds: 100),
  }) {
    if (this.duration != duration) {
      setState(() {
        this.duration = duration;
      });
    }
    setState(() {
      this.padding = padding;
    });
  }

  /// {@macro subtitle_view}
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate the visible text scale factor.

        final nr = (constraints.maxWidth * constraints.maxHeight);
        const dr =
            kTextScaleFactorReferenceWidth * kTextScaleFactorReferenceHeight;
        final textScaleFactor = sqrt((nr / dr).clamp(0.0, 1.0));

        final textScaler = widget.configuration.textScaler ??
            widget.configuration.scaleFor?.call(constraints.biggest) ??
            TextScaler.linear(textScaleFactor);
        final view = Material(
          color: Colors.transparent,
          child: AnimatedContainer(
            padding: padding,
            duration: duration,
            alignment: Alignment.bottomCenter,
            child: _lines(textScaler),
          ),
        );
        // Lumtub: laid out only, where libmpv draws the lines, so the
        // secondary line's place is known.
        if (widget.configuration.ghost) {
          return IgnorePointer(child: Opacity(opacity: 0, child: view));
        }
        return view;
      },
    );
  }

  // Lumtub: the secondary subtitle goes above the main one, in its own
  // style when the configuration has one.
  Widget _lines(TextScaler textScaler) {
    final configuration = widget.configuration;
    final main = subtitle.isEmpty ? '' : subtitle.first.trim();
    var secondary = subtitle.length < 2 || configuration.secondaryKey == null || subtitle[1] == staleSecondary ? '' : subtitle[1].trim();
    // libmpv's copy of the secondary subtitle holds the main one's lines
    // after a blank line, invisible.
    if (configuration.ghost) secondary = secondary.split(RegExp(r'\n\s*\n')).first.trim();
    final secondaryStyle = configuration.secondaryStyle;
    final custom = main.isEmpty || configuration.ghost ? null : configuration.mainLine?.call(main, configuration.style, textScaler, configuration.outline);
    if (secondaryStyle == null && custom == null) {
      return SubtitleLine(
        [if (secondary.isNotEmpty) secondary, if (main.isNotEmpty) main].join('\n'),
        style: configuration.style,
        textAlign: configuration.textAlign,
        textScaler: textScaler,
        outline: configuration.outline,
        lines: 4,
      );
    }
    Widget second = SubtitleLine(secondary, style: secondaryStyle ?? configuration.style, textAlign: configuration.textAlign, textScaler: textScaler, outline: configuration.outline);
    final shown = configuration.secondaryShown;
    if (configuration.blurSecondary && shown != null && !configuration.ghost) {
      second = BlurredUntilShown(shown: shown, sigma: textScaler.scale((secondaryStyle ?? configuration.style).fontSize ?? 14) * blurSigmaEms, child: second);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (secondary.isNotEmpty)
          KeyedSubtree(key: _secondaryKey, child: second),
        if (secondary.isNotEmpty && main.isNotEmpty) SizedBox(height: textScaler.scale(configuration.spacing)),
        if (custom != null)
          custom
        else if (main.isNotEmpty)
          SubtitleLine(main, style: configuration.style, textAlign: configuration.textAlign, textScaler: textScaler, outline: configuration.outline),
      ],
    );
  }
}

// Lumtub: one subtitle, kept to [lines] lines where it can be. Text that
// would wrap past them is drawn a little smaller, down to [_smallest] of its
// size, and wrapped lines are evened out, so a cue never ends on a lone word.
// Lines run no wider than [_widest] of the picture.
class SubtitleLine extends StatelessWidget {
  const SubtitleLine(this.text, {required this.style, required this.textAlign, required this.textScaler, this.outline = 0, this.lines = 2});

  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final TextScaler textScaler;

  /// How far a solid black outline reaches out from the letters, in
  /// logical pixels, as libass draws one; 0 for none.
  final double outline;
  final int lines;

  static const _smallest = 0.85;
  static const _widest = 0.9;

  static final _layouts = <Object, _Fit>{};

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final room = constraints.maxWidth.isFinite ? constraints.maxWidth : MediaQuery.sizeOf(context).width;
      final fit = layout(text, style, textScaler, room * _widest, lines, Directionality.of(context));
      final shown = fit.shrink == 1.0 ? style : style.copyWith(fontSize: (style.fontSize ?? 14) * fit.shrink);
      final letters = Text(text, style: shown, textAlign: textAlign, textScaler: textScaler);
      if (outline <= 0) return SizedBox(width: fit.width, child: letters);
      // The outline under the letters: their shapes stroked twice as wide
      // as it reaches, round at the corners, in the letters' opacity.
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = outline * 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF000000).withValues(alpha: shown.color?.a ?? 1);
      return SizedBox(
        width: fit.width,
        child: Stack(children: [
          Text(text, style: shown.copyWith(foreground: stroke, shadows: const []), textAlign: textAlign, textScaler: textScaler),
          letters,
        ]),
      );
    });
  }

  /// The size factor and line width for [text] in lines of at most [room].
  static _Fit layout(String text, TextStyle style, TextScaler scaler, double room, int lines, TextDirection direction) {
    final key = Object.hash(text, style, scaler, room.floor(), lines);
    final known = _layouts[key];
    if (known != null) return known;
    final painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: direction, textScaler: scaler, textAlign: TextAlign.center);
    int count(double width) {
      painter.layout(maxWidth: width);
      return painter.computeLineMetrics().length;
    }

    var shrink = 1.0;
    var wrapped = count(room);
    if (wrapped > lines) {
      painter.text = TextSpan(text: text, style: style.copyWith(fontSize: (style.fontSize ?? 14) * _smallest));
      final smaller = count(room);
      if (smaller < wrapped) {
        shrink = _smallest;
        wrapped = smaller;
      } else {
        painter.text = TextSpan(text: text, style: style);
      }
    }
    var width = room;
    if (wrapped > 1) {
      // The narrowest width that keeps the same number of lines.
      var low = room / 2, high = room;
      for (var i = 0; i < 8; i++) {
        final middle = (low + high) / 2;
        if (count(middle) > wrapped) {
          low = middle;
        } else {
          high = middle;
        }
      }
      width = min(room, high + 1);
    } else {
      width = min(room, painter.maxIntrinsicWidth + 1);
    }
    painter.dispose();
    if (_layouts.length > 64) _layouts.clear();
    return _layouts[key] = _Fit(shrink, width);
  }
}

class _Fit {
  const _Fit(this.shrink, this.width);
  final double shrink;
  final double width;
}

/// {@template subtitle_view_configuration}
/// SubtitleViewConfiguration
/// -------------------------
///
/// Configurable options for customizing the [SubtitleView] behaviour.
/// {@endtemplate}
/// Lumtub: [child] blurred while [shown] is false. The blur only paints:
/// the line takes the same room and wraps the same either way.
class BlurredUntilShown extends StatelessWidget {
  const BlurredUntilShown({super.key, required this.shown, required this.sigma, required this.child});

  final ValueListenable<bool> shown;
  final double sigma;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: shown,
        builder: (context, shown, child) => shown
            ? child!
            : ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
                child: child,
              ),
        child: child,
      );
}

class SubtitleViewConfiguration {
  /// Whether the subtitles should be visible or not.
  final bool visible;

  /// The text style to be used for the subtitles.
  final TextStyle style;

  /// The text alignment to be used for the subtitles.
  final TextAlign textAlign;

  /// The text scaler to be used for the subtitles.
  final TextScaler? textScaler;

  /// The padding to be used for the subtitles.
  final EdgeInsets padding;

  /// Lumtub: the text scale for a view of the given size, used when
  /// [textScaler] is null instead of scaling by area against 1080p.
  final TextScaler Function(Size size)? scaleFor;

  /// Lumtub: the style of the secondary subtitle; null draws it like the
  /// main one.
  final TextStyle? secondaryStyle;

  /// Lumtub: the gap between the secondary and the main subtitle.
  final double spacing;

  /// Lumtub: the chosen secondary subtitle, null for none. When it changes,
  /// the secondary line on screen goes until mpv sends the new track's.
  final Object? secondaryKey;

  /// Lumtub: the secondary subtitle is blurred until [secondaryShown] is
  /// true, as when the pointer is over it ([onSecondaryHover]) or it was
  /// tapped ([onSecondaryTap]).
  final bool blurSecondary;
  final ValueListenable<bool>? secondaryShown;
  final ValueChanged<bool>? onSecondaryHover;
  final VoidCallback? onSecondaryTap;

  /// Lumtub: libmpv draws the lines; this view only lays them out, unseen,
  /// so the secondary line's place is known.
  final bool ghost;

  /// Lumtub: a solid outline around the letters, as libmpv draws one: how
  /// far it reaches out from them in logical pixels; 0 for none.
  final double outline;

  /// Lumtub: draws the main line in place of [SubtitleLine] when it gives a
  /// widget, such as words with their readings for the learning pack.
  final Widget? Function(String text, TextStyle style, TextScaler scaler, double outline)? mainLine;

  /// Lumtub: whether a pointer at a global position is on something in
  /// the main line that [onMainTap] handles, such as a word; such taps are
  /// taken above the controls.
  final bool Function(Offset global)? mainHit;
  final ValueChanged<Offset>? onMainTap;

  /// Lumtub: the pointer came onto (true) or left (false) what
  /// [mainHit] says is in the main line.
  final ValueChanged<bool>? onMainHover;

  /// {@macro subtitle_view_configuration}
  const SubtitleViewConfiguration({
    this.visible = true,
    this.style = const TextStyle(
      height: 1.4,
      fontSize: 32.0,
      letterSpacing: 0.0,
      wordSpacing: 0.0,
      color: Color(0xffffffff),
      fontWeight: FontWeight.normal,
      backgroundColor: Color(0xaa000000),
    ),
    this.textAlign = TextAlign.center,
    this.textScaler,
    this.secondaryStyle,
    this.scaleFor,
    this.spacing = 4.0,
    this.secondaryKey,
    this.blurSecondary = false,
    this.secondaryShown,
    this.onSecondaryHover,
    this.onSecondaryTap,
    this.ghost = false,
    this.outline = 0,
    this.mainLine,
    this.mainHit,
    this.onMainTap,
    this.onMainHover,
    this.padding = const EdgeInsets.fromLTRB(
      16.0,
      0.0,
      16.0,
      24.0,
    ),
  });
}

/// Lumtub: how far a blurred secondary subtitle is blurred, as a share of
/// its letters' size.
const blurSigmaEms = 0.18;

/// Lumtub: takes the pointer over the secondary subtitle's place on
/// screen, which [rect] tells as it is now, above the controls: hovering
/// it and tapping it show a blurred one.
class SecondaryRevealArea extends StatelessWidget {
  const SecondaryRevealArea({super.key, required this.rect, required this.configuration});

  final Rect? Function() rect;
  final SubtitleViewConfiguration configuration;

  @override
  Widget build(BuildContext context) => MouseRegion(
        // Elsewhere the pointer goes on to the controls below.
        opaque: false,
        hitTestBehavior: HitTestBehavior.deferToChild,
        onEnter: (_) => configuration.onSecondaryHover?.call(true),
        onExit: (_) => configuration.onSecondaryHover?.call(false),
        child: GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onTap: configuration.onSecondaryTap,
          child: _RectHit(rect),
        ),
      );
}

/// Lumtub: takes taps on what [SubtitleViewConfiguration.mainHit] says is
/// in the main line, above the controls; elsewhere they go on below.
class MainLineTapArea extends StatelessWidget {
  const MainLineTapArea({super.key, required this.configuration});

  final SubtitleViewConfiguration configuration;

  @override
  Widget build(BuildContext context) => MouseRegion(
        opaque: false,
        hitTestBehavior: HitTestBehavior.deferToChild,
        cursor: SystemMouseCursors.click,
        onEnter: configuration.onMainHover == null ? null : (_) => configuration.onMainHover!(true),
        onExit: configuration.onMainHover == null ? null : (_) => configuration.onMainHover!(false),
        child: GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onTapUp: (details) => configuration.onMainTap?.call(details.globalPosition),
          child: _PointHit(configuration.mainHit ?? (_) => false),
        ),
      );
}

class _PointHit extends LeafRenderObjectWidget {
  const _PointHit(this.hit);
  final bool Function(Offset global) hit;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderPointHit(hit);

  @override
  void updateRenderObject(BuildContext context, _RenderPointHit renderObject) => renderObject.hit = hit;
}

class _RenderPointHit extends RenderBox {
  _RenderPointHit(this.hit);
  bool Function(Offset global) hit;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool hitTestSelf(Offset position) => attached && hit(localToGlobal(position));
}

class _RectHit extends LeafRenderObjectWidget {
  const _RectHit(this.rect);
  final Rect? Function() rect;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderRectHit(rect);

  @override
  void updateRenderObject(BuildContext context, _RenderRectHit renderObject) => renderObject.rect = rect;
}

/// Hit only inside the rectangle [rect] gives at the time of the event.
class _RenderRectHit extends RenderBox {
  _RenderRectHit(this.rect);
  Rect? Function() rect;

  /// Room around the line that still counts as on it.
  static const _slack = 8.0;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool hitTestSelf(Offset position) {
    final area = rect();
    if (area == null || !attached) return false;
    return area.inflate(_slack).contains(localToGlobal(position));
  }
}
