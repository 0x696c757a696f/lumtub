import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/background_json.dart';

void main() {
  test('small and large documents decode the same as jsonDecode', () async {
    final small = jsonEncode({'id': 'a', 'formats': []});
    final large = jsonEncode({
      'id': 'b',
      'formats': [for (var i = 0; i < 5000; i++) {'format_id': '$i', 'url': 'https://example.com/${'x' * 40}', 'height': i % 2160}],
    });
    expect(large.length, greaterThan(64 * 1024));
    for (final text in [small, large]) {
      expect(await decodeJsonInBackground(text), jsonDecode(text));
      expect(await decodeUtf8JsonInBackground(utf8.encode(text)), jsonDecode(text));
    }
  });

  test('bad JSON fails as a FormatException', () async {
    await expectLater(decodeJsonInBackground('{'), throwsFormatException);
    await expectLater(decodeJsonInBackground('[${'1,' * 40000}'), throwsFormatException);
  });
}
