import 'package:flutter_test/flutter_test.dart';
import 'package:ytplus/app/library_controller.dart';
import 'package:ytplus/channel_feed.dart';
import 'package:ytplus/models.dart';
import 'package:ytplus/video_repository.dart';

void main() {
  const channel = ChannelRef('UCuAXFkgsw1L7xaCfnd5JJOw', 'Rick Astley');

  test('builds the feed address from the channel id', () {
    expect(ChannelFeed.feedUri(channel).toString(), 'https://www.youtube.com/feeds/videos.xml?channel_id=UCuAXFkgsw1L7xaCfnd5JJOw');
  });

  test('parses the entries of a channel feed', () {
    const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns:media="http://search.yahoo.com/mrss/" xmlns="http://www.w3.org/2005/Atom">
 <title>Rick Astley</title>
 <author><name>Rick Astley</name></author>
 <entry>
  <id>yt:video:dQw4w9WgXcQ</id>
  <yt:videoId>dQw4w9WgXcQ</yt:videoId>
  <yt:channelId>UCuAXFkgsw1L7xaCfnd5JJOw</yt:channelId>
  <title>Never Gonna Give You Up &amp; more</title>
  <author><name>Rick Astley</name></author>
  <published>2009-10-25T06:57:33+00:00</published>
  <media:group><media:community><media:statistics views="1700000000"/></media:community></media:group>
 </entry>
 <entry>
  <yt:videoId>broken</yt:videoId>
  <title>No valid id</title>
 </entry>
</feed>''';
    final items = ChannelFeed.parse(xml, channel);
    expect(items, hasLength(1));
    final item = items.single;
    expect(item.id, 'dQw4w9WgXcQ');
    expect(item.title, 'Never Gonna Give You Up & more');
    expect(item.channel, 'Rick Astley');
    expect(item.channelId, channel.id);
    expect(item.viewCount, 1700000000);
    expect(item.published, DateTime.utc(2009, 10, 25, 6, 57, 33));
  });

  test('merges channel feeds newest first, undated last', () {
    VideoItem video(String id, [DateTime? published]) => VideoItem(id: id, title: id, channel: '', url: '', published: published);
    final merged = LibraryController.mergeFeeds([
      [video('a', DateTime(2026, 1, 1)), video('b')],
      [video('c', DateTime(2026, 3, 1)), video('a', DateTime(2026, 1, 1))],
    ]);
    expect(merged.map((item) => item.id), ['c', 'a', 'b']);
  });

  test('lists a channel\'s uploads by item range', () {
    final arguments = VideoRepository('yt-dlp.exe').channelArguments(channel, start: 21, count: 20);
    expect(arguments, containsAllInOrder(['--flat-playlist', '--playlist-items', '21:40']));
    expect(arguments.sublist(arguments.length - 2), ['--', 'https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw/videos']);
  });

  test('reads the channel id from yt-dlp entries', () {
    final item = VideoItem.fromJson({'id': 'dQw4w9WgXcQ', 'title': 'x', 'channel': 'Rick Astley', 'channel_id': 'UCuAXFkgsw1L7xaCfnd5JJOw'});
    expect(item.channelRef, channel);
    expect(VideoItem.fromJson({'id': 'dQw4w9WgXcQ', 'title': 'x', 'channel_id': 'bad'}).channelRef, isNull);
    expect(const VideoItem(id: 'dQw4w9WgXcQ', title: 'x', channel: '', url: '').withChannel(channel).channel, 'Rick Astley');
  });
}
