import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/language_guess.dart';
import 'package:lumtub/skins/skin.dart' show contrastRatio;
import 'package:lumtub/ui/linked_text.dart';

void main() {
  test('a dark accent on a dark page is lightened until links read', () {
    final colors = ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark).copyWith(primary: const Color(0xFF1A3A7A), surface: const Color(0xFF101418));
    expect(contrastRatio(linkColor(ThemeData(colorScheme: colors)), colors.surface), greaterThanOrEqualTo(4.5));
  });

  test('an accent that already reads is kept', () {
    final colors = ColorScheme.fromSeed(seedColor: Colors.blue).copyWith(primary: const Color(0xFF0842A0), surface: Colors.white);
    expect(linkColor(ThemeData(colorScheme: colors)), const Color(0xFF0842A0));
  });

  test("a link's letters do not decide a line's language", () {
    expect(looksLike('📲 The app I use to learn languages: https://www.lingq.com/learn-languages-like-steve-kaufmann?utm_source=yt&utm_medium=pin&utm_campaign=syt&utm_content=IW5FmQqATFQ', 'en'), isTrue);
  });
}
