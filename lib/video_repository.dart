import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_directories.dart';
import 'app_log.dart';
import 'background_json.dart';
import 'live_chat_repository.dart';
import 'models.dart';
import 'process_priority.dart';
import 'process_runner.dart';
import 'stream_resolver.dart';
import 'youtube_listing.dart';
import 'l10n/l10n.dart';
import 'native_core.dart';

enum SearchFilter {
  all('All', null),
  videos('Videos', 'EgIQAQ%253D%253D'),
  shorts('Shorts', 'EgIQCQ%253D%253D'),
  live('Live', 'EgJAAQ%253D%253D'),
  channels('Channel', 'EgIQAg%253D%253D'),
  playlists('Playlist', 'EgIQAw%253D%253D');

  const SearchFilter(this._label, this.sp);
  final String _label;
  String get label => tr(_label);
  /// YouTube's own filter parameter, as its results page URL carries it.
  final String? sp;
}

/// The tabs of a channel page; [path] is the channel URL's tab, null for
/// posts, which yt-dlp does not list.
enum ChannelTab {
  videos('Videos', '/videos'),
  shorts('Shorts', '/shorts'),
  live('Live', '/streams'),
  playlists('Playlist', '/playlists'),
  podcasts('Podcasts', '/podcasts'),
  posts('Community', null);

  const ChannelTab(this._label, this.path);
  final String _label;
  String get label => tr(_label);
  final String? path;
}

/// A listing read a page at a time from one source, such as one yt-dlp
/// process. Each page continues where the last stopped, so scrolling through
/// n results costs O(n) instead of re-fetching earlier pages.
class Listing {
  Listing(this._open, {this.channel, this.timeout = const Duration(seconds: 60), this.idleTimeout = const Duration(seconds: 20)});

  final Stream<String> Function() _open;
  /// Filled in on videos, for listings that leave the channel out.
  final ChannelRef? channel;
  final Duration timeout;
  /// How long the source may sit unread before it is closed. A yt-dlp
  /// process waiting for the next page holds ~40 MB, and every list the
  /// user has looked at would keep one; the next page then starts a new
  /// one and skips what was already read.
  final Duration idleTimeout;

  StreamIterator<String>? _lines;
  Timer? _idle;
  /// Lines read from the source so far, kept or not.
  int _read = 0;
  int _found = 0;
  bool _done = false;

  bool get done => _done;

  /// The error that ended the listing after its first entries, which
  /// otherwise reads as its end: a list with nothing left to show after
  /// its filters reports it instead of calling itself empty.
  Object? lateError;

  /// A listing made once [make] has what it needs, such as search words
  /// to translate first.
  static Listing deferred(Future<Listing> Function() make) => Listing(() async* {
        yield* (await make())._open();
      });

  /// This listing with its lines passed through [refine] first, such as
  /// to keep only videos in one language.
  Listing refined(Stream<String> Function(Stream<String> lines) refine) => Listing(() => refine(_open()), channel: channel, timeout: timeout, idleTimeout: idleTimeout);

  /// This listing, then [then]'s once this one ends, such as a wider
  /// search after a narrow one ran out; [switched] is called between.
  Listing followedBy(Listing Function() then, {void Function()? switched}) => Listing(() async* {
        yield* _open();
        switched?.call();
        yield* then()._open();
      }, channel: channel, timeout: timeout, idleTimeout: idleTimeout);

  /// Up to [count] more entries, each a [VideoItem] or [ChannelResult].
  /// Fails when the source ends with an error before listing anything or
  /// stalls; other errors after the first entries end the listing.
  Stream<Object> next(int count) async* {
    if (_done) return;
    _idle?.cancel();
    try {
      var lines = _lines;
      if (lines == null) {
        lines = _lines = StreamIterator(_open());
        // Reopened after going idle: past what was already shown.
        for (var skip = _read; skip > 0; skip--) {
          if (!await _move(lines)) return;
        }
      }
      var taken = 0;
      while (taken < count) {
        if (!await _move(lines)) return;
        _read++;
        var entry = parseListingEntry(lines.current);
        if (entry == null) continue;
        final ref = channel;
        if (entry is VideoItem && ref != null) entry = entry.withChannel(ref);
        _found++;
        taken++;
        yield entry;
      }
    } finally {
      if (!_done) _idle = Timer(idleTimeout, _suspend);
    }
  }

