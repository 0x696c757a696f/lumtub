import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app_updater.dart';

void main() {
  test('an update swaps the app bundle for the one in the disk image', () async {
    final temp = await Directory.systemTemp.createTemp('lumtub-mac-update');
    addTearDown(() => temp.delete(recursive: true));
    Directory('${temp.path}/Applications/Lumtub.app/Contents/MacOS').createSync(recursive: true);
    final app = '${temp.path}/Applications/Lumtub.app';
    File('$app/Contents/MacOS/Lumtub').writeAsStringSync('old');
    final running = File('$app/Contents/MacOS/Lumtub').openSync();
    addTearDown(running.closeSync);
    Directory('${temp.path}/image/Lumtub.app/Contents/MacOS').createSync(recursive: true);
    File('${temp.path}/image/Lumtub.app/Contents/MacOS/Lumtub').writeAsStringSync('new');
    Link('${temp.path}/image/Applications').createSync('/Applications');
    final dmg = File('${temp.path}/update.dmg');
    final made = await Process.run('/usr/bin/hdiutil', ['create', '-quiet', '-volname', 'Lumtub', '-srcfolder', '${temp.path}/image', '-format', 'UDZO', dmg.path]);
    expect(made.exitCode, 0, reason: '${made.stderr}');

    expect(macBundleWritable(app), isTrue);
    await replaceMacApp(dmg, app);
    expect(File('$app/Contents/MacOS/Lumtub').readAsStringSync(), 'new');
    expect(Directory('$app.old').existsSync(), isFalse);
    expect(Directory('$app.update').existsSync(), isFalse);
    expect(dmg.existsSync(), isFalse);
    expect(String.fromCharCodes(running.readSync(3)), 'old');
  }, skip: Platform.isMacOS ? null : 'macOS only');
}
