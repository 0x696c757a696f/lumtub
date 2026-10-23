import 'dart:io';

import 'live_chat.dart';
import 'process_runner.dart';

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
      ? '${Directory.systemTemp.path}${Platform.pathSeparator}ytplus-live-chat'
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
    final contents = await file.readAsString();
    return contents.trim().isEmpty ? const [] : LiveChatMessage.parseLines(contents);
  }
}
