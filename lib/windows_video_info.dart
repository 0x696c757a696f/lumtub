import 'dart:io';

import 'system_env.dart';

class WindowsVideoInfo {
  const WindowsVideoInfo({
    this.gpuNames = const [],
    this.vp9Extension = ExtensionStatus.unknown,
    this.av1Extension = ExtensionStatus.unknown,
  });

  final List<String> gpuNames;
  final ExtensionStatus vp9Extension;
  final ExtensionStatus av1Extension;

  static Future<WindowsVideoInfo> read() async {
    // Tests run without asking PowerShell, whose process outlives them.
    if (!Platform.isWindows || Platform.environment.containsKey('FLUTTER_TEST')) {
      return const WindowsVideoInfo();
    }
    final gpus = await _runLines(
        'Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name');
    return WindowsVideoInfo(
      gpuNames: gpus,
      vp9Extension: await _extensionStatus('Microsoft.VP9VideoExtensions'),
      av1Extension: await _extensionStatus('Microsoft.AV1VideoExtension'),
    );
  }

  static Future<ExtensionStatus> _extensionStatus(String name) async {
    try {
      // The name goes in by environment, never into the command text.
      final result = await Process.run(
        windowsProgram(r'System32\WindowsPowerShell\v1.0\powershell.exe'),
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r"if (Get-AppxPackage -Name $env:LUMTUB_PACKAGE -ErrorAction SilentlyContinue) { 'present' } else { 'missing' }"
        ],
        environment: {'LUMTUB_PACKAGE': name},
      ).timeout(const Duration(seconds: 8));
      if (result.exitCode != 0) return ExtensionStatus.unknown;
      return result.stdout.toString().trim() == 'present'
          ? ExtensionStatus.present
          : ExtensionStatus.missing;
    } catch (_) {
      return ExtensionStatus.unknown;
    }
  }

  static Future<List<String>> _runLines(String command) async {
    try {
      final result = await Process.run(
              windowsProgram(r'System32\WindowsPowerShell\v1.0\powershell.exe'),
              ['-NoProfile', '-NonInteractive', '-Command', command])
          .timeout(const Duration(seconds: 8));
      if (result.exitCode != 0) return const [];
      return result.stdout
          .toString()
          .split(RegExp(r'\r?\n'))
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

enum ExtensionStatus { present, missing, unknown }
