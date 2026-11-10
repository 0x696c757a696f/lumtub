import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app_updater.dart';
import 'package:lumtub/zip_archive.dart';
import 'package:lumtub/native_core.dart';
import 'package:lumtub/network_proxy.dart';
import 'package:lumtub/power.dart';
import 'package:lumtub/screenshot.dart';
import 'package:lumtub/secure_store.dart';
import 'package:lumtub/user_folders.dart';

void main() {
  test('only a discharging system battery saves power on Linux', () {
    expect(Power.linuxSupplySaving('Battery\n', 'Discharging\n', ''), isTrue);
    expect(Power.linuxSupplySaving('Battery', 'Charging', ''), isFalse);
    expect(Power.linuxSupplySaving('Battery', 'Discharging', 'Device'), isFalse);
    expect(Power.linuxSupplySaving('Mains', 'Discharging', ''), isFalse);
  });

  test('a screenshot name never starts with a dot', () {
    expect(screenshotName('.hidden title', Duration.zero, DateTime(2026)), startsWith('hidden title_'));
    expect(screenshotName('...', Duration.zero, DateTime(2026)), startsWith('Lumtub_'));
  });

  test('user folders follow each system', () {
    expect(userFolder(UserFolder.videos, environment: {'USERPROFILE': r'C:\Users\me'}, windows: true), r'C:\Users\me\Videos');
    expect(userFolder(UserFolder.videos, environment: {'HOME': '/Users/me'}, windows: false, mac: true), '/Users/me/Movies');
    expect(userFolder(UserFolder.pictures, environment: {'HOME': '/nonexistent/me'}, windows: false, mac: false), '/nonexistent/me/Pictures');
    expect(userFolder(UserFolder.videos, environment: {}, windows: false, mac: false), isNull);
    const dirs = '# comment\nXDG_VIDEOS_DIR="\$HOME/视频"\nXDG_PICTURES_DIR="\$HOME/"\n';
    expect(xdgUserDir(dirs, 'VIDEOS', '/home/me'), '/home/me/视频');
    expect(xdgUserDir(dirs, 'PICTURES', '/home/me'), isNull);
    expect(xdgUserDir(dirs, 'MUSIC', '/home/me'), isNull);
  });

  group('Linux system proxy', () {
    test('the environment comes first', () async {
      final proxy = await NetworkProxy.linux(environment: {'https_proxy': 'http://10.0.0.2:3128/'}, gsettings: (_) async => fail('not asked'));
      expect(proxy.url, 'http://10.0.0.2:3128');
    });

    test('GNOME manual proxy', () async {
      final values = {
        'org.gnome.system.proxy mode': 'manual',
        'org.gnome.system.proxy.https host': '',
        'org.gnome.system.proxy.https port': '0',
        'org.gnome.system.proxy.http host': '',
        'org.gnome.system.proxy.http port': '0',
        'org.gnome.system.proxy.socks host': '127.0.0.1',
        'org.gnome.system.proxy.socks port': '1080',
      };
      final proxy = await NetworkProxy.linux(environment: const {}, gsettings: (key) async => values[key]);
      expect(proxy.url, 'socks5://127.0.0.1:1080');
    });

    test('no proxy', () async {
      final proxy = await NetworkProxy.linux(environment: const {}, gsettings: (key) async => key.endsWith('mode') ? 'none' : null);
      expect(proxy.url, isNull);
    });
  });

  test('unzips folders, keeps executables executable and stays inside', () async {
    final temp = await Directory.systemTemp.createTemp('lumtub-zip');
    addTearDown(() => temp.delete(recursive: true));
    final source = Directory('${temp.path}/source')..createSync();
    File('${source.path}/tool').writeAsStringSync('#!/bin/sh\necho hi\n');
    Directory('${source.path}/_internal/lib').createSync(recursive: true);
    File('${source.path}/_internal/lib/data.txt').writeAsStringSync('x' * 5000);
    if (!Platform.isWindows) Process.runSync('chmod', ['+x', '${source.path}/tool']);
    final archive = File('${temp.path}/a.zip');
    final made = Process.runSync('python3', ['-I', '-c', '''
import zipfile, os, sys
src, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(src):
        for d in dirs:
            z.write(os.path.join(root, d), os.path.relpath(os.path.join(root, d), src))
        for f in files:
            z.write(os.path.join(root, f), os.path.relpath(os.path.join(root, f), src))
    z.writestr('../escape.txt', 'no')
''', source.path, archive.path]);
    expect(made.exitCode, 0, reason: made.stderr.toString());
    final into = Directory('${temp.path}/out')..createSync();
    final written = await extractZip(archive, into);
    expect(written, containsAll(['tool', '_internal/lib/data.txt']));
    expect(written, isNot(contains('../escape.txt')));
    expect(File('${temp.path}/escape.txt').existsSync(), isFalse);
    expect(File('${into.path}/_internal/lib/data.txt').readAsStringSync(), 'x' * 5000);
    if (!Platform.isWindows) {
      final run = Process.runSync('${into.path}/tool', const []);
      expect(run.stdout.toString().trim(), 'hi');
    }
  }, skip: Platform.isWindows ? 'made with python3, which Windows runners may lack' : null);

  test('the vault keeps account files sealed and opens them again', () async {
    final temp = await Directory.systemTemp.createTemp('lumtub-vault');
    addTearDown(() => temp.delete(recursive: true));
    final file = SecureJsonFile(File('${temp.path}/account.bin'), VaultProtector());
    await file.write({'token': 'secret-value'});
    expect(file.file.readAsStringSync(), isNot(contains('secret-value')));
    expect(await file.read(), {'token': 'secret-value'});
    file.file.writeAsBytesSync([...file.file.readAsBytesSync().take(20), 0x30, 0x30]);
    expect(await file.read(), isNull);
  }, skip: NativeCore.instance == null ? 'needs lumtub_core' : _keychainLocked);

  test('the macOS proxy comes from scutil, HTTPS first', () async {
    const both = '<dictionary> {\n  HTTPEnable : 1\n  HTTPPort : 7890\n  HTTPProxy : 127.0.0.1\n  HTTPSEnable : 1\n  HTTPSPort : 7891\n  HTTPSProxy : 127.0.0.1\n}';
    expect((await NetworkProxy.mac(scutil: () async => both)).url, 'http://127.0.0.1:7891');
    const socks = '<dictionary> {\n  HTTPEnable : 0\n  SOCKSEnable : 1\n  SOCKSPort : 1080\n  SOCKSProxy : 10.0.0.2\n}';
    expect((await NetworkProxy.mac(scutil: () async => socks)).url, 'socks5://10.0.0.2:1080');
    expect((await NetworkProxy.mac(scutil: () async => '<dictionary> {\n  HTTPEnable : 0\n}')).url, isNull);
    expect((await NetworkProxy.mac(scutil: () async => null)).url, isNull);
  });

  test('a PAC script set on macOS or GNOME gives the proxy it names', () async {
    const pac = '<dictionary> {\n  HTTPEnable : 0\n  ProxyAutoConfigEnable : 1\n  ProxyAutoConfigURLString : http://127.0.0.1:7890/pac\n}';
    final asked = <String>[];
    Future<String?> fetch(String url) async {
      asked.add(url);
      return 'socks5h://127.0.0.1:7890';
    }
    expect((await NetworkProxy.mac(scutil: () async => pac, fetchPac: fetch)).url, 'socks5h://127.0.0.1:7890');
    final gnome = {'org.gnome.system.proxy mode': 'auto', 'org.gnome.system.proxy autoconfig-url': 'file:///etc/proxy.pac'};
    expect((await NetworkProxy.linux(environment: const {}, gsettings: (key) async => gnome[key], fetchPac: fetch)).url, 'socks5h://127.0.0.1:7890');
    expect(asked, ['http://127.0.0.1:7890/pac', 'file:///etc/proxy.pac']);
    expect((await NetworkProxy.pac('http://x/pac', fetch: (_) async => null)).url, isNull);
  });

  test('an update replaces the AppImage by rename, keeping the running file intact', () async {
    final temp = await Directory.systemTemp.createTemp('lumtub-appimage');
    addTearDown(() => temp.delete(recursive: true));
    final image = File('${temp.path}/Lumtub.AppImage')..writeAsStringSync('old');
    final open = image.openSync();
    addTearDown(open.closeSync);
    final update = File('${temp.path}/download.AppImage')..writeAsStringSync('new');
    await replaceAppImage(update, image.path);
    expect(image.readAsStringSync(), 'new');
    expect(update.existsSync(), isFalse);
    expect(File('${image.path}.update').existsSync(), isFalse);
    expect(String.fromCharCodes(open.readSync(3)), 'old');
    expect(image.statSync().modeString(), 'rwxr-xr-x');
  }, skip: Platform.isWindows ? 'Linux only' : null);
}

/// A CI Mac has no unlocked login keychain, where the vault keeps its key;
/// asking for it waits on a prompt nobody answers.
final String? _keychainLocked = Platform.isMacOS && Platform.environment['CI'] == 'true' ? 'no login keychain on CI' : null;
