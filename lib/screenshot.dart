import 'dart:async';
import 'dart:io';

import 'system_env.dart';

import 'package:media_kit/media_kit.dart';

/// Where screenshots go: Pictures\Lumtub of the signed-in Windows user.
Directory screenshotDirectory([Map<String, String>? environment]) {
  final env = environment ?? Platform.environment;
  final home = env['USERPROFILE'] ?? env['HOME'] ?? '.';
  return Directory('$home${Platform.pathSeparator}Pictures${Platform.pathSeparator}Lumtub');
}

/// A file name for a screenshot of [title] at [position]: the title cut to
/// 40 characters and cleaned of what Windows does not allow in names.
String screenshotName(String title, Duration position, DateTime now) {
  final clean = title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  final short = clean.length > 40 ? clean.substring(0, 40).trim() : clean;
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(position.inHours)}-${two(position.inMinutes % 60)}-${two(position.inSeconds % 60)}';
  final stamp = '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}';
  return '${short.isEmpty ? 'Lumtub' : short}_${time}_$stamp.png';
}

/// Saves the current frame, without subtitles or the interface, into
/// [directory] and returns the file, or null when libmpv could not.
Future<File?> takeScreenshot(Player player, {required String title, Directory? directory}) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return null;
  final dir = directory ?? screenshotDirectory();
  await dir.create(recursive: true);
  final file = File('${dir.path}${Platform.pathSeparator}${screenshotName(title, player.state.position, DateTime.now())}');
  await platform.command(['screenshot-to-file', file.path, 'video']);
  return await file.exists() ? file : null;
}

/// Puts the picture at [file] on the clipboard, best effort. On Linux it
/// takes wl-copy (Wayland) or xclip (X11), when installed.
Future<void> copyImageToClipboard(File file) async {
  if (Platform.isLinux) {
    try {
      if (Platform.environment['WAYLAND_DISPLAY']?.isNotEmpty ?? false) {
        final copy = await Process.start('wl-copy', ['--type', 'image/png']);
        await copy.stdin.addStream(file.openRead());
        await copy.stdin.close();
        await copy.exitCode.timeout(const Duration(seconds: 10));
      } else {
        await Process.run('xclip', ['-selection', 'clipboard', '-t', 'image/png', '-i', file.path]).timeout(const Duration(seconds: 10));
      }
    } catch (_) {
      // Neither is installed; the file is saved.
    }
    return;
  }
  if (Platform.isMacOS) {
    try {
      await Process.run('osascript', ['-e', 'on run argv', '-e', 'set the clipboard to (read (POSIX file (item 1 of argv)) as «class PNGf»)', '-e', 'end run', file.path]).timeout(const Duration(seconds: 10));
    } catch (_) {
      // The file is saved.
    }
    return;
  }
  if (!Platform.isWindows) return;
  final path = file.path.replaceAll("'", "''");
  try {
    await Process.run('powershell.exe', [
      '-STA',
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "Add-Type -AssemblyName System.Windows.Forms,System.Drawing; \$i=[System.Drawing.Image]::FromFile('$path'); [System.Windows.Forms.Clipboard]::SetImage(\$i); \$i.Dispose()",
    ]).timeout(const Duration(seconds: 10));
  } catch (_) {
    // The file is saved; the clipboard is a convenience.
  }
}

/// Shows [file] selected in Explorer, or its folder in the file manager.
Future<void> revealInFolder(File file) async {
  if (!Platform.isWindows) return openWithDesktop(file.parent.path);
  await Process.start('explorer.exe', ['/select,${file.path}']);
}
