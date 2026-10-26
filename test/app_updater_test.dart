import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
}
