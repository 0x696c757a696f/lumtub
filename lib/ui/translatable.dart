import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../l10n/l10n.dart';
import '../language_guess.dart';
import '../player_settings.dart' show SubtitleLanguage, interfaceTranslationLanguage;
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

  /// For 沉浸式翻译: translates once, quietly, when the text is in none of
  /// the languages the person reads.
  void _auto() {
    _autoTried = true;
    if (!needsTranslation(widget.controller, widget.text)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_visible && !_loading) unawaited(_toggle(quiet: true));
    });
  }

  Future<void> _toggle({bool quiet = false}) async {
    final prefs = widget.controller.preferences;
    final language = quiet ? prefs.immersiveTarget : prefs.translateTarget;
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
    // 沉浸式翻译 also leaves alone the languages the user listed; a tap on
    // 翻译 translates them as asked.
    // A tap also turns Chinese into the other script; only 沉浸式翻译 takes
    // the two as one.
    final kept = quiet ? {language, ...prefs.neverTranslate} : {language};
    bool reads(String l) => kept.any((k) => readsAs(l, k, chineseAsOne: quiet && prefs.chineseAsOne));
    if (prefs.skipSameLanguage && reads(text) && lines.every((l) => reads(l) || !_hasLetters(l))) {
      if (quiet) return;
      return setState(() => _error = tr('Already in {0}, nothing to translate', [TranslationLanguage.byCode(language).label]));
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await translateForeignLines(widget.controller.translator, text, language, (line) => reads(line) || !_hasLetters(line));
      if (!mounted || text != widget.text) return;
      // The service gave the text back as it was: it is in that language.
      if (_same(result, text)) {
        if (quiet) return setState(() => _loading = false);
        return setState(() {
          _loading = false;
          _error = tr('Already in {0}, nothing to translate', [TranslationLanguage.byCode(language).label]);
        });
      }
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
      _fail(text, quiet ? null : tr('Translation failed. Check your network or proxy.'));
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
            icon: _loading ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(AppIcons.translate, size: 16),
            label: Text(_visible ? (both ? tr('Hide translation') : tr('Show original')) : tr('Translation'), style: const TextStyle(fontSize: 12)),
          ),
          if (_error != null) Text(_error!, style: TextStyle(color: colors.error, fontSize: 12)),
        ]),
      ),
    ]);
  }
}

/// The languages 沉浸式翻译 leaves alone: the one it translates into, the
/// interface's, Windows' and those the user listed as never translated.
Set<String> readLanguages(AppController controller) => {
      controller.preferences.immersiveTarget,
      ...controller.preferences.neverTranslate,
      interfaceTranslationLanguage.code,
      SubtitleLanguage.systemTranslation.code,
    };

/// Whether some line of [text] is in none of [readLanguages].
bool needsTranslation(AppController controller, String text) {
  final known = readLanguages(controller);
  final chineseAsOne = controller.preferences.chineseAsOne;
  return text.split('\n').any((line) => _hasLetters(line) && !known.any((language) => readsAs(line, language, chineseAsOne: chineseAsOne)));
}

bool _same(String a, String b) => a.replaceAll(RegExp(r'\s+'), ' ').trim() == b.replaceAll(RegExp(r'\s+'), ' ').trim();

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
          padding: const EdgeInsetsDirectional.only(start: 8),
          decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: colors.primary.withValues(alpha: 0.6), width: 2))),
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
        // Hidden until the pointer is over it, it has keyboard focus or it
        // is tapped (Enter, Space or Select on focus), for listening practice.
        return FocusableActionDetector(
          onShowHoverHighlight: (over) => setState(() => _revealed = over),
          onFocusChange: (focused) => setState(() => _revealed = focused),
          actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => setState(() => _revealed = !_revealed))},
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
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
