import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'models.dart';
import 'youtube_web.dart';

/// Channel ids found for @handles, so a second tap asks nothing.
final _found = <String, String>{};

/// The `UC…` id of the channel with [handle] (`@name`), asked of YouTube's
/// `navigation/resolve_url`; null when it names no channel.
Future<String?> channelIdOfHandle(http.Client client, String handle) async {
  final name = handle.trim();
  // Handles may be in any script, so only spaces and URL parts rule one out.
  if (!RegExp(r'^@[^\s/?#&]{1,100}$').hasMatch(name)) return null;
  if (_found[name] case final id?) return id;
  try {
    final response = await client
        .post(
          Uri.parse('https://www.youtube.com/youtubei/v1/navigation/resolve_url?prettyPrint=false'),
          headers: YoutubeWeb.apiHeaders(),
          body: jsonEncode({
            'context': {
              'client': {'clientName': 'WEB', 'clientVersion': YoutubeWeb.clientVersion, 'hl': 'en'},
            },
            'url': handleUrl(name),
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw StateError('HTTP ${response.statusCode}');
    final id = browseIdOfResolved(jsonDecode(utf8.decode(response.bodyBytes)));
    if (id != null) _found[name] = id;
    return id;
  } catch (e) {
    logWarn('Could not look up the channel $name: $e');
    return null;
  }
}

/// The page address of [handle]: the `@` as it is, the rest encoded, as
/// YouTube links it; `%40name` names no channel.
String handleUrl(String handle) => 'https://www.youtube.com/@${Uri.encodeComponent(handle.substring(1))}';

/// The channel id in a `navigation/resolve_url` answer.
String? browseIdOfResolved(Object? answer) {
  if (answer is! Map) return null;
  final endpoint = answer['endpoint'];
  final browse = endpoint is Map ? endpoint['browseEndpoint'] : null;
  final id = browse is Map ? browse['browseId'] : null;
  return id is String && ChannelRef.isValidId(id) ? id : null;
}
