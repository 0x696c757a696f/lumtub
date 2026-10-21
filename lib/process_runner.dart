import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  final process = await Process.start(executable, arguments, environment: environment);
  onStart?.call(process);
  const decoder = Utf8Decoder(allowMalformed: true);
  final out = process.stdout.transform(decoder).join();
  final err = process.stderr.transform(decoder).join();
  try {
    final code = await process.exitCode.timeout(timeout);
    return ProcessResult(process.pid, code, await out, await err);
  } on TimeoutException {
    process.kill();
    rethrow;
  }
}
