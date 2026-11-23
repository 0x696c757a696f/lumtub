import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/learning/video_difficulty.dart';
import 'package:lumtub/learning/video_words.dart';

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
}
