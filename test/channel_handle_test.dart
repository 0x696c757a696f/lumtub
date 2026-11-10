import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/channel_handle.dart';

void main() {
  test('reads the channel id of a resolved handle', () {
    expect(browseIdOfResolved({'endpoint': {'browseEndpoint': {'browseId': 'UCBR8-60-B28hp2BmDPdntcQ'}}}), 'UCBR8-60-B28hp2BmDPdntcQ');
    expect(browseIdOfResolved({'endpoint': {'urlEndpoint': {'url': 'https://example.com'}}}), isNull);
    expect(browseIdOfResolved({'endpoint': {'browseEndpoint': {'browseId': 'FEwhat_to_watch'}}}), isNull);
    expect(browseIdOfResolved(null), isNull);
  });

  test('asks YouTube once per handle and only for handles', () async {
    var asked = 0;
    final client = MockClient((request) async {
      asked++;
      expect(request.url.path, '/youtubei/v1/navigation/resolve_url');
      expect((jsonDecode(request.body) as Map)['url'], 'https://www.youtube.com/%40ThuyVanDo-v4p');
      return http.Response(jsonEncode({'endpoint': {'browseEndpoint': {'browseId': 'UCaaaaaaaaaaaaaaaaaaaaaa'}}}), 200);
    });
    expect(await channelIdOfHandle(client, '@ThuyVanDo-v4p'), 'UCaaaaaaaaaaaaaaaaaaaaaa');
    expect(await channelIdOfHandle(client, '@ThuyVanDo-v4p'), 'UCaaaaaaaaaaaaaaaaaaaaaa');
    expect(asked, 1);
    expect(await channelIdOfHandle(client, 'Just a name'), isNull);
    expect(await channelIdOfHandle(client, '@two words'), isNull);
    expect(asked, 1);
  });

  test('handles in other scripts are looked up', () async {
    final client = MockClient((request) async {
      expect((jsonDecode(request.body) as Map)['url'], 'https://www.youtube.com/${Uri.encodeComponent('@黄总-🙂')}');
      return http.Response(jsonEncode({'endpoint': {'browseEndpoint': {'browseId': 'UCbbbbbbbbbbbbbbbbbbbbbb'}}}), 200);
    });
    expect(await channelIdOfHandle(client, '@黄总-🙂'), 'UCbbbbbbbbbbbbbbbbbbbbbb');
  });

  test('a failed lookup gives null', () async {
    final client = MockClient((_) async => http.Response('nope', 500));
    expect(await channelIdOfHandle(client, '@nobody'), isNull);
  });
}
