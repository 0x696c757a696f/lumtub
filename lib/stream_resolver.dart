import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'app_log.dart';
import 'background_json.dart';
import 'blocked_sign_in.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import 'models.dart';
import 'native_core.dart';
import 'native_http.dart';
import 'playback_failure.dart';
import 'player_settings.dart';
import 'process_priority.dart';
import 'process_runner.dart';
import 'video_codec.dart';
import 'video_facts_lookup.dart';
import 'youtube_player_probe.dart';
import 'volume_balance.dart';

/// What yt-dlp found for one video: every format, the ones picked for
/// [format], and the metadata the watch page shows. What the formats offer
/// is read by lumtub_core (native/lumtub_core/src/resolved.rs).
/// One language a video's sound is offered in.
class AudioLanguage {
  const AudioLanguage(this.code, this.kind);

  /// YouTube's code: `en`, `es-US`.
  final String code;

  /// `original`, `dub`, `auto` (an automatic dub), or empty when not said.
  final String kind;

  bool get isOriginal => kind == 'original';
}

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
      // yt-dlp's text of [info] is kept for the other settings an open asks
      // about (three or so): writing a megabyte of it again for each took
      // longer than the core's reading of it.
      final text = _text ??= jsonEncode(info);
      final answer = core.resolved(text, jsonEncode({'disabled': disabled, 'cap': cap, 'fetched': fetched.millisecondsSinceEpoch ~/ 1000}));
      return answer == null ? null : jsonDecode(answer) as Map<String, dynamic>;
    });
  }

  /// Stream addresses carry their expiry time; they are used well before it.
  DateTime get expires {
    final at = _summary()?['expires'];
    return at is int ? DateTime.fromMillisecondsSinceEpoch(at * 1000) : fetched.add(const Duration(hours: 1));
  }

  /// The languages the sound comes in, the original first; empty when the
  /// video has one.
  List<AudioLanguage> get audioLanguages => [
        for (final t in (_summary()?['audioTracks'] as List?) ?? const [])
          if (t is Map && t['language'] is String) AudioLanguage(t['language'] as String, '${t['kind']}'),
      ];

  bool get fresh => DateTime.now().isBefore(expires);

  /// For the log when an address is refused: how old it is, and which
  /// YouTube client and formats yt-dlp took it from.
  /// The YouTube clients (`c=` of each address) the picked streams came
  /// from, such as `TVHTML5`.
  List<String> get clients => [for (final c in (_summary()?['clients'] as List?) ?? const []) '$c'];

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

  /// The most frames a second of each height [heightsFor] lists, where
  /// above 30, for labels such as 1080p60.
  Map<int, int> frameRatesFor(PlayerSettings settings) => {
        for (final MapEntry(:key, :value) in ((_summary(settings)?['frameRates'] as Map?) ?? const {}).entries)
          if (int.tryParse('$key') case final height?) height: (value as num).toInt(),
      };

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

  /// The YouTube clients a live stream is also asked as, beside yt-dlp's
  /// own. Phones add android_vr: yt-dlp's default clients give a live
  /// stream's HLS address only once its JavaScript challenge is solved,
  /// which a phone's JavaScript runtime may not manage, and the one client
  /// that needs no JavaScript (visionos) lists no live formats at all.
  String? liveClients = Platform.isAndroid || Platform.isIOS ? 'default,android_vr' : null;
  /// yt-dlp's `--proxy` value at the time of each call.
  final String? Function()? proxy;
  /// Where info files for `--load-info-json` are kept.
  final Directory infoDirectory;
  final Map<String, String>? _environment;

  /// The cookie sign-in, for members-only videos.
  MembersCookies? Function()? members;

  /// Whether both IPv4 and IPv6 reach YouTube with no proxy between, so a
  /// video taken for a bot over one is asked again over the other.
  bool Function()? bothFamilies;

  /// Whether a video taken for a bot is asked once more with the cookie
  /// sign-in (设置 › 网络, off by default). Only a video played in the
  /// foreground, at most [BlockedSignIn.perHour] times an hour; for
  /// [BlockedSignIn.remember] after a refusal the first request already
  /// goes signed in.
  bool Function()? signInWhenBlocked;

  /// The signed-in way past a bot check, shared with downloads.
  late final blockedSignIn = BlockedSignIn(cookies: () => members?.call(), enabled: () => signInWhenBlocked?.call() ?? false, directory: () => infoDirectory);

  /// Told when a video plays only because it was asked signed in, once
  /// each time this network is refused.
  void Function(String videoId)? onSignedInPlay;

  /// What yt-dlp says when YouTube takes the address for a bot.
  static final botCheck = RegExp(r"not a bot|confirm you.?re not|Sign in to confirm", caseSensitive: false);

  /// Each kept answer takes about 5 MB once decoded (measured with a 1 MB
  /// answer: 55 MB for 12), so only the last few are kept.
  static const _keep = 4;
  /// The video last asked for in the foreground, kept whatever background
  /// extractions come after it: it is likely the one playing.
  String? _asked;
  final _results = <String, Future<ResolvedVideo>>{};
  /// The format each entry of [_results] is being resolved with.
  final _formats = <String, String>{};
  final _formatSorts = <String, String?>{};
  /// The proxy each entry of [_results] was resolved through: addresses
  /// handed out through one may not work through another.
  final _proxies = <String, String?>{};
  /// The entries of [_results] resolved with `live`.
  final _lives = <String>{};

  /// Until when yt-dlp is asked with its TV clients after a run without
  /// them gave nothing (see [avoidingTv]).
  DateTime? _tvNeededUntil;

  /// How long the TV clients are asked again after a run without them
  /// failed.
  static const tvNeededFor = Duration(minutes: 30);

  /// yt-dlp's `--extractor-args` value that asks only the client a quick
  /// start asks as (visionOS), leaving out the TV and web clients.
  static const visionOnly = 'youtube:player_client=visionos';

  /// The clients a run with the browser sign-in's cookies asks.
  static const signedClients = 'youtube:player_client=default,tv_samsung';

  /// Whether yt-dlp asks only the visionOS client, as it does unless a
  /// run that way just failed. Measured on a Windows PC on 2026-11-17
  /// (yt-dlp 2026.11.16, five videos, each client alone): with its default
  /// clients a run took 15–24 s, 6–11 s of it Deno solving the TV client's
  /// JavaScript challenge on every run, and some TV addresses answered 403
  /// at once; visionOS alone took 4.3–5.1 s, needed no challenge, gave the
  /// same heights (up to 2160p) and only addresses that played. The other
  /// TV clients failed ("The page needs to be reloaded") and tv_simply and
  /// android_vr gave 360p only without a PO token.
  bool get avoidingTv {
    final until = _tvNeededUntil;
    return until == null || !DateTime.now().isBefore(until);
  }

  /// YouTube refused stream addresses yt-dlp took from a TV client the
  /// moment they were opened: the TV clients are left out again at once.
  void avoidTv() {
    // visionOS's own addresses stop after 1 MiB here: the TV clients stay.
    if (visionCut) return;
    if (!avoidingTv) logInfo("YouTube refused the TV client's stream addresses; asking yt-dlp as visionOS alone again");
    _tvNeededUntil = null;
  }

  /// Some networks get a YouTube experiment (seen in November 2026) that
  /// refuses visionOS's stream addresses past their first MiB, as it wants
  /// a PO token for them there. A quick start would play a second and
  /// stop, and so would yt-dlp asking as visionOS alone; while it lasts,
  /// quick starts are skipped and yt-dlp asks its default clients.
  bool get visionCut {
    final until = _visionCutUntil;
    return until != null && DateTime.now().isBefore(until) && _visionCutProxy == proxy?.call();
  }

  DateTime? _visionCutUntil;
  String? _visionCutProxy;

  /// When the cut was last looked for, and through which proxy.
  DateTime _visionCheckedAt = DateTime(0);
  String? _visionCheckedProxy;
  bool _visionChecking = false;

  /// How long a cut, or its absence, is trusted before it is looked for
  /// again.
  static const visionCheckFor = Duration(minutes: 30);

  /// The first byte past the part YouTube lets through.
  static const visionCutAt = 1024 * 1024;

  /// Looks, in the background, whether the address of the quick start
  /// [info] is refused past [visionCutAt], unless that was looked at
  /// lately through the same proxy.
  @visibleForTesting
  Future<void> checkVisionCut(Map<String, dynamic> info) async {
    final proxy = this.proxy?.call();
    if (_visionChecking || (_visionCheckedProxy == proxy && DateTime.now().difference(_visionCheckedAt) < visionCheckFor)) return;
    final formats = [...?(info['requested_formats'] as List?)?.whereType<Map>(), info];
    final format = formats.firstWhere((f) => f['url'] is String && ((f['filesize'] as num?) ?? 0) > visionCutAt + 4096, orElse: () => const {});
    final url = format['url'];
    if (url is! String) return;
    final headers = <String, String>{
      ...?((format['http_headers'] ?? info['http_headers']) as Map?)?.cast<String, String>(),
    };
    _visionChecking = true;
    {
      try {
        final client = _quickClient ??= appHttpClient();
        final response = await client
            .get(Uri.parse('$url&range=$visionCutAt-${visionCutAt + 4095}'), headers: headers)
            .timeout(const Duration(seconds: 8));
        final status = response.statusCode;
        if (status != 200 && status != 206 && status != 403) return;
        _visionCheckedAt = DateTime.now();
        _visionCheckedProxy = proxy;
        if (status == 403) {
          _visionCutUntil = DateTime.now().add(visionCheckFor);
          _visionCutProxy = proxy;
          _tvNeededUntil = _visionCutUntil;
          logWarn("YouTube refuses visionOS's stream addresses past 1 MiB on this network; quick starts are off and yt-dlp asks its default clients for ${visionCheckFor.inMinutes} minutes");
        } else if (_visionCutUntil != null) {
          _visionCutUntil = null;
          logInfo("visionOS's stream addresses play past 1 MiB again");
        }
      } catch (e) {
        logInfo('Could not check visionOS addresses past 1 MiB: $e');
      } finally {
        _visionChecking = false;
      }
    }
  }

  @visibleForTesting
  set quickClient(http.Client client) => _quickClient = client;

  /// mpv's own default when no format was chosen.
  static String expressionOf(String format) => format == 'ytdl' ? 'bestvideo+bestaudio/best' : format;

  /// [live] also lists a live stream's separate picture and sound above
  /// 1080p, which have no manifest (see `LiveSplit`).
  List<String> arguments(String videoId, String format, {String? formatSort, String? cookies, bool live = false}) {
    final proxy = this.proxy?.call();
    return [
      if (proxy != null) ...['--proxy', proxy],
        if (cookies != null) ...['--cookies', cookies],
        if (cacheDirectory != null) ...['--cache-dir', cacheDirectory!],
        if (deno != null) ...['--js-runtimes', 'deno:${deno!}'],
        '--extractor-retries', '3',
        if (live)
          ...['--extractor-args', 'youtube:formats=incomplete${liveClients == null ? '' : ';player_client=$liveClients'}']
        // A signed-in run keeps yt-dlp's own clients for signed-in users,
        // and asks the Samsung TV client too: on an address YouTube takes
        // for a bot it was let through signed in every time where the
        // others mostly were not (SimpMusic issue 2861, 2026-11-11).
        else if (cookies != null)
          ...['--extractor-args', signedClients]
        else if (avoidingTv)
          ...['--extractor-args', visionOnly],
        '--no-playlist',
        '--dump-single-json',
        '--format', expressionOf(format),
        if (formatSort != null) ...['--format-sort', formatSort],
        '--', 'https://www.youtube.com/watch?v=$videoId',
      ];
  }

  /// The resolved video, from the cache while it is fresh.
  /// [membersOnly] (as a list marked it) asks signed in from the start.
  /// [live]: see [arguments].
  Future<ResolvedVideo> resolve(String videoId, String format, {String? formatSort, bool membersOnly = false, bool live = false}) {
    _asked = videoId;
    // A card prefetched in the background is now being waited on.
    final lowered = _lowered[videoId];
    if (lowered != null) restorePriority(lowered);
    final cached = _results[videoId];
    // Another format needs another extraction.
    if (cached != null && _formats[videoId] == format && _formatSorts[videoId] == formatSort && _proxies[videoId] == proxy?.call() && (_lives.contains(videoId) || !live)) {
      return cached.then((video) => video.fresh ? video : _start(videoId, format, formatSort: formatSort, membersOnly: membersOnly, live: live),
          onError: (_) => _start(videoId, format, formatSort: formatSort, membersOnly: membersOnly, live: live));
    }
    return _start(videoId, format, formatSort: formatSort, membersOnly: membersOnly, live: live);
  }

  /// The extraction of [videoId] if one is running or done; never starts
  /// yt-dlp.
  Future<ResolvedVideo>? cached(String videoId) => _results[videoId];

  /// Extractions that have finished, by video id.
  final _done = <String, ResolvedVideo>{};

  /// Whether a fresh extraction of [videoId] with [format] is already done.
  bool resolved(String videoId, String format) {
    final video = _done[videoId];
    return video != null && video.format == format && video.fresh;
  }

  http.Client? _quickClient;

  /// YouTube's measured loudness of videos a quick start asked about, in dB
  /// above its reference level; read by 音量平衡.
  final _loudness = <String, double>{};
  double? loudnessOf(String videoId) => _loudness[videoId];

  /// Told when [loudnessOf] learns a video's loudness, which can be after
  /// yt-dlp has already started it.
  void Function(String videoId)? onLoudness;

  /// A quick start for [videoId]: YouTube's visionOS client's streams,
  /// picked by the format policy [policy] (`FormatPolicy.settingsJson`),
  /// without yt-dlp. Null when the video cannot be started that way (live,
  /// ciphered, refused, not answered within a few seconds); [resolve]
  /// still has the whole answer.
  Future<ResolvedVideo?> quick(String videoId, String format, String policy) async {
    if (visionCut) {
      logInfo('Quick start of $videoId: skipped, visionOS addresses stop after 1 MiB here');
      return null;
    }
    final core = NativeCore.instance;
    final request = core?.quickRequest(videoId);
    if (core == null || request == null) return null;
    final watch = Stopwatch()..start();
    try {
      final parts = jsonDecode(request) as Map<String, dynamic>;
      final client = _quickClient ??= appHttpClient();
      final headers = {'Content-Type': 'application/json', ...(parts['headers'] as Map).cast<String, String>()};
      final body = (parts['body'] as Map).cast<String, Object?>();
      final response = await YoutubePlayerProbe.post(client, headers, body, timeout: const Duration(seconds: 6), playing: true);
      if (response.statusCode != 200) {
        logInfo('Quick start of $videoId: /player answered HTTP ${response.statusCode}');
        return null;
      }
      final answer = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (VolumeBalance.loudnessIn(answer) case final loudness?) {
        _loudness[videoId] = loudness;
        if (_loudness.length > 200) _loudness.remove(_loudness.keys.first);
        onLoudness?.call(videoId);
      }
      final text = core.quickInfo(answer, policy);
      if (text == null) {
        // visionOS taken for a bot: yt-dlp asking only as visionOS would be
        // too, so it asks its default clients for a while.
        if (answer.contains('"LOGIN_REQUIRED"') && avoidingTv) {
          _tvNeededUntil = DateTime.now().add(tvNeededFor);
          logInfo("visionOS was taken for a bot; yt-dlp asks its default clients for ${tvNeededFor.inMinutes} minutes");
        }
        if (answer.contains('"LOGIN_REQUIRED"') && botCheck.hasMatch(answer)) blockedSignIn.noteBlocked();
        logInfo('Quick start of $videoId: left to yt-dlp (${VideoFactsLookup.playerWhy(answer)})');
        return null;
      }
      final info = jsonDecode(text) as Map<String, dynamic>;
      logInfo('Quick start of $videoId in ${watch.elapsedMilliseconds} ms');
      blockedSignIn.noteAnswered();
      unawaited(checkVisionCut(info));
      return ResolvedVideo(info, _infoFile(videoId), format, text: text);
    } catch (e) {
      logInfo('Quick start of $videoId failed: $e');
      return null;
    }
  }

  /// Starts resolving [videoId] in the background, if not already done.
  /// One at a time, at low priority: each extraction runs YouTube's
  /// JavaScript for seconds, and a pointer passing over a grid would
  /// otherwise start one per card. While one runs, only the card asked for
  /// last waits its turn.
  void prefetch(String videoId, String format, {String? formatSort}) {
    // The pointer is on a card: a click may follow.
    _warm(format, formatSort);
    if (_results.containsKey(videoId) && _formats[videoId] == format && _formatSorts[videoId] == formatSort && _proxies[videoId] == proxy?.call()) return;
    if (!prefetchAllowed(videoId)) return;
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

  /// How long a video that failed to resolve is not prefetched again.
  static const failureMemory = Duration(seconds: 30);

  /// How long prefetching pauses after YouTube asked for a "not a bot"
  /// check or answered 429: every background run would only be refused
  /// too, and more requests keep the address flagged longer.
  static const refusalPause = Duration(minutes: 10);

  /// When each video last failed to resolve, while [failureMemory] lasts.
  final _failedAt = <String, DateTime>{};

  /// Until when prefetching is paused, after YouTube refused this address.
  DateTime? _refusedUntil;

  /// Whether a background extraction of [videoId] is worth starting now.
  /// Opening a video always resolves it; only guesses wait.
  bool prefetchAllowed(String videoId) {
    final now = DateTime.now();
    if (_refusedUntil case final until? when now.isBefore(until)) return false;
    final failed = _failedAt[videoId];
    return failed == null || now.difference(failed) >= failureMemory;
  }

  void _noteFailure(String videoId, Object error) {
    final now = DateTime.now();
    _failedAt.removeWhere((_, at) => now.difference(at) >= failureMemory);
    _failedAt[videoId] = now;
    final kind = PlaybackFailure.classify(['$error']).kind;
    if (kind == FailureKind.botCheck || kind == FailureKind.rateLimited) {
      final paused = _refusedUntil != null && now.isBefore(_refusedUntil!);
      _refusedUntil = now.add(refusalPause);
      if (!paused) logWarn('YouTube refused this address (${kind.name}); prefetching pauses for ${refusalPause.inMinutes} minutes');
    }
  }

  void _noteSuccess(String videoId) {
    _failedAt.remove(videoId);
    // A video asked signed in got through, not this address.
    if (_refusedUntil != null && !blockedSignIn.recentlyBlocked) {
      _refusedUntil = null;
      logInfo('YouTube answers this address again; prefetching resumes');
    }
  }

  bool _prefetching = false;
  /// Background extractions still running, by video id: their process ids.
  final _lowered = <String, int>{};
  (String, String, String?)? _nextPrefetch;

  void _drop(String videoId) {
    _formats.remove(videoId);
    _formatSorts.remove(videoId);
    _proxies.remove(videoId);
    _lives.remove(videoId);
    _results.remove(videoId);
    _done.remove(videoId);
    _deleteInfo(videoId);
  }

  /// Drops every finished answer but the one asked for last, when the app
  /// goes to the background with nothing playing.
  void trim() {
    for (final id in [for (final id in _done.keys) if (id != _asked) id]) {
      _drop(id);
    }
  }

  /// Drops what is known about [videoId], for example after its streams
  /// failed to play.
  void forget(String videoId) {
    _results.remove(videoId);
    _done.remove(videoId);
    _formats.remove(videoId);
    _formatSorts.remove(videoId);
    _proxies.remove(videoId);
    _lives.remove(videoId);
    _deleteInfo(videoId);
  }

  /// [forget]s [videoId] when [video] is its kept answer, whose addresses
  /// were refused; an answer still being made, or another one, is kept.
  void forgetAnswer(String videoId, ResolvedVideo video) {
    if (identical(_done[videoId], video)) forget(videoId);
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

  Future<ResolvedVideo> _start(String videoId, String format, {String? formatSort, bool background = false, bool membersOnly = false, bool live = false}) {
    final future = _run(videoId, format, formatSort: formatSort, background: background, membersOnly: membersOnly, live: live);
    _results.remove(videoId);
    _done.remove(videoId);
    _results[videoId] = future;
    _formats[videoId] = format;
    _formatSorts[videoId] = formatSort;
    _proxies[videoId] = proxy?.call();
    if (live) {
      _lives.add(videoId);
    } else {
      _lives.remove(videoId);
    }
    // Answers whose addresses expired are of no more use.
    for (final id in [for (final e in _done.entries) if (!e.value.fresh && e.key != _asked && e.key != videoId) e.key]) {
      _drop(id);
    }
    while (_results.length > _keep) {
      _drop(_results.keys.firstWhere((id) => id != _asked && id != videoId));
    }
    // A failure is not kept, so the next attempt runs yt-dlp again.
    future.then((video) {
      _noteSuccess(videoId);
      if (identical(_results[videoId], future)) _done[videoId] = video;
    }, onError: (Object e) {
      _noteFailure(videoId, e);
      if (identical(_results[videoId], future)) forget(videoId);
    });
    return future;
  }

  /// Errors a second attempt can get past, unlike a private or removed video.
  static final _transient = RegExp(r'HTTP Error 5\d\d|timed out|Connection (reset|aborted|refused)|Remote end closed|getaddrinfo|IncompleteRead', caseSensitive: false);

  /// What yt-dlp says when the clients it asked gave nothing to play,
  /// which the TV client may still give; a private, removed or
  /// members-only video stays refused whichever client asks.
  static final _tvMayHelp = RegExp(r'not a bot|Requested format is not available|No video formats found|Only images are available|PO Token', caseSensitive: false);

  /// Whether [error] is a network failure that resolving already retried.
  static bool isTransient(Object error) => _transient.hasMatch('$error');

  /// What yt-dlp says about a video only the channel's members may watch.
  static final membersOnlyError = RegExp(r"members.only|join this channel|channel's members", caseSensitive: false);

  Future<ResolvedVideo> _run(String videoId, String format, {String? formatSort, bool background = false, bool membersOnly = false, bool live = false}) async {
    final watch = Stopwatch()..start();
    // Background runs never open the cookies: that may bring up Windows Hello.
    final cookies = background ? null : members?.call();
    final signedIn = cookies != null && cookies.signedIn;
    Future<ProcessResult> run({bool signed = false}) =>
        signed ? _signedIn(cookies!, videoId, format, formatSort: formatSort, live: live) : _ytDlp(videoId, format, formatSort: formatSort, background: background ? videoId : null, live: live);
    var signed = membersOnly && signedIn;
    // Refused for a bot a moment ago: asking without the account again
    // would only be refused too, after seconds.
    var signedFirst = false;
    if (!signed && !background && blockedSignIn.recentlyBlocked && blockedSignIn.usable != null && blockedSignIn.take()) {
      logInfo('$videoId is asked signed in from the start: this network was taken for a bot a moment ago');
      signed = signedFirst = true;
    }
    var result = await run(signed: signed);
    if (signedFirst && _failed(result) && !botCheck.hasMatch(result.stderr.toString())) {
      // The account did not help this one (cookies no longer valid, say):
      // asked as before.
      logInfo('$videoId failed signed in (${_lastLine(result)}); asking without the account');
      signed = false;
      result = await run();
    }
    if (_failed(result) && _transient.hasMatch(result.stderr.toString())) {
      logWarn('Resolving $videoId hit a network error, retrying once');
      await Future<void>.delayed(const Duration(seconds: 2));
      result = await run(signed: signed);
    }
    if (_failed(result) && !live && !signed && avoidingTv && _tvMayHelp.hasMatch(result.stderr.toString())) {
      // The other clients may give nothing this video can play (when
      // YouTube takes them for a bot, say): the TV client is asked too
      // for a while.
      logWarn("Resolving $videoId as visionOS alone failed; asking yt-dlp's default clients for ${tvNeededFor.inMinutes} minutes");
      _tvNeededUntil = DateTime.now().add(tvNeededFor);
      result = await run(signed: signed);
    }
    if (_failed(result) && !signed && botCheck.hasMatch(result.stderr.toString()) && ProcessTree.switchedFamily == null && (bothFamilies?.call() ?? false)) {
      // YouTube rates IPv4 addresses and IPv6 networks apart: the other
      // family is asked once, and kept for a while when it gets through.
      final other = ProcessTree.familyArguments.contains('--force-ipv4') ? '6' : '4';
      logWarn('Resolving $videoId was taken for a bot; asking again over IPv$other');
      ProcessTree.switchFamily(other);
      final again = await run(signed: signed);
      if (_failed(again)) {
        ProcessTree.switchFamily(null);
      } else {
        logInfo('IPv$other got $videoId through; yt-dlp keeps to it for 30 minutes');
      }
      result = again;
    }
    if (_failed(result) && !signed && signedIn && membersOnlyError.hasMatch(result.stderr.toString())) {
      logInfo('$videoId is members-only, asking again signed in');
      signed = true;
      result = await run(signed: true);
    }
    if (_failed(result) && !signed && botCheck.hasMatch(result.stderr.toString())) blockedSignIn.noteBlocked();
    if (!_failed(result) && !signed) blockedSignIn.noteAnswered();
    if (_failed(result) && !signed && !signedFirst && !background && signedIn && botCheck.hasMatch(result.stderr.toString()) && blockedSignIn.usable != null && blockedSignIn.take()) {
      logInfo('$videoId was taken for a bot; asking again signed in (${blockedSignIn.usedThisHour} this hour)');
      signed = true;
      result = await run(signed: true);
      if (!_failed(result) && blockedSignIn.tell()) onSignedInPlay?.call(videoId);
    } else if (signedFirst && signed && !_failed(result) && blockedSignIn.tell()) {
      onSignedInPlay?.call(videoId);
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
  Future<ProcessResult> _signedIn(MembersCookies cookies, String videoId, String format, {String? formatSort, bool live = false}) async {
    await infoDirectory.create(recursive: true);
    final path = '${infoDirectory.path}${Platform.pathSeparator}$videoId-${_cookieFiles++}.cookies.txt';
    try {
      if (!await cookies.writeCookies(path)) {
        logWarn('The cookie sign-in could not be opened for $videoId');
        return await _ytDlp(videoId, format, formatSort: formatSort, live: live);
      }
      return await _ytDlp(videoId, format, formatSort: formatSort, cookies: path, live: live);
    } finally {
      cookies.wipeCookies(path);
    }
  }

  static String _lastLine(ProcessResult result) => const LineSplitter().convert(result.stderr.toString().trim()).lastOrNull ?? 'exit ${result.exitCode}';

  bool _failed(ProcessResult result) => result.exitCode != 0 || result.stdout.toString().trim().isEmpty;

  /// yt-dlp for [videoId]; [background] (the video id) runs it at low
  /// priority until [resolve] asks for that video. A video played in the
  /// foreground goes to the standby yt-dlp when one with the same
  /// arguments is waiting, and another is started for the next.
  Future<ProcessResult> _ytDlp(String videoId, String format, {String? formatSort, String? background, String? cookies, bool live = false}) async {
    final plain = background == null && cookies == null && !live;
    try {
      if (plain) {
        if (await _fromStandby(videoId, format, formatSort) case final result?) return result;
      }
      return await runWithTimeout(
        ytDlpPath,
        arguments(videoId, format, formatSort: formatSort, cookies: cookies, live: live),
        timeout: _timeout,
        environment: _environment,
        onStart: (process) {
          _working[videoId] = process.pid;
          if (background == null) return;
          lowerPriority(process.pid);
          _lowered[background] = process.pid;
        },
      );
    } finally {
      _working.remove(videoId);
      _lowered.remove(videoId);
      if (plain) _warm(format, formatSort);
    }
  }

  static const _timeout = Duration(seconds: 45);

  /// Whether a yt-dlp is kept started and waiting for the next video's
  /// address, so a click does not wait for yt-dlp to start (about 2.6 s of
  /// a 6 s run on a Windows PC, measured 2026-11-17: 6.17 s → 3.74 s).
  /// Desktop only: the phones run yt-dlp inside the app's own Python.
  /// Off under `flutter test`, whose fake yt-dlp scripts count their runs.
  bool standbyEnabled = (Platform.isWindows || Platform.isLinux || Platform.isMacOS) && Platform.environment['FLUTTER_TEST'] != 'true';

  /// How long a standby waits for a video before it is ended; the pointer
  /// on a card starts one again.
  static Duration standbyIdle = const Duration(minutes: 5);

  _Standby? _standby;

  /// What a standby was started with, so one started before the IPv4
  /// setting changed is not used after.
  static String _standbyKey(List<String> args) => '${ProcessTree.familyArguments.join()}\u0000${args.join('\u0000')}';
  /// The arguments of the standby being started, so two calls start one.
  String? _starting;

  /// [arguments] for the standby: everything but the address, which it
  /// reads from stdin.
  List<String> standbyArguments(String format, String? formatSort) {
    final all = arguments('', format, formatSort: formatSort);
    return [...all.sublist(0, all.length - 2), '--batch-file', '-'];
  }

  /// Makes sure a standby with the arguments for [format] is waiting.
  void _warm(String format, String? formatSort) {
    if (!standbyEnabled) return;
    final args = standbyArguments(format, formatSort);
    final key = _standbyKey(args);
    final standby = _standby;
    if (standby != null && standby.key == key && !standby.collected.exited) {
      standby.keep();
      return;
    }
    if (_starting == key) return;
    standby?.end();
    _standby = null;
    _starting = key;
    unawaited(() async {
      try {
        final process = await ProcessTree.start(ytDlpPath, args, environment: _environment);
        // On Windows it starts below normal priority, beside whatever is
        // playing, and gets normal priority back when given a video;
        // elsewhere a lowered priority could not be raised again.
        if (Platform.isWindows) lowerPriority(process.pid);
        final made = _Standby(key, CollectedProcess(process, ytDlpPath, args));
        if (_starting != key) {
          made.end();
          return;
        }
        _standby = made;
      } catch (e) {
        logDebug(() => 'Could not start a standby yt-dlp: $e');
      } finally {
        if (_starting == key) _starting = null;
      }
    }());
  }

  /// [videoId] read by the standby, when one with the right arguments is
  /// waiting; null otherwise.
  Future<ProcessResult?> _fromStandby(String videoId, String format, String? formatSort) async {
    final standby = _standby;
    if (standby == null || standby.collected.exited || standby.key != _standbyKey(standbyArguments(format, formatSort))) return null;
    _standby = null;
    standby.taken();
    final process = standby.collected.process;
    restorePriority(process.pid);
    try {
      process.stdin.writeln('https://www.youtube.com/watch?v=$videoId');
      await process.stdin.flush();
      await process.stdin.close();
    } catch (e) {
      logDebug(() => 'The standby yt-dlp could not take $videoId: $e');
      standby.end();
      return null;
    }
    _working[videoId] = process.pid;
    logDebug(() => 'Resolving $videoId with the standby yt-dlp');
    return standby.collected.result(_timeout);
  }

  /// The yt-dlp running for each video.
  final _working = <String, int>{};

  /// Lowers the yt-dlp still reading [videoId] once a quick start has
  /// played it: its answer is still wanted, for the qualities, subtitles
  /// and a reopen, but not at the cost of the starting video.
  void unhurried(String videoId) {
    final pid = _working[videoId];
    if (pid == null || _lowered.containsKey(videoId)) return;
    lowerPriority(pid);
    _lowered[videoId] = pid;
  }
}

/// A yt-dlp started with `--batch-file -`, its imports done, waiting for
/// an address on stdin. Ended when unused for [StreamResolver.standbyIdle].
class _Standby {
  _Standby(this.key, this.collected) {
    keep();
  }

  /// Its arguments, joined.
  final String key;
  final CollectedProcess collected;
  Timer? _idle;

  void keep() {
    _idle?.cancel();
    _idle = Timer(StreamResolver.standbyIdle, end);
  }

  void taken() => _idle?.cancel();

  void end() {
    _idle?.cancel();
    if (!collected.exited) collected.process.kill();
  }
}
