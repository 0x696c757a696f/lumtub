import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/window_frame.dart';

void main() {
  test('a rect goes to the runner as left, top, right, bottom', () {
    expect(WindowFrame.rectToList(const Rect.fromLTWH(10, 2, 46, 30)), [10, 2, 56, 32]);
  });

  test('button reports map to states and stay in range', () {
    expect(WindowFrame.buttonStateOf(0), WindowButtonState.none);
    expect(WindowFrame.buttonStateOf(1), WindowButtonState.hover);
    expect(WindowFrame.buttonStateOf(2), WindowButtonState.pressed);
    expect(WindowFrame.buttonStateOf(9), WindowButtonState.pressed);
    expect(WindowFrame.buttonStateOf(null), WindowButtonState.none);
  });

  test('edges are sent by name', () {
    expect(WindowEdge.bottomRight.name, 'bottomRight');
  });
}
