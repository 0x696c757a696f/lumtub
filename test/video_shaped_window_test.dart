import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/ui/fill_window.dart';
import 'package:lumtub/ui/theater_mode.dart';
import 'package:lumtub/ui/window_chrome.dart';
import 'package:lumtub/window_frame.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the window takes the video shape only while the video fills it', () {
    final shapes = <Object?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(WindowFrame.channelName), (call) async {
      if (call.method == 'keepVideoShape') shapes.add(call.arguments);
      return null;
    });
    WindowFrame.debugSupported = true;
    addTearDown(() {
      WindowFrame.debugSupported = null;
      fillingWindow.value = false;
      WindowChrome.fullscreen.value = false;
    });

    VideoShapedWindow.aspect = 16 / 9;
    expect(shapes, isEmpty, reason: 'not filling the window yet');

    fillingWindow.value = true;
    expect(shapes, [16 / 9]);

    VideoShapedWindow.aspect = 16 / 9;
    expect(shapes, [16 / 9], reason: 'the same shape is not sent again');

    VideoShapedWindow.aspect = 4 / 3;
    expect(shapes, [16 / 9, 4 / 3]);

    // On to fullscreen: the window lets the shape go first.
    fillingWindow.value = false;
    WindowChrome.fullscreen.value = true;
    expect(shapes, [16 / 9, 4 / 3, 0.0]);

    WindowChrome.fullscreen.value = false;
    VideoShapedWindow.aspect = double.nan;
    fillingWindow.value = true;
    expect(shapes, [16 / 9, 4 / 3, 0.0], reason: 'an unknown shape leaves the window as it is');
  });
}
