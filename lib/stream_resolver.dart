import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'app_log.dart';
import 'background_json.dart';
import 'models.dart';
import 'native_core.dart';
import 'player_settings.dart';
import 'process_priority.dart';
import 'process_runner.dart';
import 'video_codec.dart';

/// What yt-dlp found for one video: every format, the ones picked for
/// [format], and the metadata the watch page shows. What the formats offer
/// is read by lumtub_core (native/lumtub_core/src/resolved.rs).
class ResolvedVideo {
  ResolvedVideo(this.info, this.file, this.format, {DateTime? now, String? text})
      : fetched = now ?? DateTime.now(),
        _text = text;

  final Map<String, dynamic> info;
  /// [info] saved for `--load-info-json`.
  final File file;
  /// The yt-dlp format expression [info] was resolved with.
  final String format;
  final DateTime fetched;
  /// [info] as yt-dlp printed it.
  String? _text;
  final _summaries = <String, Map<String, dynamic>?>{};

  /// The core's reading of [info] for the codecs [settings] disable and
  /// the height [cap]; null without the core.
  Map<String, dynamic>? _summary([PlayerSettings? settings, int cap = 0]) {
    final disabled = settings == null ? const <String>[] : [for (final c in VideoCodec.values) if (settings.disabledCodecs.contains(c)) c.name];
    return _summaries.putIfAbsent('${disabled.join(',')}/$cap', () {
      final core = NativeCore.instance;
      if (core == null) return null;
      final answer = core.resolved(_text ??= jsonEncode(info), jsonEncode({'disabled': disabled, 'cap': cap, 'fetched': fetched.millisecondsSinceEpoch ~/ 1000}));
      return answer == null ? null : jsonDecode(answer) as Map<String, dynamic>;
    });
  }

  /// Stream addresses carry their expiry time; they are used well before it.
  DateTime get expires {
    final at = _summary()?['expires'];
    return at is int ? DateTime.fromMillisecondsSinceEpoch(at * 1000) : fetched.add(const Duration(hours: 1));
  }

  bool get fresh => DateTime.now().isBefore(expires);

  /// For the log when an address is refused: how old it is, and which
  /// YouTube client and formats yt-dlp took it from.
  String get origin {
    final summary = _summary();
    final clients = (summary?['clients'] as List?)?.join('/') ?? '?';
    final formats = (summary?['formats'] as List?)?.join('+') ?? '?';
    return 'resolved ${DateTime.now().difference(fetched).inSeconds} s ago, client $clients, formats $formats';
  }

  VideoDetails get details => VideoDetails.fromJson(info);

  /// Video heights this video offers, highest first; with [settings], only
  /// those that exist in a codec it allows.
  List<int> heightsFor([PlayerSettings? settings]) =>
      ((_summary(settings)?[settings == null ? 'allHeights' : 'heights'] as List?) ?? const []).cast<int>();

  List<int> get heights => heightsFor();

  /// When the tallest picture up to [cap] (0 for none) exists only in codecs
  /// [settings] disable: that height, those codecs, and the tallest height
  /// that does play.
  ({int height, List<VideoCodec> codecs, int playing})? lostToDisabled(PlayerSettings settings, int cap) {
    final lost = _summary(settings, max(0, cap))?['lost'];
    if (lost is! Map) return null;
    return (
      height: lost['height'] as int,
      codecs: [for (final name in lost['codecs'] as List) if (VideoCodec.byName(name) case final codec?) codec],
      playing: lost['playing'] as int,
    );
  }

  /// An mpv EDL address that plays the picked formats directly, the way
  /// mpv's ytdl_hook builds it, or null when only ytdl_hook can play them
  /// (live streams, fragmented formats).
  String? get directUrl => directAddress();

  /// [directUrl] with each stream address passed through [relay], which
  /// may return another address for it (see `ChunkedRelay`).
  String? directAddress({String? Function(String url, int? size)? relay}) {
    final streams = _summary()?['streams'];
    if (streams is! List || streams.isEmpty) return null;
    final addresses = [
      for (final stream in streams.cast<Map>())
        relay?.call(stream['url'] as String, stream['size'] as int?) ?? stream['url'] as String,
    ];
    return NativeCore.instance?.edl(addresses);
  }

