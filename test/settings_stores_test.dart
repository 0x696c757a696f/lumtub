import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app_directories.dart';
import 'package:lumtub/app_log.dart';
import 'package:lumtub/app_preferences.dart';
import 'package:lumtub/appearance_settings.dart';
import 'package:lumtub/player_settings.dart';

void main() {
  late Directory root;
  late AppDirectories directories;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('lumtub_settings');
    directories = AppDirectories.at(root);
    await directories.config.create(recursive: true);
    await AppLog.open(directories.logs);
  });
  tearDown(() async {
    await AppLog.current?.flush();
    AppLog.current = null;
    await root.delete(recursive: true);
  });

  Future<String> logText() async {
    await AppLog.current!.flush();
    final log = AppLog.current!.file;
    return log.existsSync() ? log.readAsString() : '';
  }

  File config(String name) => File('${directories.config.path}/$name');

  test('a truncated preferences file is kept as .broken and defaults are used', () async {
    final store = AppPreferencesStore(directories);
    await store.save(const AppPreferences(hideShorts: true, seekSeconds: 9));
    final text = await store.file.readAsString();
    await store.file.writeAsString(text.substring(0, text.length ~/ 2));
    final loaded = await store.load();
    expect(loaded.hideShorts, isFalse);
    expect(File('${store.file.path}.broken').existsSync(), isTrue);
    expect(store.file.existsSync(), isFalse);
    expect(await logText(), contains('preferences.json could not be read'));
  });

  test('a corrupt player settings file is kept as .broken and defaults are used', () async {
    final store = PlayerSettingsStore(directories);
    await store.file.writeAsString('{"volume": ');
    final loaded = await store.load();
    expect(loaded.toJson(), const PlayerSettings().toJson());
    expect(File('${store.file.path}.broken').readAsStringSync(), '{"volume": ');
    expect(await logText(), contains('player_settings.json could not be read'));
  });

  test('a corrupt appearance file is kept as .broken and defaults are used', () async {
    final store = AppearanceSettingsStore(directories);
    await store.file.writeAsString('not json at all');
    final loaded = await store.load();
    expect(loaded.toJson(), const AppearanceSettings().toJson());
    expect(File('${store.file.path}.broken').existsSync(), isTrue);
    expect(await logText(), contains('appearance.json could not be read'));
  });

  test('a missing file gives defaults without a backup or a warning', () async {
    expect((await AppPreferencesStore(directories).load()).hideShorts, isFalse);
    expect(config('preferences.json.broken').existsSync(), isFalse);
    expect(await logText(), isNot(contains('could not be read')));
  });

  test('saves round trip and leave no temporary file', () async {
    final store = AppPreferencesStore(directories);
    await store.save(const AppPreferences(hideShorts: true, seekSeconds: 9));
    final loaded = await store.load();
    expect(loaded.hideShorts, isTrue);
    expect(loaded.seekSeconds, 9);
    expect(config('preferences.json.tmp').existsSync(), isFalse);
  });

  test('overlapping saves end with the last one written whole', () async {
    final store = AppPreferencesStore(directories);
    final saves = [for (var i = 1; i <= 20; i++) store.save(AppPreferences(seekSeconds: i))];
    await Future.wait(saves);
    expect((await store.load()).seekSeconds, 20);
    expect(config('preferences.json.broken').existsSync(), isFalse);
  });
}
