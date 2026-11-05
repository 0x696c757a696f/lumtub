import 'l10n/l10n.dart';

/// When the thin progress line shows along the bottom of the video while
/// the controls are hidden.
enum ProgressLine {
  always('Always'),
  fullscreen('Fullscreen only'),
  never('Never');

  const ProgressLine(this._label);
  final String _label;
  String get label => tr(_label);

  static ProgressLine parse(Object? raw, ProgressLine fallback) => values.where((v) => v.name == raw).firstOrNull ?? fallback;

  bool shows({required bool fullscreen}) => switch (this) {
        always => true,
        ProgressLine.fullscreen => fullscreen,
        never => false,
      };
}
