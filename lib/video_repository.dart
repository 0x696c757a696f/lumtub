import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_directories.dart';
import 'models.dart';
import 'stream_resolver.dart';

enum SearchFilter {
  all('全部', null),
  videos('视频', 'EgIQAQ%253D%253D'),
  shorts('Shorts', 'EgIQCQ%253D%253D'),
  live('直播', 'EgJAAQ%253D%253D'),
  channels('频道', 'EgIQAg%253D%253D'),
  playlists('播放列表', 'EgIQAw%253D%253D');

  const SearchFilter(this.label, this.sp);
  final String label;
  /// YouTube's own filter parameter, as its results page URL carries it.
  final String? sp;
}

/// The tabs of a channel page; [path] is the channel URL's tab, null for
/// posts, which yt-dlp does not list.
enum ChannelTab {
  videos('视频', '/videos'),
  shorts('Shorts', '/shorts'),
  live('直播', '/streams'),
  playlists('播放列表', '/playlists'),
  posts('社区', null);

  const ChannelTab(this.label, this.path);
  final String label;
  final String? path;
}

/// A listing read a page at a time from one source, such as one yt-dlp
/// process. Each page continues where the last stopped, so scrolling through
/// n results costs O(n) instead of re-fetching earlier pages.
class Listing {
  Listing(this._open, {this.channel, this.timeout = const Duration(seconds: 60)});

  final Stream<String> Function() _open;
  /// Filled in on videos, for listings that leave the channel out.
  final ChannelRef? channel;
  final Duration timeout;

  StreamIterator<String>? _lines;
  int _found = 0;
  bool _done = false;

  bool get done => _done;

  /// Up to [count] more entries, each a [VideoItem] or [ChannelResult].
  /// Fails when the source ends with an error before listing anything or
  /// stalls; other errors after the first entries end the listing.
  Stream<Object> next(int count) async* {
    if (_done) return;
    final lines = _lines ??= StreamIterator(_open());
    var taken = 0;
    while (taken < count) {
      final bool more;
      try {
        more = await lines.moveNext().timeout(timeout, onTimeout: () => throw TimeoutException('yt-dlp 加载超时'));
      } catch (e) {
        close();
        if (_found == 0 || e is TimeoutException) rethrow;
        return;
      }
      if (!more) {
        _done = true;
        return;
      }
      var entry = parseListingEntry(lines.current);
      if (entry == null) continue;
      final ref = channel;
      if (entry is VideoItem && ref != null) entry = entry.withChannel(ref);
      _found++;
      taken++;
      yield entry;
    }
  }

  void close() {
    _done = true;
    unawaited(_lines?.cancel());
  }
}

class VideoRepository {
  final String ytDlpPath;
  final String? cacheDirectory;
  VideoRepository(this.ytDlpPath, {this.cacheDirectory});

  /// Resolves videos for playback ahead of libmpv.
  late final StreamResolver streams = StreamResolver(
    ytDlpPath,
    cacheDirectory: cacheDirectory,
    infoDirectory: Directory(cacheDirectory == null
        ? '${Directory.systemTemp.path}${Platform.pathSeparator}ytplus-info'
        : '${cacheDirectory!}${Platform.pathSeparator}..${Platform.pathSeparator}temp${Platform.pathSeparator}info'),
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
  List<String> listingArguments(String url) => [
        '--no-warnings',
        '--skip-download',
        if (cacheDirectory != null) ...['--cache-dir', cacheDirectory!],
        '--flat-playlist',
        '--lazy-playlist',
        '--dump-json',
        '--', url,
      ];

  /// Search results; one yt-dlp process serves every page.
  Listing search(String query, {SearchFilter filter = SearchFilter.all, String? sp}) =>
      _listing(searchUrl(query.trim(), filter: filter, sp: sp));

  /// [channel]'s uploads, newest first.
  Listing channelVideos(ChannelRef channel) => channelTab(channel, ChannelTab.videos);

  /// One tab of [channel]: uploads, Shorts, live streams or playlists.
  Listing channelTab(ChannelRef channel, ChannelTab tab) => _listing('${channel.url}${tab.path ?? '/videos'}', channel: channel);

  /// The videos of a YouTube playlist.
  Listing playlist(String id) => _listing('https://www.youtube.com/playlist?list=$id');

  /// Videos of [channel] matching [query].
  Listing channelSearch(ChannelRef channel, String query) =>
      _listing('${channel.url}/search?query=${Uri.encodeQueryComponent(query.trim())}', channel: channel);

  Listing _listing(String url, {ChannelRef? channel}) =>
      Listing(() => _lines(listingArguments(url)), channel: channel);

  Stream<String> _lines(List<String> arguments) async* {
    final process = await Process.start(ytDlpPath, arguments, environment: _environment);
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
        throw StateError(err.isEmpty ? 'yt-dlp exited with code $exitCode' : err);
      }
    } finally {
      process.kill();
    }
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
