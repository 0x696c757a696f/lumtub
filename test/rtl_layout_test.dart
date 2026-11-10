import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/ui/video_card.dart';

Widget _host(TextDirection direction, Widget child, {double width = 320}) => MaterialApp(
      builder: (context, page) => Directionality(textDirection: direction, child: page!),
      home: Scaffold(body: Align(alignment: AlignmentDirectional.topStart, child: SizedBox(width: width, child: child))),
    );

const _item = VideoItem(id: 'abcdefghijk', title: 'عنوان الفيديو الطويل جدا لاختبار التفاف النص في الاتجاه من اليمين إلى اليسار', channel: 'القناة', url: 'u', duration: 185);

void main() {
  for (final width in [220.0, 320.0]) {
    testWidgets('a video card in right-to-left lays out without overflow at $width', (tester) async {
      await tester.pumpWidget(_host(TextDirection.rtl, SizedBox(height: 300, child: VideoCard(item: _item, onOpen: () {})), width: width));
      expect(tester.takeException(), isNull);
      expect(find.text('3:05'), findsOneWidget);
    });
  }

  testWidgets('the duration badge and the card swap sides in right-to-left', (tester) async {
    Future<double> badgeCenter(TextDirection d) async {
      await tester.pumpWidget(_host(d, SizedBox(height: 300, child: VideoCard(item: _item, onOpen: () {}))));
      final card = tester.getRect(find.byType(VideoCard));
      return (tester.getCenter(find.text('3:05')).dx - card.left) / card.width;
    }

    final ltr = await badgeCenter(TextDirection.ltr);
    final rtl = await badgeCenter(TextDirection.rtl);
    expect(ltr, greaterThan(0.5));
    expect(rtl, lessThan(0.5));
  });

  testWidgets('a compact tile in right-to-left lays out without overflow', (tester) async {
    await tester.pumpWidget(_host(TextDirection.rtl, CompactVideoTile(item: _item, onOpen: () {}), width: 300));
    expect(tester.takeException(), isNull);
  });
}
