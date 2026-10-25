import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app_updater.dart';

void main() {
  group('isNewerRelease', () {
    final built = DateTime.utc(2026, 10, 25, 12);

    test('a higher version is newer', () {
      expect(isNewerRelease('0.2.1-72ec49d', 'v0.2.2-1234567'), isTrue);
      expect(isNewerRelease('0.2.1-72ec49d', 'v0.3.0-1234567'), isTrue);
      expect(isNewerRelease('0.9.9-72ec49d', 'v1.0.0-1234567'), isTrue);
    });

    test('a lower version is not', () {
      expect(isNewerRelease('0.2.1-72ec49d', 'v0.2.0-1234567', published: built.add(const Duration(days: 1)), built: built), isFalse);
      expect(isNewerRelease('1.0.0-72ec49d', 'v0.10.0-1234567'), isFalse);
    });

    test('the same release is not', () {
      expect(isNewerRelease('0.2.1-72ec49d', 'v0.2.1-72ec49d', published: built.add(const Duration(hours: 1)), built: built), isFalse);
    });

    test('the same version from a later commit is', () {
      expect(isNewerRelease('0.2.1-aaaaaaa', 'v0.2.1-72ec49d', published: built.add(const Duration(hours: 1)), built: built), isTrue);
      expect(isNewerRelease('0.2.1-aaaaaaa', 'v0.2.1-72ec49d', published: built.subtract(const Duration(hours: 1)), built: built), isFalse);
      expect(isNewerRelease('0.2.1-aaaaaaa', 'v0.2.1-72ec49d'), isFalse);
    });

    test('a development build never updates', () {
      expect(isNewerRelease('开发版', 'v9.0.0-1234567'), isFalse);
    });
  });

  group('updateScript', () {
    test('runs the installer silently after Lumtub exits', () {
      final script = updateScript(package: r'C:\cache\updates\Lumtub_0.2.2_windows-x64-setup.exe', processId: 42, executable: r'C:\Lumtub\lumtub.exe', portable: false, relaunch: false);
      expect(script, contains('Wait-Process -Id 42'));
      expect(script, contains("Start-Process -FilePath 'C:\\cache\\updates\\Lumtub_0.2.2_windows-x64-setup.exe' -ArgumentList '/VERYSILENT'"));
      expect(script, isNot(contains('Expand-Archive')));
      expect(script, isNot(contains("Start-Process -FilePath 'C:\\Lumtub\\lumtub.exe'")));
    });

    test('unpacks the portable ZIP over the folder and relaunches', () {
      final script = updateScript(package: r"C:\it's\Lumtub_0.2.2_windows-x64.zip", processId: 7, executable: r'C:\Lumtub\lumtub.exe', portable: true, relaunch: true);
      expect(script, contains("Expand-Archive -LiteralPath 'C:\\it''s\\Lumtub_0.2.2_windows-x64.zip'"));
      expect(script, contains("-Destination 'C:\\Lumtub'"));
      expect(script, isNot(contains('/VERYSILENT')));
      expect(script.trimRight(), endsWith("Start-Process -FilePath 'C:\\Lumtub\\lumtub.exe'"));
    });
  });
}
