import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'youtube_web.dart';

/// Asks YouTube's `/player` (or `/next`) for a few fields of one video,
/// such as its language, whether it is live or whether it is labeled as
/// made with AI, without its streams.
class YoutubePlayerProbe {
  YoutubePlayerProbe(this._client);

  final http.Client _client;

  /// Endpoints and masks YouTube refused or answered without what they
  /// ask for; whole answers are asked for from then on.
  static final _refused = <String>{};

  // As the Rust core's TV sign-in sends them.
  static const _tvVersion = '7.20260901.15.00';
  static const _tvUserAgent = 'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)';

  /// Whether [fields] are still asked for as a mask.
  bool masks(String fields, {String endpoint = 'player'}) => !_refused.contains(endpoint) && !_refused.contains('$endpoint $fields');

  /// The answer's bytes, cut down to [fields] (an `X-Goog-FieldMask`)
  /// where YouTube allows it. With [expect], a masked answer that lacks
  /// that key is asked again whole, and when the whole one has it the mask
  /// is dropped from then on.
  ///
  /// With [tv], YouTube's TV app asks instead of the website: it gets
  /// answers the website is refused without a sign-in.
  Future<List<int>> fetch(String id, String? fields, {String endpoint = 'player', String? expect, bool tv = false}) async {
    final masked = fields != null && masks(fields, endpoint: endpoint);
    final response = await _client
        .post(
          Uri.parse('https://www.youtube.com/youtubei/v1/$endpoint?prettyPrint=false'),
          headers: {
            ...YoutubeWeb.apiHeaders(),
            if (tv) ...{'User-Agent': _tvUserAgent, 'X-YouTube-Client-Name': '7', 'X-YouTube-Client-Version': _tvVersion},
            // Only the few fields read, instead of a few hundred kilobytes.
            if (masked) 'X-Goog-FieldMask': fields,
          },
          body: jsonEncode({
            'context': {
              'client': tv
                  ? {'clientName': 'TVHTML5', 'clientVersion': _tvVersion, 'userAgent': _tvUserAgent, 'hl': 'en', 'timeZone': 'UTC', 'utcOffsetMinutes': 0}
                  : {'clientName': 'WEB', 'clientVersion': YoutubeWeb.clientVersion, 'hl': 'en', 'timeZone': 'UTC', 'utcOffsetMinutes': 0},
            },
            'videoId': id,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 400 && masked) {
      _refused.add(endpoint);
      logInfo('YouTube refused the field mask for /$endpoint; asking for whole answers');
      return fetch(id, fields, endpoint: endpoint, tv: tv);
    }
    if (response.statusCode != 200) throw StateError('$endpoint answered HTTP ${response.statusCode}');
    if (masked && expect != null && !utf8.decode(response.bodyBytes, allowMalformed: true).contains('"$expect"')) {
      final whole = await fetch(id, null, endpoint: endpoint, tv: tv);
      if (utf8.decode(whole, allowMalformed: true).contains('"$expect"')) {
        _refused.add('$endpoint $fields');
        logInfo('The /$endpoint field mask left out $expect; asking for whole answers');
      }
      return whole;
    }
    return response.bodyBytes;
  }
}
