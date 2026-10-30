import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../l10n/l10n.dart';
import '../language_guess.dart';
import '../translation.dart';
import 'theme.dart';
import 'app_icons.dart';

/// [builder]'s content for [text], with a 翻译 button under it. Tapping it
/// translates [text] into the language chosen in the settings and shows the
/// translation under the original (双语对照), or in its place when that is
/// turned off. Nothing is sent until the button is tapped.
class Translatable extends StatefulWidget {
  const Translatable({super.key, required this.controller, required this.text, required this.builder, this.padding = EdgeInsets.zero});
  final AppController controller;
  final String text;
  /// Draws the text it is given: the original or the translation.
  final Widget Function(BuildContext context, String text) builder;
  final EdgeInsetsGeometry padding;

  @override
  State<Translatable> createState() => _TranslatableState();
}

class _TranslatableState extends State<Translatable> {
  String? _translation;
  /// The language [_translation] is in.
  String? _language;
  bool _showing = false;
  bool _loading = false;
  String? _error;
  /// 沉浸式翻译 already tried this text (translated, same language or
  /// failed), so it is not asked again on every build.
  bool _autoTried = false;
  /// [_showing] came from 沉浸式翻译, so turning it off hides it again.
  bool _byImmersive = false;

  @override
  void didUpdateWidget(Translatable old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _translation = _language = _error = null;
      _showing = _loading = _autoTried = false;
    }
  }

  bool get _visible => _showing && !(_byImmersive && !widget.controller.preferences.immersiveTranslation);

  /// For 沉浸式翻译: translates once, quietly, when the text is foreign.
  void _auto() {
    _autoTried = true;
    final language = widget.controller.preferences.translateTarget;
    final lines = widget.text.split('\n').where((l) => l.trim().isNotEmpty);
    if (!lines.any((l) => _hasLetters(l) && !looksLike(l, language))) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_visible && !_loading) unawaited(_toggle(quiet: true));
    });
  }

  Future<void> _toggle({bool quiet = false}) async {
    final prefs = widget.controller.preferences;
    final language = prefs.translateTarget;
    if (_visible) {
      return setState(() => _showing = _byImmersive = false);
    }
    if (_translation != null && _language == language) {
      return setState(() {
        _showing = true;
        _byImmersive = quiet;
      });
    }
    final text = widget.text;
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty);
    if (prefs.skipSameLanguage && looksLike(text, language) && lines.every((l) => looksLike(l, language) || !_hasLetters(l))) {
      if (quiet) return;
      return setState(() => _error = tr('已经是{0}，不用翻译', [TranslationLanguage.byCode(language).label]));
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await translateForeignLines(widget.controller.translator, text, language, (line) => looksLike(line, language) || !_hasLetters(line));
      if (!mounted || text != widget.text) return;
      setState(() {
        _translation = result;
        _language = language;
        _showing = true;
        _byImmersive = quiet;
        _loading = false;
      });
    } on TranslationException catch (e) {
      _fail(text, quiet ? null : e.message);
    } catch (_) {
      _fail(text, quiet ? null : tr('无法翻译，请检查网络或代理'));
    }
  }

  void _fail(String text, String? message) {
    if (!mounted || text != widget.text) return;
    setState(() {
      _error = message;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final prefs = widget.controller.preferences;
    if (prefs.immersiveTranslation && !_autoTried && widget.text.trim().isNotEmpty) _auto();
    // 沉浸式翻译 always shows both.
    final both = prefs.bilingualTranslation || prefs.immersiveTranslation;
    final translation = _visible && both ? TranslationView(style: prefs.translationStyle, child: widget.builder(context, _translation!)) : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (translation != null && prefs.translationFirst) ...[translation, const SizedBox(height: 4)],
      widget.builder(context, _visible && !both ? _translation! : widget.text),
      if (translation != null && !prefs.translationFirst) ...[const SizedBox(height: 4), translation],
      Padding(
        padding: widget.padding,
        child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          TextButton.icon(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 4), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            onPressed: _loading ? null : _toggle,
            icon: _loading ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(AppIcons.translate, size: 16),
            label: Text(_visible ? (both ? tr('隐藏译文') : tr('显示原文')) : tr('翻译'), style: const TextStyle(fontSize: 12)),
          ),
          if (_error != null) Text(_error!, style: TextStyle(color: colors.error, fontSize: 12)),
        ]),
      ),
    ]);
  }
}

/// Whether [line] has a word in it, not just emoji, digits or a link.
bool _hasLetters(String line) => RegExp(r'\p{L}{2,}', unicode: true).hasMatch(line.replaceAll(RegExp(r'https?://\S+'), ''));

/// A translation shown beside its original, in one of [TranslationStyle].
class TranslationView extends StatefulWidget {
  const TranslationView({super.key, required this.style, required this.child});
  final TranslationStyle style;
  final Widget child;

  @override
  State<TranslationView> createState() => _TranslationViewState();
}

class _TranslationViewState extends State<TranslationView> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final child = DefaultTextStyle.merge(style: TextStyle(color: colors.onSurfaceVariant), child: widget.child);
    switch (widget.style) {
      case TranslationStyle.quote:
        return Container(
          padding: const EdgeInsets.only(left: 8),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: colors.primary.withValues(alpha: 0.6), width: 2))),
          child: child,
        );
      case TranslationStyle.plain:
        return child;
      case TranslationStyle.highlight:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: colors.primaryContainer.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(6)),
          child: child,
        );
      case TranslationStyle.underline:
        return DefaultTextStyle.merge(
          style: TextStyle(decoration: TextDecoration.underline, decorationStyle: TextDecorationStyle.dashed, decorationColor: colors.primary.withValues(alpha: 0.7)),
          child: child,
        );
      case TranslationStyle.box:
        return CustomPaint(
          painter: _DashedBox(colors.primary.withValues(alpha: 0.6)),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: child),
        );
      case TranslationStyle.blur:
        // Hidden until the pointer is over it or it is tapped, for
        // listening practice.
        return MouseRegion(
          onEnter: (_) => setState(() => _revealed = true),
          onExit: (_) => setState(() => _revealed = false),
          child: GestureDetector(
            onTap: () => setState(() => _revealed = !_revealed),
            child: ImageFiltered(
              enabled: !_revealed,
              imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: child,
            ),
          ),
        );
    }
  }
}

class _DashedBox extends CustomPainter {
  _DashedBox(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)));
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBox old) => old.color != color;
}
