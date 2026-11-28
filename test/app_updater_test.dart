import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/app_updater.dart';
import 'package:lumtub/native_core.dart';

void main() {
  final skip = NativeCore.instance == null ? 'needs lumtub_core (LUMTUB_CORE_DLL)' : null;
  final built = DateTime.utc(2026, 10, 25, 12);
  Map<String, dynamic> release(String tag, DateTime published) => {
        'tag_name': tag,
        'html_url': 'https://github.com/0x696c757a696f/lumtub/releases/tag/$tag',
        'published_at': published.toIso8601String(),
        'assets': [
          {'name': 'Lumtub_${tag.substring(1)}_windows-x64-setup.exe', 'digest': 'sha256:00'},
          {'name': 'Lumtub_${tag.substring(1)}_windows-x64-setup.exe.sig'},
          {'name': 'Lumtub_${tag.substring(1)}_windows-x64.zip'},
          {'name': 'Lumtub_${tag.substring(1)}_windows-x64-v3-setup.exe'},
        ],
      };

  test('offers a newer release with the package file', () {
    final offer = offerOf(release('v0.2.2-1234567', built), current: '0.2.1-72ec49d', built: built, package: 'windows-x64')!;
    expect(offer.version, '0.2.2-1234567');
    expect(offer.page, endsWith('/v0.2.2-1234567'));
    expect(offer.asset!['name'], 'Lumtub_0.2.2-1234567_windows-x64-setup.exe');
    expect(offer.asset!['digest'], 'sha256:00');
    expect(offer.signature!['name'], 'Lumtub_0.2.2-1234567_windows-x64-setup.exe.sig');
    expect(offerOf(release('v0.2.2-1234567', built), current: '0.2.1-72ec49d', built: built, package: 'windows-x64', portable: true)!.asset!['name'], 'Lumtub_0.2.2-1234567_windows-x64.zip');
  }, skip: skip);

  test('asks for the release again with its ETag and keeps the answer on 304', () async {
    final sent = <String?>[];
    final client = MockClient((request) async {
      sent.add(request.headers['If-None-Match']);
      if (sent.length == 1) return http.Response(jsonEncode(release('v9.9.9-1234567', built)), 200, headers: {'etag': 'W/"abc"'});
      return http.Response('', 304);
    });
    final folder = Directory.systemTemp.createTempSync('updater');
    addTearDown(() => folder.deleteSync(recursive: true));
    final updater = AppUpdater(client: client, directory: folder, download: (asset, into, onProgress) async => throw UnimplementedError());
    await updater.check();
    final first = updater.available;
    expect(updater.error, isNull);
    await updater.check();
    expect(sent, [null, 'W/"abc"']);
    expect(updater.error, isNull);
    expect(updater.available?.version, first?.version);
  });

  test('reads the release from github.com when the API limits this address', () async {
    final asked = <String>[];
    final api = MockClient((request) async {
      asked.add(request.url.toString());
      if (request.url.host == 'api.github.com') return http.Response('{"message":"API rate limit exceeded"}', 403);
      return http.Response('<feed><entry><link rel="alternate" href="https://github.com/0x696c757a696f/lumtub/releases/tag/v9.9.9-1234567"/><updated>2026-11-19T09:00:00Z</updated></entry></feed>', 200);
    });
    MockClient pages(int status) => MockClient((request) async {
          asked.add(request.url.toString());
          return http.Response('', status, headers: {if (status == 302) 'location': 'https://github.com/0x696c757a696f/lumtub/releases/tag/v9.9.9-1234567'});
        });
    final folder = Directory.systemTemp.createTempSync('updater');
    addTearDown(() => folder.deleteSync(recursive: true));
    var updater = AppUpdater(client: api, directory: folder, download: (asset, into, onProgress) async => throw UnimplementedError(), plainClient: () => pages(302));
    await updater.check();
    expect(updater.error, isNull);
    expect(asked, contains('https://github.com/0x696c757a696f/lumtub/releases/latest'));
    expect(asked, contains('https://github.com/0x696c757a696f/lumtub/releases.atom'));

    updater = AppUpdater(client: api, directory: folder, download: (asset, into, onProgress) async => throw UnimplementedError(), plainClient: () => pages(500));
    await updater.check();
    expect(updater.error, contains('GitHub'));
    expect(updater.error, contains('403'));
    expect(updater.error, isNot(contains('YouTube')));
  });

  test('names GitHub when it answers something else', () async {
    final folder = Directory.systemTemp.createTempSync('updater');
    addTearDown(() => folder.deleteSync(recursive: true));
    final updater = AppUpdater(client: MockClient((_) async => http.Response('', 502)), directory: folder, download: (asset, into, onProgress) async => throw UnimplementedError());
    await updater.check();
    expect(updater.error, contains('GitHub'));
    expect(updater.error, contains('502'));
  });

  test('reads the tag, time and package names of a release from its pages', () {
    expect(releaseTagOfRedirect('0x696c757a696f/lumtub', 'https://github.com/0x696c757a696f/lumtub/releases/tag/v0.2.53-588804e'), 'v0.2.53-588804e');
    expect(releaseTagOfRedirect('0x696c757a696f/lumtub', 'https://github.com/0x696c757a696f/lumtub/releases'), isNull);
    expect(releaseTagOfRedirect('0x696c757a696f/lumtub', 'https://example.com/0x696c757a696f/lumtub/releases/tag/v1'), isNull);
    expect(releaseTagOfRedirect('0x696c757a696f/lumtub', null), isNull);
    const feed = '<feed><entry><link rel="alternate" type="text/html" href="https://github.com/0x696c757a696f/lumtub/releases/tag/v0.2.53-aaaaaaa"/><updated>2026-11-18T01:00:00Z</updated></entry><entry><link rel="alternate" type="text/html" href="https://github.com/0x696c757a696f/lumtub/releases/tag/v0.2.53-588804e"/><updated>2026-11-19T09:00:00Z</updated></entry></feed>';
    expect(publishedInFeed(feed, 'v0.2.53-588804e'), '2026-11-19T09:00:00Z');
    expect(publishedInFeed(feed, 'v0.2.52-1111111'), isNull);
    String name(String package, {bool portable = false}) => ((releaseOfTag('v0.2.53-588804e', package: package, portable: portable)['assets'] as List).first as Map)['name'] as String;
    expect(name('linux-x64'), 'Lumtub_0.2.53-588804e_linux-x64.AppImage');
    expect(name('macos-arm64'), 'Lumtub_0.2.53-588804e_macos-arm64.dmg');
    expect(name('android-arm64-v8a'), 'Lumtub_0.2.53-588804e_android-arm64-v8a.apk');
    expect(name('windows-x64'), 'Lumtub_0.2.53-588804e_windows-x64-setup.exe');
    expect(name('windows-x64', portable: true), 'Lumtub_0.2.53-588804e_windows-x64.zip');
    final release = releaseOfTag('v0.2.53-588804e', package: 'linux-x64', portable: false, published: '2026-11-19T09:00:00Z');
    expect(release['published_at'], '2026-11-19T09:00:00Z');
    expect(((release['assets'] as List)[1] as Map)['browser_download_url'], 'https://github.com/0x696c757a696f/lumtub/releases/download/v0.2.53-588804e/Lumtub_0.2.53-588804e_linux-x64.AppImage.sig');
    expect(releaseOfTag('v1.0.0-1234567', package: '', portable: false)['assets'], isEmpty);
  });

  test('does not offer the running or an older release', () {
    final later = built.add(const Duration(hours: 1));
    expect(offerOf(release('v0.2.1-72ec49d', later), current: '0.2.1-72ec49d', built: built), isNull);
    expect(offerOf(release('v0.2.0-1234567', later), current: '0.2.1-72ec49d', built: built), isNull);
    expect(offerOf(release('v0.2.1-1234567', later), current: '0.2.1-aaaaaaa', built: built)?.version, '0.2.1-1234567');
    expect(offerOf(release('v9.0.0-1234567', later), current: '开发版', built: built), isNull);
  }, skip: skip);

  test('writes the install script', () {
    final script = updateScript(package: r'C:\cache\updates\Lumtub_0.2.2_windows-x64-setup.exe', processId: 42, executable: r'C:\Lumtub\lumtub.exe', portable: false, relaunch: true)!;
    expect(script, contains('Wait-Process -Id 42'));
    expect(script, contains('/VERYSILENT'));
    expect(script, endsWith(r"Start-Process -FilePath 'C:\Lumtub\lumtub.exe'"));
  }, skip: skip);

  test('rejects a package whose signature does not hold', () {
    final folder = Directory.systemTemp.createTempSync('lumtub-update');
    addTearDown(() => folder.deleteSync(recursive: true));
    final file = File('${folder.path}/Lumtub_0.2.4-abcdef0_windows-x64-setup.exe')..writeAsStringSync('package');
    final sig = File('${file.path}.sig')..writeAsBytesSync(List.filled(3373, 1));
    expect(verifyUpdate(file: file.path, name: 'Lumtub_0.2.4-abcdef0_windows-x64-setup.exe', signature: sig.path), "The update's signature does not match");
    expect(verifyUpdate(file: file.path, name: 'x', signature: '${folder.path}/missing.sig'), startsWith('Could not read the signature'));
  }, skip: skip);

  test('a check finishing after dispose notifies nobody', () async {
    final client = MockClient((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      return http.Response(jsonEncode(release('v9.9.9-1234567', built)), 200);
    });
    final folder = Directory.systemTemp.createTempSync('updater');
    addTearDown(() => folder.deleteSync(recursive: true));
    final updater = AppUpdater(client: client, directory: folder, download: (asset, into, onProgress) async => throw UnimplementedError());
    final check = updater.check();
    updater.dispose();
    await check;
  });

  group('a newer release before the update is installed', () {
    // The package must carry the version it is checked as, as the core's
    // check_package demands.
    String? verifier({required String file, required String name, required String signature, String? version, String? current}) =>
        version != null && name.contains('_${version}_') ? null : 'The update\'s package is not the version offered';
    Map<String, dynamic> releaseOf(String version) => {
          'tag_name': 'v$version',
          'html_url': 'https://github.com/0x696c757a696f/lumtub/releases/tag/v$version',
          'published_at': built.toIso8601String(),
          'assets': [
            {'name': 'Lumtub_${version}_linux-x64.AppImage', 'digest': 'sha256:00'},
            {'name': 'Lumtub_${version}_linux-x64.AppImage.sig', 'browser_download_url': 'https://github.com/x/Lumtub_${version}_linux-x64.AppImage.sig'},
          ],
        };
    late String latest;
    late Directory folder;
    final client = MockClient((request) async {
      if (request.url.host == 'api.github.com') return http.Response(jsonEncode(releaseOf(latest)), 200);
      return http.Response('signature', 200);
    });
    setUp(() {
      AppUpdater.debugCanInstall = true;
      folder = Directory('${Directory.systemTemp.createTempSync('updater').path}/updates')..createSync();
    });
    tearDown(() {
      AppUpdater.debugCanInstall = null;
      folder.parent.deleteSync(recursive: true);
    });
    Future<File> fetch(Map<String, dynamic> asset, Directory into, void Function(int, int?) progress) async =>
        File('${into.path}/${asset['name']}')..writeAsStringSync('package');
    AppUpdater updater({Future<File> Function(Map<String, dynamic>, Directory, void Function(int, int?))? download}) =>
        AppUpdater(client: client, directory: folder, download: download ?? fetch, verifier: verifier, current: '0.2.1-72ec49d', package: 'linux-x64');

    test('replaces the downloaded package and tells again', () async {
      final u = updater();
      latest = '0.2.2-1111111';
      await u.check(download: true);
      expect(u.readyVersion, '0.2.2-1111111');
      expect(u.noticeKey, '0.2.2-1111111 ready');
      await u.dismissNotice();
      expect(u.showsNotice, isFalse);
      latest = '0.2.3-2222222';
      await u.check(download: true);
      expect(u.readyVersion, '0.2.3-2222222');
      expect(u.ready!.path, endsWith('Lumtub_0.2.3-2222222_linux-x64.AppImage'));
      expect(u.rejected, isNull);
      expect(folder.listSync().map((f) => f.path.split(Platform.pathSeparator).last).toSet(), {'Lumtub_0.2.3-2222222_linux-x64.AppImage', 'Lumtub_0.2.3-2222222_linux-x64.AppImage.sig'});
      expect(u.showsNotice, isTrue);
    });

    test('a release found during a download is downloaded right after it', () async {
      final gate = Completer<void>();
      var calls = 0;
      final u = updater(download: (asset, into, progress) async {
        if (calls++ == 0) await gate.future;
        return fetch(asset, into, progress);
      });
      latest = '0.2.2-1111111';
      final first = u.check(download: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(u.downloading, '0.2.2-1111111');
      latest = '0.2.3-2222222';
      await u.check(download: true);
      // Meanwhile the older one is what installs: it is checked as its own version.
      gate.complete();
      await first;
      expect(u.readyVersion, '0.2.3-2222222');
      expect(File('${folder.path}/Lumtub_0.2.2-1111111_linux-x64.AppImage').existsSync(), isFalse);
      expect(u.rejected, isNull);
    });

    test('a package not installed yet is kept across starts and used again', () async {
      File('${folder.path}/Lumtub_0.2.2-1111111_linux-x64.AppImage').writeAsStringSync('package');
      File('${folder.path}/Lumtub_0.2.2-1111111_linux-x64.AppImage.sig').writeAsStringSync('signature');
      File('${folder.path}/Lumtub_0.2.1-72ec49d_linux-x64.AppImage').writeAsStringSync('installed');
      File('${folder.path}/update.log').writeAsStringSync('updated');
      latest = '0.2.2-1111111';
      final u = updater();
      u.start(download: () => false);
      addTearDown(u.dispose);
      for (var i = 0; i < 100 && u.readyVersion == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(u.readyVersion, '0.2.2-1111111');
      expect(File('${folder.path}/Lumtub_0.2.1-72ec49d_linux-x64.AppImage').existsSync(), isFalse);
      expect(File('${folder.path}/update.log').existsSync(), isFalse);
    });

    test('a closed notice stays closed after a restart', () async {
      latest = '0.2.2-1111111';
      final u = updater();
      await u.check();
      expect(u.noticeKey, '0.2.2-1111111 available');
      await u.dismissNotice();
      final again = updater();
      again.start(download: () => false);
      addTearDown(again.dispose);
      for (var i = 0; i < 100 && again.available == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(again.showsNotice, isFalse);
    });
  }, skip: skip);

  test('only plain package names and this project\'s pages are used', () {
    expect(AppUpdater.safeName('Lumtub_0.2.3-abc1234_windows-x64-setup.exe'), isTrue);
    expect(AppUpdater.safeName('Lumtub_../../evil.exe'), isFalse);
    expect(AppUpdater.safeName(r'Lumtub_x\evil.exe'), isFalse);
    expect(AppUpdater.safeName('evil.exe'), isFalse);
    expect(AppUpdater.safeName(null), isFalse);
    const releases = 'https://github.com/0x696c757a696f/lumtub/releases';
    expect(AppUpdater.releasePage('$releases/tag/v0.2.3-abc1234'), '$releases/tag/v0.2.3-abc1234');
    expect(AppUpdater.releasePage('https://evil.example/0x696c757a696f/lumtub/releases'), releases);
    expect(AppUpdater.releasePage('https://github.com/someone/else/releases'), releases);
    expect(AppUpdater.releasePage('http://github.com/0x696c757a696f/lumtub/releases'), releases);
    expect(AppUpdater.releasePage(''), releases);
  });

  test('a link in place of a kept package is not used', () async {
    if (Platform.isWindows) return;
    final root = Directory.systemTemp.createTempSync('updater');
    addTearDown(() => root.deleteSync(recursive: true));
    final folder = Directory('${root.path}/updates')..createSync();
    final elsewhere = File('${root.path}/other')..writeAsStringSync('package');
    Link('${folder.path}/Lumtub_0.2.2-1111111_linux-x64.AppImage').createSync(elsewhere.path);
    File('${folder.path}/Lumtub_0.2.2-1111111_linux-x64.AppImage.sig').writeAsStringSync('signature');
    final client = MockClient((request) async => http.Response(jsonEncode({
          'tag_name': 'v0.2.2-1111111',
          'html_url': 'https://github.com/0x696c757a696f/lumtub/releases/tag/v0.2.2-1111111',
          'published_at': built.toIso8601String(),
          'assets': [
            {'name': 'Lumtub_0.2.2-1111111_linux-x64.AppImage', 'digest': 'sha256:00'},
            {'name': 'Lumtub_0.2.2-1111111_linux-x64.AppImage.sig'},
          ],
        }), 200));
    String? accept({required String file, required String name, required String signature, String? version, String? current}) => null;
    final u = AppUpdater(client: client, directory: folder, download: (asset, into, progress) async => throw UnimplementedError(), verifier: accept, current: '0.2.1-72ec49d', package: 'linux-x64');
    await u.check();
    expect(u.available, isNotNull);
    expect(u.ready, isNull);
  }, skip: skip);
}
