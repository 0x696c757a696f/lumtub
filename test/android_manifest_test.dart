import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('Android keeps settings, history and sign-ins off its cloud backups', () {
    expect(manifest, contains('android:allowBackup="false"'));
  });

  test('the Android app is never shipped debuggable', () {
    expect(manifest, isNot(contains('android:debuggable="true"')));
  });
}
