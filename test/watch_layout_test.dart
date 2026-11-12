import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/device.dart';
import 'package:lumtub/ui/common.dart';

void main() {
  Future<bool> phoneLike(WidgetTester tester, Size size, {bool touch = true, bool tv = false}) async {
    debugTouchFirst = touch;
    Device.tv = tv;
    addTearDown(() {
      debugTouchFirst = null;
      Device.tv = false;
    });
    late bool result;
    await tester.pumpWidget(MediaQuery(data: MediaQueryData(size: size), child: Builder(builder: (context) {
      result = watchesLikePhone(context);
      return const SizedBox();
    })));
    return result;
  }

  testWidgets('the watch page is laid out as a phone\'s on phones and upright tablets, never on TVs or computers', (tester) async {
    expect(await phoneLike(tester, const Size(412, 800)), isTrue);
    expect(await phoneLike(tester, const Size(800, 412)), isTrue);
    expect(await phoneLike(tester, const Size(800, 1280)), isTrue);
    expect(await phoneLike(tester, const Size(1280, 800)), isFalse);
    expect(await phoneLike(tester, const Size(960, 540), tv: true), isFalse);
    expect(await phoneLike(tester, const Size(540, 960), tv: true), isFalse);
    expect(await phoneLike(tester, const Size(800, 1280), touch: false), isFalse);
  });
}
