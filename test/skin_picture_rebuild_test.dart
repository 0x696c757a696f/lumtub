import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/skins/skin.dart';
import 'package:lumtub/ui/skin_paint.dart';

void main() {
  testWidgets('a skin picture stays up while the window rebuilds', (tester) async {
    final layer = ImagePaint('${Directory.current.path}/skins/aquarium/day.jpg', builtIn: false, fit: 'cover', opacity: 1);
    late StateSetter rebuild;
    var n = 0;
    await tester.pumpWidget(StatefulBuilder(builder: (context, setState) {
      rebuild = setState;
      n++;
      return Directionality(textDirection: TextDirection.ltr, child: SkinLayers([layer], key: ValueKey(n > 100)));
    }));
    // Decoding happens off the test's fake clock.
    for (var i = 0; i < 50 && tester.widget<RawImage>(find.byType(RawImage)).image == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    for (var i = 0; i < 3; i++) {
      rebuild(() {});
      await tester.pump();
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull, reason: 'frame after rebuild $i');
    }
  });

  test('the same picture at the same size is the same provider', () {
    final a = BoxDecodedImage(FileImage(File('x.jpg')), width: 512, height: 256, cover: true);
    final b = BoxDecodedImage(FileImage(File('x.jpg')), width: 512, height: 256, cover: true);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == BoxDecodedImage(FileImage(File('x.jpg')), width: 768, height: 256, cover: true), isFalse);
  });
}
