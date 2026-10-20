import 'dart:io';

/// The app version, set by the release build with `--dart-define`.
const appVersion = String.fromEnvironment('YTPLUS_VERSION', defaultValue: '开发版');

/// A small plain-text log in the app's `logs` folder, for diagnosing problems
/// on other people's computers. It stays on this computer and never contains
/// tokens or signed stream addresses.
class AppLog {
  AppLog(this.file);
  final File file;

  /// The log of this run; null until [open] succeeds, and logging is then a
  /// no-op.
  static AppLog? current;

  static const maxBytes = 1024 * 1024;

  /// Starts the log, keeping the previous one as `ytplus.old.log` once it
  /// grows past [maxBytes].
  static Future<AppLog?> open(Directory directory) async {
    try {
      await directory.create(recursive: true);
      final file = File('${directory.path}${Platform.pathSeparator}ytplus.log');
      if (await file.exists() && await file.length() > maxBytes) {
        await file.rename('${directory.path}${Platform.pathSeparator}ytplus.old.log');
      }
      return current = AppLog(file);
    } on FileSystemException {
      return null;
    }
  }

  void write(String level, String message) {
    final line = '${DateTime.now().toIso8601String()} $level ${redact(message)}\n';
    try {
      file.writeAsStringSync(line, mode: FileMode.append, flush: true);
    } on FileSystemException {
      // A full or locked disk must not break playback.
    }
  }

  static final _secrets = [
    // OAuth values in queries, forms and JSON.
    RegExp(r'''((?:access_token|refresh_token|id_token|client_secret|code|token)["']?\s*[:=]\s*["']?)[^\s&"',}]+''', caseSensitive: false),
    RegExp(r'(Bearer\s+)\S+', caseSensitive: false),
  ];
  // Stream addresses are signed for one viewer and expire; the host is
  // enough to tell what failed.
  static final _streamUrl = RegExp(r'https?://([\w.-]*googlevideo\.com)/\S*');

  static String redact(String message) {
    var text = message.replaceAllMapped(_streamUrl, (m) => 'https://${m[1]}/…');
    for (final pattern in _secrets) {
      text = text.replaceAllMapped(pattern, (m) => '${m[1]}***');
    }
    return text;
  }
}

void logInfo(String message) => AppLog.current?.write('INFO ', message);

void logError(String message, [Object? error, StackTrace? stack]) => AppLog.current?.write(
      'ERROR',
      [message, if (error != null) '$error', if (stack != null) '$stack'].join('\n'),
    );
