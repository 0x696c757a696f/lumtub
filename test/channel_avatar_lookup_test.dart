import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/channel_avatar_lookup.dart';
import 'package:lumtub/ui/pages/channel_page.dart';

void main() {
  const id = 'UCuAXFkgsw1L7xaCfnd5JJOw';
  const other = 'UCBR8-60-B28hp2BmDPdntcQ';
  final lookup = ChannelAvatarLookup.instance;
  tearDown(lookup.reset);

  test('looks a channel up once, keeps it on disk and takes pictures listings gave', () async {
    final dir = Directory.systemTemp.createTempSync('lumtub_avatar_lookup');
    addTearDown(() => dir.deleteSync(recursive: true));
    final asked = <String>[];
    final client = MockClient((request) async {
      asked.add(request.url.pathSegments.last);
      return http.Response('<meta property="og:image" content="https://yt3.googleusercontent.com/${request.url.pathSegments.last}=s900">', 200);
    });
    final file = File('${dir.path}/channel_avatars.json');
    lookup.configure(client, file);
    var told = 0;
    void listener() => told++;
    lookup.addListener(listener);
    addTearDown(() => lookup.removeListener(listener));
    expect(lookup.of(id), isNull);
    expect(lookup.of(id), isNull);
    await pumpEventQueue();
    expect(lookup.of(id), 'https://yt3.googleusercontent.com/$id=s900');
    expect(asked, [id]);
    expect(told, 1);
    expect(lookup.of('not a channel'), isNull);
    lookup.remember(other, 'https://yt3.ggpht.com/given');
    expect(lookup.of(other), 'https://yt3.ggpht.com/given');
    expect(asked, [id]);
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    expect(jsonDecode(file.readAsStringSync()), {id: 'https://yt3.googleusercontent.com/$id=s900', other: 'https://yt3.ggpht.com/given'});
    lookup.reset();
    lookup.configure(MockClient((_) async => throw StateError('asked again')), file);
    expect(lookup.of(id), 'https://yt3.googleusercontent.com/$id=s900');
  });

  testWidgets('an avatar shows the letter until the picture is found', (tester) async {
    final client = MockClient((request) async => http.Response('', 404));
    lookup.configure(client, File('${Directory.systemTemp.path}/lumtub_none_${DateTime.now().microsecondsSinceEpoch}.json'));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ChannelAvatar(name: 'Anna', channelId: id))));
    await tester.pump();
    expect(find.text('A'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
