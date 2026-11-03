import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ffmpeg_component.dart';
import 'package:lumtub/native_core.dart';
import 'package:lumtub/network_proxy.dart';
import 'package:lumtub/secure_store.dart';

void main() {
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

  test('picks the static LGPL Linux ffmpeg', () {
    const names = [
      'ffmpeg-master-latest-linux64-lgpl.tar.xz',
      'ffmpeg-master-latest-linux64-lgpl-shared.tar.xz',
      'ffmpeg-n7.1-latest-linux64-lgpl-7.1.tar.xz',
      'ffmpeg-n8.0-latest-linux64-lgpl-8.0.tar.xz',
      'ffmpeg-n8.0-latest-linux64-gpl-8.0.tar.xz',
      'ffmpeg-n8.0-latest-linuxarm64-lgpl-8.0.tar.xz',
    ];
    expect(linuxFfmpegAssetName(names, arm64: false), 'ffmpeg-n8.0-latest-linux64-lgpl-8.0.tar.xz');
    expect(linuxFfmpegAssetName(names, arm64: true), 'ffmpeg-n8.0-latest-linuxarm64-lgpl-8.0.tar.xz');
    expect(linuxFfmpegAssetName(['ffmpeg-master-latest-linuxarm64-lgpl.tar.xz'], arm64: true), 'ffmpeg-master-latest-linuxarm64-lgpl.tar.xz');
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
  }, skip: NativeCore.instance == null ? 'needs lumtub_core' : null);
}
