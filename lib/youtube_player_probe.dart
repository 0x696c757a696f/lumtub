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

  /// Whether YouTube takes a field mask; when it refuses one, whole
  /// answers are asked for from then on.
  static final _refused = <String>{};

  /// The answer's bytes, cut down to [fields] (an `X-Goog-FieldMask`)
  /// where YouTube allows it.
  Future<List<int>> fetch(String id, String? fields, {String endpoint = 'player'}) async {
    final masked = fields != null && !_refused.contains(endpoint);
    final response = await _client
        .post(
          Uri.parse('https://www.youtube.com/youtubei/v1/$endpoint?prettyPrint=false'),
          headers: {
            ...YoutubeWeb.apiHeaders(),
            // Only the few fields read, instead of a few hundred kilobytes.
            if (masked) 'X-Goog-FieldMask': fields,
          },
          body: jsonEncode({
            'context': {
              'client': {'clientName': 'WEB', 'clientVersion': YoutubeWeb.clientVersion, 'hl': 'en', 'timeZone': 'UTC', 'utcOffsetMinutes': 0},
            },
            'videoId': id,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 400 && masked) {
      _refused.add(endpoint);
      logInfo('YouTube refused the field mask for /$endpoint; asking for whole answers');
      return fetch(id, fields, endpoint: endpoint);
    }
    if (response.statusCode != 200) throw StateError('$endpoint answered HTTP ${response.statusCode}');
    return response.bodyBytes;
  }
}
