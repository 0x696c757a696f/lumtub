import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:material_ui/material_ui.dart';

import '../l10n/l10n.dart';

/// Shown in place of a part of the page whose build failed, instead of
/// Flutter's plain grey box: a short note in the page's own colours, never
/// taller than [maxHeight] so the rest of a list still shows. The error
/// itself goes to the error log through [FlutterError.onError].
class BuildErrorBox extends StatelessWidget {
  const BuildErrorBox({super.key});

  static const maxHeight = 120.0;

  /// In release and profile builds; debug builds keep Flutter's red screen
  /// with the error on it.
  static void install() {
    if (kDebugMode) return;
    ErrorWidget.builder = (details) => const BuildErrorBox();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    String text;
    try {
      text = tr('This part could not be shown; the details are in the error log');
    } catch (_) {
      text = 'This part could not be shown; the details are in the error log';
    }
    return Directionality(
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      child: LimitedBox(
        maxHeight: maxHeight,
        child: ClipRect(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: colors.outlineVariant),
              borderRadius: const BorderRadius.all(Radius.circular(8)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      color: colors.onSurfaceVariant,
                      decoration: TextDecoration.none),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