  /// The User-Agent the stream addresses were issued for.
  String? get userAgent => _summary()?['userAgent'] as String?;
}

/// The cookie sign-in, handed to yt-dlp only for a members-only video,
/// which YouTube shows only to a signed-in member.
abstract interface class MembersCookies {
  bool get signedIn;
  /// Writes the cookies to [path]; false when they cannot be had.
  Future<bool> writeCookies(String path);
  /// Wipes and deletes what [writeCookies] wrote.
  void wipeCookies(String path);
}

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

  /// The cookie sign-in, for members-only videos.
  MembersCookies? Function()? members;

  static const _keep = 12;
  final _results = <String, Future<ResolvedVideo>>{};
  /// The format each entry of [_results] is being resolved with.
  final _formats = <String, String>{};
  final _formatSorts = <String, String?>{};
  /// The proxy each entry of [_results] was resolved through: addresses
  /// handed out through one may not work through another.
  final _proxies = <String, String?>{};

  /// mpv's own default when no format was chosen.
  static String expressionOf(String format) => format == 'ytdl' ? 'bestvideo+bestaudio/best' : format;

  List<String> arguments(String videoId, String format, {String? formatSort, String? cookies}) {
    final proxy = this.proxy?.call();
    return [
      if (proxy != null) ...['--proxy', proxy],
        if (cookies != null) ...['--cookies', cookies],
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
  /// [membersOnly] (as a list marked it) asks signed in from the start.
  Future<ResolvedVideo> resolve(String videoId, String format, {String? formatSort, bool membersOnly = false}) {
    // A card prefetched in the background is now being waited on.
    final lowered = _lowered[videoId];
    if (lowered != null) restorePriority(lowered);
    final cached = _results[videoId];
    // Another format needs another extraction.
    if (cached != null && _formats[videoId] == format && _formatSorts[videoId] == formatSort && _proxies[videoId] == proxy?.call()) {
      return cached.then((video) => video.fresh ? video : _start(videoId, format, formatSort: formatSort, membersOnly: membersOnly),
          onError: (_) => _start(videoId, format, formatSort: formatSort, membersOnly: membersOnly));
    }
    return _start(videoId, format, formatSort: formatSort, membersOnly: membersOnly);
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
    if (_results.containsKey(videoId) && _formats[videoId] == format && _formatSorts[videoId] == formatSort && _proxies[videoId] == proxy?.call()) return;
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
    _proxies.remove(videoId);
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

  /// Deletes info files older than [maxAge] that earlier runs left behind,
  /// and cookie files a crash left, after a few minutes.
  Future<void> deleteStaleInfo({Duration maxAge = const Duration(days: 1)}) async {
    try {
      if (!await infoDirectory.exists()) return;
      final limit = DateTime.now().subtract(maxAge);
      final cookieLimit = DateTime.now().subtract(const Duration(minutes: 5));
      await for (final entity in infoDirectory.list()) {
        if (entity is! File) continue;
        if (entity.path.endsWith('.cookies.txt')) {
          if ((await entity.lastModified()).isBefore(cookieLimit)) {
            await entity.writeAsBytes(List<int>.filled(await entity.length(), 0), flush: true);
            await entity.delete();
          }
          continue;
        }
        if (!entity.path.endsWith('.json')) continue;
        if ((await entity.lastModified()).isBefore(limit)) await entity.delete();
      }
    } on FileSystemException {
      // The cleanup is best effort.
    }
  }

  Future<ResolvedVideo> _start(String videoId, String format, {String? formatSort, bool background = false, bool membersOnly = false}) {
    final future = _run(videoId, format, formatSort: formatSort, background: background, membersOnly: membersOnly);
    _results.remove(videoId);
    _results[videoId] = future;
    _formats[videoId] = format;
    _formatSorts[videoId] = formatSort;
    _proxies[videoId] = proxy?.call();
    while (_results.length > _keep) {
      final oldest = _results.keys.first;
      _formats.remove(oldest);
      _formatSorts.remove(oldest);
      _proxies.remove(oldest);
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

  /// Whether [error] is a network failure that resolving already retried.
  static bool isTransient(Object error) => _transient.hasMatch('$error');

  /// What yt-dlp says about a video only the channel's members may watch.
  static final membersOnlyError = RegExp(r"members.only|join this channel|channel's members", caseSensitive: false);

  Future<ResolvedVideo> _run(String videoId, String format, {String? formatSort, bool background = false, bool membersOnly = false}) async {
    final watch = Stopwatch()..start();
    // Background runs never open the cookies: that may bring up Windows Hello.
    final cookies = background ? null : members?.call();
    final signedIn = cookies != null && cookies.signedIn;
    Future<ProcessResult> run({bool signed = false}) =>
        signed ? _signedIn(cookies!, videoId, format, formatSort: formatSort) : _ytDlp(videoId, format, formatSort: formatSort, background: background ? videoId : null);
    var signed = membersOnly && signedIn;
    var result = await run(signed: signed);
    if (_failed(result) && _transient.hasMatch(result.stderr.toString())) {
      logWarn('Resolving $videoId hit a network error, retrying once');
      await Future<void>.delayed(const Duration(seconds: 2));
      result = await run(signed: signed);
    }
    if (_failed(result) && !signed && signedIn && membersOnlyError.hasMatch(result.stderr.toString())) {
      logInfo('$videoId is members-only, asking again signed in');
      signed = true;
      result = await run(signed: true);
    }
    final output = result.stdout.toString().trim();
    final err = result.stderr.toString().trim();
    if (_failed(result)) {
      throw StateError(err.isEmpty ? 'yt-dlp exited with code ${result.exitCode}' : err);
    }
    // Warnings such as a failed JavaScript challenge explain slow or
    // missing streams, so they go to the log.
    final warnings = const LineSplitter().convert(err).where((line) => line.startsWith('WARNING')).take(5).toList();
    if (warnings.isNotEmpty) logWarn('yt-dlp warnings for $videoId:\n${warnings.join('\n')}');
    final line = const LineSplitter().convert(output).last;
    final data = await decodeJsonInBackground(line);
    if (data is! Map<String, dynamic>) throw const FormatException('Unexpected yt-dlp output');
    await infoDirectory.create(recursive: true);
    final file = _infoFile(videoId);
    await file.writeAsString(output);
    logDebug(() => 'Resolved $videoId${background ? ' (prefetch)' : ''} in ${watch.elapsedMilliseconds} ms');
    return ResolvedVideo(data, file, format, text: line);
  }

  static int _cookieFiles = 0;

  /// yt-dlp for [videoId] with the signed-in cookies, in a file of their
  /// own that is wiped as soon as yt-dlp is done.
  Future<ProcessResult> _signedIn(MembersCookies cookies, String videoId, String format, {String? formatSort}) async {
    await infoDirectory.create(recursive: true);
    final path = '${infoDirectory.path}${Platform.pathSeparator}$videoId-${_cookieFiles++}.cookies.txt';
    try {
      if (!await cookies.writeCookies(path)) {
        logWarn('The cookie sign-in could not be opened for $videoId');
        return await _ytDlp(videoId, format, formatSort: formatSort);
      }
      return await _ytDlp(videoId, format, formatSort: formatSort, cookies: path);
    } finally {
      cookies.wipeCookies(path);
    }
  }

  bool _failed(ProcessResult result) => result.exitCode != 0 || result.stdout.toString().trim().isEmpty;

  /// yt-dlp for [videoId]; [background] (the video id) runs it at low
  /// priority until [resolve] asks for that video.
  Future<ProcessResult> _ytDlp(String videoId, String format, {String? formatSort, String? background, String? cookies}) async {
    try {
      return await runWithTimeout(
        ytDlpPath,
        arguments(videoId, format, formatSort: formatSort, cookies: cookies),
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