  /// The next line, false at the end; see [next] for which errors fail.
  Future<bool> _move(StreamIterator<String> lines) async {
    final bool more;
    try {
      more = await lines.moveNext().timeout(timeout, onTimeout: () => throw TimeoutException(tr('yt-dlp timed out loading')));
    } catch (e) {
      close();
      if (_found == 0 || e is TimeoutException) rethrow;
      lateError = e;
      return false;
    }
    if (!more) _done = true;
    return more;
  }

  void _suspend() {
    final lines = _lines;
    _lines = null;
    unawaited(lines?.cancel());
  }

  void close() {
    _done = true;
    _idle?.cancel();
    unawaited(_lines?.cancel());
  }
}

class VideoRepository {
  final String ytDlpPath;
  final String? cacheDirectory;
  /// Deno for YouTube's JavaScript challenges.
  final String? deno;
  /// Put before PATH for yt-dlp, so it finds Deno even though
  /// [Platform.environment] still holds the PATH from before the app
  /// added them.
  final List<String> toolDirectories;
  /// yt-dlp's `--proxy` value at the time of each call, see
  /// `NetworkProxy.ytDlpValue`.
  final String? Function()? proxy;
  /// Reads search results and channel tabs from YouTube's web API, with
  /// yt-dlp as the fallback; null lists everything with yt-dlp.
  final YoutubeListing? web;
  VideoRepository(this.ytDlpPath, {this.cacheDirectory, this.deno, this.toolDirectories = const [], this.proxy, http.Client? client})
      : web = client == null ? null : YoutubeListing(client);

  List<String> get _proxyArguments {
    final value = proxy?.call();
    return value == null ? const [] : ['--proxy', value];
  }

  /// Resolves videos for playback ahead of libmpv.
  late final StreamResolver streams = StreamResolver(
    ytDlpPath,
    cacheDirectory: cacheDirectory,
    deno: deno,
    proxy: proxy,
    infoDirectory: Directory(cacheDirectory == null
        ? '${Directory.systemTemp.path}${Platform.pathSeparator}lumtub-info'
        : '${cacheDirectory!}${Platform.pathSeparator}..${Platform.pathSeparator}temp${Platform.pathSeparator}info'),
    environment: _environment,
  );

  /// Read-only chat replay, written under this repository's configured cache.
  late final LiveChatRepository liveChat = LiveChatRepository(
    ytDlpPath,
    cacheDirectory: cacheDirectory,
    deno: deno,
    proxy: proxy,
    environment: _environment,
  );

  static const pageSize = 20;

  /// YouTube's results page for [query], which lists channels as well as
  /// videos; `sp` is YouTube's own filter parameter.
  static String searchUrl(String query, {SearchFilter filter = SearchFilter.all, String? sp}) {
    final params = sp ?? filter.sp;
    return 'https://www.youtube.com/results?search_query=${Uri.encodeQueryComponent(query)}${params == null ? '' : '&sp=$params'}';
  }

  /// yt-dlp arguments that print a listing's entries one per line as they
  /// arrive. `--lazy-playlist` matters: without it yt-dlp collects the whole
  /// listing before printing anything.
  List<String> listingArguments(String url, {String? cookies}) => [
        '--no-warnings',
        '--skip-download',
        if (cacheDirectory != null) ...['--cache-dir', cacheDirectory!],
        if (cookies != null) ...['--cookies', cookies],
        ..._proxyArguments,
        '--extractor-retries', '3',
        '--flat-playlist',
        '--lazy-playlist',
        '--extractor-args', 'youtubetab:approximate_date',
        '--dump-json',
        '--', url,
      ];

