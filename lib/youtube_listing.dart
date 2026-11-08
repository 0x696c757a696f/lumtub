import 'dart:convert';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'native_core.dart';
import 'video_repository.dart';
import 'youtube_web.dart';

/// Search results and channel tabs read from YouTube's web API, a page per
/// request, without starting yt-dlp. The native core turns each response
/// into the lines `yt-dlp --flat-playlist --dump-json` prints, so [Listing]
/// reads them the same way. The API is asked in English, as yt-dlp asks it.
class YoutubeListing {
  YoutubeListing(this._client);
  final http.Client _client;

  /// Whether listings can be read this way: the native core reads them.
  static bool get available => NativeCore.instance != null;

  /// The search for [query]; [sp] is YouTube's filter parameter as its
  /// results page URL carries it, [region] the country to search as from.
  Stream<String> search(String query, {String? sp, String? region}) => _pages('search', {
        'query': query,
        // The URL form is encoded twice; the API takes it decoded once.
        if (sp != null && sp.isNotEmpty) 'params': Uri.decodeQueryComponent(sp),
      }, region: region);

  /// The uploads, Shorts, live streams or playlists of channel
  /// [channelId].
  Stream<String> channelTab(String channelId, ChannelTab tab) => _pages('browse', {
        'browseId': channelId,
        'params': switch (tab) {
          ChannelTab.shorts => 'EgZzaG9ydHPyBgUKA5oBAA%3D%3D',
          ChannelTab.live => 'EgdzdHJlYW1z8gYECgJ6AA%3D%3D',
          ChannelTab.playlists => 'EglwbGF5bGlzdHPyBgQKAkIA',
          _ => 'EgZ2aWRlb3PyBgQKAjoA',
        },
      });

  /// The videos of playlist [id].
  Stream<String> playlist(String id) => _pages('browse', {'browseId': 'VL$id'});

  /// Whether [tab] can be read through [channelTab].
  static bool hasTab(ChannelTab tab) => tab == ChannelTab.videos || tab == ChannelTab.shorts || tab == ChannelTab.live || tab == ChannelTab.playlists;

  // A results page runs to a megabyte.
  static Future<Object?> _readInBackground(List<int> bytes) => Isolate.run(() {
        final core = NativeCore.instance!;
        return jsonDecode(core.take(core.withBytes(bytes, core.youtubeListing)) ?? 'null');
      });

  Stream<String> _pages(String endpoint, Map<String, Object> first, {String? region, Set<String>? followed}) async* {
    final seen = <String>{};
    // Rows (a channel's playlist sections) show their first few items;
    // each whole row is read after the page that showed it.
    followed ??= {};
    followed.add('${first['browseId']} ${first['params']}');
    final shelves = <Map<String, Object>>[];
    Map<String, Object> body = first;
    final tokens = <String>{};
    // A page can hold only videos already listed, or parts the core does
    // not read: the next may still have videos. A few such pages in a row
    // end it.
    var empty = 0;
    for (var page = 0; page < 50; page++) {
      final response = await _client
          .post(
            Uri.parse('https://www.youtube.com/youtubei/v1/$endpoint?prettyPrint=false'),
            headers: YoutubeWeb.apiHeaders(),
            body: jsonEncode({
              'context': {
                'client': {
                  'clientName': 'WEB',
                  'clientVersion': YoutubeWeb.clientVersion,
                  'hl': 'en',
                  'timeZone': 'UTC',
                  'utcOffsetMinutes': 0,
                  if (region != null && region.isNotEmpty) 'gl': region.toUpperCase(),
                },
              },
              ...body,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw StateError('YouTube $endpoint returned HTTP ${response.statusCode}');
      final read = await _readInBackground(response.bodyBytes);
      if (read is! Map<String, dynamic>) throw const FormatException('Unexpected YouTube response');
      var added = 0;
      for (final entry in (read['entries'] as List).cast<Map<String, dynamic>>()) {
        final id = entry['id'];
        if (id is String && !seen.add(id)) continue;
        added++;
        yield jsonEncode(entry);
      }
      for (final shelf in (read['shelves'] as List? ?? const []).cast<Map<String, dynamic>>()) {
        if (followed.add('${shelf['browseId']} ${shelf['params']}')) shelves.add({'browseId': '${shelf['browseId']}', 'params': '${shelf['params']}'});
      }
      final next = read['continuation'];
      empty = added == 0 ? empty + 1 : 0;
      if (next is! String || !tokens.add(next) || empty >= 3) break;
      body = {'continuation': next};
    }
    for (final shelf in shelves) {
      try {
        await for (final line in _pages(endpoint, shelf, region: region, followed: followed)) {
          final id = (jsonDecode(line) as Map)['id'];
          if (id is String && !seen.add(id)) continue;
          yield line;
        }
      } catch (e) {
        // The row's first items are already listed.
        logWarn('YouTube listing row failed: $e');
      }
    }
  }

  /// The lines of [web], or of [fallback] when [web] fails or finds nothing
  /// before its first line. A failure after that ends the listing.
  static Stream<String> orElse(Stream<String> Function() web, Stream<String> Function() fallback) async* {
    var any = false;
    try {
      await for (final line in web()) {
        any = true;
        yield line;
      }
    } catch (e) {
      if (any) rethrow;
      logWarn('YouTube listing failed, using yt-dlp: $e');
    }
    if (!any) yield* fallback();
  }
}
