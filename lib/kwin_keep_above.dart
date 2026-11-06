import 'dart:io';

/// Keeping Lumtub's window above the others on KDE Plasma under Wayland,
/// where a program cannot do it itself: a short KWin script, loaded over
/// D-Bus with gdbus, sets keepAbove on the windows of this process.
class KWinKeepAbove {
  KWinKeepAbove._();

  /// Whether this is a KDE Plasma desktop.
  static bool get available => Platform.isLinux && (Platform.environment['XDG_CURRENT_DESKTOP'] ?? '').toUpperCase().split(':').contains('KDE');

  /// The KWin script that sets keepAbove to [above] on the windows of
  /// process [processId], for KWin 6 (windowList) and 5 (clientList).
  static String script(int processId, bool above) => '''
const windows = workspace.windowList ? workspace.windowList() : workspace.clientList();
for (const window of windows) {
  if (window.pid === $processId) window.keepAbove = $above;
}
''';

  static int _serial = 0;

  /// The script number in loadScript's answer, such as `(int32 3,)`.
  static int? scriptId(String answer) => int.tryParse(RegExp(r'(-?\d+)\s*,').firstMatch(answer)?.group(1) ?? '');

  /// Keeps the window above the others or lets it go; false when KWin
  /// could not be asked.
  static Future<bool> set(bool above) async {
    if (!available) return false;
    final folder = await Directory.systemTemp.createTemp('lumtub-kwin-');
    final name = 'lumtub-keep-above-$pid-${_serial++}';
    final file = File('${folder.path}/keep-above.js');
    try {
      await file.writeAsString(script(pid, above));
      final loaded = await _call('/Scripting', 'org.kde.kwin.Scripting.loadScript', [file.path, name]);
      final id = loaded == null ? null : scriptId(loaded);
      if (id == null || id < 0) return false;
      final ran = await _call('/Scripting/Script$id', 'org.kde.kwin.Script.run', const []) ?? await _call('/$id', 'org.kde.kwin.Script.run', const []);
      await _call('/Scripting', 'org.kde.kwin.Scripting.unloadScript', [name]);
      return ran != null;
    } catch (_) {
      return false;
    } finally {
      try {
        await folder.delete(recursive: true);
      } catch (_) {}
    }
  }

  static Future<String?> _call(String path, String method, List<String> arguments) async {
    final result = await Process.run('gdbus', ['call', '--session', '--dest', 'org.kde.KWin', '--object-path', path, '--method', method, ...arguments]);
    return result.exitCode == 0 ? '${result.stdout}' : null;
  }
}

/// Hiding Lumtub to the tray when it is minimised on KDE Plasma under
/// Wayland, where no program is told it was: a KWin script, left loaded
/// while the setting is on, tells the runner over D-Bus.
class KWinMinimizeWatch {
  KWinMinimizeWatch._();

  static const _name = 'lumtub-minimize-to-tray';

  /// The script that calls the runner's Minimized method when a window of
  /// process [processId] is minimised, for KWin 6 and 5.
  static String script(int processId) => '''
const service = 'org.mpris.MediaPlayer2.lumtub.instance$processId';
function minimized(window) {
  if (window.pid === $processId && window.minimized) callDBus(service, '/org/mpris/MediaPlayer2', 'io.github.lumtub.Window', 'Minimized');
}
if (workspace.windowList) {
  const watch = (window) => {
    if (window.pid === $processId) window.minimizedChanged.connect(() => minimized(window));
  };
  workspace.windowList().forEach(watch);
  workspace.windowAdded.connect(watch);
} else {
  workspace.clientMinimized.connect(minimized);
}
''';

  /// Starts or stops watching; one script at a time, whichever Lumtub
  /// loaded it last.
  static Future<void> set(bool on) async {
    if (!KWinKeepAbove.available) return;
    try {
      await KWinKeepAbove._call('/Scripting', 'org.kde.kwin.Scripting.unloadScript', const [_name]);
      if (!on) return;
      final folder = Directory('${Directory.systemTemp.path}/lumtub-kwin-$pid');
      await folder.create(recursive: true);
      final file = File('${folder.path}/minimize-to-tray.js');
      await file.writeAsString(script(pid));
      final loaded = await KWinKeepAbove._call('/Scripting', 'org.kde.kwin.Scripting.loadScript', [file.path, _name]);
      final id = loaded == null ? null : KWinKeepAbove.scriptId(loaded);
      if (id == null || id < 0) return;
      await KWinKeepAbove._call('/Scripting/Script$id', 'org.kde.kwin.Script.run', const []) ?? await KWinKeepAbove._call('/$id', 'org.kde.kwin.Script.run', const []);
    } catch (_) {}
  }
}