  /// Search results; one yt-dlp process serves every page. [region] is
  /// YouTube's country code (`gl`) to search as from, if not the one the
  /// connection gives.
  Listing search(String query, {SearchFilter filter = SearchFilter.all, String? sp, String? region}) {
    final url = searchUrl(query.trim(), filter: filter, sp: sp);
    Stream<String> ytDlp() => region == null || region.isEmpty ? _lines(listingArguments(url)) : _regionLines(url, region);
    final web = this.web;
    if (web == null || !YoutubeListing.available) return Listing(ytDlp);
    return Listing(() => YoutubeListing.orElse(() => web.search(query.trim(), sp: sp ?? filter.sp, region: region), ytDlp, videos: true));
  }

  /// The videos [first] finds, or a search for [query] when it finds none
  /// or fails.
  Listing videosOr(Future<List<VideoItem>> Function() first, String query) => Listing(() => YoutubeListing.orElse(() async* {
        for (final item in await first()) {
          yield jsonEncode(item.toJson());
        }
      }, () => search(query, filter: SearchFilter.videos)._open()));

  /// Several searches at once, a few results of each in turn, for a mix
  /// of zones. A search that fails drops out; the mix fails only if all do.
  Listing searchMix(List<String> queries, {String? sp, String? region}) =>
      Listing(() => interleave([for (final q in queries) () => search(q, sp: sp, region: region)._open()]));

  /// Lines from each of [sources] in turn, up to [run] at a time from each.
  /// Up to [parallel] sources are read at once and a source with nothing
  /// ready yet is passed over, so one slow search holds back no other;
  /// the next source starts when one ends. Each source reads at most
  /// [ahead] lines before it waits to be taken from.
  static Stream<String> interleave(List<Stream<String> Function()> sources, {int run = 3, int parallel = 4, int ahead = 40}) async* {
    final pending = [...sources];
    final feeds = <_Feed>[];
    var signal = Completer<void>();
    void wake() {
      if (!signal.isCompleted) signal.complete();
    }

    void start() {
      while (feeds.length < parallel && pending.isNotEmpty) {
        feeds.add(_Feed(pending.removeAt(0)(), ahead, wake));
      }
    }

    Object? lastError;
    var yielded = false;
    var i = 0;
    try {
      start();
      while (feeds.isNotEmpty) {
        _Feed? ready;
        for (var k = 0; k < feeds.length; k++) {
          final feed = feeds[(i + k) % feeds.length];
          if (feed.lines.isNotEmpty || feed.ended) {
            i = (i + k) % feeds.length;
            ready = feed;
            break;
          }
        }
        if (ready == null) {
          await signal.future;
          signal = Completer<void>();
          continue;
        }
        var taken = 0;
        while (taken < run && ready.lines.isNotEmpty) {
          taken++;
          yielded = true;
          yield ready.take();
        }
        if (ready.ended && ready.lines.isEmpty) {
          lastError = ready.error ?? lastError;
          feeds.removeAt(i);
          start();
        } else {
          i++;
        }
        if (feeds.isNotEmpty) i %= feeds.length;
      }
      if (!yielded && lastError != null) throw lastError;
    } finally {
      for (final feed in feeds) {
        await feed.cancel();
      }
    }
  }

  /// YouTube takes the country from the PREF cookie, as its own location
  /// setting saves it. Each process gets a cookie file of its own with
  /// nothing else in it, removed afterwards, so no visitor id is kept.
  Stream<String> _regionLines(String url, String region) async* {
    final directory = Directory(cacheDirectory == null
        ? '${Directory.systemTemp.path}${Platform.pathSeparator}lumtub-region'
        : '${cacheDirectory!}${Platform.pathSeparator}..${Platform.pathSeparator}temp${Platform.pathSeparator}region');
    await directory.create(recursive: true);
    final file = File('${directory.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}-${_cookieFiles++}.txt');
    await file.writeAsString(regionCookies(region));
    try {
      yield* _lines(listingArguments(url, cookies: file.path));
    } finally {
      try {
        await file.delete();
      } on FileSystemException {
        // Left for 清理缓存.
      }
    }
  }

