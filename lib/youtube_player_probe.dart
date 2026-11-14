import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'native_core.dart';
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

  static String? _visitor;
  static final _visitorData = RegExp(r'"visitorData"\s*:\s*"([A-Za-z0-9_%=-]{10,200})"');

  @visibleForTesting
  static void forgetVisitor() => _visitor = null;

  /// Whether [fields] are still asked for as a mask.
  bool masks(String fields, {String endpoint = 'player'}) => !_refused.contains(endpoint) && !_refused.contains('$endpoint $fields');

  /// The answer's bytes, cut down to [fields] (an `X-Goog-FieldMask`)
  /// where YouTube allows it. With [expect], a masked answer that lacks
  /// that key is asked again whole, and when the whole one has it the mask
  /// is dropped from then on.
  ///
  /// With [tv], YouTube's TV app asks instead of the website: it gets
  /// answers the website is refused without a sign-in.
  ///
  /// [hl] is the language the answer's texts are asked in: a title the
  /// uploader translated comes back in it.
  Future<List<int>> fetch(String id, String? fields, {String endpoint = 'player', String? expect, bool tv = false, String hl = 'en'}) => fetchAs(
        tv ? PlayerClient.tv : PlayerClient.web,
        id,
        fields,
        endpoint: endpoint,
        expect: expect,
        hl: hl,
      );

  /// [fetch] as [client] asks. [PlayerClient.quick] needs the Rust core:
  /// without it the TV app asks.
  Future<List<int>> fetchAs(PlayerClient client, String id, String? fields, {String endpoint = 'player', String? expect, String hl = 'en'}) async {
    final masked = fields != null && masks(fields, endpoint: endpoint);
    final (headers, body) = _request(client, id, hl);
    // The visitor id YouTube gave, sent back as a browser sends its cookie:
    // a stranger with none is the first taken for a bot.
    if (_visitor case final visitor?) {
      headers['X-Goog-Visitor-Id'] = visitor;
      ((body['context'] as Map)['client'] as Map)['visitorData'] = visitor;
    }
    final response = await _client
        .post(
          Uri.parse('https://www.youtube.com/youtubei/v1/$endpoint?prettyPrint=false'),
          headers: {
            ...headers,
            // Only the few fields read, instead of a few hundred kilobytes.
            if (masked) 'X-Goog-FieldMask': '$fields,responseContext.visitorData',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    if (_visitor == null && response.statusCode == 200) {
      _visitor = _visitorData.firstMatch(utf8.decode(response.bodyBytes.take(4096).toList(), allowMalformed: true))?.group(1);
    }
    if (response.statusCode == 400 && masked) {
      _refused.add(endpoint);
      logWarn('YouTube refused the field mask for /$endpoint; asking for whole answers');
      return fetchAs(client, id, fields, endpoint: endpoint, hl: hl);
    }
    if (response.statusCode != 200) throw StateError('$endpoint answered HTTP ${response.statusCode}');
    if (masked && expect != null && !utf8.decode(response.bodyBytes, allowMalformed: true).contains('"$expect"')) {
      final whole = await fetchAs(client, id, null, endpoint: endpoint, hl: hl);
      if (utf8.decode(whole, allowMalformed: true).contains('"$expect"')) {
        _refused.add('$endpoint $fields');
        logWarn('The /$endpoint field mask left out $expect; asking for whole answers');
      }
      return whole;
    }
    return response.bodyBytes;
  }

  static (Map<String, String>, Map<String, Object?>) _request(PlayerClient client, String id, String hl) {
    if (client == PlayerClient.quick) {
      // As a quick start asks (see quick.rs), with the texts in [hl].
      if (NativeCore.instance?.quickRequest(id) case final json?) {
        final parts = jsonDecode(json) as Map<String, dynamic>;
        final body = (parts['body'] as Map).cast<String, Object?>();
        ((body['context'] as Map)['client'] as Map)['hl'] = hl;
        return ({'Content-Type': 'application/json', 'Accept-Language': hl, ...(parts['headers'] as Map).cast<String, String>()}, body);
      }
      client = PlayerClient.tv;
    }
    final tv = client == PlayerClient.tv;
    return (
      {
        ...YoutubeWeb.apiHeaders(acceptLanguage: hl),
        if (tv) ...{'User-Agent': _tvUserAgent, 'X-YouTube-Client-Name': '7', 'X-YouTube-Client-Version': _tvVersion},
      },
      {
        'context': {
          'client': tv
              ? {'clientName': 'TVHTML5', 'clientVersion': _tvVersion, 'userAgent': _tvUserAgent, 'hl': hl, 'timeZone': 'UTC', 'utcOffsetMinutes': 0}
              : {'clientName': 'WEB', 'clientVersion': YoutubeWeb.clientVersion, 'hl': hl, 'timeZone': 'UTC', 'utcOffsetMinutes': 0},
        },
        'videoId': id,
      },
    );
  }
}

/// Which of YouTube's apps asks: the website, the TV app, or the app a
/// quick start asks as (visionOS), whose answers YouTube refuses least.
enum PlayerClient { quick, tv, web }
