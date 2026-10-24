import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_log.dart';
import 'format_policy.dart';
import 'models.dart';
import 'player_settings.dart';
import 'process_priority.dart';
import 'process_runner.dart';

/// What yt-dlp found for one video: every format, the ones picked for
/// [format], and the metadata the watch page shows.
class ResolvedVideo {
  ResolvedVideo(this.info, this.file, this.format, {DateTime? now}) : fetched = now ?? DateTime.now();

  final Map<String, dynamic> info;
  /// [info] saved for `--load-info-json`.
  final File file;
  /// The yt-dlp format expression [info] was resolved with.
  final String format;
  final DateTime fetched;

  /// Stream addresses carry their expiry time; they are used well before it.
  DateTime get expires {
    final limit = fetched.add(const Duration(hours: 1));
    final expire = int.tryParse(Uri.tryParse(_tracks.firstOrNull?['url']?.toString() ?? '')?.queryParameters['expire'] ?? '');
    if (expire == null) return limit;
    final at = DateTime.fromMillisecondsSinceEpoch(expire * 1000).subtract(const Duration(minutes: 15));
    return at.isBefore(limit) ? at : limit;
  }

  bool get fresh => DateTime.now().isBefore(expires);

  VideoDetails get details => VideoDetails.fromJson(info);

  /// Video heights this video offers, highest first; with [settings], only
  /// those that exist in a codec it allows.
  List<int> heightsFor([PlayerSettings? settings]) {
    final formats = info['formats'];
    if (formats is! List) return const [];
    final heights = <int>{
      for (final f in formats.whereType<Map>())
        if (f['vcodec'] != null && f['vcodec'] != 'none' && f['height'] is int && (f['height'] as int) > 0 && (settings == null || FormatPolicy.allowsName(settings, f['vcodec']))) f['height'] as int,
    };
    return heights.toList()..sort((a, b) => b.compareTo(a));
  }

  List<int> get heights => heightsFor();

  List<Map<String, dynamic>> get _tracks {
    final requested = info['requested_formats'];
    if (requested is List && requested.isNotEmpty) return requested.whereType<Map<String, dynamic>>().toList();
    return info['url'] is String ? [info] : const [];
  }

  /// An mpv EDL address that plays the picked formats directly, the way
  /// mpv's ytdl_hook builds it, or null when only ytdl_hook can play them
  /// (live streams, fragmented formats).
  String? get directUrl => directAddress();

  /// [directUrl] with each stream address passed through [relay], which
  /// may return another address for it (see `ChunkedRelay`).
  String? directAddress({String? Function(String url, int? size)? relay}) {
    if (info['is_live'] == true || info['live_status'] == 'is_live') return null;
    final tracks = _tracks;
    if (tracks.isEmpty) return null;
    final streams = <String>[];
    for (final track in tracks) {
      final url = track['url']?.toString() ?? '';
      final protocol = track['protocol']?.toString() ?? '';
      if (track['fragments'] != null || !(protocol == 'https' || protocol == 'http') || !url.startsWith('http')) return null;
      final size = track['filesize'] is int ? track['filesize'] as int : null;
      final address = relay?.call(url, size) ?? url;
      streams.add('!new_stream;!no_clip;!no_chapters;%${utf8.encode(address).length}%$address');
    }
    return 'edl://${streams.join(';')}';
  }

  /// The User-Agent the stream addresses were issued for.
  String? get userAgent {
    for (final track in [..._tracks, info]) {
      final headers = track['http_headers'];
      if (headers is Map && headers['User-Agent'] != null) return headers['User-Agent'].toString();
    }
    return null;
  }
}

/// Runs yt-dlp once per video ahead of playback and keeps the result, so
/// libmpv does not have to extract it again: the watch page, the quality
/// menu and playback share one extraction, and a card the pointer rests on
/// can be resolved before it is clicked.
class StreamResolver {
  StreamResolver(this.ytDlpPath, {this.cacheDirectory, this.deno, this.proxy, required this.infoDirectory, Map<String, String>? environment})
      : _environment = environment {
    unawaited(deleteStaleInfo());
  }

