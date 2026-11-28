import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/skins/skin.dart';
import 'package:lumtub/ui/skin_paint.dart';
import 'package:material_ui/material_ui.dart';

Future<ByteData> _draw(SkinPaint layer, Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
  paintSkinLayer(canvas, Offset.zero & size, layer);
  final image = await recorder.endRecording().toImage(size.width.round(), size.height.round());
  return (await image.toByteData())!;
}

int _bright(ByteData data, int width, int x, int y) => data.getUint8((y * width + x) * 4);

void main() {
  testWidgets('tiled patterns put their marks where drawn ones were', (tester) async {
    await tester.runAsync(() async {
      const size = Size(64, 64);
      // Lines 8 apart, 2 thick: rows 0–1, 8–9 … lit, the rows between dark.
      final lines = await _draw(
          const PatternPaint('lines', Colors.white, spacing: 8, size: 2, angle: 0), size);
      for (final y in [0, 8, 16, 40, 56]) {
        expect(_bright(lines, 64, 20, y), greaterThan(200), reason: 'line at $y');
      }
      for (final y in [4, 12, 30, 61]) {
        expect(_bright(lines, 64, 20, y), lessThan(40), reason: 'gap at $y');
      }
      // A grid: lit along both sets of lines, dark in the cells.
      final grid = await _draw(
          const PatternPaint('grid', Colors.white, spacing: 16, size: 2, angle: 0), size);
      expect(_bright(grid, 64, 32, 7), greaterThan(200));
      expect(_bright(grid, 64, 7, 48), greaterThan(200));
      expect(_bright(grid, 64, 8, 8), lessThan(40));
      // Dots: lit round each point, dark between them.
      final dots = await _draw(
          const PatternPaint('dots', Colors.white, spacing: 8, size: 2, angle: 0), size);
      expect(_bright(dots, 64, 16, 16), greaterThan(100));
      expect(_bright(dots, 64, 20, 20), lessThan(40));
    });
  });

  test('every pattern type paints without error, rotated too', () {
    for (final type in PatternPaint.types) {
      for (final angle in [0.0, 30.0]) {
        final recorder = ui.PictureRecorder();
        paintSkinLayer(Canvas(recorder), const Rect.fromLTWH(3.5, 7.25, 250, 300),
            PatternPaint(type, const Color(0x80FFFFFF), spacing: 2, size: 1, angle: angle));
        recorder.endRecording().dispose();
      }
    }
  });
}
