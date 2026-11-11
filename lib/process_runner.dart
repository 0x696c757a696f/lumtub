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
  final out = process.stdout.transform(decoder).join();
  // stdout is the answer and is kept whole; of stderr, which a failing
  // tool can fill with the same warning over and over, the last part.
  final err = _tail(process.stderr.transform(decoder), stderrLimit);
  try {
    final code = await process.exitCode.timeout(timeout);
    return ProcessResult(process.pid, code, await out, await err);
  } on TimeoutException {
    process.kill();
    rethrow;
  }
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
