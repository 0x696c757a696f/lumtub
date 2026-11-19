import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/shadowing.dart';
import 'package:lumtub/shortcut_bindings.dart';
import 'package:lumtub/subtitle_cues.dart';

class FakeMicrophone implements Microphone {
  FakeMicrophone({this.allow = true, this.fails = false});
  final bool allow;
  final bool fails;
  StreamController<Uint8List>? controller;
  int? rate;
  bool stopped = false;
  bool disposed = false;

  @override
  Future<bool> allowed() async => allow;

  @override
  Future<Stream<Uint8List>> start({required int sampleRate}) async {
    if (fails) throw StateError('no input device');
    rate = sampleRate;
    return (controller = StreamController<Uint8List>()).stream;
  }

  @override
  Future<void> stop() async {
    stopped = true;
    await controller?.close();
  }

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  late Directory folder;
  setUp(() => folder = Directory.systemTemp.createTempSync('shadowing'));
  tearDown(() {
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  });

  test('a WAV header that says what follows', () {
    final pcm = Uint8List.fromList(List.generate(1001, (i) => i % 256));
    final wav = wavBytes(pcm, sampleRate: 44100);
    final data = ByteData.sublistView(wav);
    expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
    expect(ascii.decode(wav.sublist(8, 16)), 'WAVEfmt ');
    expect(data.getUint16(20, Endian.little), 1);
    expect(data.getUint16(22, Endian.little), 1);
    expect(data.getUint32(24, Endian.little), 44100);
    expect(data.getUint32(28, Endian.little), 88200);
    expect(data.getUint16(34, Endian.little), 16);
    expect(ascii.decode(wav.sublist(36, 40)), 'data');
    // An odd last byte is half a sample and is left out.
    expect(data.getUint32(40, Endian.little), 1000);
    expect(data.getUint32(4, Endian.little), 1036);
    expect(wav.length, 1044);
    expect(wav.sublist(44), pcm.sublist(0, 1000));
  });

  test('a take is what the microphone heard, saved as WAV', () async {
    final mic = FakeMicrophone();
    final shadowing = Shadowing(folder, microphone: mic);
    await shadowing.start();
    expect(shadowing.recording, isTrue);
    expect(mic.rate, Shadowing.sampleRate);
    for (var i = 0; i < 10; i++) {
      mic.controller!.add(Uint8List(4410));
    }
    final take = await shadowing.stop();
    expect(mic.stopped, isTrue);
    expect(shadowing.recording, isFalse);
    expect(take, isNotNull);
    expect(take!.lengthSync(), 44 + 44100);
    expect(shadowing.take?.path, take.path);
    await shadowing.dispose();
    expect(mic.disposed, isTrue);
    expect(take.existsSync(), isFalse);
  });

  test('a take too short to hear is not kept', () async {
    final mic = FakeMicrophone();
    final shadowing = Shadowing(folder, microphone: mic);
    await shadowing.start();
    mic.controller!.add(Uint8List(100));
    expect(await shadowing.stop(), isNull);
    expect(shadowing.take, isNull);
  });

  test('a denied or missing microphone says why', () async {
    await expectLater(Shadowing(folder, microphone: FakeMicrophone(allow: false)).start(), throwsA(isA<ShadowException>().having((e) => e.denied, 'denied', isTrue)));
    await expectLater(
      Shadowing(folder, microphone: FakeMicrophone(fails: true)).start(),
      throwsA(isA<ShadowException>().having((e) => e.denied, 'denied', isFalse).having((e) => e.detail, 'detail', contains('no input device'))),
    );
  });

  test('a new take replaces the last one', () async {
    final mic = FakeMicrophone();
    final shadowing = Shadowing(folder, microphone: mic);
    await shadowing.start();
    mic.controller!.add(Uint8List(20000));
    final first = await shadowing.stop();
    await shadowing.start();
    mic.controller!.add(Uint8List(30000));
    final second = await shadowing.stop();
    expect(second!.path, first!.path);
    expect(second.lengthSync(), 44 + 30000);
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