  static int _cookieFiles = 0;

  /// A Netscape cookie file holding only YouTube's PREF with country [gl].
  static String regionCookies(String gl) =>
      '# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/\tTRUE\t2147483647\tPREF\tgl=${gl.toUpperCase()}&hl=en\n';

  /// [channel]'s uploads, newest first.
  Listing channelVideos(ChannelRef channel) => channelTab(channel, ChannelTab.videos);

  /// One tab of [channel]: uploads, Shorts, live streams, playlists or
  /// podcasts.
  Listing channelTab(ChannelRef channel, ChannelTab tab) {
    final url = '${channel.url}${tab.path ?? '/videos'}';
    final web = this.web;
    if (web != null && YoutubeListing.available && YoutubeListing.hasTab(tab)) {
      return Listing(() => YoutubeListing.orElse(() => web.channelTab(channel.id, tab), () => _lines(listingArguments(url))), channel: channel);
    }
    if (tab != ChannelTab.playlists && tab != ChannelTab.podcasts) return _listing(url, channel: channel);
    return Listing(() => _expandingLines(url), channel: channel);
  }

  /// A playlists tab split into shelves ("Created playlists", "Saved
  /// playlists") lists each shelf only as a link to its own page, which
  /// --flat-playlist does not follow; those pages are listed in their turn.
  Stream<String> _expandingLines(String url) async* {
    final followed = <String>{};
    await for (final line in _lines(listingArguments(url))) {
      final shelf = shelfUrl(line);
      if (shelf == null) {
        yield line;
      } else if (followed.add(shelf)) {
        yield* _lines(listingArguments(shelf));
      }
    }
  }

  /// The URL of a channel tab shelf that a flat listing line links to, or
  /// null when the line is an entry itself.
  static String? shelfUrl(String line) {
    try {
      final data = jsonDecode(line);
      if (data is! Map) return null;
      final url = data['url']?.toString() ?? '';
      final uri = Uri.tryParse(url);
      if (uri == null || uri.host != 'www.youtube.com' || uri.queryParameters.containsKey('list')) return null;
      final path = uri.path;
      return (path.endsWith('/playlists') || path.endsWith('/podcasts')) && uri.queryParameters.isNotEmpty ? url : null;
    } catch (_) {
      return null;
    }
  }

  /// The videos of a YouTube playlist.
  Listing playlist(String id) {
    final url = 'https://www.youtube.com/playlist?list=$id';
    final web = this.web;
    if (web == null || !YoutubeListing.available) return _listing(url);
    return Listing(() => YoutubeListing.orElse(() => web.playlist(id), () => _lines(listingArguments(url))));
  }

  /// Videos of [channel] matching [query].
  Listing channelSearch(ChannelRef channel, String query) =>
      _listing('${channel.url}/search?query=${Uri.encodeQueryComponent(query.trim())}', channel: channel);

  /// Whether yt-dlp's [error] says a channel has no such tab.
  static bool missingTab(String error) => RegExp(r'This channel does not have an? \w+ tab').hasMatch(error);

  Listing _listing(String url, {ChannelRef? channel}) =>
      Listing(() => _lines(listingArguments(url)), channel: channel);

  Stream<String> _lines(List<String> arguments) async* {
    final process = await ProcessTree.start(ytDlpPath, arguments, environment: _environment);
    lowerPriority(process.pid);
    final stderr = StringBuffer();
    final errors = process.stderr.transform(utf8.decoder).listen(stderr.write);
    try {
      // Reading pauses while the page is full, which pauses yt-dlp through
      // the pipe until the next page is asked for.
      yield* process.stdout.transform(utf8.decoder).transform(const LineSplitter());
      final exitCode = await process.exitCode;
      await errors.cancel();
      if (exitCode != 0) {
        final err = stderr.toString().trim();
        // A channel without that tab (no videos, no Shorts) has nothing to
        // list; it is not a failure.
        if (missingTab(err)) return;
        throw StateError(err.isEmpty ? 'yt-dlp exited with code $exitCode' : err);
      }
    } finally {
      process.kill();
    }
  }

