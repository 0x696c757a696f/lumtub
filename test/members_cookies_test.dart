import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/youtube_web_sign_in.dart';

void main() {
  test('writes the signed-in cookies for yt-dlp and wipes them after', () async {
    if (Platform.isMacOS && Platform.environment['CI'] == 'true') {
      markTestSkipped('the account vault needs the login keychain, which a CI Mac lacks');
      return;
    }
    if (!YoutubeWebSignIn.available) {
      expect(Platform.environment['LUMTUB_CORE_DLL'], isNull, reason: 'the core was given but not loaded');
      markTestSkipped('no native core');
      return;
    }
    final dir = await Directory.systemTemp.createTemp('lumtub_members');
    addTearDown(() => dir.delete(recursive: true));
    final source = File('${dir.path}/cookies.txt');
    await source.writeAsString('# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/\tTRUE\t1900000000\tSAPISID\tabc\n.youtube.com\tTRUE\t/\tTRUE\t1900000000\tLOGIN_INFO\txyz\n.google.com\tTRUE\t/\tTRUE\t1900000000\tSID\tother\n');
    final sign = YoutubeWebSignIn(folder: dir.path)..load();
    final out = '${dir.path}/v.cookies.txt';
    expect(await sign.writeCookies(out), isFalse);
    sign.importFile(source.path, presence: false);
    for (var i = 0; i < 100 && sign.waiting; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(sign.signedIn, isTrue, reason: '${sign.error}');
    expect(await sign.writeCookies(out), isTrue);
    final text = File(out).readAsStringSync();
    expect(text, startsWith('# Netscape HTTP Cookie File'));
    expect(text, contains('\tSAPISID\tabc'));
    expect(text, contains('\tLOGIN_INFO\txyz'));
    expect(text, isNot(contains('other')));
    sign.wipeCookies(out);
    expect(File(out).existsSync(), isFalse);
    sign.signOut();
    sign.dispose();
  });
}
