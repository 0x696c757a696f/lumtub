import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'l10n/l10n.dart';
import 'youtube_comments.dart';

/// Saves what YouTube's TV app is answered for the pages a TV-code sign-in
/// could bring into Lumtub, to read their format from. Stays on this PC.
Future<String> saveTvSamples(http.Client client, String accessToken, Directory logs) async {
  final folder = Directory('${logs.path}${Platform.pathSeparator}tv-samples');
  await folder.create(recursive: true);
  final requests = <String, (String, Map<String, Object?>)>{
    'home': ('browse', {'browseId': 'FEwhat_to_watch'}),
    'history': ('browse', {'browseId': 'FEhistory'}),
    'subscriptions': ('browse', {'browseId': 'FEsubscriptions'}),
    'watch-later': ('browse', {'browseId': 'VLWL'}),
    'library': ('browse', {'browseId': 'FElibrary'}),
    'playlists': ('browse', {'browseId': 'FEplaylist_aggregation'}),
    'watch': ('next', {'videoId': 'dQw4w9WgXcQ'}),
    'comments': ('next', {'continuation': YoutubeComments.videoSectionToken('dQw4w9WgXcQ')}),
  };
  final results = <String>[];
  for (final MapEntry(key: name, value: (endpoint, body)) in requests.entries) {
    try {
      final response = await client
          .post(
            Uri.parse('https://www.youtube.com/youtubei/v1/$endpoint?prettyPrint=false'),
            headers: {...YoutubeComments.tvHeaders(youtubeAcceptLanguage), 'Authorization': 'Bearer $accessToken'},
            body: jsonEncode({'context': {'client': YoutubeComments.tvClient(youtubeHl)}, ...body}),
          )
          .timeout(const Duration(seconds: 20));
      await File('${folder.path}${Platform.pathSeparator}$name.json').writeAsBytes(response.bodyBytes);
      results.add('$name ${response.statusCode} ${response.bodyBytes.length}');
    } catch (e) {
      results.add('$name $e');
    }
  }
  logInfo('TV samples saved: ${results.join(' · ')}');
  return tr('已保存到 {0}', [folder.path]);
}
