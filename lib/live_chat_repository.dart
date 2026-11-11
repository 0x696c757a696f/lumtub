import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'app_log.dart';
import 'live_chat.dart';
import 'process_priority.dart';
import 'process_runner.dart';
import 'native_core.dart';

/// Fetches the read-only chat replay that yt-dlp exposes as the `live_chat`
/// subtitle track. It shares yt-dlp's component, proxy and disk cache with
/// normal video extraction.
class LiveChatRepository {
  LiveChatRepository(
    this.ytDlpPath, {
    this.cacheDirectory,
    this.deno,
    this.proxy,
    Map<String, String>? environment,
  }) : _environment = environment;

  final String ytDlpPath;
  final String? cacheDirectory;
  final String? deno;
  final String? Function()? proxy;
  final Map<String, String>? _environment;

  Directory get directory => Directory(cacheDirectory == null
      ? '${Directory.systemTemp.path}${Platform.pathSeparator}lumtub-live-chat'
      : '${cacheDirectory!}${Platform.pathSeparator}live-chat');

  File fileFor(String videoId) => File('${directory.path}${Platform.pathSeparator}$videoId.live_chat.json');

  List<String> arguments(String videoId) => [
        '--no-warnings',
        '--skip-download',
        '--no-playlist',
        if (cacheDirectory != null) ...['--cache-dir', cacheDirectory!],
        if (proxy?.call() case final value?) ...['--proxy', value],
        if (deno != null) ...['--js-runtimes', 'deno:$deno'],
        '--write-subs',
        // A chat still running is written to "<name>.part" until it ends;
        // the lines are read as they arrive, so they go to the file itself.
        '--no-part',
        '--sub-langs', 'live_chat',
        '--sub-format', 'json',
        '--output', '${directory.path}${Platform.pathSeparator}%(id)s.%(ext)s',
        '--', 'https://www.youtube.com/watch?v=$videoId',
      ];

  /// Downloads and parses a finished stream's chat replay. Videos without
  /// public chat replay leave no output file and return an empty list.
  Future<List<LiveChatMessage>> replay(String videoId) async {
    final file = fileFor(videoId);
    await directory.create(recursive: true);
    try {
      await file.delete();
    } on FileSystemException {
      // No previous replay for this video.
    }
    final result = await runWithTimeout(
      ytDlpPath,
      arguments(videoId),
      timeout: const Duration(minutes: 2),
      environment: _environment,
    );
    if (!await file.exists()) {
      final error = result.stderr.toString().trim();
      if (result.exitCode == 0 || RegExp(r'no subtitles|live chat replay is not available', caseSensitive: false).hasMatch(error)) return const [];
      throw StateError(error.isEmpty ? 'yt-dlp exited with code ${result.exitCode}' : error);
    }
    return _readReplay(file);
  }

  /// The most read from the chat file at once.
  static const _readBytes = 4 << 20;
  /// A chat line is a few kilobytes; one longer than this is skipped.
  static const _lineBytes = 16 << 20;
  static const _errorChars = 256 << 10;

  // A replay of a long stream runs to hundreds of megabytes, nearly all
  // of it markup the messages leave out; it is read a few megabytes of
  // lines at a time, so only the messages are held whole.
  static Future<List<LiveChatMessage>> _readReplay(File file) => Isolate.run(() => readReplayFile(file));

  /// The messages of the replay [file], read [chunkChars] of lines at a time.
  static Future<List<LiveChatMessage>> readReplayFile(File file, {int chunkChars = 4 << 20}) async {
    final messages = <LiveChatMessage>[];
    final lines = StringBuffer();
    void parse() {
      if (lines.isEmpty) return;
      messages.addAll(LiveChatMessage.parseLines(lines.toString()));
      lines.clear();
    }

    await for (final line in file.openRead().transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      lines
        ..write(line)
        ..write('\n');
      if (lines.length >= chunkChars) parse();
    }
    parse();
    return messages;
  }

  /// Streams new messages from an active live chat. yt-dlp owns YouTube's
  /// continuation requests and appends each action to the same JSON format
  /// used for recorded replays. Cancelling the subscription stops that run.
  Stream<LiveChatMessage> current(String videoId) async* {
    final file = fileFor(videoId);
    await directory.create(recursive: true);
    try {
      await file.delete();
    } on FileSystemException {
      // The previous managed chat capture did not exist.
    }
    final process = await ProcessTree.start(
      ytDlpPath,
      arguments(videoId),
      environment: _environment,
    );
    lowerPriority(process.pid);
    // Only the end of yt-dlp's errors is kept; it names what went wrong.
    var errors = '';
    final errorSubscription = process.stderr.transform(utf8.decoder).listen((text) {
      errors += text;
      if (errors.length > _errorChars) errors = errors.substring(errors.length - _errorChars);
    });
    // Read and dropped: unread, yt-dlp's progress lines fill the pipe and
    // it stops fetching the chat.
    final outputSubscription = process.stdout.listen((_) {});
    var running = true;
    var exitCode = 0;
    unawaited(process.exitCode.then((code) {
      exitCode = code;
      running = false;
    }));
    var offset = 0;
    var pending = <int>[];
    // Set while a line longer than [_lineBytes] is being skipped.
    var skipping = false;
    var yielded = false;
    try {
      while (running || pending.isNotEmpty) {
        if (await file.exists()) {
          final length = await file.length();
          if (length > offset) {
            final reader = await file.open();
            try {
              await reader.setPosition(offset);
              while (offset < length) {
                final piece = await reader.read(min(length - offset, _readBytes));
                if (piece.isEmpty) break;
                offset += piece.length;
                var start = 0;
                if (skipping) {
                  final end = piece.indexOf(10);
                  if (end < 0) continue;
                  skipping = false;
                  start = end + 1;
                }
                pending.addAll(piece.sublist(start));
                final lastLine = pending.lastIndexOf(10);
                if (lastLine >= 0) {
                  final lines = utf8.decode(pending.sublist(0, lastLine + 1), allowMalformed: true);
                  pending = pending.sublist(lastLine + 1);
                  for (final message in LiveChatMessage.parseLines(lines)) {
                    yielded = true;
                    yield message;
                  }
                }
                if (pending.length > _lineBytes) {
                  logWarn('Live chat: skipped a line over ${_lineBytes >> 20} MiB');
                  pending = [];
                  skipping = true;
                }
              }
            } finally {
              await reader.close();
            }
          }
        }
        if (!running) {
          if (pending.isNotEmpty) {
            for (final message in LiveChatMessage.parseLine(utf8.decode(pending, allowMalformed: true))) {
              yielded = true;
              yield message;
            }
            pending = const [];
          }
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
      if (!yielded && exitCode != 0) {
        final error = errors.trim();
        throw StateError(error.isEmpty ? 'yt-dlp exited with code $exitCode' : error);
      }
    } finally {
      process.kill();
      await errorSubscription.cancel();
      await outputSubscription.cancel();
    }
  }
}
