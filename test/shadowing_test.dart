import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/shadowing.dart';
import 'package:lumtub/shortcut_bindings.dart';
import 'package:lumtub/subtitle_cues.dart';

class FakeMicrophone implements Microphone {
  FakeMicrophone({this.allow = true, this.fails = false});
  final bool allow;
  final bool fails;
  bool started = false;
  bool released = false;

  /// What the next stop writes, in bytes after the header.
  int heard = 0;

  @override
  Future<bool> allowed() async => allow;

  @override
  Future<void> start() async {
    if (fails) throw StateError('no input device');
    started = true;
  }

  @override
  Future<double?> stopInto(File file) async {
    started = false;
    if (heard == 0) return null;
    await file.writeAsBytes(Uint8List(44 + heard));
    return heard / 88200;
  }

  @override
  Future<void> release() async => released = true;
}

void main() {
  late Directory folder;
  setUp(() => folder = Directory.systemTemp.createTempSync('shadowing'));
  tearDown(() {
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  });

  const first = (start: Duration(seconds: 3), end: Duration(seconds: 5), text: 'Hello');
  const second = (start: Duration(seconds: 6), end: Duration(seconds: 8), text: 'Bye');

  test('a take is what the microphone heard, kept as a file of its line', () async {
    final mic = FakeMicrophone();
    final shadowing = Shadowing(folder, microphone: mic);
    await shadowing.start();
    expect(shadowing.recording, isTrue);
    expect(mic.started, isTrue);
    mic.heard = 88200;
    final take = await shadowing.stop(first);
    expect(mic.started, isFalse);
    expect(shadowing.recording, isFalse);
    expect(take, isNotNull);
    expect(take!.file.lengthSync(), 44 + 88200);
    expect(take.length, const Duration(seconds: 1));
    expect(take.line, first);
    expect(take.part, {'seconds': 0.0, 'take': take.file.path});
    expect(shadowing.last, same(take));
    expect(shadowing.takes.keys, [first.start]);
    await shadowing.dispose();
    expect(mic.released, isTrue);
    expect(take.file.existsSync(), isFalse);
    expect(shadowing.takes, isEmpty);
  });

  test('a take too short to hear is not kept, nor replaces a good one', () async {
    final mic = FakeMicrophone();
    final shadowing = Shadowing(folder, microphone: mic);
    await shadowing.start();
    mic.heard = 100;
    expect(await shadowing.stop(first), isNull);
    expect(shadowing.last, isNull);
    expect(folder.listSync(), isEmpty);
    await shadowing.start();
    mic.heard = 20000;
    final good = await shadowing.stop(first);
    await shadowing.start();
    mic.heard = 100;
    expect(await shadowing.stop(first), isNull);
    expect(good!.file.lengthSync(), 44 + 20000);
    expect(shadowing.last, same(good));
  });

  test('a denied or missing microphone says why', () async {
    await expectLater(Shadowing(folder, microphone: FakeMicrophone(allow: false)).start(), throwsA(isA<ShadowException>().having((e) => e.denied, 'denied', isTrue)));
    final failing = Shadowing(folder, microphone: FakeMicrophone(fails: true));
    await expectLater(
      failing.start(),
      throwsA(isA<ShadowException>().having((e) => e.denied, 'denied', isFalse).having((e) => e.detail, 'detail', contains('no input device'))),
    );
    expect(failing.recording, isFalse);
  });

  test('each line keeps its newest take, and its sound from the video', () async {
    final mic = FakeMicrophone();
    final shadowing = Shadowing(folder, microphone: mic);
    await shadowing.start();
    mic.heard = 30000;
    await shadowing.stop(second);
    await shadowing.start();
    mic.heard = 20000;
    final firstTake = await shadowing.stop(first);
    firstTake!.original = shadowing.fileFor(first, 'line', 'wav');
    firstTake.originalSeconds = 2.4;
    await shadowing.start();
    mic.heard = 40000;
    final again = await shadowing.stop(first);
    expect(again!.file.path, firstTake.file.path);
    expect(again.file.lengthSync(), 44 + 40000);
    expect(again.original?.path, firstTake.original!.path);
    expect(again.part, {'original': firstTake.original!.path, 'seconds': 2.4, 'take': again.file.path});
    expect([for (final take in shadowing.inOrder) take.line.text], ['Hello', 'Bye']);
    expect(shadowing.last, same(again));
  });

  test('E records, and no other player action has it', () {
    final keys = shortcutKeys(const {});
    const e = KeyCombo(LogicalKeyboardKey.keyE);
    expect(keys[PlayerAction.shadow], [e]);
    expect([for (final MapEntry(:key, :value) in keys.entries) if (!key.page && value.contains(e)) key], [PlayerAction.shadow]);
  });

  group('CSV of the subtitle list', () {
    test('times, both lines, and quoting where needed', () {
      final rows = <PairedCue>[
        (cue: (start: const Duration(milliseconds: 1500), end: const Duration(seconds: 3), text: 'Hello, world'), second: '你好，世界'),
        (cue: (start: const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 4), end: const Duration(hours: 1, minutes: 2, seconds: 5), text: 'She said "hi"\nthen left'), second: null),
      ];
      final csv = pairedCuesCsv(rows);
      expect(csv.startsWith('﻿start,end,text,translation\r\n'), isTrue);
      final lines = csv.substring(1).split('\r\n');
      expect(lines[1], '0:00:01.500,0:00:03.000,"Hello, world",你好，世界');
      expect(lines[2], '1:02:03.004,1:02:05.000,"She said ""hi""\nthen left",');
      expect(lines.last, '');
      expect(lines, hasLength(4));
    });
  });
}