  /// The `lang` values yt-dlp accepts; any other stops the extraction.
  static const _metadataLanguages = {
    'af', 'az', 'id', 'ms', 'bs', 'ca', 'cs', 'da', 'de', 'et', 'en-IN', 'en-GB', 'en', 'es', 'es-419', 'es-US', 'eu', 'fil', 'fr', 'fr-CA',
    'gl', 'hr', 'zu', 'is', 'it', 'sw', 'lv', 'lt', 'hu', 'nl', 'no', 'uz', 'pl', 'pt-PT', 'pt', 'ro', 'sq', 'sk', 'sl', 'sr-Latn', 'fi',
    'sv', 'vi', 'tr', 'be', 'bg', 'ky', 'kk', 'mk', 'mn', 'ru', 'sr', 'uk', 'el', 'hy', 'iw', 'ur', 'ar', 'fa', 'ne', 'mr', 'hi', 'as',
    'bn', 'pa', 'gu', 'or', 'ta', 'te', 'kn', 'ml', 'si', 'th', 'lo', 'my', 'ka', 'am', 'km', 'zh-CN', 'zh-TW', 'zh-HK', 'ja', 'ko',
  };

  /// yt-dlp arguments for watch-page metadata. Skipping the player JS keeps
  /// this cheaper than the extraction libmpv runs for playback; formats are
  /// not needed here. The title and description come in the app's language
  /// when the uploader translated them, else as written.
  List<String> detailsArguments(String videoId) => [
        '--no-warnings',
        '--skip-download',
        if (cacheDirectory != null) ...['--cache-dir', cacheDirectory!],
        '--no-playlist',
        ..._proxyArguments,
        '--ignore-no-formats-error',
        '--extractor-args', ['youtube:player_skip=js', if (_metadataLanguages.contains(youtubeHl)) 'lang=$youtubeHl'].join(';'),
        '--dump-json',
        '--', 'https://www.youtube.com/watch?v=$videoId',
      ];

  Future<VideoDetails> details(String videoId) async {
    final result = await runWithTimeout(ytDlpPath, detailsArguments(videoId), timeout: const Duration(seconds: 45), environment: _environment);
    final output = result.stdout.toString().trim();
    if (result.exitCode != 0 || output.isEmpty) {
      final err = result.stderr.toString().trim();
      throw StateError(err.isEmpty ? 'yt-dlp exited with code ${result.exitCode}' : err);
    }
    final data = await decodeJsonInBackground(const LineSplitter().convert(output).last);
    if (data is! Map<String, dynamic>) throw const FormatException('Unexpected yt-dlp output');
    return VideoDetails.fromJson(data);
  }

  /// The environment yt-dlp runs in, for downloads started elsewhere.
  Map<String, String> get processEnvironment => _environment;

  Map<String, String> get _environment {
    // Windows names it "Path"; keep one entry under its own spelling.
    final pathKey = Platform.environment.keys.firstWhere((key) => key.toUpperCase() == 'PATH', orElse: () => 'PATH');
    return {
      ...Platform.environment,
      if (toolDirectories.isNotEmpty)
        pathKey: [...toolDirectories, Platform.environment[pathKey] ?? ''].join(Platform.isWindows ? ';' : ':'),
      // yt-dlp prints paths and titles in UTF-8, not the Windows code page.
      'PYTHONUTF8': '1',
      'PYTHONIOENCODING': 'utf-8',
      if (cacheDirectory != null) ...{
        'TMP': '${cacheDirectory!}${Platform.pathSeparator}..${Platform.pathSeparator}temp',
        'TEMP': '${cacheDirectory!}${Platform.pathSeparator}..${Platform.pathSeparator}temp',
      },
    };
  }
}

/// How many watched videos the history keeps.
const historyLimit = 5000;

class HistoryStore {
  final AppDirectories directories;
  HistoryStore(this.directories);

