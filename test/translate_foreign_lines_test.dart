import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/language_guess.dart';
import 'package:lumtub/translation.dart';

class _Echo implements Translator {
  final sent = <String>[];
  @override
  Future<String> translate(String text, String target) async {
    sent.add(text);
    return text.split('\n').map((l) => '[$l]').join('\n');
  }
}

void main() {
  bool zh(String line) => dartLooksLike(line, 'zh-CN');

  test('only the lines in another language are sent and replaced', () async {
    final t = _Echo();
    final out = await translateForeignLines(t, 'Be still, and know that I am God\n处于真实的自己的生活状态，是得到安宁的途径。', 'zh-CN', zh);
    expect(t.sent, ['Be still, and know that I am God']);
    expect(out, '[Be still, and know that I am God]\n处于真实的自己的生活状态，是得到安宁的途径。');
  });

  test('text wholly in another language goes as it is', () async {
    final t = _Echo();
    expect(await translateForeignLines(t, 'one\ntwo', 'zh-CN', zh), '[one]\n[two]');
    expect(t.sent, ['one\ntwo']);
  });

  test('a reply with other line counts stands where the first foreign line was', () async {
    final t = _Join();
    expect(await translateForeignLines(t, 'a b\n这是中文的\nc d', 'zh-CN', zh), 'X\n这是中文的');
  });
}

class _Join implements Translator {
  @override
  Future<String> translate(String text, String target) async => 'X';
}
