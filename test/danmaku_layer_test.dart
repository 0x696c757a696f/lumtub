import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/danmaku.dart';
import 'package:lumtub/live_chat.dart';
import 'package:lumtub/native_core.dart';
import 'package:lumtub/ui/danmaku_layer.dart';

import 'player_controls_test.dart' show FakePlayer;

void main() {
  final core = NativeCore.instance;

  LiveChatMessage message(String id, String text, int ms) => LiveChatMessage(
      id: id, kind: LiveChatKind.message, text: text, offset: Duration(milliseconds: ms));

  test('a replay message is where the layout puts it, moving right to left', () {
    final player = FakePlayer()
      ..state = FakePlayer().state.copyWith(position: const Duration(seconds: 6), playing: false);
    final overlay = DanmakuOverlay(player)
      ..start(const DanmakuSettings(enabled: true, seconds: 16), live: false);
    addTearDown(overlay.stop);
    overlay.add([message('a', 'hello', 5000), message('b', 'later', 40000)]);
    // Given to the layout up to 30 s ahead of the clock.
    overlay.now();
    final items = overlay.visibleAt(6000 - overlay.duration, 7500);
    expect(items.map((i) => i.key), [startsWith('t5000')]);
    final item = items.single;
    final at6 = item.x(6000, overlay.duration), at7 = item.x(7000, overlay.duration);
    expect(at6, closeTo(1920 - 1000 * (1920 + item.width) / 16000, 1e-9));
    expect(at7, lessThan(at6));
    expect(item.x(5000 + overlay.duration, overlay.duration), closeTo(-item.width, 1e-9),
        reason: 'it has just left on the left');
  }, skip: core == null ? 'needs lumtub_core' : null);

  testWidgets('the layer draws a message at its place over the picture', (tester) async {
    final player = FakePlayer()
      ..state =
          FakePlayer().state.copyWith(position: const Duration(milliseconds: 9000), playing: false);
    final overlay = DanmakuOverlay(player)
      ..start(const DanmakuSettings(enabled: true, seconds: 16, opacity: 1), live: false);
    addTearDown(overlay.stop);
    overlay.add([message('a', 'HELLO WORLD', 1000)]);
    final shown = ValueNotifier<DanmakuOverlay?>(overlay);
    final key = GlobalKey();
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
          key: key,
          child: ColoredBox(color: const Color(0xFF000000), child: DanmakuLayer(overlay: shown))),
    ));
    // The message is drawn into an image off the frame, then shown.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final image = (await tester.runAsync(
        () => (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage()))!;
    final bytes = (await tester.runAsync(image.toByteData))!;
    final width = image.width;
    image.dispose();
    // At 9 s a message that came in at 1 s has gone half way: its left edge
    // near x = 960 - 8000 * (1920 + w) / 16000 / 2 in this 960-wide box.
    var minX = width, maxX = -1, maxY = -1;
    for (var i = 0; i < bytes.lengthInBytes; i += 4) {
      if (bytes.getUint8(i) > 200 && bytes.getUint8(i + 1) > 200 && bytes.getUint8(i + 2) > 200) {
        final x = (i ~/ 4) % width, y = (i ~/ 4) ~/ width;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
    expect(maxX, greaterThan(minX), reason: 'white text drawn');
    final item = overlay.visibleAt(9000 - overlay.duration, 9000).single;
    final left = item.x(9000, overlay.duration) / 2;
    expect(minX, inInclusiveRange(left - 2, left + 12));
    expect(maxY, lessThan(52 * 1.25 / 2 + 2), reason: 'in the top lane');
    await tester.pumpWidget(const SizedBox());
  }, skip: core == null);
}
