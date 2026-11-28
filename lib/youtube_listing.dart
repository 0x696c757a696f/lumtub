import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'channel_sort.dart';
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
  /// [hl] is the language YouTube is asked in, which it ranks results by:
  /// asked in English, a search for "Cristianesimo" from Italy brought
  /// English videos first (user log, 2026-11-19: 0 of 240 in Italian).
  /// Counts and times are then written in that language: views are read
  /// as a plain number, and how long ago is left out.
  Stream<String> search(String query, {String? sp, String? region, String? hl}) => _pages('search', {
        'query': query,
        // The URL form is encoded twice; the API takes it decoded once.
        if (sp != null && sp.isNotEmpty) 'params': Uri.decodeQueryComponent(sp),
      }, region: region, hl: hl);

  /// The uploads, Shorts, live streams or playlists of channel
  /// [channelId].
  Stream<String> channelTab(String channelId, ChannelTab tab, {ChannelSort sort = ChannelSort.latest}) => _pages('browse', {
        'browseId': channelId,
        'params': switch (tab) {
          ChannelTab.shorts => 'EgZzaG9ydHPyBgUKA5oBAA%3D%3D',
          ChannelTab.live => 'EgdzdHJlYW1z8gYECgJ6AA%3D%3D',
          ChannelTab.playlists => 'EglwbGF5bGlzdHPyBgQKAkIA',
          _ => 'EgZ2aWRlb3PyBgQKAjoA',
        },
      }, sort: sort == ChannelSort.latest ? null : sort.chip);

  /// The videos of playlist [id].
  Stream<String> playlist(String id) => _pages('browse', {'browseId': 'VL$id'});

  /// Whether [tab] can be read through [channelTab].
  static bool hasTab(ChannelTab tab) => tab == ChannelTab.videos || tab == ChannelTab.shorts || tab == ChannelTab.live || tab == ChannelTab.playlists;

  // A results page runs to a megabyte.
  static Future<Object?> _readInBackground(List<int> bytes, {bool chips = false}) => Isolate.run(() {
        final core = NativeCore.instance!;
        final read = jsonDecode(core.take(core.withBytes(bytes, core.youtubeListing)) ?? 'null');
        if (chips && read is Map<String, dynamic>) read['sortChips'] = sortChipTokens(jsonDecode(utf8.decode(bytes)));
        return read;
      });

  Stream<String> _pages(String endpoint, Map<String, Object> first, {String? region, Set<String>? followed, String? sort, String? hl}) async* {
    final seen = <String>{};
    // Rows (a channel's playlist sections) show their first few items;
    // each whole row is read after the page that showed it.
    followed ??= {};
    followed.add('${first['browseId']} ${first['params']}');
    final shelves = <Map<String, Object>>[];
    var body = first;
    final tokens = <String>{};
    // A page can hold only videos already listed, or parts the core does
    // not read: the next may still have videos. A few such pages in a row
    // end it.
    var empty = 0;
    // A playlist logs each page it reads, as one opened on a phone stayed
    // loading with nothing in the log (2026-11-27).
    final traced = '${first['browseId'] ?? ''}'.startsWith('VL') ? first['browseId'] : null;
    for (var page = 0; page < 50; page++) {
      final asked = Stopwatch()..start();
      final response = await _client
          .post(
            Uri.parse('https://www.youtube.com/youtubei/v1/$endpoint?prettyPrint=false'),
            headers: YoutubeWeb.apiHeaders(),
            body: jsonEncode({
              'context': {
                'client': {
                  'clientName': 'WEB',
                  'clientVersion': YoutubeWeb.clientVersion,
                  'hl': hl ?? 'en',
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
      final read = await _readInBackground(response.bodyBytes, chips: sort != null && page == 0);
      if (read is! Map<String, dynamic>) throw const FormatException('Unexpected YouTube response');
      if (traced != null) {
        logInfo('YouTube $traced page ${page + 1}: ${(read['entries'] as List).length} entries, ${response.bodyBytes.length} bytes in ${asked.elapsedMilliseconds} ms${read['continuation'] is String ? ', more to read' : ''}');
      }
      if (sort != null && page == 0) {
        // The sorted list is the chip's own; the default page is shown only
        // when YouTube offers no such chip.
        final token = (read['sortChips'] as Map?)?[sort];
        if (token is String) {
          tokens.add(token);
          body = {'continuation': token};
          continue;
        }
      }
      if (page == 0 && (read['entries'] as List).isEmpty) _logEmpty(endpoint, first, response.bodyBytes);
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
        await for (final line in _pages(endpoint, shelf, region: region, followed: followed, hl: hl)) {
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

  /// Says what an answer without entries held instead, so a list that
  /// comes up empty on one network but not another can be told apart:
  /// YouTube's notices ("This playlist does not exist"), or no list at all.
  static void _logEmpty(String endpoint, Map<String, Object> asked, List<int> body) {
    final text = utf8.decode(body, allowMalformed: true);
    final notices = {
      for (final match in RegExp(r'"(?:alertRenderer|alertWithButtonRenderer)":\{[^{}]*?"text":\{(?:"simpleText":"([^"]{1,200})"|"runs":\[\{"text":"([^"]{1,200})")').allMatches(text)) match[1] ?? match[2],
    }.whereType<String>();
    final what = asked['browseId'] ?? (asked['query'] == null ? endpoint : 'search');
    logInfo('YouTube $what: first page has no entries (${body.length} bytes, '
        '${text.contains('"twoColumnBrowseResultsRenderer"') || text.contains('"twoColumnSearchResultsRenderer"') ? 'with' : 'without'} a list'
        '${notices.isEmpty ? '' : '; ${notices.join(' / ')}'})');
    // The answer itself, beside the log, for whoever reads it: it was
    // asked signed out, so it holds nothing of the user's. Only the latest
    // is kept.
    final log = AppLog.current;
    if (log != null) {
      unawaited(File('${log.file.parent.path}${Platform.pathSeparator}empty-listing.json').writeAsBytes(body).then((_) {}, onError: (_) {}));
    }
  }

  /// The lines of [web], or of [fallback] when [web] fails or finds nothing
  /// before its first line. A failure after that ends the listing. With
  /// [videos], only a video counts as found: a search that turns up
  /// channels alone still asks [fallback].
  static Stream<String> orElse(Stream<String> Function() web, Stream<String> Function() fallback, {bool videos = false}) async* {
    var any = false, lines = 0;
    try {
      await for (final line in web()) {
        lines++;
        any = any || !videos || line.contains('"ie_key":"Youtube"');
        yield line;
      }
    } catch (e) {
      if (any) rethrow;
      logWarn('YouTube listing failed, using yt-dlp: $e');
    }
    if (!any) {
      logInfo('YouTube listing gave no videos ($lines entries), using yt-dlp');
      yield* fallback();
    }
  }
}
