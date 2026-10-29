import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/app/library_controller.dart';
import 'package:lumtub/library_store.dart';
import 'package:lumtub/models.dart';

void main() {
  const channel = ChannelRef('UCuAXFkgsw1L7xaCfnd5JJOw', 'A channel');

  String entry(String id, String title, DateTime published) => '''
 <entry>
  <yt:videoId>$id</yt:videoId>
  <yt:channelId>${channel.id}</yt:channelId>
  <title>$title</title>
  <published>${published.toUtc().toIso8601String()}</published>
 </entry>''';

  test('marks the feed videos that are live or about to be', () async {
    final now = DateTime.now();
    final feed = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns="http://www.w3.org/2005/Atom">
${entry('aaaaaaaaaaa', 'Streaming now', now.subtract(const Duration(hours: 1)))}
${entry('bbbbbbbbbbb', 'Starts tonight', now.subtract(const Duration(hours: 2)))}
${entry('ccccccccccc', 'A video', now.subtract(const Duration(hours: 3)))}
${entry('ddddddddddd', 'Old video', now.subtract(const Duration(days: 30)))}
</feed>''';
    final asked = <String>[];
    final client = MockClient((request) async {
      if (request.url.path == '/feeds/videos.xml') return http.Response.bytes(utf8.encode(feed), 200);
      final id = (jsonDecode(request.body) as Map)['videoId'] as String;
      asked.add(id);
      expect(request.headers['X-Goog-FieldMask'], 'videoDetails.videoId,videoDetails.isLive,videoDetails.isUpcoming');
      return http.Response(jsonEncode({
        'videoDetails': {
          if (id == 'aaaaaaaaaaa') 'isLive': true,
          if (id == 'bbbbbbbbbbb') 'isUpcoming': true,
        },
      }), 200);
    });
    final dir = Directory.systemTemp.createTempSync('live');
    final library = LibraryController(LibraryStore(File('${dir.path}/library.json')), client: client);
    library.store.toggleFollow(channel);
    await library.refreshFeed(force: true);
    final states = {for (final item in library.feed) item.id: item.liveStatus};
    expect(states, {'aaaaaaaaaaa': 'is_live', 'bbbbbbbbbbb': 'is_upcoming', 'ccccccccccc': null, 'ddddddddddd': null});
    expect(asked, isNot(contains('ddddddddddd')), reason: 'old videos are not asked about');
    dir.deleteSync(recursive: true);
  });
}
