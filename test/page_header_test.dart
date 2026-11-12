import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/common.dart';

void main() {
  Widget header(double width) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: PageHeader('观看历史', subtitle: '5 个视频 · 仅保存在这台设备上', trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                TextButton(onPressed: () {}, child: const Text('观看统计')),
                TextButton(onPressed: () {}, child: const Text('选择')),
                TextButton(onPressed: () {}, child: const Text('清空')),
              ])),
            ),
          ),
        ),
      );

  testWidgets('on a phone the buttons go under the title instead of squeezing it', (tester) async {
    await tester.pumpWidget(header(390));
    expect(tester.getTopLeft(find.text('选择')).dy, greaterThan(tester.getBottomLeft(find.text('5 个视频 · 仅保存在这台设备上')).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a wide page they stay beside it', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(header(1000));
    expect(tester.getTopLeft(find.text('选择')).dx, greaterThan(tester.getTopRight(find.text('观看历史')).dx));
    expect(tester.getBottomLeft(find.text('选择')).dy, lessThanOrEqualTo(tester.getBottomLeft(find.text('5 个视频 · 仅保存在这台设备上')).dy + 12));
  });
}
