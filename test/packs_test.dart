import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/app_directories.dart';
import 'package:lumtub/packs.dart';
import 'package:lumtub/tool_manager.dart';
import 'package:lumtub/ui/pages/settings_subpages.dart';
import 'package:lumtub/ui/theme.dart';

void main() {
  late Directory temp;
  late Map<String, List<int>> served;
  late List<String?> ranges;
  late PackManager packs;

  Pack pack(String version, Map<String, List<int>> files, {List<String> platforms = const [], String minApp = ''}) => Pack(
        id: 'shaders-upscale',
        version: version,
        kind: PackKind.shader,
        titles: const {'en': 'Upscaling shaders', 'zh-Hans': '超分着色器'},
        license: 'MIT',
        minApp: minApp,
        platforms: platforms,
        files: [
          for (final MapEntry(:key, :value) in files.entries)
            PackFile(path: key, url: 'https://github.com/0x696c757a696f/lumtub/releases/download/packs/${key.split('/').last}', sha256: '${sha256.convert(value)}', size: value.length),
        ],
      );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lumtub-packs');
    served = {};
    ranges = [];
    final client = MockClient((request) async {
      final name = request.url.pathSegments.last;
      final body = served[name];
      if (body == null) return http.Response('Not Found', 404);
      final range = request.headers['Range'];
      ranges.add(range);
      if (range != null) {
        final from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        return http.Response.bytes(body.sublist(from), 206);
      }
      return http.Response.bytes(body, 200);
    });
    final tools = ToolManager(AppDirectories.at(temp), (a, b) {}, client: client);
    packs = PackManager(Directory('${temp.path}${Platform.pathSeparator}packs'), tools);
  });
  tearDown(() async {
    packs.dispose();
    await temp.delete(recursive: true);
  });

  test('a pack installs, is found again and is removed', () async {
    final shader = utf8.encode('//!HOOK MAIN\n');
    final notes = utf8.encode('notes');
    served = {'FSR.glsl': shader, 'README.txt': notes};
    packs.catalogForTesting = [pack('1.0.0', {'glsl/FSR.glsl': shader, 'README.txt': notes})];
    expect(packs.offered.map((p) => p.id), ['shaders-upscale']);
    final installed = await packs.install('shaders-upscale');
    expect(await installed.file('glsl/FSR.glsl').readAsBytes(), shader);
    expect(packs.offered, isEmpty);
    expect(packs.installedSize, shader.length + notes.length);

    final again = PackManager(packs.root, packs.tools);
    addTearDown(again.dispose);
    await again.load();
    expect(again.installed.single.pack.version, '1.0.0');
    expect(again.installed.single.pack.title, 'Upscaling shaders');

    await packs.remove('shaders-upscale');
    expect(packs.installed, isEmpty);
    expect(Directory('${packs.root.path}${Platform.pathSeparator}shaders-upscale').existsSync(), isFalse);
  });

  test('a newer version replaces the old one', () async {
    served = {'FSR.glsl': utf8.encode('old')};
    packs.catalogForTesting = [pack('1.0.0', {'FSR.glsl': utf8.encode('old')})];
    await packs.install('shaders-upscale');
    served = {'FSR.glsl': utf8.encode('new one')};
    packs.catalogForTesting = [pack('1.1.0', {'FSR.glsl': utf8.encode('new one')})];
    expect(packs.offered.single.version, '1.1.0');
    final installed = await packs.install('shaders-upscale');
    expect(installed.pack.version, '1.1.0');
    final folders = Directory('${packs.root.path}${Platform.pathSeparator}shaders-upscale').listSync().map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last);
    expect(folders, ['1.1.0']);
  });

  test('a file that does not match the catalog is not installed', () async {
    served = {'FSR.glsl': utf8.encode('tampered')};
    packs.catalogForTesting = [pack('1.0.0', {'FSR.glsl': utf8.encode('original')})];
    await expectLater(packs.install('shaders-upscale'), throwsA(anything));
    expect(packs.installed, isEmpty);
    await packs.load();
    expect(packs.installed, isEmpty);
    expect(packs.error, isNotNull);
  });

  test('a download stopped halfway goes on from where it stopped', () async {
    final body = List<int>.generate(5000, (i) => i % 251);
    served = {'model.bin': body};
    packs.catalogForTesting = [pack('1.0.0', {'model.bin': body})];
    final staging = Directory('${packs.root.path}/shaders-upscale/1.0.0.new');
    await staging.create(recursive: true);
    await File('${staging.path}/model.bin.part').writeAsBytes(body.sublist(0, 1200));
    final installed = await packs.install('shaders-upscale');
    expect(ranges, ['bytes=1200-']);
    expect(await installed.file('model.bin').readAsBytes(), body);
  });

  test('a pack for another build or a newer app is not offered', () {
    packs.catalogForTesting = [pack('1.0.0', {'a': [1]}, minApp: '999.0.0')];
    // Builds made outside CI have no version and take every pack.
    expect(packs.offered.length, 1);
    expect(Pack.fromJson(pack('1.0.0', {'a': [1]}).toJson())!.toJson(), pack('1.0.0', {'a': [1]}).toJson());
  });

  test('a missing catalog says none are published', () async {
    await packs.refresh();
    expect(packs.error, contains('No data packs are published yet'));
    expect(packs.refreshing, isFalse);
  });

  test('an installed pack whose entry was changed to leave its folder is ignored', () async {
    final folder = Directory('${packs.root.path}/evil/1.0.0');
    await folder.create(recursive: true);
    final entry = pack('1.0.0', {'../../outside': [1]}).toJson()..['id'] = 'evil';
    await File('${folder.path}/pack.json').writeAsString(jsonEncode(entry));
    await packs.load();
    expect(packs.installed, isEmpty);
  }, skip: Platform.environment['LUMTUB_CORE_DLL'] == null ? 'the core checks entries' : false);

  testWidgets('the settings list installed and offered packs and downloads one', (tester) async {
    final shader = utf8.encode('//!HOOK MAIN\n');
    served = {'FSR.glsl': shader};
    final other = Pack(
      id: 'asr-whisper-small',
      version: '1',
      kind: PackKind.model,
      titles: const {'en': 'Whisper small'},
      license: 'MIT',
      files: [PackFile(path: 'm.bin', url: 'https://huggingface.co/x/m.bin', sha256: 'a' * 64, size: 3 << 20)],
    );
    packs.catalogForTesting = [pack('1.0.0', {'FSR.glsl': shader}), other];
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Colors.red, Brightness.light),
      home: Scaffold(body: ListView(children: [PacksSection(packs)])),
    ));
    expect(find.text('Upscaling shaders'), findsOneWidget);
    expect(find.text('Whisper small'), findsOneWidget);
    expect(find.textContaining('3.0 MB'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Download').first);
    await tester.pumpAndSettle();
    expect(find.text('Download Upscaling shaders?'), findsOneWidget);
    expect(find.textContaining('github.com'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => packs.install('shaders-upscale'));
    await tester.pumpAndSettle();
    expect(packs.installed.single.pack.id, 'shaders-upscale');
    expect(find.byTooltip('Delete'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
