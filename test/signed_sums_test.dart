import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/learning/license.dart';

void main() {
  // A SHA256SUMS signed as the learning packs workflow signs it.
  final sums = utf8.encode('${'a' * 64}  ja-jmdict.tsv.gz\n${'b' * 64} *en-ecdict.sqlite.gz\n');
  const signature = '/jPRqdu2L6kcXSgAtmtLI+jKi7qDX/Ac/1dJ5jywUimq3/gR54MIz/P9GhdjC82+aEo1e3CW49/5KpK4/GRyDQ==';

  test('a signed list of sums is read', () {
    final signed = SignedSums.verify(sums, signature);
    expect(signed, isNotNull);
    expect(signed!.of('ja-jmdict.tsv.gz'), 'a' * 64);
    expect(signed.of('en-ecdict.sqlite.gz'), 'b' * 64);
    expect(signed.of('jmdict.tsv.gz'), isNull);
  });

  test('a changed list, or a bad signature, is refused', () {
    final changed = [...sums]..[0] = 'c'.codeUnitAt(0);
    expect(SignedSums.verify(changed, signature), isNull);
    expect(SignedSums.verify(sums, 'not base64!'), isNull);
    expect(SignedSums.verify(sums, base64.encode(List.filled(64, 0))), isNull);
  });
}
