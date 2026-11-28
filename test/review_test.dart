import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/learning/review.dart';
import 'package:lumtub/learning/vocabulary.dart';

void main() {
  final now = DateTime(2026, 11, 21, 10);

  test('a new word: again comes back in minutes, good in days, easy later', () {
    final again = Fsrs.next(null, ReviewGrade.again, now);
    final good = Fsrs.next(null, ReviewGrade.good, now);
    final easy = Fsrs.next(null, ReviewGrade.easy, now);
    expect(again.due.difference(now), Fsrs.relearn);
    expect(good.due.difference(now).inDays, 3);
    expect(easy.due.difference(now).inDays, 15);
    expect(again.difficulty, greaterThan(good.difficulty));
  });

  test('intervals grow with each good review and shrink after a lapse', () {
    var state = Fsrs.next(null, ReviewGrade.good, now);
    var last = state.due.difference(now);
    var time = state.due;
    for (var i = 0; i < 4; i++) {
      state = Fsrs.next(state, ReviewGrade.good, time);
      final gap = state.due.difference(time);
      expect(gap, greaterThan(last));
      last = gap;
      time = state.due;
    }
    final lapsed = Fsrs.next(state, ReviewGrade.again, time);
    expect(lapsed.stability, lessThan(state.stability));
    expect(lapsed.lapses, 1);
    expect(lapsed.due.difference(time), Fsrs.relearn);
  });

  test('hard gives less time than good, good less than easy', () {
    final first = Fsrs.next(null, ReviewGrade.good, now);
    final later = first.due;
    final hard = Fsrs.next(first, ReviewGrade.hard, later).stability;
    final good = Fsrs.next(first, ReviewGrade.good, later).stability;
    final easy = Fsrs.next(first, ReviewGrade.easy, later).stability;
    expect(hard, lessThan(good));
    expect(good, lessThan(easy));
  });

  test('store: due order, new words per day, streak, and saving', () async {
    final dir = Directory.systemTemp.createTempSync('review');
    final store = ReviewStore(File('${dir.path}/review.json'));
    await store.load();
    VocabularyWord word(String w, int day) =>
        VocabularyWord(word: w, language: 'zh', added: DateTime(2026, 11, day));
    final words = [for (var i = 0; i < 30; i++) word('w$i', 1)];
    expect(store.dueCount(words, now), ReviewStore.newPerDay);
    // The book is newest first: the oldest word comes first in review.
    expect(store.due(words, now).first.word, 'w29');
    await store.grade('zh:w29', ReviewGrade.good, now);
    expect(store.dueCount(words, now), ReviewStore.newPerDay - 1);
    expect(store.streak(now), 1);
    expect(store.streak(now.add(const Duration(days: 1))), 1);
    expect(store.streak(now.add(const Duration(days: 2))), 0);
    final again = ReviewStore(File('${dir.path}/review.json'));
    await again.load();
    expect(again.of('zh:w29')!.reps, 1);
    expect(again.due(words, now.add(const Duration(days: 3))).first.word, 'w29');
    dir.deleteSync(recursive: true);
  });

  test('store: time per word learnt from reviews, focus mode kept, next due', () async {
    final dir = Directory.systemTemp.createTempSync('review');
    final store = ReviewStore(File('${dir.path}/review.json'));
    await store.load();
    expect(store.minutesFor(0), 0);
    expect(store.minutesFor(1), 1);
    expect(store.minutesFor(20), 4);
    for (var i = 0; i < 40; i++) {
      await store.grade('zh:w$i', ReviewGrade.good, now, seconds: 6);
    }
    expect(store.secondsPerWord, closeTo(6, 0.2));
    // A word left open for an hour counts as a minute at most.
    await store.grade('zh:x', ReviewGrade.good, now, seconds: 3600);
    expect(store.secondsPerWord, lessThan(12));
    await store.setFocus(true);
    final words = [VocabularyWord(word: 'w0', language: 'zh', added: DateTime(2026, 11))];
    expect(store.nextDue(words, now), store.of('zh:w0')!.due);
    final again = ReviewStore(File('${dir.path}/review.json'));
    await again.load();
    expect(again.focus, isTrue);
    expect(again.secondsPerWord, closeTo(store.secondsPerWord, 0.01));
    dir.deleteSync(recursive: true);
  });

  test("today's scenes: words by video, most words first, no video last", () {
    VocabularyWord word(String w, String video) => VocabularyWord(
        word: w,
        language: 'ja',
        videoId: video,
        videoTitle: video.isEmpty ? '' : 'Title $video',
        added: DateTime(2026, 11));
    final scenes = todaysScenes([word('a', ''), word('b', 'v1'), word('c', 'v2'), word('d', 'v2')]);
    expect([for (final s in scenes) s.videoId], ['v2', 'v1', '']);
    expect([for (final w in scenes.first.words) w.word], ['c', 'd']);
    expect(scenes.first.title, 'Title v2');
    expect(scenes.first.video.url, 'https://www.youtube.com/watch?v=v2');
  });

  test('a remembered word looked up again while watching comes back today', () async {
    final dir = Directory.systemTemp.createTempSync('review');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = ReviewStore(File('${dir.path}/review.json'));
    final start = DateTime.utc(2026, 11, 1, 9);
    // Never reviewed: nothing to bring back.
    expect(await store.lookedUpAgain('ja:食べる', start), isFalse);
    await store.grade('ja:食べる', ReviewGrade.good, start);
    final due = store.of('ja:食べる')!.due;
    // Within the hour of its grade it is the same study.
    expect(await store.lookedUpAgain('ja:食べる', start.add(const Duration(minutes: 20))), isFalse);
    final later = start.add(const Duration(hours: 5));
    expect(due.isAfter(later), isTrue);
    expect(await store.lookedUpAgain('ja:食べる', later), isTrue);
    final state = store.of('ja:食べる')!;
    expect(state.due, later);
    // Only when it comes back: stability and counts stay as graded.
    expect(state.reps, 1);
    expect(state.lapses, 0);
    expect(store.reviewedOn(later), 1);
    // Already due: nothing more to do.
    expect(await store.lookedUpAgain('ja:食べる', later.add(const Duration(minutes: 5))), isFalse);
  });
}
