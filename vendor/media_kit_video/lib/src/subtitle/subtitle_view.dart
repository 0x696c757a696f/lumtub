/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:async';
import 'dart:math';
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
        return Material(
          color: Colors.transparent,
          child: AnimatedContainer(
            padding: padding,
            duration: duration,
            alignment: Alignment.bottomCenter,
            child: _lines(textScaler),
          ),
        );
      },
    );
  }

  // Lumtub: the secondary subtitle goes above the main one, in its own
  // style when the configuration has one.
  Widget _lines(TextScaler textScaler) {
    final configuration = widget.configuration;
    final main = subtitle.isEmpty ? '' : subtitle.first.trim();
    final secondary = subtitle.length < 2 || configuration.secondaryKey == null || subtitle[1] == staleSecondary ? '' : subtitle[1].trim();
    final secondaryStyle = configuration.secondaryStyle;
    if (secondaryStyle == null) {
      return SubtitleLine(
        [if (secondary.isNotEmpty) secondary, if (main.isNotEmpty) main].join('\n'),
        style: configuration.style,
        textAlign: configuration.textAlign,
        textScaler: textScaler,
        lines: 4,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (secondary.isNotEmpty)
          SubtitleLine(secondary, style: secondaryStyle, textAlign: configuration.textAlign, textScaler: textScaler),
        if (secondary.isNotEmpty && main.isNotEmpty) SizedBox(height: textScaler.scale(configuration.spacing)),
        if (main.isNotEmpty)
          SubtitleLine(main, style: configuration.style, textAlign: configuration.textAlign, textScaler: textScaler),
      ],
    );
  }
}

// Lumtub: one subtitle, kept to [lines] lines where it can be. Text that
// would wrap past them is drawn a little smaller, down to [_smallest] of its
// size, and wrapped lines are evened out, so a cue never ends on a lone word.
// Lines run no wider than [_widest] of the picture.
class SubtitleLine extends StatelessWidget {
  const SubtitleLine(this.text, {required this.style, required this.textAlign, required this.textScaler, this.lines = 2});

  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final TextScaler textScaler;
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
      return SizedBox(
        width: fit.width,
        child: Text(text, style: shown, textAlign: textAlign, textScaler: textScaler),
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
    this.padding = const EdgeInsets.fromLTRB(
      16.0,
      0.0,
      16.0,
      24.0,
    ),
  });
}
