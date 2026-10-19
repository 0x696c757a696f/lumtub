import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ytplus/app/account_controller.dart';
import 'package:ytplus/app/library_controller.dart';
import 'package:ytplus/google_auth.dart';
import 'package:ytplus/library_store.dart';
import 'package:ytplus/secure_store.dart';

/// Stands in for DPAPI off Windows; it only has to round-trip.
class _XorProtector implements SecretProtector {
  @override
  Uint8List protect(Uint8List data) => Uint8List.fromList([for (final b in data) b ^ 0x5a]);
  @override
  Uint8List unprotect(Uint8List data) => protect(data);
}

void main() {
  late Directory dir;
  late LibraryController library;
  final requests = <String>[];
  var revokedTokens = <String>[];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ytplus_account');
    library = LibraryController(LibraryStore(File('${dir.path}/library.json')));
    requests.clear();
    revokedTokens = [];
  });
  tearDown(() async {
    await library.flush();
    await dir.delete(recursive: true);
  });

  http.Response json(Object data) => http.Response.bytes(utf8.encode(jsonEncode(data)), 200);

  final google = MockClient((request) async {
    final path = request.url.path;
    requests.add(path);
    switch (path) {
      case '/token':
        return http.Response('{"access_token":"access","expires_in":3600,"refresh_token":"refresh-secret"}', 200);
      case '/revoke':
        revokedTokens.add(Uri.splitQueryString(request.body)['token']!);
        return http.Response('', 200);
      case '/youtube/v3/channels':
        return json({'items': [{'snippet': {'title': '我的频道'}, 'contentDetails': {'relatedPlaylists': {'likes': 'LL'}}}]});
      case '/youtube/v3/subscriptions':
        return json({'items': [{'snippet': {'title': 'Rick Astley', 'resourceId': {'channelId': 'UCuAXFkgsw1L7xaCfnd5JJOw'}}}]});
      case '/youtube/v3/playlists':
        return json({'items': [{'id': 'PL1', 'snippet': {'title': '音乐'}, 'contentDetails': {'itemCount': 1}}]});
      case '/youtube/v3/playlistItems':
        final id = request.url.queryParameters['playlistId'];
        return json({'items': [{'snippet': {'title': '$id 视频', 'videoOwnerChannelId': 'UCuAXFkgsw1L7xaCfnd5JJOw'}, 'contentDetails': {'videoId': id == 'LL' ? 'dQw4w9WgXcQ' : 'aaaaaaaaaaa'}}]});
    }
    return http.Response('', 404);
  });

  AccountController controller(List<String> notices) => AccountController(
        clientFile: File('${dir.path}/google-client.json'),
        credentials: SecureJsonFile(File('${dir.path}/google-account.bin'), _XorProtector()),
        client: google,
        library: library,
        notice: notices.add,
        openBrowser: (uri) async {
          final redirect = Uri.parse(uri.queryParameters['redirect_uri']!);
          final client = HttpClient();
          await (await (await client.getUrl(redirect.replace(queryParameters: {'code': 'c', 'state': uri.queryParameters['state']!}))).close()).drain<void>();
          client.close();
        },
      );

  test('signs in, imports subscriptions and playlists, and signs out', () async {
    final notices = <String>[];
    final account = controller(notices);
    await account.load();
    expect(account.client, isNull, reason: 'test builds have no built-in client');
    await account.setCustomClient(const OAuthClientConfig('1-a.apps.googleusercontent.com', 's'));
    await account.signIn();
    expect(account.signedIn, isTrue, reason: account.error);
    expect(account.name, '我的频道');
    // signIn starts the first sync without waiting for it.
    while (account.syncing || account.lastSync == null) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(account.error, isNull);
    expect(library.isFollowing('UCuAXFkgsw1L7xaCfnd5JJOw'), isTrue);
    expect(library.playlists.map((p) => (p.id, p.name, p.items.single.id)), [('yt:LL', '喜欢的视频', 'dQw4w9WgXcQ'), ('yt:PL1', '音乐', 'aaaaaaaaaaa')]);
    expect(notices.last, contains('新增 1 个'));

    // The token on disk is encrypted, and comes back after a restart.
    final raw = await File('${dir.path}/google-account.bin').readAsBytes();
    expect(utf8.decode(raw, allowMalformed: true), isNot(contains('refresh-secret')));
    final restarted = controller([]);
    await restarted.load();
    expect(restarted.signedIn, isTrue);
    expect(restarted.name, '我的频道');

    // A second sync replaces the mirrors and leaves the user's playlists.
    final own = library.createPlaylist('自己的');
    await restarted.sync();
    expect(library.playlists.map((p) => p.id), ['yt:LL', 'yt:PL1', own.id]);
    expect(library.channels, hasLength(1));

    await restarted.signOut();
    expect(restarted.signedIn, isFalse);
    expect(revokedTokens, ['refresh-secret']);
    expect(await File('${dir.path}/google-account.bin').exists(), isFalse);
    expect(library.channels, hasLength(1), reason: 'imported data stays');
  });

  test('a removed YouTube playlist is removed from the mirror', () {
    library.mirrorRemotePlaylists({'PL1': (name: 'a', items: const []), 'PL2': (name: 'b', items: const [])});
    library.mirrorRemotePlaylists({'PL2': (name: 'b2', items: const [])});
    expect(library.playlists.map((p) => (p.id, p.name)), [('yt:PL2', 'b2')]);
  });

  test('a damaged credentials file means signed out', () async {
    await File('${dir.path}/google-account.bin').writeAsBytes([1, 2, 3]);
    final account = controller([]);
    await account.load();
    expect(account.signedIn, isFalse);
  });
}
