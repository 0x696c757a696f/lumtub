import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/app/account_controller.dart';
import 'package:lumtub/app/library_controller.dart';
import 'package:lumtub/library_store.dart';
import 'package:lumtub/secure_store.dart';
import 'package:lumtub/ui/pages/account_settings.dart';
import 'package:lumtub/youtube_web_sign_in.dart';

class _Plain implements SecretProtector {
  @override
  Uint8List protect(Uint8List data) => data;
  @override
  Uint8List unprotect(Uint8List data) => data;
}

/// The sign-ins lay out on a phone's width in every state.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('account_phone'));
  tearDown(() => dir.deleteSync(recursive: true));

  // The narrowest iPhone (SE) and Android phones, at normal and large text.
  for (final (width, scale) in [for (final w in [320.0, 360.0, 375.0, 412.0]) for (final s in [1.0, 1.3]) (w, s)]) {
    for (final (google, waiting) in [(false, false), (false, true), (true, false)]) {
      testWidgets('sign-ins (Google $google, browser waiting $waiting) fit $width wide at text ×$scale', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final account = AccountController(
          clientFile: File('${dir.path}/client.json'),
          credentials: SecureJsonFile(File('${dir.path}/account.bin'), _Plain()),
          client: MockClient((_) async => http.Response('', 404)),
          library: LibraryController(LibraryStore(File('${dir.path}/library.json'))),
          notice: (_) {},
        )
          ..state = google ? AccountState.signedIn : AccountState.signedOut
          ..name = 'A long account name for a phone';
        final web = YoutubeWebSignIn(folder: dir.path)
          ..waiting = waiting
          ..browser = 'Chrome';
        await tester.pumpWidget(MaterialApp(builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!), home: Scaffold(body: SingleChildScrollView(child: AccountSettings(account: account, webSignIn: web, note: const TextStyle())))));
        // Signed in to Google, its section is open already.
        if (!google) {
          await tester.ensureVisible(find.text('Google sign-in'));
          await tester.tap(find.text('Google sign-in'));
        }
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
