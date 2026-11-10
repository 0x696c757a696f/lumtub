import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app/library_controller.dart';
import 'package:lumtub/app/subscription_import_actions.dart';
import 'package:lumtub/library_store.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/subscription_import.dart';

const a = 'UCaaaaaaaaaaaaaaaaaaaaaa';
const b = 'UCbbbbbbbbbbbbbbbbbbbbbb';
const c = 'UCcccccccccccccccccccc-_';

SubscriptionImport parse(String s) => parseSubscriptions(utf8.encode(s));

void main() {
  test('NewPipe keeps only YouTube and counts the rest as skipped', () {
    final r = parse(jsonEncode({
      'app_version': '0.27',
      'subscriptions': [
        {'service_id': 0, 'url': 'https://www.youtube.com/channel/$a', 'name': 'A'},
        {'service_id': 1, 'url': 'https://soundcloud.com/x', 'name': 'S'},
        {'service_id': 0, 'url': 'https://www.youtube.com/@handle', 'name': 'H'},
        {'service_id': 0, 'url': 'https://www.youtube.com/channel/$a', 'name': 'A again'},
        'junk',
      ],
    }));
    expect(r.format, SubscriptionFormat.newPipe);
    expect(r.channels, [(a, 'A')]);
    expect(r.skipped, 3);
  });

  test('FreeTube profiles.db merges profiles and dedupes', () {
    final r = parse('${jsonEncode({'_id': 'allChannels', 'name': 'All Channels', 'subscriptions': [{'id': a, 'name': 'A', 'thumbnail': 'x'}, {'id': b, 'name': 'B'}]})}\n\n'
        '${jsonEncode({'_id': 'p2', 'name': 'Music', 'subscriptions': [{'id': b, 'name': 'B'}, {'id': c, 'name': 'C'}]})}\n'
        'not json\n');
    expect(r.format, SubscriptionFormat.freeTube);
    expect(r.channels, [(a, 'A'), (b, 'B'), (c, 'C')]);
  });

  test('FreeTube single JSON export and YouTube-format JSON', () {
    expect(parse(jsonEncode({'subscriptions': [{'id': a, 'name': 'A'}]})).channels, [(a, 'A')]);
    final r = parse(jsonEncode([
      {'snippet': {'title': 'A', 'resourceId': {'channelId': a}}},
      {'snippet': {'title': 'B', 'resourceId': {'channelId': 'bad'}}},
    ]));
    expect(r.format, SubscriptionFormat.youtubeJson);
    expect(r.channels, [(a, 'A')]);
    expect(r.skipped, 1);
  });

  test('Takeout CSV with a localized header, quotes and BOM', () {
    final r = parseSubscriptions(utf8.encode('﻿频道 ID,频道网址,频道标题\r\n$a,http://www.youtube.com/channel/$a,"Comma, ""Quoted"""\r\n\r\n$b,http://www.youtube.com/channel/$b,B\r\nbroken row,x,y\r\n'));
    expect(r.format, SubscriptionFormat.csv);
    expect(r.channels, [(a, 'Comma, "Quoted"'), (b, 'B')]);
    expect(r.skipped, 1);
  });

  test('OPML with folders, entities and non-channel feeds', () {
    final r = parse('''<?xml version="1.0"?><opml version="1.1"><body><outline text="YouTube Subscriptions" title="YouTube Subscriptions">
<outline text="A &amp; B" title="A &amp; B" type="rss" xmlUrl="https://www.youtube.com/feeds/videos.xml?channel_id=$a" />
<outline text='C' type="rss" xmlUrl="https://www.youtube.com/feeds/videos.xml?channel_id=$c"/>
<outline text="List" xmlUrl="https://www.youtube.com/feeds/videos.xml?playlist_id=PL123"/>
</outline></body></opml>''');
    expect(r.format, SubscriptionFormat.opml);
    expect(r.channels, [(a, 'A & B'), (c, 'C')]);
    expect(r.skipped, 1);
  });

  test('malformed or foreign input gives nothing and does not throw', () {
    for (final s in ['', '   ', '{', '[1,2', '{"subscriptions": 5}', '<opml><outline', 'hello world', 'a,b,c\n1,2,3']) {
      final r = parse(s);
      expect(r.channels, isEmpty, reason: s);
    }
    expect(parseSubscriptions([0xff, 0xfe, 0x00, 0x41]).channels, isEmpty);
    expect(parse('{"subscriptions": 5}').format, isNull);
  });

  test('importing adds new channels once and leaves followed ones alone', () async {
    final dir = Directory.systemTemp.createTempSync('lumtub_import');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = LibraryStore(File('${dir.path}/library.json'))..channels.add(const ChannelRef(a, 'Mine', 'https://yt3.ggpht.com/a'));
    final library = LibraryController(store);
    final data = parse('Channel Id,Channel Url,Channel Title\n$a,u,A\n$b,u,B\n$b,u,B\nx,y,z\n');
    final first = followImported(library, data);
    expect((first.added, first.already, first.skipped), (1, 1, 1));
    expect(library.channels.map((ch) => ch.id), [a, b]);
    expect(library.channels.first.name, 'Mine');
    final second = followImported(library, data);
    expect((second.added, second.already), (0, 2));
    expect(library.channels, hasLength(2));
    await library.flush();
  });
}
