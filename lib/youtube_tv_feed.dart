import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'app_log.dart';
import 'models.dart';
import 'native_core.dart';
import 'youtube_tv_sign_in.dart';

/// The account's own pages on YouTube, read the way YouTube's TV app reads
/// them with the TV-code sign-in: the home feed, watch history, Watch Later
/// and the playlists. Each page comes as the JSON lines a [Listing] reads,
/// parsed by the Rust core (native/lumtub_core/src/tv_browse.rs).
class YoutubeTvFeed {
  YoutubeTvFeed(this.signIn);

  final SignedInnerTube signIn;

  static const home = 'default';
  static const history = 'FEhistory';
  static const watchLater = 'VLWL';
  static const playlists = 'FEplaylist_aggregation';

  /// The Watch Later playlist's id, for [PlaylistResult].
  static const watchLaterId = 'WL';

  static Pointer<Utf8> Function(Pointer<Uint8>, int, bool)? _browse;
  static bool _tried = false;

  static Pointer<Utf8> Function(Pointer<Uint8>, int, bool)? get _native {
    if (_tried) return _browse;
    _tried = true;
    final core = NativeCore.instance;
    if (core == null) return null;
    try {
      return _browse = core.library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size, Bool), Pointer<Utf8> Function(Pointer<Uint8>, int, bool)>('lumtub_tv_browse');
    } catch (e) {
      logInfo('The TV pages are not in this core: $e');
      return null;
    }
  }

  /// Whether the account's pages can be read now.
  bool get available => signIn.signedIn && _native != null;

  /// The entries of [browseId], page after page, as listing lines; at most
  /// [pages] pages. Shorts rows are left out unless [shorts].
  Stream<String> lines(String browseId, {bool shorts = false, int pages = 20}) async* {
    if (_native == null) return;
    Map<String, Object?> body = {'browseId': browseId};
    final seen = <String>{};
    for (var page = 0; page < pages; page++) {
      final answer = await signIn.post('browse', body);
      if (answer == null) return;
      if (answer.status != 200) throw StateError('YouTube answered ${answer.status} for $browseId');
      final data = await read(answer.body, shorts: shorts);
      if (data == null) throw StateError('YouTube sent a page that is not JSON for $browseId');
      for (final entry in (data['entries'] as List? ?? const []).whereType<Map>()) {
        final id = '${entry['id'] ?? ''}';
        if (seen.add(id)) yield jsonEncode(entry);
      }
      for (final list in (data['playlists'] as List? ?? const []).whereType<Map>()) {
        final id = '${list['id'] ?? ''}';
        if (seen.add('list:$id')) yield jsonEncode(playlistLine(list));
      }
      final next = data['continuation'];
      if (next is! String || next.isEmpty) return;
      body = {'continuation': next};
    }
  }

  /// Up to [limit] videos of [browseId].
  Future<List<VideoItem>> videos(String browseId, {int limit = 60}) async {
    final found = <VideoItem>[];
    await for (final line in lines(browseId, pages: 3)) {
      if (parseListingEntry(line) case final VideoItem item) found.add(item);
      if (found.length >= limit) break;
    }
    return found;
  }

  /// The account's own playlists. Watch Later and Liked videos, whose ids
  /// are too short for [PlaylistResult.isValidId], are left out.
  Future<List<PlaylistResult>> accountPlaylists() async {
    final found = <PlaylistResult>[];
    await for (final line in lines(playlists, pages: 3)) {
      if (parseListingEntry(line) case final PlaylistResult list) found.add(list);
    }
    return found;
  }

  /// A playlist tile read by the core as the line a flat yt-dlp listing
  /// prints for one.
  static Map<String, Object?> playlistLine(Map list) => {
        'ie_key': 'YoutubeTab',
        'id': list['id'],
        'url': 'https://www.youtube.com/playlist?list=${list['id']}',
        'title': list['title'],
        'playlist_count': list['count'],
        if (list['thumbnail'] case final String url) 'thumbnails': [{'url': url}],
      };

  /// A TV app `/browse` answer read by the core, on another isolate: a page
  /// runs to a megabyte.
  static Future<Map<String, Object?>?> read(Uint8List body, {bool shorts = false}) => Isolate.run(() {
        final core = NativeCore.instance;
        final browse = _native;
        if (core == null || browse == null) return null;
        final text = core.take(core.withBytes(body, (bytes, length) => browse(bytes, length, shorts)));
        final data = text == null ? null : jsonDecode(text);
        return data is Map<String, Object?> ? data : null;
      });
}
