import 'dart:io';

import 'package:flutter/services.dart';

import 'js_challenge_plugin.dart';

/// yt-dlp on Android: Android lets an app start only the programs in its
/// own library folder, so yt-dlp (a Python zip app kept with the other
/// components) runs as an argument of the Python there. [ProcessTree.start]
/// turns every start of a yt-dlp into that.
class AndroidPython {
  AndroidPython._(this.python, this.quickJs, this.environment, this.bundledYtDlp, this.plugins);

  /// The interpreter, libpython.so in the app's library folder.
  final String python;

  /// QuickJS, for YouTube's JavaScript challenges.
  final String? quickJs;

  /// What Python needs to find its library and certificates.
  final Map<String, String> environment;

  /// The yt-dlp that came with the app, to install when none is there.
  final String? bundledYtDlp;

  /// The folder of Lumtub's yt-dlp plugin, which solves YouTube's
  /// challenges with the core's QuickJS in Python's own process; null
  /// when it could not be set up, and libqjs.so is started instead.
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
      answer['quickjs'],
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
    final js = quickJs;
    return (
      python,
      [
        script,
        if (plugins != null && !arguments.contains('--plugin-dirs')) ...['--plugin-dirs', plugins!],
        if (js != null && !arguments.contains('--js-runtimes')) ...['--js-runtimes', 'quickjs:$js'],
        ...arguments,
      ],
      {...?environment, ...this.environment},
    );
  }
}
