import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  setUp(() {
    IosVideoLayer.current = 7;
    IosVideoLayer.active.value = false;
  });

  test('picture-in-picture events reach the app with their seconds and errors', () {
    final seen = <(IosPipEvent, double?, String?)>[];
    IosVideoLayer.onEvent = (event, seconds, error) => seen.add((event, seconds, error));
    IosVideoLayer.handleEvent(7, 'skip', -15);
    IosVideoLayer.handleEvent(7, 'play', null);
    IosVideoLayer.handleEvent(7, 'failed:not possible now', null);
    IosVideoLayer.handleEvent(7, 'something new', null);
    expect(seen, [(IosPipEvent.skip, -15.0, null), (IosPipEvent.play, null, null), (IosPipEvent.failed, null, 'not possible now')]);
  });

  test('the window counts as open from its start until it stops or fails', () {
    IosVideoLayer.onEvent = null;
    IosVideoLayer.handleEvent(7, 'willStart', null);
    expect(IosVideoLayer.active.value, isTrue);
    IosVideoLayer.handleEvent(7, 'restore', null);
    expect(IosVideoLayer.active.value, isTrue);
    IosVideoLayer.handleEvent(7, 'stopped', null);
    expect(IosVideoLayer.active.value, isFalse);
    IosVideoLayer.handleEvent(7, 'started', null);
    IosVideoLayer.handleEvent(7, 'failed:error', null);
    expect(IosVideoLayer.active.value, isFalse);
  });

  test("another player's layer is ignored", () {
    var calls = 0;
    IosVideoLayer.onEvent = (_, __, ___) => calls++;
    IosVideoLayer.handleEvent(8, 'started', null);
    expect(calls, 0);
    expect(IosVideoLayer.active.value, isFalse);
  });
}