  final String ytDlpPath;
  final String? cacheDirectory;
  /// The Deno yt-dlp solves YouTube's JavaScript challenges with. Without
  /// it the stream addresses are throttled to a crawl or left out.
  final String? deno;
  /// yt-dlp's `--proxy` value at the time of each call.
  final String? Function()? proxy;
  /// Where info files for `--load-info-json` are kept.
  final Directory infoDirectory;
  final Map<String, String>? _environment;

  static const _keep = 12;
  final _results = <String, Future<ResolvedVideo>>{};
  /// The format each entry of [_results] is being resolved with.
  final _formats = <String, String>{};
  final _formatSorts = <String, String?>{};

  /// mpv's own default when no format was chosen.
  static String expressionOf(String format) => format == 'ytdl' ? 'bestvideo+bestaudio/best' : format;

  List<String> arguments(String videoId, String format, {String? formatSort}) {
    final proxy = this.proxy?.call();
    return [
      if (proxy != null) ...['--proxy', proxy],
        if (cacheDirectory != null) ...['--cache-dir', cacheDirectory!],
        if (deno != null) ...['--js-runtimes', 'deno:${deno!}'],
        '--extractor-retries', '3',
        '--no-playlist',
        '--dump-single-json',
        '--format', expressionOf(format),
        if (formatSort != null) ...['--format-sort', formatSort],
        '--', 'https://www.youtube.com/watch?v=$videoId',
      ];
  }

  /// The resolved video, from the cache while it is fresh.
  Future<ResolvedVideo> resolve(String videoId, String format, {String? formatSort}) {
    // A card prefetched in the background is now being waited on.
    final lowered = _lowered[videoId];
    if (lowered != null) restorePriority(lowered);
    final cached = _results[videoId];
    // Another format needs another extraction.
    if (cached != null && _formats[videoId] == format && _formatSorts[videoId] == formatSort) {
      return cached.then((video) => video.fresh ? video : _start(videoId, format, formatSort: formatSort), onError: (_) => _start(videoId, format, formatSort: formatSort));
    }
    return _start(videoId, format, formatSort: formatSort);
  }

  /// The extraction of [videoId] if one is running or done; never starts
  /// yt-dlp.
  Future<ResolvedVideo>? cached(String videoId) => _results[videoId];

  /// Starts resolving [videoId] in the background, if not already done.
  /// One at a time, at low priority: each extraction runs YouTube's
  /// JavaScript for seconds, and a pointer passing over a grid would
  /// otherwise start one per card. While one runs, only the card asked for
  /// last waits its turn.
  void prefetch(String videoId, String format, {String? formatSort}) {
    if (_results.containsKey(videoId) && _formats[videoId] == format && _formatSorts[videoId] == formatSort) return;
    if (_prefetching) {
      _nextPrefetch = (videoId, format, formatSort);
      return;
    }
    _prefetching = true;
    unawaited(_start(videoId, format, formatSort: formatSort, background: true).then((_) {}, onError: (_) {}).whenComplete(() {
      _prefetching = false;
      final next = _nextPrefetch;
      _nextPrefetch = null;
      if (next != null) prefetch(next.$1, next.$2, formatSort: next.$3);
    }));
  }

  bool _prefetching = false;
  /// Background extractions still running, by video id: their process ids.
  final _lowered = <String, int>{};
  (String, String, String?)? _nextPrefetch;

  /// Drops what is known about [videoId], for example after its streams
  /// failed to play.
  void forget(String videoId) {
    _results.remove(videoId);
    _formats.remove(videoId);
    _formatSorts.remove(videoId);
    _deleteInfo(videoId);
  }

  File _infoFile(String videoId) => File('${infoDirectory.path}${Platform.pathSeparator}$videoId.json');

  /// Deleted at once, so it cannot land after the next resolve rewrote it.
  void _deleteInfo(String videoId) {
    try {
      _infoFile(videoId).deleteSync();
    } on FileSystemException {
      // Not there, or still open: left for the startup cleanup.
    }
  }

