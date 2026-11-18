import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_log.dart';
import 'device.dart';
import 'window_frame.dart';

/// What the runner managed when asked to let the desktop through.
@immutable
class WindowGlassState {
  const WindowGlassState({this.shown = false, this.blurred = false, this.restart = false});

  /// The desktop (on a phone or tablet, the wallpaper) shows through
  /// wherever the app leaves the window clear.
  final bool shown;

  /// The system blurs what lies behind.
  final bool blurred;

  /// Android: the change takes effect at the next start.
  final bool restart;

  @override
  bool operator ==(Object other) => other is WindowGlassState && other.shown == shown && other.blurred == blurred && other.restart == restart;

  @override
  int get hashCode => Object.hash(shown, blurred, restart);

  @override
  String toString() => 'WindowGlassState(shown: $shown, blurred: $blurred, restart: $restart)';
}

/// 窗口透明: the desktop seen through the window, under any skin
/// (docs/specs/window-glass.md). The runners answer on the window frame
/// channel; the app then lays its own tint, readable at every setting,
/// over what they let through ([GlassLook]).
abstract final class WindowGlass {
  static const _channel = MethodChannel(WindowFrame.channelName);

  /// Windows, macOS and Linux, and Android phones and tablets (their
  /// wallpaper). Not TVs, which have no wallpaper behind apps, nor iOS,
  /// which shows apps nothing behind them.
  static bool get possible => debugPossible ?? (WindowFrame.supported || (Platform.isAndroid && !Device.tv));

  @visibleForTesting
  static bool? debugPossible;

  /// What the runner said last.
  static final state = ValueNotifier<WindowGlassState>(const WindowGlassState());

  static ({bool on, bool dark, bool blur, int tint})? _asked;

  /// Asks the runner to let the desktop through, or to stop; [dark] shades
  /// the system's own blur, [blur] asks for one, [tint] is the skin's page
  /// colour, which frosts the blur where the system lays a colour over it.
  /// The answer lands in [state]; asking the same again does nothing.
  static Future<void> apply({required bool on, required bool dark, required bool blur, Color tint = const Color(0xFF000000)}) async {
    final ask = (on: on, dark: dark, blur: blur, tint: tint.toARGB32());
    if (ask == _asked || !possible) return;
    // Nothing to undo at start while it was never on.
    if (_asked == null && !on) {
      _asked = ask;
      return;
    }
    _asked = ask;
    try {
      final answer = await _channel.invokeMapMethod<String, Object?>('setDesktopGlass', {'on': on, 'dark': dark, 'blur': blur, 'tint': ask.tint});
      if (_asked != ask) return;
      state.value = WindowGlassState(shown: answer?['shown'] == true, blurred: answer?['blurred'] == true, restart: answer?['restart'] == true);
      if (on) logInfo('Window glass: ${state.value}, system ${answer?['system'] ?? '-'}, build ${answer?['build'] ?? '-'}');
    } on MissingPluginException {
      state.value = const WindowGlassState();
    } on PlatformException catch (e) {
      logError('Window glass failed', e);
      state.value = const WindowGlassState();
    }
  }
}
