import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'native_core.dart';
import 'video_repository.dart';

/// Search results and channel tabs read from YouTube's web API, a page per
/// request, without starting yt-dlp. The native core turns each response
/// into the lines `yt-dlp --flat-playlist --dump-json` prints, so [Listing]
/// reads them the same way. The API is asked in English, as yt-dlp asks it.
class YoutubeListing {
  YoutubeListing(this._client);
  final http.Client _client;

  static const _clientVersion = '2.20260708.00.00';

  /// Whether listings can be read this way: the native core reads them.
  static bool get available => NativeCore.instance != null;

  /// The search for [query]; [sp] is YouTube's filter parameter as its
  /// results page URL carries it, [region] the country to search as from.
  Stream<String> search(String query, {String? sp, String? region}) => _pages('search', {
        'query': query,
        // The URL form is encoded twice; the API takes it decoded once.
        if (sp != null && sp.isNotEmpty) 'params': Uri.decodeQueryComponent(sp),
      }, region: region);

  /// The uploads, Shorts or live streams of channel [channelId].
  Stream<String> channelTab(String channelId, ChannelTab tab) => _pages('browse', {
        'browseId': channelId,
        'params': switch (tab) {
          ChannelTab.shorts => 'EgZzaG9ydHPyBgUKA5oBAA%3D%3D',
          ChannelTab.live => 'EgdzdHJlYW1z8gYECgJ6AA%3D%3D',
          _ => 'EgZ2aWRlb3PyBgQKAjoA',
        },
      });

  /// Whether [tab] can be read through [channelTab].
  static bool hasTab(ChannelTab tab) => tab == ChannelTab.videos || tab == ChannelTab.shorts || tab == ChannelTab.live;

  Stream<String> _pages(String endpoint, Map<String, Object> first, {String? region}) async* {
    final core = NativeCore.instance!;
    final seen = <String>{};
    Map<String, Object> body = first;
    for (var page = 0; page < 50; page++) {
      final response = await _client
          .post(
            Uri.parse('https://www.youtube.com/youtubei/v1/$endpoint?prettyPrint=false'),
            headers: const {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
              'Content-Type': 'application/json',
              'Origin': 'https://www.youtube.com',
              'X-YouTube-Client-Name': '1',
              'X-YouTube-Client-Version': _clientVersion,
              'Cookie': 'CONSENT=YES+cb; SOCS=CAI',
            },
            body: jsonEncode({
              'context': {
                'client': {
                  'clientName': 'WEB',
                  'clientVersion': _clientVersion,
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
      final read = jsonDecode(core.take(core.withText(utf8.decode(response.bodyBytes), core.youtubeListing)) ?? 'null');
      if (read is! Map<String, dynamic>) throw const FormatException('Unexpected YouTube response');
      var added = 0;
      for (final entry in (read['entries'] as List).cast<Map<String, dynamic>>()) {
        final id = entry['id'];
        if (id is String && !seen.add(id)) continue;
        added++;
        yield jsonEncode(entry);
      }
      final next = read['continuation'];
      if (next is! String || added == 0) return;
      body = {'continuation': next};
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
      logInfo('YouTube listing failed, using yt-dlp: $e');
    }
    if (!any) yield* fallback();
  }
}
