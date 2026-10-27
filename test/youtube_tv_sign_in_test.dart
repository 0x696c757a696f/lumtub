import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/native_http.dart';
import 'package:lumtub/youtube_tv_sign_in.dart';

/// Stands in for youtube.com: the TV page and script, the device-code
/// endpoints and InnerTube.
class _FakeYouTube {
  late final HttpServer server;
  var polls = 0;
  var refreshGone = false;
  final asked = <String>[];
  final bodies = <Map<String, dynamic>>[];
  final authorizations = <String?>[];

  String get base => 'http://127.0.0.1:${server.port}';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      asked.add(path);
      final text = await utf8.decodeStream(request);
      final body = text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>;
      bodies.add(body);
      authorizations.add(request.headers.value('authorization'));
      Object? answer;
      String? page;
      var status = 200;
      switch (path) {
        case '/tv':
          page = '<script id="base-js" src="$base/base.js" nonce="n"></script>';
        case '/base.js':
          page = 'x={clientId:"42-tv.apps.googleusercontent.com",\$a:"tvsecret"}';
        case '/o/oauth2/device/code':
          answer = {'device_code': 'D', 'user_code': 'ABC-DEF', 'verification_url': 'https://yt.example/activate', 'interval': 0, 'expires_in': 60};
        case '/o/oauth2/token' when body['grant_type'] == 'refresh_token':
          (status, answer) = refreshGone ? (400, {'error': 'invalid_grant'}) : (200, {'access_token': 'A2', 'expires_in': 3600});
        case '/o/oauth2/token':
          (status, answer) = ++polls < 2 ? (428, {'error': 'authorization_pending'}) : (200, {'access_token': 'A1', 'expires_in': 0, 'refresh_token': 'R'});
        default:
          answer = {'ok': path};
      }
      request.response.statusCode = status;
      request.response.write(page ?? jsonEncode(answer));
      await request.response.close();
    });
  }
}

void main() {
  late Directory dir;
  late _FakeYouTube youtube;

  setUp(() async {
    NativeHttp.configure();
    dir = await Directory.systemTemp.createTemp('lumtub_tv');
    youtube = _FakeYouTube();
    await youtube.start();
  });
  tearDown(() async {
    await youtube.server.close(force: true);
    await dir.delete(recursive: true);
  });

  Future<void> settled(YoutubeTvSignIn sign) async {
    for (var i = 0; i < 200 && sign.state == TvSignInState.waiting; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('signs in with the TV app\'s client, keeps the sign-in, and makes requests as the TV app', () async {
    final sign = YoutubeTvSignIn(folder: dir.path, base: youtube.base);
    final codes = <String?>[];
    sign.addListener(() => codes.add(sign.code));
    sign.signIn();
    await settled(sign);
    expect(sign.state, TvSignInState.signedIn, reason: sign.error);
    expect(codes, contains('ABC-DEF'));
    expect(sign.address, 'https://yt.example/activate');
    final device = youtube.bodies[youtube.asked.indexOf('/o/oauth2/device/code')];
    expect((device['client_id'], device['device_model']), ('42-tv.apps.googleusercontent.com', 'ytlr::'));
    expect(youtube.bodies[youtube.asked.indexOf('/o/oauth2/token')]['client_secret'], 'tvsecret');

    final answer = await sign.post('next', {'videoId': 'x'});
    expect(answer!.status, 200);
    final sent = youtube.bodies.last;
    expect((sent['videoId'], sent['context']['client']['clientName']), ('x', 'TVHTML5'));
    expect(youtube.authorizations.last, 'Bearer A2', reason: 'the first token had already run out');

    await expectLater(sign.post('account/set_setting', const {}), throwsStateError);

    final again = YoutubeTvSignIn(folder: dir.path, base: youtube.base)..load();
    expect(again.signedIn, isTrue);
    youtube.refreshGone = true;
    expect(await again.post('browse', {'browseId': 'FEhistory'}), isNull);
    expect(again.signedIn, isFalse);
    expect(again.error, isNotNull);
    expect(File('${dir.path}/youtube-tv.bin').existsSync(), isFalse);
  }, skip: !YoutubeTvSignIn.available);
}
