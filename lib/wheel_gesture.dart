import 'l10n/l10n.dart';

/// What the mouse wheel does over the video. Ctrl + wheel always steps
/// through the playback speeds.
enum WheelGesture {
  off('Off'),
  volume('Volume'),
  brightness('Brightness'),
  split('Left half brightness, right half volume');

  const WheelGesture(this._label);
  final String _label;
  String get label => tr(_label);

  static WheelGesture parse(Object? raw, WheelGesture fallback) =>
      values.where((v) => v.name == raw).firstOrNull ?? fallback;
}
