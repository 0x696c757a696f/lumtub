import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'native_core.dart';

/// Runs [executable] and collects its output like [Process.run], but kills it
/// when [timeout] passes (and throws a [TimeoutException]); `Process.run`
/// with `.timeout` would give up waiting and leave it running.
/// [onStart] gets the started process, for example to lower its priority.
Future<ProcessResult> runWithTimeout(
  String executable,
  List<String> arguments, {
  required Duration timeout,
  Map<String, String>? environment,
  void Function(Process process)? onStart,
}) async {
  final process = await ProcessTree.start(executable, arguments, environment: environment);
  onStart?.call(process);
  const decoder = Utf8Decoder(allowMalformed: true);
  // stdout is the answer and is kept whole up to [stdoutLimit]; of stderr,
  // which a failing tool can fill with the same warning over and over,
  // the last part.
  var tooLong = false;
  final out = _upTo(process.stdout.transform(decoder), stdoutLimit, () {
    tooLong = true;
    process.kill();
  });
  final err = _tail(process.stderr.transform(decoder), stderrLimit);
  try {
    final code = await process.exitCode.timeout(timeout);
    final text = await out;
    if (tooLong) throw ProcessException(executable, arguments, 'Output longer than ${stdoutLimit >> 20} Mi characters; stopped');
    return ProcessResult(process.pid, code, text, await err);
  } on TimeoutException {
    process.kill();
    rethrow;
  }
}

/// The most of a process's stdout read, in characters: far above any
/// answer yt-dlp gives (a long video's JSON is a few MiB), so only a
/// runaway process reaches it.
const stdoutLimit = 64 << 20;

/// [pieces] joined; past [limit] characters [onTooLong] runs once and the
/// rest is dropped.
Future<String> _upTo(Stream<String> pieces, int limit, void Function() onTooLong) async {
  final kept = StringBuffer();
  var over = false;
  await for (final piece in pieces) {
    if (over) continue;
    kept.write(piece);
    if (kept.length > limit) {
      over = true;
      onTooLong();
    }
  }
  return kept.toString();
}

/// The most of a process's stderr kept, in characters.
const stderrLimit = 1 << 20;

/// [lines] joined, keeping the last [limit] characters.
Future<String> _tail(Stream<String> lines, int limit) async {
  final kept = StringBuffer();
  await for (final piece in lines) {
    kept.write(piece);
    if (kept.length > limit * 2) {
      final text = kept.toString();
      kept
        ..clear()
        ..write(text.substring(text.length - limit));
    }
  }
  final text = kept.toString();
  return text.length > limit ? text.substring(text.length - limit) : text;
}
