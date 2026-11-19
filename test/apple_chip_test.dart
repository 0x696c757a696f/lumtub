import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/apple_chip.dart';

void main() {
  test('A12 and later decode VP9, A11 and before do not', () {
    expect(AppleChip.hasVp9('iPhone10,6'), false); // iPhone X, A11
    expect(AppleChip.hasVp9('iPhone11,8'), true); // iPhone XR, A12
    expect(AppleChip.hasVp9('iPhone17,1'), true);
    expect(AppleChip.hasVp9('iPad7,11'), false); // iPad 7, A10
    expect(AppleChip.hasVp9('iPad8,1'), true); // iPad Pro 2018, A12X
    expect(AppleChip.hasVp9('iPad11,1'), true); // iPad mini 5, A12
    expect(AppleChip.hasVp9('iPod9,1'), false);
    expect(AppleChip.hasVp9('RealityDevice14,1'), true);
    expect(AppleChip.hasVp9('arm64'), null);
    expect(AppleChip.hasVp9(''), null);
  });
}