  late File file;
  final List<VideoItem> items = [];
  /// When each video in [items] was last played, by id; entries saved by
  /// an older Lumtub have none.
  final Map<String, DateTime> watched = {};
  final _writes = WriteQueue();
  Timer? _saveTimer;

  Future<void> initialize() async {
    file = File('${directories.data.path}${Platform.pathSeparator}watch_history.json');
    if (!await file.exists()) return;
    try {
      final data = await decodeJsonInBackground(await file.readAsString());
      if (data is! List) throw const FormatException('The history is not a list');
      for (final value in data) {
        try {
          if (value is Map<String, dynamic>) {
            final item = VideoItem.fromJson(value);
            items.add(item);
            if (DateTime.tryParse('${value['watched_at'] ?? ''}') case final at?) watched[item.id] = at.toLocal();
          }
        } catch (e) {
          logWarn('Skipped an unreadable history entry: $e');
        }
      }
      if (items.length > historyLimit) items.removeRange(historyLimit, items.length);
    } catch (e) {
      items.clear();
      watched.clear();
      await setBrokenFileAside(file, e);
    }
  }

  Future<void> clear() {
    items.clear();
    watched.clear();
    return _saveNow();
  }

  /// Forgets the videos with these ids.
  Future<void> remove(Set<String> ids) {
    items.removeWhere((item) => ids.contains(item.id));
    watched.removeWhere((id, _) => ids.contains(id));
    return _saveNow();
  }

  /// Sets the live status of the videos with these ids.
  Future<void> setLiveStatus(Map<String, String?> states) {
    for (final (i, item) in items.indexed) {
      if (states.containsKey(item.id)) items[i] = item.withLiveStatus(states[item.id]);
    }
    return _saveNow();
  }

  /// Puts [item] first. The file follows after a moment, so videos played
  /// one after another are one write; [flush] writes it at once.
  Future<void> record(VideoItem item) {
    items.removeWhere((other) => other.id == item.id);
    items.insert(0, item);
    watched[item.id] = DateTime.now();
    if (items.length > historyLimit) {
      for (final old in items.skip(historyLimit)) {
        watched.remove(old.id);
      }
      items.removeRange(historyLimit, items.length);
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), () => unawaited(_saveNow()));
    return Future.value();
  }

  /// Gives a remembered video the length its player found, when the list
  /// it came from had none.
  Future<void> fillDuration(String id, int seconds) {
    final at = items.indexWhere((item) => item.id == id);
    if (at < 0 || items[at].duration != null) return Future.value();
    items[at] = items[at].withDuration(seconds);
    return _saveNow();
  }

  /// Completes when every change so far is on disk.
  Future<void> flush() => _saveNow();

  /// The text is made when the write's turn comes, so it is the latest state.
  Future<void> _saveNow() {
    _saveTimer?.cancel();
    _saveTimer = null;
    return _writes.run(() async {
      try {
        await writeFileAtomic(file, jsonEncode([
          for (final item in items) {...item.toJson(), if (watched[item.id] case final at?) 'watched_at': at.toUtc().toIso8601String()},
        ]));
      } catch (e) {
        logError('Could not save the watch history', e);
      }
    });
  }
}

/// One source of [VideoRepository.interleave], read ahead into [lines].
class _Feed {
  _Feed(Stream<String> source, this._ahead, this._wake) {
    _subscription = source.listen(
      (line) {
        lines.add(line);
        if (lines.length >= _ahead) _subscription.pause();
        _wake();
      },
      onError: (Object e) => error = e,
      onDone: () {
        ended = true;
        _wake();
      },
    );
  }

  final int _ahead;
  final void Function() _wake;
  late final StreamSubscription<String> _subscription;
  final lines = <String>[];
  bool ended = false;
  Object? error;

  String take() {
    final line = lines.removeAt(0);
    if (_subscription.isPaused && lines.length < _ahead) _subscription.resume();
    return line;
  }

  Future<void> cancel() => _subscription.cancel();
}
