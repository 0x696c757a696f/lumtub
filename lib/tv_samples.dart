import 'dart:io';

import 'app_log.dart';
import 'l10n/l10n.dart';
import 'youtube_comments.dart';
import 'youtube_tv_sign_in.dart';

/// Saves what YouTube's TV app is answered for the pages a TV-code sign-in
/// could bring into Lumtub, to read their format from. Stays on this PC.
Future<String> saveTvSamples(SignedInnerTube signIn, Directory logs) async {
  final folder = Directory('${logs.path}${Platform.pathSeparator}tv-samples');
  await folder.create(recursive: true);
  final requests = <String, (String, Map<String, Object?>)>{
    'home': ('browse', {'browseId': 'default'}),
    'home-what-to-watch': ('browse', {'browseId': 'FEwhat_to_watch'}),
    'history': ('browse', {'browseId': 'FEhistory'}),
    'subscriptions': ('browse', {'browseId': 'FEsubscriptions'}),
    'watch-later': ('browse', {'browseId': 'VLWL'}),
    'library': ('browse', {'browseId': 'FEmy_youtube'}),
    'playlists': ('browse', {'browseId': 'FEplaylist_aggregation'}),
    'watch': ('next', {'videoId': 'dQw4w9WgXcQ'}),
    'comments': ('next', {'continuation': YoutubeComments.videoSectionToken('dQw4w9WgXcQ')}),
  };
  final results = <String>[];
  for (final MapEntry(key: name, value: (endpoint, body)) in requests.entries) {
    try {
      final answer = await signIn.post(endpoint, body);
      if (answer == null) {
        results.add('$name signed out');
        continue;
      }
      await File('${folder.path}${Platform.pathSeparator}$name.json').writeAsBytes(answer.body);
      results.add('$name ${answer.status} ${answer.body.length}');
    } catch (e) {
      results.add('$name $e');
    }
  }
  logInfo('TV samples saved: ${results.join(' · ')}');
  return tr('已保存到 {0}', [folder.path]);
}
