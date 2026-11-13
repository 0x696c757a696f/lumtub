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

  for (final width in [360.0, 412.0]) {
    for (final state in TvSignInState.values) {
      testWidgets('TV-code sign-in ${state.name} fits $width wide', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final account = AccountController(
          clientFile: File('${dir.path}/client.json'),
          credentials: SecureJsonFile(File('${dir.path}/account.bin'), _Plain()),
          client: MockClient((_) async => http.Response('', 404)),
          library: LibraryController(LibraryStore(File('${dir.path}/library.json'))),
          notice: (_) {},
        );
        final tv = YoutubeTvSignIn(folder: dir.path)
          ..state = state
          ..name = 'A long account name for a phone'
          ..code = state == TvSignInState.waiting ? 'ABCD-EFGH-IJKL' : null;
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: AccountSettings(account: account, tvSignIn: tv, saveTvSamples: () async => '', note: const TextStyle())))));
        // Signed in or waiting, the section is open already.
        if (state == TvSignInState.signedOut) await tester.tap(find.text('TV-code sign-in'));
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
