import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/learning/vocabulary.dart';

VocabularyWord _word(String word, {String sentence = '我们一起学习中文', int seconds = 75}) => VocabularyWord(
      word: word,
      language: 'zh',
      reading: 'xué xí',
      meaning: 'to learn; to study',
      sentence: sentence,
      translation: 'We study Chinese, together',
      videoId: 'abc123',
      videoTitle: 'Lesson "one"',
      at: Duration(seconds: seconds),
      added: DateTime.utc(2026, 11, 20),
    );

void main() {
  test('the book keeps one entry per word, newest first, across a restart', () async {
    final folder = await Directory.systemTemp.createTemp('vocab');
    addTearDown(() => folder.delete(recursive: true));
    final file = File('${folder.path}/vocabulary.json');
    final book = VocabularyBook(file);
    await book.add(_word('学习'));
    await book.add(_word('中文'));
    await book.add(_word('学习', sentence: '学习很重要'));
    expect(book.words.map((w) => w.word), ['学习', '中文']);
    final again = VocabularyBook(file);
    await again.load();
    expect(again.words.map((w) => w.word), ['学习', '中文']);
    expect(again.words.first.sentence, '学习很重要');
    expect(again.words.first.at, const Duration(seconds: 75));
    await again.remove(again.words.first);
    expect(again.contains('zh', '学习'), isFalse);
  });

  test('CSV quotes what needs it and links to the moment', () {
    final csv = vocabularyCsv([_word('学习')]);
    expect(csv, startsWith('﻿word,reading,meaning,sentence,translation,video,time,link\r\n'));
    expect(csv, contains('学习,xué xí,to learn; to study,我们一起学习中文,"We study Chinese, together","Lesson ""one""",1:15,https://www.youtube.com/watch?v=abc123&t=74s'));
  });

  test('Anki file has the header, the word in bold and no stray tabs', () {
    final anki = vocabularyAnki([_word('学习')]);
    final lines = anki.trim().split('\n');
    expect(lines.take(4), ['#separator:tab', '#html:true', '#columns:Front\tBack\tTags', '#tags column:3']);
    final fields = lines[4].split('\t');
    expect(fields, hasLength(3));
    expect(fields[0], '学习');
    expect(fields[1], contains('我们一起<b>学习</b>中文'));
    expect(fields[1], contains('>Lesson "one" 1:15</a>'));
    expect(fields[2], 'lumtub lumtub::zh');
  });
}
