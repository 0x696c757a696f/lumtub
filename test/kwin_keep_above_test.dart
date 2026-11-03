import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/kwin_keep_above.dart';

void main() {
  test('the KWin script sets keepAbove on this process\'s windows in KWin 5 and 6', () {
    final script = KWinKeepAbove.script(4242, true);
    expect(script, contains('workspace.windowList ? workspace.windowList() : workspace.clientList()'));
    expect(script, contains('window.pid === 4242'));
    expect(script, contains('window.keepAbove = true'));
    expect(KWinKeepAbove.script(1, false), contains('window.keepAbove = false'));
  });

  test('reads the script number gdbus prints', () {
    expect(KWinKeepAbove.scriptId('(3,)\n'), 3);
    expect(KWinKeepAbove.scriptId('(int32 12,)'), 12);
    expect(KWinKeepAbove.scriptId('(-1,)'), -1);
    expect(KWinKeepAbove.scriptId('()'), isNull);
  });
}
