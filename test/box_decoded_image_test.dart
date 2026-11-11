import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/skin_paint.dart';

void main() {
  test('a camera photo is decoded at the size the box shows it', () {
    expect(BoxDecodedImage.sizeFor(6000, 4000, width: 1920, height: 1280, cover: true), (1920, 1280));
    // A portrait photo covering a wide box keeps the box's width.
    expect(BoxDecodedImage.sizeFor(3000, 4000, width: 1920, height: 1280, cover: true), (1920, 2560));
    expect(BoxDecodedImage.sizeFor(3000, 4000, width: 1920, height: 1280, cover: false), (960, 1280));
  });

  test('a small picture is never enlarged', () {
    expect(BoxDecodedImage.sizeFor(800, 600, width: 1920, height: 1280, cover: true), (800, 600));
  });

  test('the same box shares one decoded picture', () {
    const inner = 'photo.jpg';
    expect(const BoxDecodedKey(inner, 1024, 768, true), const BoxDecodedKey(inner, 1024, 768, true));
    expect(const BoxDecodedKey(inner, 1024, 768, true) == const BoxDecodedKey(inner, 1280, 768, true), isFalse);
  });

  testWidgets('a big picture file comes out at the box size', (tester) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 3000, 2000), Paint()..color = const Color(0xFF336699));
      final picture = recorder.endRecording();
      final big = await picture.toImage(3000, 2000);
      picture.dispose();
      final png = await big.toByteData(format: ui.ImageByteFormat.png);
      big.dispose();
      final file = File('${Directory.systemTemp.createTempSync('box').path}/big.png')..writeAsBytesSync(png!.buffer.asUint8List());
      final done = Completer<ImageInfo>();
      BoxDecodedImage(FileImage(file), width: 768, height: 512, cover: true).resolve(ImageConfiguration.empty).addListener(ImageStreamListener((info, _) => done.complete(info)));
      final info = await done.future;
      expect((info.image.width, info.image.height), (768, 512));
      info.dispose();
    });
  });
}
