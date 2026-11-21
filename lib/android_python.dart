import 'dart:io';

import 'package:flutter/services.dart';

import 'js_challenge_plugin.dart';
import 'native_core.dart';

/// yt-dlp on Android: Android lets an app start only the programs in its
/// own library folder, so yt-dlp (a Python zip app kept with the other
/// components) runs as an argument of the Python there. [ProcessTree.start]
/// turns every start of a yt-dlp into that.
class AndroidPython {
  AndroidPython._(this.python, this.environment, this.bundledYtDlp, this.plugins);

  /// The interpreter, libpython.so in the app's library folder: a small
  /// launcher for CPython's libpython3.x.so beside it.
  final String python;

  /// What Python needs to find its library and certificates.
  final Map<String, String> environment;

  /// The yt-dlp that came with the app, to install when none is there.
  final String? bundledYtDlp;

  /// The folder of Lumtub's yt-dlp plugin, which solves YouTube's
  /// challenges with the core's QuickJS in Python's own process; null
  /// when it could not be set up, and yt-dlp then has no JavaScript runtime.
  final String? plugins;

  /// Set once Python is ready; null off Android or when it could not be.
  static AndroidPython? current;

  static const _channel = MethodChannel('lumtub/python');

  /// Unpacks Python the first time (a few seconds) and sets [current].
  static Future<AndroidPython?> prepare() async {
    if (!Platform.isAndroid) return null;
    final answer = await _channel.invokeMapMethod<String, String>('prepare');
    if (answer == null) return null;
    final python = answer['python'];
    if (python == null) return null;
    final lib = answer['libraries']!;
    final core = answer['core'];
    final plugins = core == null ? null : await JsChallengePlugin.install(answer['temporary']!);
    return current = AndroidPython._(
      python,
      {
        'PYTHONHOME': answer['home']!,
        'HOME': answer['home']!,
        'LD_LIBRARY_PATH': lib,
        'SSL_CERT_FILE': answer['certificates']!,
        'TMPDIR': answer['temporary']!,
        'PATH': '${Platform.environment['PATH'] ?? '/system/bin'}:${answer['programs']!}',
        'PYTHONIOENCODING': 'utf-8',
        if (plugins != null) 'LUMTUB_CORE': core!,
      },
      answer['bundledYtDlp'],
      plugins,
    );
  }

  /// Whether [executable] is a yt-dlp to run with Python.
  static bool runs(String executable) => current != null && (executable.endsWith('/yt-dlp') || executable.endsWith('/yt-dlp-bundled'));

  /// The program, arguments and environment that start [script] with
  /// [arguments] and [environment].
  (String, List<String>, Map<String, String>) command(String script, List<String> arguments, Map<String, String>? environment) {
    // Lumtub's plugin folder goes after --no-plugin-dirs, which would
    // otherwise clear it.
    final lead = arguments.takeWhile(ProcessTree.ytDlpIsolation.contains).length;
    return (
      python,
      [
        script,
        ...arguments.take(lead),
        if (plugins != null && !arguments.contains(plugins)) ...['--plugin-dirs', plugins!],
        ...arguments.skip(lead),
      ],
      {...?environment, ...this.environment},
    );
  }
}
