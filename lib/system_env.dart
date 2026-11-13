import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

import 'app_log.dart';

typedef _SetEnvNative = Int32 Function(Pointer<Utf16>, Pointer<Utf16>);
typedef _SetEnvDart = int Function(Pointer<Utf16>, Pointer<Utf16>);

/// Prepend tool paths to the CURRENT process environment.
/// This allows mpv's built-in ytdl_hook.lua to discover yt-dlp.
void addToPath(Iterable<String> directories) {
  final separator = Platform.isWindows ? ';' : ':';
  final prefixes = directories.where((p) => p.trim().isNotEmpty).join(separator);
  if (prefixes.isEmpty) return;
  final value = '$prefixes$separator${Platform.environment['PATH'] ?? ''}';
  if (Platform.isWindows) {
    final kernel = DynamicLibrary.open('kernel32.dll');
    final setEnv = kernel.lookupFunction<_SetEnvNative, _SetEnvDart>('SetEnvironmentVariableW');
    final key = 'PATH'.toNativeUtf16();
    final native = value.toNativeUtf16();
    try {
      if (setEnv(key, native) == 0) throw const FileSystemException('Could not update PATH for player');
    } finally {
      calloc.free(key);
      calloc.free(native);
    }
    return;
  }
  final setEnv = DynamicLibrary.process().lookupFunction<Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32), int Function(Pointer<Utf8>, Pointer<Utf8>, int)>('setenv');
  final key = 'PATH'.toNativeUtf8();
  final native = value.toNativeUtf8();
  try {
    if (setEnv(key, native, 1) != 0) throw const FileSystemException('Could not update PATH for player');
  } finally {
    calloc.free(key);
    calloc.free(native);
  }
}

/// Starts Lumtub again and ends this process, such as after the language
/// changed.
Future<void> restartApp() async {
  if (Platform.isWindows) {
    // The new copy waits for this one to end: only one Lumtub runs at a time.
    await Process.start(Platform.resolvedExecutable, ['--restart-after=$pid'], mode: ProcessStartMode.detached);
  } else {
    // Started once this process has ended: on Linux a copy started now
    // would only hand itself to this one, which then quits, and an
    // AppImage's mounted folder goes away with it, so the image itself is
    // started.
    final appImage = Platform.environment['APPIMAGE'];
    final target = Platform.isLinux && appImage != null && appImage.isNotEmpty ? appImage : Platform.resolvedExecutable;
    await Process.start('/bin/sh', ['-c', r'while kill -0 "$1" 2>/dev/null; do sleep 0.2; done; exec "$2"', 'lumtub-restart', '$pid', target], mode: ProcessStartMode.detached);
  }
  await AppLog.current?.flush();
  exit(0);
}

/// Hands [text] to Android's share sheet; false where there is none, so
/// the caller copies it instead.
Future<bool> shareText(String text) async {
  if (!Platform.isAndroid && !Platform.isIOS) return false;
  try {
    await const MethodChannel('lumtub/windows_shell').invokeMethod<void>('shareText', text);
    return true;
  } catch (e) {
    logWarn('Could not open the share sheet: $e');
    return false;
  }
}

/// Opens [target], a web address, file or folder, with the desktop's
/// default program (xdg-open). Does nothing on Windows, which has its own
/// ways. On Android only web addresses open, in the browser; there is no
/// file manager to hand a folder to.
Future<void> openWithDesktop(String target) async {
  if (Platform.isWindows) return;
  if (Platform.isAndroid || Platform.isIOS) {
    if (!target.startsWith('http://') && !target.startsWith('https://')) return;
    try {
      await const MethodChannel('lumtub/windows_shell').invokeMethod<void>('openUrl', target);
    } catch (e) {
      logWarn('Could not open $target: $e');
    }
    return;
  }
  try {
    await Process.start(Platform.isMacOS ? 'open' : 'xdg-open', [target], mode: ProcessStartMode.detached);
  } catch (e) {
    logWarn('Could not open $target: $e');
  }
}
