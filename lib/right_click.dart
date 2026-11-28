import 'l10n/l10n.dart';

/// What a right click on the video does.
enum RightClick {
  /// The video fills the window, the page round it hidden, without going
  /// fullscreen; a second right click brings the page back.
  fillWindow,

  /// Out of fullscreen first, then back, as in wiliwili.
  back,
  off;

  String get label => switch (this) {
        fillWindow => tr('Fill the window'),
        back => tr('Exit fullscreen, or else go back'),
        off => tr('Off'),
      };

  /// Settings saved before the choice was a switch for going back; left
  /// off, it now fills the window.
  static RightClick parse(Object? raw, Object? oldBack) =>
      values.where((v) => v.name == raw).firstOrNull ?? (oldBack == true ? back : fillWindow);
}

/// What a middle click (pressing the wheel) on the video does.
enum MiddleClick {
  off,
  playPause,
  mute,
  fillWindow,
  pip;

  String get label => switch (this) {
        off => tr('Off'),
        playPause => tr('Play or pause'),
        mute => tr('Mute or unmute'),
        fillWindow => tr('Fill the window'),
        pip => tr('Picture in picture'),
      };

  static MiddleClick parse(Object? raw) => values.where((v) => v.name == raw).firstOrNull ?? off;
}
