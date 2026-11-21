import 'package:flutter/widgets.dart';

import 'app/app_controller.dart';
import 'ui/pages/settings_sections.dart' show SettingEntry, SettingsCategory;

/// How a plugin draws the main subtitle line on the video and takes taps
/// on it: [line] gives the widget drawn in place of the plain line (null
/// keeps the plain one), [hit] says whether a global position is on
/// something [tap] handles. Such taps are taken above the controls.
typedef VideoLineHooks = ({
  Widget? Function(String text, TextStyle style, TextScaler scaler, double outline) line,
  bool Function(Offset global) hit,
  ValueChanged<Offset> tap,
});

/// An entry a plugin adds to the side rail. It opens over the page shown
/// and is never the selected one.
typedef PluginDestination = ({IconData icon, IconData selectedIcon, String label, void Function(BuildContext context) open});

/// Something built into Lumtub from outside its source: it starts with
/// the app and may add to the player, the subtitle list, the subtitles
/// panel, the side rail and the settings. Every hook does nothing unless
/// overridden.
abstract class LumtubPlugin {
  const LumtubPlugin();

  /// Called once Lumtub is ready: folders made, settings read, player up.
  Future<void> start(AppController controller) async {}

  /// Called as the app controller goes away.
  void dispose() {}

  /// Notifies when what the hooks below draw has changed.
  Listenable? get changes => null;

  /// The main subtitle line on the video; null leaves it plain.
  VideoLineHooks? videoLine(BuildContext context, AppController controller) => null;

  /// One line of the subtitle list beside the video; null leaves it plain
  /// text. [other] is the line paired with it, [at] where it starts.
  Widget? listLine(BuildContext context, AppController controller, String text, TextStyle style, {String? other, required Duration at}) => null;

  /// Added under 语言学习 in the player's subtitles panel.
  Widget? subtitlePanel(BuildContext context, AppController controller) => null;

  /// Entries added to the side rail after Lumtub's own.
  List<PluginDestination> destinations(AppController controller) => const [];

  /// Entries added at the end of a settings category.
  List<SettingEntry> settings(SettingsCategory category, AppController controller) => const [];
}

/// The plugins this build was started with; none in Lumtub itself.
abstract final class Plugins {
  static List<LumtubPlugin> _all = const [];
  static Listenable _changes = _Never();

  static List<LumtubPlugin> get all => _all;

  /// Changes when any plugin's [LumtubPlugin.changes] does.
  static Listenable get changes => _changes;

  static void use(List<LumtubPlugin> plugins) {
    _all = List.unmodifiable(plugins);
    final changes = [for (final p in plugins) if (p.changes case final c?) c];
    _changes = changes.isEmpty ? _Never() : Listenable.merge(changes);
  }

  static VideoLineHooks? videoLine(BuildContext context, AppController controller) {
    for (final plugin in _all) {
      final hooks = plugin.videoLine(context, controller);
      if (hooks != null) return hooks;
    }
    return null;
  }

  static Widget? listLine(BuildContext context, AppController controller, String text, TextStyle style, {String? other, required Duration at}) {
    for (final plugin in _all) {
      final line = plugin.listLine(context, controller, text, style, other: other, at: at);
      if (line != null) return line;
    }
    return null;
  }

  static List<Widget> subtitlePanel(BuildContext context, AppController controller) => [
        for (final plugin in _all)
          if (plugin.subtitlePanel(context, controller) case final panel?) panel,
      ];

  static List<PluginDestination> destinations(AppController controller) => [
        for (final plugin in _all) ...plugin.destinations(controller),
      ];

  static List<SettingEntry> settings(SettingsCategory category, AppController controller) => [
        for (final plugin in _all) ...plugin.settings(category, controller),
      ];
}

/// A listenable that never notifies.
class _Never implements Listenable {
  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
