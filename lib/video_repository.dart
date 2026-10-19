import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_directories.dart';
import 'models.dart';

class VideoRepository {
  final String ytDlpPath;
  final String? cacheDirectory;
  VideoRepository(this.ytDlpPath, {this.cacheDirectory});

  static const pageSize = 20;

  /// yt-dlp arguments for one page of search results, 1-based [start].
  List<String> searchArguments(String query, {int start = 1, int count = pageSize}) {
    final end = start + count - 1;
    return [
      '--no-warnings',
      '--skip-download',
      if (cacheDirectory != null) ...['--cache-dir', cacheDirectory!],
      '--flat-playlist',
      '--dump-json',
      '--playlist-items', '$start:$end',
      '--', 'ytsearch$end:$query',
    ];
  }

  /// Streams search results as yt-dlp prints them, so the first cards appear
  /// before the whole page has been fetched. Cancelling the subscription
  /// stops yt-dlp.
  Stream<VideoItem> search(String query, {int start = 1, int count = pageSize}) {
    final q = query.trim();
    if (q.isEmpty) return const Stream.empty();
    return _listing(searchArguments(q, start: start, count: count), firstPage: start == 1);
  }

  /// yt-dlp arguments for one page of a channel's uploads, newest first.
  List<String> channelArguments(ChannelRef channel, {int start = 1, int count = pageSize}) => [
        '--no-warnings',
        '--skip-download',
        if (cacheDirectory != null) ...['--cache-dir', cacheDirectory!],
        '--flat-playlist',
        '--dump-json',
        '--playlist-items', '$start:${start + count - 1}',
        '--', '${channel.url}/videos',
      ];

  /// A page of [channel]'s uploads. Channel listings do not repeat the
  /// channel on every entry, so it is filled in here.
  Stream<VideoItem> channelVideos(ChannelRef channel, {int start = 1, int count = pageSize}) =>
      _listing(channelArguments(channel, start: start, count: count), firstPage: start == 1)
          .map((item) => item.withChannel(channel));

  Stream<VideoItem> _listing(List<String> arguments, {required bool firstPage}) {
    late final StreamController<VideoItem> output;
    Process? process;
    Timer? timeout;
    var found = 0;
    var finished = false;

    void finish([Object? error]) {
      if (finished) return;
      finished = true;
      timeout?.cancel();
      process?.kill();
      if (error != null) output.addError(error);
      unawaited(output.close());
    }

    output = StreamController<VideoItem>(
      onListen: () async {
        try {
          process = await Process.start(ytDlpPath, arguments, environment: _environment);
        } catch (e) {
          finish(e);
          return;
        }
        if (finished) {
          process!.kill();
          return;
        }
        timeout = Timer(const Duration(seconds: 60), () => finish(TimeoutException('yt-dlp 加载超时')));
        final stderr = StringBuffer();
        final errors = process!.stderr.transform(utf8.decoder).listen(stderr.write);
        try {
          await for (final line in process!.stdout.transform(utf8.decoder).transform(const LineSplitter())) {
            if (finished) break;
            final item = VideoItem.tryParseLine(line);
            if (item == null) continue;
            found++;
            output.add(item);
          }
          final exitCode = await process!.exitCode;
          await errors.cancel();
          if (found == 0 && firstPage) {
            final err = stderr.toString().trim();
            finish(StateError(err.isEmpty ? 'YouTube did not return any results.' : err));
          } else if (found == 0 && exitCode != 0) {
            final err = stderr.toString().trim();
            finish(StateError(err.isEmpty ? 'yt-dlp exited with code $exitCode' : err));
          } else {
            finish();
          }
        } catch (e) {
          finish(e);
        }
      },
      onCancel: () => finish(),
    );
    return output.stream;
  }

  /// yt-dlp arguments for watch-page metadata. Skipping the player JS keeps
  /// this cheaper than the extraction libmpv runs for playback; formats are
  /// not needed here.
  List<String> detailsArguments(String videoId) => [
        '--no-warnings',
        '--skip-download',
        if (cacheDirectory != null) ...['--cache-dir', cacheDirectory!],
        '--no-playlist',
        '--ignore-no-formats-error',
        '--extractor-args', 'youtube:player_skip=js',
        '--dump-json',
        '--', 'https://www.youtube.com/watch?v=$videoId',
      ];

  Future<VideoDetails> details(String videoId) async {
    final result = await Process.run(ytDlpPath, detailsArguments(videoId), stdoutEncoding: utf8, stderrEncoding: utf8, environment: _environment)
        .timeout(const Duration(seconds: 45));
    final output = result.stdout.toString().trim();
    if (result.exitCode != 0 || output.isEmpty) {
      final err = result.stderr.toString().trim();
      throw StateError(err.isEmpty ? 'yt-dlp exited with code ${result.exitCode}' : err);
    }
    final data = jsonDecode(const LineSplitter().convert(output).last);
    if (data is! Map<String, dynamic>) throw const FormatException('Unexpected yt-dlp output');
    return VideoDetails.fromJson(data);
  }

  Map<String, String> get _environment => {
        ...Platform.environment,
        if (cacheDirectory != null) ...{
          'TMP': '${cacheDirectory!}${Platform.pathSeparator}..${Platform.pathSeparator}temp',
          'TEMP': '${cacheDirectory!}${Platform.pathSeparator}..${Platform.pathSeparator}temp',
        },
      };
}

class HistoryStore {
  final AppDirectories directories;
  HistoryStore(this.directories);

  late File file;
  final List<VideoItem> items = [];

  Future<void> initialize() async {
    file = File('${directories.data.path}${Platform.pathSeparator}watch_history.json');
    if (!await file.exists()) return;
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is List) {
        for (final value in data) {
          try {
            if (value is Map<String, dynamic>) items.add(VideoItem.fromJson(value));
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> clear() async {
    items.clear();
    await file.writeAsString('[]', flush: true);
  }

  Future<void> record(VideoItem item) async {
    items.removeWhere((other) => other.id == item.id);
    items.insert(0, item);
    if (items.length > 60) items.removeRange(60, items.length);
    await file.writeAsString(jsonEncode(items.map((e) => e.toJson()).toList()), flush: true);
  }
}
