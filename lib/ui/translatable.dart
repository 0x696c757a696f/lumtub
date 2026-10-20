import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../l10n/l10n.dart';
import '../translation.dart';
import 'theme.dart';

/// [builder]'s content for [text], with a 翻译 button under it. Tapping it
/// translates [text] into the language chosen in the settings and shows the
/// translation in its place; 显示原文 brings the original back. Nothing is
/// sent until the button is tapped.
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

  @override
  void didUpdateWidget(Translatable old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _translation = _language = _error = null;
      _showing = _loading = false;
    }
  }

  Future<void> _toggle() async {
    final language = widget.controller.preferences.translateLanguage;
    if (_showing) return setState(() => _showing = false);
    if (_translation != null && _language == language) return setState(() => _showing = true);
    final text = widget.text;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.controller.translator.translate(text, language);
      if (!mounted || text != widget.text) return;
      setState(() {
        _translation = result;
        _language = language;
        _showing = true;
        _loading = false;
      });
    } on TranslationException catch (e) {
      _fail(text, e.message);
    } catch (_) {
      _fail(text, tr('无法翻译，请检查网络或代理'));
    }
  }

  void _fail(String text, String message) {
    if (!mounted || text != widget.text) return;
    setState(() {
      _error = message;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      widget.builder(context, _showing ? _translation! : widget.text),
      Padding(
        padding: widget.padding,
        child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          TextButton.icon(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            onPressed: _loading ? null : _toggle,
            icon: _loading ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.translate_rounded, size: 16),
            label: Text(_showing ? tr('显示原文') : tr('翻译'), style: const TextStyle(fontSize: 12)),
          ),
          if (_error != null) Text(_error!, style: TextStyle(color: colors.error, fontSize: 12)),
        ]),
      ),
    ]);
  }
}
