import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/secure_store.dart';
import 'package:lumtub/youtube_tv_sign_in.dart';

class _XorProtector implements SecretProtector {
  @override
  Uint8List protect(Uint8List data) => Uint8List.fromList([for (final b in data) b ^ 0x5a]);
  @override
  Uint8List unprotect(Uint8List data) => protect(data);
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('lumtub_tv'));
  tearDown(() => dir.delete(recursive: true));

  SecureJsonFile file() => SecureJsonFile(File('${dir.path}/youtube-tv.bin'), _XorProtector());

  test('shows the code, waits for it to be typed in, then keeps and refreshes the sign-in', () async {
    var polls = 0;
    var refreshGone = false;
    final grants = <String>[];
    final client = MockClient((request) async {
      final body = Uri.splitQueryString(request.body);
      if (request.url.path.endsWith('/device/code')) {
        expect(body['client_id'], YoutubeTvSignIn.clientId);
        return http.Response(jsonEncode({'device_code': 'D', 'user_code': 'ABC-DEF-GHI', 'verification_url': 'https://www.google.com/device', 'interval': 0, 'expires_in': 60}), 200);
      }
      grants.add(body['grant_type']!);
      if (body['grant_type'] == 'refresh_token') {
        return refreshGone ? http.Response('{"error":"invalid_grant"}', 400) : http.Response('{"access_token":"A2","expires_in":3600}', 200);
      }
      return ++polls < 3 ? http.Response('{"error":"authorization_pending"}', 428) : http.Response('{"access_token":"A1","expires_in":0,"refresh_token":"R"}', 200);
    });
    final sign = YoutubeTvSignIn(credentials: file(), client: client, pollFloor: Duration.zero);
    final codes = <String?>[];
    sign.addListener(() => codes.add(sign.code));
    await sign.signIn();
    expect(codes, contains('ABC-DEF-GHI'));
    expect((sign.signedIn, sign.address, polls), (true, 'https://www.google.com/device', 3));
    expect(await sign.accessToken(), 'A2');

    final again = YoutubeTvSignIn(credentials: file(), client: client);
    await again.load();
    expect(again.signedIn, isTrue);
    refreshGone = true;
    expect(await again.accessToken(), isNull);
    expect(again.signedIn, isFalse);
    expect(again.error, isNotNull);
    expect(await File('${dir.path}/youtube-tv.bin').exists(), isFalse);
  });

  test('a denied code ends the wait with why', () async {
    final sign = YoutubeTvSignIn(
      credentials: file(),
      client: MockClient((request) async => request.url.path.endsWith('/device/code')
          ? http.Response('{"device_code":"D","user_code":"X","interval":0}', 200)
          : http.Response('{"error":"access_denied"}', 403)),
      pollFloor: Duration.zero,
    );
    await sign.signIn();
    expect(sign.state, TvSignInState.signedOut);
    expect(sign.error, isNotNull);
  });
}
