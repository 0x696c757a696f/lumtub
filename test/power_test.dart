import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/power.dart';

void main() {
  test('saves power on battery or with battery saver', () {
    expect(Power.savingOf(acLine: 0, systemStatus: 0), isTrue);
    expect(Power.savingOf(acLine: 1, systemStatus: 1), isTrue);
    expect(Power.savingOf(acLine: 1, systemStatus: 0), isFalse);
    // Unknown (255) with saver off: a desktop.
    expect(Power.savingOf(acLine: 255, systemStatus: 0), isFalse);
    expect(Power.saving, isFalse);
  });
}
