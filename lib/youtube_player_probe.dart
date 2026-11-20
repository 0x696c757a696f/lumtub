import 'dart:convert';
import 'dart:isolate';

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
  // The page writes it as a JSON string, which may escape characters. It
  // ran to 548 characters on 2026-11-16.
  static final _visitorData = RegExp(r'"(?:VISITOR_DATA|visitorData)"\s*:\s*"((?:[^"\\]|\\.){10,4000})"');
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
  ///
  /// [playing] is a video being started, which never waits: the `/player`
  /// lookups made for lists (languages, lengths, live states) wait while one is
  /// asked and go a few at a time, as YouTube answers a visitor that asks
  /// too much with "Sign in to confirm you're not a bot", playback
  /// included. A start refused that way asks again at once as the visitor
  /// the refusal names, which playback keeps from then on.
  static Future<http.Response> post(
    http.Client client,
    Map<String, String> headers,
    Map<String, Object?> body, {
    String endpoint = 'player',
    String? mask,
    Duration timeout = const Duration(seconds: 15),
    bool playing = false,
  }) async {
    // Only a start is counted as one: a lookup of another endpoint (/next
    // for the AI filter) counted and never let go held every lookup for a
    // list back for good, so a language picked in Explore showed nothing.
    if (playing) {
      _playing++;
    } else if (endpoint == 'player' && await _waitForPlayback()) {
      return http.Response('', 429, reasonPhrase: 'Resting');
    }
    try {
      final response = await _post(client, headers, body, endpoint: endpoint, mask: mask, timeout: timeout, playing: playing);
      if (!playing && endpoint == 'player' && response.statusCode == 200) _backgroundAnswered(response);
      return response;
    } finally {
      if (playing) {
        _playing--;
        _playedAt = DateTime.now();
      }
    }
  }

  /// Videos being started, and when the last start was answered.
  static int _playing = 0;
  static DateTime _playedAt = DateTime(0);
  /// When the next lookup for a list may go.
  static DateTime _nextLookup = DateTime(0);
  /// Lookups for lists in a row YouTube took for a bot's, and until when
  /// none is asked after too many.
  static int _refusedInRow = 0;
  static DateTime _restUntil = DateTime(0);

  /// Lookups for lists go at most one per [lookupSpacing], and none while a
  /// video starts or for [afterPlayback] after.
  static const lookupSpacing = Duration(milliseconds: 25);

  /// Whether a phone's app is hidden: lookups for lists wait meanwhile.
  static bool appHidden = false;
  static const afterPlayback = Duration(seconds: 3);
  /// After [refusalsBeforeRest] refusals in a row, lookups for lists rest
  /// for [rest]: asking on only keeps YouTube refusing, playback too.
  static const refusalsBeforeRest = 5;
  static const rest = Duration(minutes: 10);

  /// Holds a lookup for a list back; true when it is not to be asked at
  /// all for now.
  static Future<bool> _waitForPlayback() async {
    while (true) {
      final now = DateTime.now();
      if (now.isBefore(_restUntil)) return true;
      // A phone suspends a hidden app within seconds: a lookup started then
      // stalls until it times out. They wait for the app to come back.
      if (appHidden) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        continue;
      }
      final free = _playedAt.add(afterPlayback);
      if (_playing > 0 || now.isBefore(free)) {
        await Future<void>.delayed(_playing > 0 ? const Duration(milliseconds: 200) : free.difference(now));
        continue;
      }
      if (now.isBefore(_nextLookup)) {
        final wait = _nextLookup.difference(now);
        _nextLookup = _nextLookup.add(lookupSpacing);
        await Future<void>.delayed(wait);
        // A start may have come meanwhile.
        if (_playing > 0) continue;
        return DateTime.now().isBefore(_restUntil);
      }
      _nextLookup = now.add(lookupSpacing);
      return false;
    }
  }

  static void _backgroundAnswered(http.Response response) {
    if (!_botCheck(response)) {
      _refusedInRow = 0;
      return;
    }
    if (++_refusedInRow < refusalsBeforeRest) return;
    _refusedInRow = 0;
    _restUntil = DateTime.now().add(rest);
    logWarn('YouTube took $refusalsBeforeRest lookups in a row for a bot\'s; lookups for lists rest ${rest.inMinutes} minutes so playback is not refused too');
  }

  static bool _botCheck(http.Response response) {
    // A refusal is a few kilobytes; an answer with the video is far longer
    // and is not decoded here again.
    if (response.bodyBytes.length > 32 << 10) return false;
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    return text.contains('"LOGIN_REQUIRED"') && text.contains('bot');
  }

  /// The visitor playback asks as once YouTube refused it as the shared
  /// one, by the visitor data the refusal named.
  static String? _playVisitor;

  @visibleForTesting
  static void resetTraffic() {
    _playing = 0;
    _playedAt = DateTime(0);
    _nextLookup = DateTime(0);
    _refusedInRow = 0;
    _restUntil = DateTime(0);
    _playVisitor = null;
  }

  static Future<http.Response> _post(
    http.Client client,
    Map<String, String> headers,
    Map<String, Object?> body, {
    required String endpoint,
    required String? mask,
    required Duration timeout,
    required bool playing,
  }) async {
    final known = await addVisitor(client, headers, body);
    final own = playing ? _playVisitor : null;
    if (own != null) _useVisitor(headers, body, own);
    Future<http.Response> send({required bool masked}) => client
        .post(
          Uri.parse('https://www.youtube.com/youtubei/v1/$endpoint?prettyPrint=false'),
          headers: {...headers, if (masked && mask != null) 'X-Goog-FieldMask': mask},
          body: jsonEncode(body),
        )
        .timeout(timeout);
    final response = await send(masked: known);
    if (playing && known && response.statusCode == 200 && _botCheck(response)) {
      final data = _visitorIn(utf8.decode(response.bodyBytes, allowMalformed: true));
      if (data == null || data == (own ?? headers['X-Goog-Visitor-Id'])) return response;
      _playVisitor = data;
      logInfo('YouTube took the visitor for a bot; playback asks as the visitor its answer named');
      _useVisitor(headers, body, data);
      return send(masked: true);
    }
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

  static void _useVisitor(Map<String, String> headers, Map<String, Object?> body, String data) {
    headers['X-Goog-Visitor-Id'] = data;
    // The page's cookies name the other visitor.
    headers['Cookie'] = YoutubeWeb.consentCookie;
    ((body['context'] as Map)['client'] as Map)['visitorData'] = data;
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
      // Close to a megabyte: read off the UI thread.
      final bytes = response.bodyBytes;
      final (data, length, named) = await Isolate.run(() {
        final page = utf8.decode(bytes, allowMalformed: true);
        return (_visitorIn(page), page.length, page.contains('VISITOR_DATA'));
      });
      if (response.statusCode != 200 || data == null) {
        final host = response.request?.url.host ?? 'www.youtube.com';
        logWarn('YouTube page gave no visitor data (HTTP ${response.statusCode}, $length characters'
            '${host != 'www.youtube.com' ? ', from $host' : ''}'
            '${named ? ', VISITOR_DATA unreadable' : ''}); taking it from YouTube\'s answers');
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
