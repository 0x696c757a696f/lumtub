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
  return CollectedProcess(process, executable, arguments).result(timeout);
}

/// A started process whose output is being collected from the start, so
/// it can be started long before its answer is wanted (a standby yt-dlp
/// waiting for its address on stdin).
class CollectedProcess {
  CollectedProcess(this.process, this.executable, this.arguments) {
    const decoder = Utf8Decoder(allowMalformed: true);
    // stdout is the answer and is kept whole up to [stdoutLimit]; of
    // stderr, which a failing tool can fill with the same warning over and
    // over, the last part.
    _out = _upTo(process.stdout.transform(decoder), stdoutLimit, () {
      _tooLong = true;
      process.kill();
    });
    _err = _tail(process.stderr.transform(decoder), stderrLimit);
    unawaited(process.exitCode.then((_) => exited = true, onError: (_) => exited = true));
  }

  final Process process;
  final String executable;
  final List<String> arguments;
  late final Future<String> _out;
  late final Future<String> _err;
  bool _tooLong = false;
  /// Whether the process has ended.
  bool exited = false;

  /// Its result once it exits; killed (and a [TimeoutException]) when
  /// that takes longer than [timeout].
  Future<ProcessResult> result(Duration timeout) async {
    try {
      final code = await process.exitCode.timeout(timeout);
      final text = await _out;
      if (_tooLong) throw ProcessException(executable, arguments, 'Output longer than ${stdoutLimit >> 20} Mi characters; stopped');
      return ProcessResult(process.pid, code, text, await _err);
    } on TimeoutException {
      process.kill();
      rethrow;
    }
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
