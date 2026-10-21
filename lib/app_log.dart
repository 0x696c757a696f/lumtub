import 'dart:async';
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

  static const flushDelay = Duration(milliseconds: 200);

  final _pending = StringBuffer();
  Timer? _timer;
  /// Appends run one after another, so lines stay in order.
  Future<void> _writes = Future.value();

  /// Queues a line; lines are written together shortly after, or at once
  /// for errors, without blocking the caller.
  void write(String level, String message) {
    _pending.write('${DateTime.now().toIso8601String()} $level ${redact(message)}\n');
    if (level.trim() == 'ERROR') {
      unawaited(flush());
    } else {
      _timer ??= Timer(flushDelay, () => unawaited(flush()));
    }
  }

  /// Completes once every line written so far is on disk; call it before
  /// the app exits.
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isNotEmpty) {
      final text = _pending.toString();
      _pending.clear();
      _writes = _writes.then((_) async {
        try {
          await file.writeAsString(text, mode: FileMode.append, flush: true);
        } on FileSystemException {
          // A full or locked disk must not break playback.
        }
      });
    }
    return _writes;
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
