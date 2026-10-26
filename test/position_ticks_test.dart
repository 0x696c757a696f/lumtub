import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/widgets/position_ticks.dart';

void main() {
  test('passes a position every step, and seeks back at once', () async {
    const ms = Duration(milliseconds: 1);
    final input = [0, 16, 33, 250, 266, 520, 100, 116, 400].map((m) => ms * m);
    final out = await coarse(Stream.fromIterable(input)).toList();
    expect(out, [0, 250, 520, 100, 400].map((m) => ms * m));
  });
}