  /// Deletes info files older than [maxAge] that earlier runs left behind.
  Future<void> deleteStaleInfo({Duration maxAge = const Duration(days: 1)}) async {
    try {
      if (!await infoDirectory.exists()) return;
      final limit = DateTime.now().subtract(maxAge);
      await for (final entity in infoDirectory.list()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        if ((await entity.lastModified()).isBefore(limit)) await entity.delete();
      }
    } on FileSystemException {
      // The cleanup is best effort.
    }
  }

  Future<ResolvedVideo> _start(String videoId, String format, {String? formatSort, bool background = false}) {
    final future = _run(videoId, format, formatSort: formatSort, background: background);
    _results.remove(videoId);
    _results[videoId] = future;
    _formats[videoId] = format;
    _formatSorts[videoId] = formatSort;
    while (_results.length > _keep) {
      final oldest = _results.keys.first;
      _formats.remove(oldest);
      _formatSorts.remove(oldest);
      _results.remove(oldest);
      _deleteInfo(oldest);
    }
    // A failure is not kept, so the next attempt runs yt-dlp again.
    future.then((_) {}, onError: (_) {
      if (identical(_results[videoId], future)) forget(videoId);
    });
    return future;
  }

  /// Errors a second attempt can get past, unlike a private or removed video.
  static final _transient = RegExp(r'HTTP Error 5\d\d|timed out|Connection (reset|aborted|refused)|Remote end closed|getaddrinfo|IncompleteRead', caseSensitive: false);

  Future<ResolvedVideo> _run(String videoId, String format, {String? formatSort, bool background = false}) async {
    final watch = Stopwatch()..start();
    var result = await _ytDlp(videoId, format, formatSort: formatSort, background: background ? videoId : null);
    if (_failed(result) && _transient.hasMatch(result.stderr.toString())) {
      logInfo('解析 $videoId 遇到网络错误，重试一次');
      await Future<void>.delayed(const Duration(seconds: 2));
      result = await _ytDlp(videoId, format, formatSort: formatSort, background: background ? videoId : null);
    }
    final output = result.stdout.toString().trim();
    final err = result.stderr.toString().trim();
    if (_failed(result)) {
      throw StateError(err.isEmpty ? 'yt-dlp exited with code ${result.exitCode}' : err);
    }
    // Warnings such as a failed JavaScript challenge explain slow or
    // missing streams, so they go to the log.
    final warnings = const LineSplitter().convert(err).where((line) => line.startsWith('WARNING')).take(5).toList();
    if (warnings.isNotEmpty) logInfo('yt-dlp 解析 $videoId 的警告：\n${warnings.join('\n')}');
    final data = jsonDecode(const LineSplitter().convert(output).last);
    if (data is! Map<String, dynamic>) throw const FormatException('Unexpected yt-dlp output');
    await infoDirectory.create(recursive: true);
    final file = _infoFile(videoId);
    await file.writeAsString(output);
    logInfo('已解析 $videoId${background ? '（预加载）' : ''}，用时 ${watch.elapsedMilliseconds} ms');
    return ResolvedVideo(data, file, format);
  }

  bool _failed(ProcessResult result) => result.exitCode != 0 || result.stdout.toString().trim().isEmpty;

  /// yt-dlp for [videoId]; [background] (the video id) runs it at low
  /// priority until [resolve] asks for that video.
  Future<ProcessResult> _ytDlp(String videoId, String format, {String? formatSort, String? background}) async {
    try {
      return await runWithTimeout(
        ytDlpPath,
        arguments(videoId, format, formatSort: formatSort),
        timeout: const Duration(seconds: 45),
        environment: _environment,
        onStart: (process) {
          if (background == null) return;
          lowerPriority(process.pid);
          _lowered[background] = process.pid;
        },
      );
    } finally {
      if (background != null) _lowered.remove(background);
    }
  }
}
