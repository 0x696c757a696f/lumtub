import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/learning/video_difficulty.dart';
import 'package:lumtub/learning/video_words.dart';
import 'package:lumtub/learning/word_token.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('difficulty'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a reading is kept, banded and saved', () async {
    final file = File('${dir.path}/video-difficulty.json');
    final store = VideoDifficulty();
    await store.open(file);
    store.remember('dQw4w9WgXcQ', 0.954321);
    store.remember('not an id', 0.5);
    expect(store.knownOf('dQw4w9WgXcQ'), 0.954);
    expect(store.levelOf('dQw4w9WgXcQ'), VideoLevel.right);
    expect(store.knownOf('not an id'), isNull);
    await Future<void>.delayed(const Duration(milliseconds: 2300));
    final again = VideoDifficulty();
    await again.open(file);
    expect(again.knownOf('dQw4w9WgXcQ'), 0.954);
  });

  test('bands follow the viewing studies', () {
    expect(VideoWords.levelFor(0.99), VideoLevel.easy);
    expect(VideoWords.levelFor(0.93), VideoLevel.right);
    expect(VideoWords.levelFor(0.85), VideoLevel.hard);
    expect(VideoWords.levelFor(0.6), VideoLevel.tooHard);
  });

  test('the oldest readings go first', () {
    final store = VideoDifficulty();
    String id(int i) => 'v${i.toString().padLeft(10, '0')}';
    for (var i = 0; i <= VideoDifficulty.limit; i++) {
      store.remember(id(i), 0.9);
    }
    expect(store.knownOf(id(0)), isNull);
    expect(store.knownOf(id(VideoDifficulty.limit)), 0.9);
  });

  test('names inside a sentence are not counted as new words', () {
    WordToken word(String text, String language) => WordToken(text, null, isWord: true, language: language);
    expect(looksLikeName(word('Lisboa', 'pt')), isTrue);
    expect(looksLikeName(word('Pierre', 'fr')), isTrue);
    expect(looksLikeName(word('casa', 'pt')), isFalse);
    expect(looksLikeName(word('Haus', 'de')), isFalse);
    expect(looksLikeName(word("I'm", 'en')), isFalse);
    expect(looksLikeName(word('NASA', 'en')), isFalse);
  });

  test('words being learnt remember the videos they were heard in', () {
    final store = VideoDifficulty();
    store.saw('dQw4w9WgXcQ', ['pt:casa', 'pt:ônibus']);
    store.saw('dQw4w9WgXcQ', ['pt:casa']);
    store.saw('aaaaaaaaaaa', ['pt:casa']);
    expect(store.videosWith('pt:casa'), 2);
    expect(store.videosWith('pt:ônibus'), 1);
    expect(store.videosWith('pt:gato'), 0);
    for (var i = 0; i < VideoDifficulty.videosPerWord + 5; i++) {
      store.saw('v${i.toString().padLeft(10, '0')}', ['pt:casa']);
    }
    expect(store.videosWith('pt:casa'), VideoDifficulty.videosPerWord);
  });
}
