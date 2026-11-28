import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/learning/ed25519.dart';
import 'package:lumtub/learning/license.dart';

List<int> _hex(String s) =>
    [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)];

const _testKey = [
  3,
  161,
  7,
  191,
  243,
  206,
  16,
  190,
  29,
  112,
  221,
  24,
  231,
  75,
  192,
  153,
  103,
  228,
  214,
  48,
  155,
  165,
  13,
  95,
  29,
  220,
  134,
  100,
  18,
  85,
  49,
  184
];
const _good =
    'LT1.eyJuIjoiSmF5IEV4YW1wbGUiLCJwIjoibGVhcm4iLCJkIjoiMjAyNi0xMS0yMCJ9.K_ZBIyNpn-gFlz4yVnU7WQfOU_93o9OFgLIBUXceMwGY92TqVAAuHesfCRUjM_XOoUEqPA2hh_-7f2x4wc_kBQ';
const _otherProduct =
    'LT1.eyJuIjoiSmF5IiwicCI6Im90aGVyIiwiZCI6IjIwMjYtMTEtMjAifQ.YO1lbd-051i6oiTkncF_3HkHMyK5Y1wyV3MhSv9i4CIBQsancuCal9_gzu1p-u_aBlZVCP1ArpdE8sJqZdVmBw';

void main() {
  test('RFC 8032 test vectors verify', () {
    expect(
      ed25519Verify(
        publicKey: _hex('d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'),
        message: const [],
        signature: _hex(
            'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b'),
      ),
      isTrue,
    );
    final key = _hex('3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c');
    final sig = _hex(
        '92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00');
    expect(ed25519Verify(publicKey: key, message: const [0x72], signature: sig), isTrue);
    expect(ed25519Verify(publicKey: key, message: const [0x73], signature: sig), isFalse);
    expect(
        ed25519Verify(
            publicKey: key, message: const [0x72], signature: [...sig.sublist(0, 63), sig[63] ^ 1]),
        isFalse);
  });

  test('a license signed by the key is read, with line breaks a chat app adds', () {
    final license = LearningLicense.parse('  ${_good.substring(0, 40)}\n${_good.substring(40)} ',
        key: _testKey);
    expect(license, isNotNull);
    expect(license!.name, 'Jay Example');
    expect(license.issued, '2026-11-20');
  });

  test('changed, foreign or other-product codes are refused', () {
    expect(LearningLicense.parse(_good.replaceFirst('SmF5', 'SmF6'), key: _testKey), isNull);
    expect(LearningLicense.parse(_good), isNull);
    expect(LearningLicense.parse(_otherProduct, key: _testKey), isNull);
    expect(LearningLicense.parse('hello', key: _testKey), isNull);
    expect(LearningLicense.parse('LT1.!!!.???', key: _testKey), isNull);
  });

  test('an activation receipt counts only for its code and device', () {
    const key = [
      20,
      8,
      140,
      165,
      60,
      26,
      206,
      148,
      234,
      252,
      228,
      161,
      119,
      136,
      152,
      186,
      144,
      179,
      30,
      117,
      254,
      110,
      148,
      214,
      83,
      62,
      77,
      48,
      233,
      223,
      170,
      60
    ];
    const receipt =
        'LA1.eyJjIjoiMDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWYiLCJ2IjoiZmVkY2JhOTg3NjU0MzIxMGZlZGNiYTk4NzY1NDMyMTAiLCJ0IjoiMjAyNi0xMS0yMSJ9.VHJam8_1fGVgC_dDkL-3TiCYf8C17rdDd9R8mVG0-5cwNRo7yFmNdiWQfErXpUSecmdRY6l4ZWkf_R7Ij1KZBw';
    const code = '0123456789abcdef0123456789abcdef';
    const device = 'fedcba9876543210fedcba9876543210';
    expect(ActivationReceipt.verify(receipt, codeId: code, device: device, key: key)?.day,
        DateTime(2026, 11, 21));
    expect(ActivationReceipt.verify(receipt, codeId: code, device: '0' * 32, key: key), isNull);
    expect(ActivationReceipt.verify(receipt, codeId: '1' * 32, device: device, key: key), isNull);
    expect(ActivationReceipt.verify(receipt, codeId: code, device: device), isNull);
    expect(
        ActivationReceipt.verify(receipt.replaceFirst('LA1.e', 'LA1.f'),
            codeId: code, device: device, key: key),
        isNull);
  });

  test('a code id is the start of its SHA-256', () {
    final license = LearningLicense.parse(_good, key: _testKey)!;
    expect(license.id, hasLength(32));
    expect(license.id, matches(RegExp(r'^[0-9a-f]{32}$')));
  });
}
