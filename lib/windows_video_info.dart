import 'dart:io';

class WindowsVideoInfo {
  final List<String> gpuNames;
  final ExtensionStatus vp9Extension;
  final ExtensionStatus av1Extension;

  const WindowsVideoInfo({
    this.gpuNames = const [],
    this.vp9Extension = ExtensionStatus.unknown,
    this.av1Extension = ExtensionStatus.unknown,
  });

  static Future<WindowsVideoInfo> read() async {
    if (!Platform.isWindows) return const WindowsVideoInfo();
    final gpus = await _runLines('Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name');
    return WindowsVideoInfo(
      gpuNames: gpus,
      vp9Extension: await _extensionStatus('Microsoft.VP9VideoExtensions'),
      av1Extension: await _extensionStatus('Microsoft.AV1VideoExtension'),
    );
  }

  static Future<ExtensionStatus> _extensionStatus(String name) async {
    try {
      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-Command', "if (Get-AppxPackage -Name '$name' -ErrorAction SilentlyContinue) { 'present' } else { 'missing' }"],
      ).timeout(const Duration(seconds: 8));
      if (result.exitCode != 0) return ExtensionStatus.unknown;
      return result.stdout.toString().trim() == 'present' ? ExtensionStatus.present : ExtensionStatus.missing;
    } catch (_) {
      return ExtensionStatus.unknown;
    }
  }

  static Future<List<String>> _runLines(String command) async {
    try {
      final result = await Process.run('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', command]).timeout(const Duration(seconds: 8));
      if (result.exitCode != 0) return const [];
      return result.stdout.toString().split(RegExp(r'\r?\n')).map((value) => value.trim()).where((value) => value.isNotEmpty).toSet().toList();
    } catch (_) {
      return const [];
    }
  }
}

enum ExtensionStatus { present, missing, unknown }
