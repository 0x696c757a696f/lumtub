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
import 'package:lumtub/youtube_tv_sign_in.dart';
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
    for (final state in TvSignInState.values) {
      testWidgets('TV-code sign-in ${state.name} fits $width wide at text ×$scale', (tester) async {
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
          ..state = state == TvSignInState.signedIn ? AccountState.signedIn : AccountState.signedOut
          ..name = 'A long account name for a phone';
        // The browser sign-in waits along with the TV code, else is signed out.
        final web = YoutubeWebSignIn(folder: dir.path)
          ..waiting = state == TvSignInState.waiting
          ..browser = 'Chrome';
        final tv = YoutubeTvSignIn(folder: dir.path)
          ..state = state
          ..name = 'A long account name for a phone'
          ..code = state == TvSignInState.waiting ? 'ABCD-EFGH-IJKL' : null;
        await tester.pumpWidget(MaterialApp(builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!), home: Scaffold(body: SingleChildScrollView(child: AccountSettings(account: account, tvSignIn: tv, webSignIn: web, saveTvSamples: () async => '', note: const TextStyle())))));
        // Signed in or waiting, the section is open already.
        if (state == TvSignInState.signedOut) {
          await tester.tap(find.text('TV-code sign-in'));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.ensureVisible(find.text('Browser sign-in'));
          await tester.tap(find.text('Browser sign-in'));
        }
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
        if (state == TvSignInState.waiting) {
          // The code itself is on screen, as text a line tall.
          expect(find.text('ABCD-EFGH-IJKL'), findsOneWidget);
          expect(tester.getSize(find.text('ABCD-EFGH-IJKL')).height, lessThan(60));
        }
      });
    }
  }
}
