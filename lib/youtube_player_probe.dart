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

  /// Who asks, as YouTube's own page told a visitor: its visitor data and
  /// cookies. Signed-out requests without them are the first YouTube asks
  /// to prove they are no bot; yt-dlp opens the page first for the same
  /// reason.
  static Future<_Visitor?>? _visitor;
  static DateTime _visitorAt = DateTime(0);
  static const _visitorFor = Duration(minutes: 30);
  static const _visitorRetry = Duration(minutes: 5);
  // The page writes it as a JSON string, which may escape characters.
  static final _visitorData = RegExp(r'"(?:VISITOR_DATA|visitorData)"\s*:\s*"((?:[^"\\]|\\.){10,400})"');
  static final _visitorCookie = RegExp(r'(VISITOR_INFO1_LIVE|VISITOR_PRIVACY_METADATA|YSC|__Secure-ROLLOUT_TOKEN)=([^;,\s]+)');

  @visibleForTesting
  static void forgetVisitor() {
    _visitor = null;
    _visitorAt = DateTime(0);
  }

  /// Adds the visitor YouTube's page names to a signed-out InnerTube
  /// request's [headers] and [body], opening the page first when it was
  /// not opened lately. Without one, YouTube answers `/player` for most
  /// videos with "Sign in to confirm you're not a bot". False when no
  /// visitor is known.
  static Future<bool> addVisitor(http.Client client, Map<String, String> headers, Map<String, Object?> body) async {
    final visitor = await _visitorNow(client);
    if (visitor == null) return false;
    headers['X-Goog-Visitor-Id'] = visitor.data;
    headers['Cookie'] = visitor.cookies;
    ((body['context'] as Map)['client'] as Map)['visitorData'] = visitor.data;
    return true;
  }

  /// Posts a signed-out InnerTube request to [endpoint] as [addVisitor]
  /// names the visitor. When none is known (YouTube's page did not name
  /// one), the answer's own `responseContext.visitorData` is taken as the
  /// visitor from then on, and a request YouTube refused for want of one
  /// is asked again with it: an answer of "Sign in to confirm you're not a
  /// bot" comes with visitor data, and with it the same request is
  /// answered (seen on 2026-11-14). [mask] (an `X-Goog-FieldMask`) is sent
  /// only with a visitor, as a masked answer leaves the visitor data out.
  static Future<http.Response> post(
    http.Client client,
    Map<String, String> headers,
    Map<String, Object?> body, {
    String endpoint = 'player',
    String? mask,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final known = await addVisitor(client, headers, body);
    Future<http.Response> send({required bool masked}) => client
        .post(
          Uri.parse('https://www.youtube.com/youtubei/v1/$endpoint?prettyPrint=false'),
          headers: {...headers, if (masked && mask != null) 'X-Goog-FieldMask': mask},
          body: jsonEncode(body),
        )
        .timeout(timeout);
    final response = await send(masked: known);
    if (known || response.statusCode != 200) return response;
    final answer = utf8.decode(response.bodyBytes, allowMalformed: true);
    final data = _visitorIn(answer);
    if (data == null) return response;
    if (!await _isKnown()) {
      _visitor = Future.value((data: data, cookies: YoutubeWeb.consentCookie));
      _visitorAt = DateTime.now();
      logInfo('YouTube visitor taken from a /$endpoint answer');
    }
    if (!answer.contains('"LOGIN_REQUIRED"')) return response;
    if (!await addVisitor(client, headers, body)) return response;
    return send(masked: true);
  }

  static Future<bool> _isKnown() async => await (_visitor ?? Future.value()) != null;

  static String? _visitorIn(String text) {
    final raw = _visitorData.firstMatch(text)?.group(1);
    if (raw == null) return null;
    try {
      return jsonDecode('"$raw"') as String;
    } catch (_) {
      return null;
    }
  }

  static Future<_Visitor?> _visitorNow(http.Client client) async {
    final age = DateTime.now().difference(_visitorAt);
    final known = _visitor;
    if (known != null && age < _visitorFor) {
      final visitor = await known;
      if (visitor != null || age < _visitorRetry) return visitor;
    }
    _visitorAt = DateTime.now();
    return _visitor = _openPage(client);
  }

  static Future<_Visitor?> _openPage(http.Client client) async {
    try {
      // As a browser opens it: an API request's headers may get another page.
      final response = await client.get(Uri.parse('https://www.youtube.com/'), headers: {
        'User-Agent': YoutubeWeb.userAgent,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
        'Cookie': YoutubeWeb.consentCookie,
      }).timeout(const Duration(seconds: 15));
      final page = utf8.decode(response.bodyBytes, allowMalformed: true);
      final data = response.statusCode == 200 ? _visitorIn(page) : null;
      if (data == null) {
        final host = response.request?.url.host ?? 'www.youtube.com';
        logWarn('YouTube page gave no visitor data (HTTP ${response.statusCode}, ${page.length} characters'
            '${host != 'www.youtube.com' ? ', from $host' : ''}'
            '${page.contains('VISITOR_DATA') ? ', VISITOR_DATA unreadable' : ''}); taking it from YouTube\'s answers');
        return null;
      }
      final cookies = {
        for (final m in _visitorCookie.allMatches(response.headers['set-cookie'] ?? '')) m.group(1)!: m.group(2)!,
      };
      logDebug(() => 'YouTube visitor from the page, with cookies ${cookies.keys.join(', ')}');
      return (data: data, cookies: [YoutubeWeb.consentCookie, for (final MapEntry(:key, :value) in cookies.entries) '$key=$value'].join('; '));
    } catch (e) {
      logWarn('Could not open the YouTube page for visitor data: $e');
      return null;
    }
  }

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
    final (headers, body) = _request(client, id, hl);
    // Only the few fields read, instead of a few hundred kilobytes.
    final response = await post(_client, headers, body, endpoint: endpoint, mask: fields != null && masks(fields, endpoint: endpoint) ? fields : null);
    final masked = response.request?.headers.containsKey('X-Goog-FieldMask') ?? false;
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
        // The consent cookie too: from Europe, a request without one may
        // be sent to the consent page instead of answered.
        return ({'Content-Type': 'application/json', 'Accept-Language': hl, 'Cookie': YoutubeWeb.consentCookie, ...(parts['headers'] as Map).cast<String, String>()}, body);
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

typedef _Visitor = ({String data, String cookies});

/// Which of YouTube's apps asks: the website, the TV app, or the app a
/// quick start asks as (visionOS), whose answers YouTube refuses least.
enum PlayerClient { quick, tv, web }
