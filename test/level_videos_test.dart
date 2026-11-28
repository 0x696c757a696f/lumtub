import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/caption_tracks.dart';
import 'package:lumtub/explore_filters.dart';
import 'package:lumtub/learning/english_dictionary.dart' show EnglishLevel;
import 'package:lumtub/learning/level_videos.dart';
import 'package:lumtub/learning/video_words.dart';
import 'package:lumtub/learning/word_token.dart';

WordToken _w(String text, [String language = 'it']) => WordToken(text, null, isWord: true, language: language);

void main() {
  group('levels', () {
    test('tiers follow each scale', () {
      expect(levelTierOf('ja', null), 0);
      expect(levelTierOf('ja', 1), 0); // N5
      expect(levelTierOf('ja', 3), 1); // N3
      expect(levelTierOf('ja', 5), 2); // N1
      expect(levelTierOf('zh', 4), 1);
      expect(levelTierOf('it', 6), 2);
      expect(levelTierOf('en', EnglishLevel.middleSchool.index), 0);
      expect(levelTierOf('en', EnglishLevel.cet6.index), 1);
      expect(levelTierOf('en', EnglishLevel.gre.index), 2);
    });

    test('lessons name levels as exams do', () {
      expect(levelTag('ja', 1), 'N5');
      expect(levelTag('ja', 5), 'N1');
      expect(levelTag('zh', 3), 'HSK 3');
      expect(levelTag('ko', 2), 'TOPIK II');
      expect(levelTag('fr', 2), 'A2');
      expect(levelTag('en', EnglishLevel.cet6.index), 'B2');
      expect(levelTag('it', null), isNull);
    });

    test('a lesson naming the level fits, one naming another does not', () {
      expect(lessonFit('JLPT N5 grammar in 10 minutes', 'N5'), 2);
      expect(lessonFit('Corso di cinese HSK3 lezione 1', 'HSK 3'), 2);
      expect(lessonFit('JLPT N2 listening', 'N5'), 0);
      expect(lessonFit('Japanese for everyone', 'N5'), 1);
      expect(lessonFit('anything', null), 1);
    });

    test('the bands follow the viewing studies', () {
      expect(VideoWords.levelFor(0.99), VideoLevel.easy);
      expect(VideoWords.levelFor(0.96), VideoLevel.right);
      expect(VideoWords.levelFor(0.92), VideoLevel.challenging);
      expect(VideoWords.levelFor(0.85), VideoLevel.hard);
      expect(VideoWords.levelFor(0.7), VideoLevel.tooHard);
    });
  });

  group('searches', () {
    test('every learning language has graded and native searches in it', () {
      for (final language in ['en', 'zh', 'ja', 'ko', 'es', 'fr', 'de', 'it', 'pt', 'ru']) {
        expect(gradedLevelQueries(language, 0).length, greaterThanOrEqualTo(3), reason: language);
        final native = nativeLevelQueries(language, 1);
        expect(native, hasLength(2), reason: language);
        expect(native.first, isNot(equals(nativeLevelQueries(language, 2).first)), reason: language);
      }
      expect(gradedLevelQueries('ja', 1).first, 'Japanese comprehensible input intermediate');
    });

    test('lessons explained in Chinese are written in Chinese, others go through translation', () {
      final zh = lessonQueries('ja', 0, ExploreLanguage.zh, tag: 'N5');
      expect(zh.first.translated, isFalse);
      expect(zh.first.withTag(zh.first.words), '日语入门 教程 N5');
      final it = lessonQueries('zh', 1, ExploreLanguage.it, tag: 'HSK 3');
      expect(it.first.translated, isTrue);
      expect(it.first.words, 'learn Chinese intermediate');
      expect(it.first.withTag('imparare il cinese intermedio'), 'imparare il cinese intermedio HSK 3');
    });
  });

  group('subtitle tracks', () {
    List<int> answer(List<Map<String, Object?>> tracks) => utf8.encode(jsonEncode({
          'captions': {'playerCaptionsTracklistRenderer': {'captionTracks': tracks}},
        }));

    test("the uploader's track first, else the automatic one; regions count", () {
      final tracks = captionTracksOf(answer([
        {'baseUrl': 'https://www.youtube.com/api/timedtext?v=a&lang=ja&kind=asr', 'languageCode': 'ja', 'kind': 'asr'},
        {'baseUrl': 'https://www.youtube.com/api/timedtext?v=a&lang=ja', 'languageCode': 'ja'},
        {'baseUrl': 'https://www.youtube.com/api/timedtext?v=a&lang=zh-Hans', 'languageCode': 'zh-Hans'},
      ]));
      expect(captionTrackIn(tracks, 'ja')!.automatic, isFalse);
      expect(captionTrackIn(tracks, 'zh')!.language, 'zh-Hans');
      expect(captionTrackIn(tracks, 'ko'), isNull);
      expect(captionTrackIn(captionTracksOf(answer([tracks.first.toMap()])), 'ja')!.automatic, isTrue);
    });

    test('only YouTube timedtext addresses are fetched, as WebVTT', () {
      ({String url, String language, bool automatic}) t(String url) => (url: url, language: 'ja', automatic: false);
      final url = timedTextUrl(t('https://www.youtube.com/api/timedtext?v=abc&fmt=srv3&sparams=a&sparams=b'))!;
      expect(url.queryParameters['fmt'], 'vtt');
      expect(url.queryParametersAll['sparams'], ['a', 'b']);
      expect(timedTextUrl(t('/api/timedtext?v=abc'))!.host, 'www.youtube.com');
      expect(timedTextUrl(t('http://www.youtube.com/api/timedtext?v=abc')), isNull);
      expect(timedTextUrl(t('https://evil.example/api/timedtext')), isNull);
      expect(timedTextUrl(t('https://www.youtube.com.evil.example/api/timedtext')), isNull);
      expect(timedTextUrl(t('https://www.youtube.com/redirect?q=x')), isNull);
    });

    test('broken answers give no tracks', () {
      expect(captionTracksOf(utf8.encode('not json')), isEmpty);
      expect(captionTracksOf(utf8.encode('{"captions": 3}')), isEmpty);
      expect(captionTracksOf(answer([{'languageCode': 'ja'}])), isEmpty);
    });

    test('cue times are read in milliseconds', () {
      expect(cueTimes('00:01:02.500 --> 00:01:04.000 align:start position:0%'), (62500, 64000));
      expect(cueTimes('01:00:00.000 --> 01:00:01.250'), (3600000, 3601250));
      expect(cueTimes('nonsense'), isNull);
    });
  });

  group('measuring', () {
    // "io" known, "casa" not, "Roma" a name inside a sentence.
    final features = LevelFeatures(
      language: 'it',
      automatic: true,
      words: [_w('io'), _w('casa'), _w('Roma')],
      lines: [
        [0, 0, 1],
        [0, -3],
        for (var i = 0; i < 20; i++) [1],
      ],
      starts: [0, 1000, for (var i = 0; i < 20; i++) 61000 + i * 1000],
      speech: 120000,
      units: 24,
    );

    test('known words, names and the hardest minute', () {
      final m = measureLevel(features, (w) => w.text == 'io', const {});
      // Said: io io casa io (Roma skipped as an unknown name) + 20 casa.
      expect(m.said, 24);
      expect(m.known, closeTo(3 / 24, 1e-9));
      expect(m.newWords, 1);
      expect(m.perMinute, closeTo(12, 1e-9));
      expect(m.newPerMinute, closeTo(10.5, 1e-9));
      // The first minute says too little to tell; the second knows none.
      expect(m.hardestMinute, 0);
      // A name the learner knows counts.
      expect(measureLevel(features, (w) => w.text != 'casa', const {}).said, 25);
    });

    test('a Chinese word of known characters is half known', () {
      final zh = LevelFeatures(language: 'zh', automatic: false, words: [_w('学生', 'zh'), _w('学', 'zh'), _w('生', 'zh')], lines: [[0, 1, 2]], starts: [0], speech: 60000, units: 4);
      final m = measureLevel(zh, (w) => w.text.length == 1, const {});
      expect(m.known, closeTo(2.5 / 3, 1e-9));
    });

    test('features survive a round trip and broken ones are refused', () {
      final again = LevelFeatures.fromJson(jsonDecode(jsonEncode(features.toJson())))!;
      expect(again.words.map((w) => w.text), ['io', 'casa', 'Roma']);
      expect(again.lines[1], [0, -3]);
      expect(again.automatic, isTrue);
      final bad = features.toJson()..['x'] = [[0, 7]];
      expect(LevelFeatures.fromJson(bad), isNull);
      expect(LevelFeatures.fromJson({'v': 99}), isNull);
    });

    test('readings survive a round trip and out-of-range ones are refused', () {
      final m = measureLevel(features, (w) => w.text == 'io', const {});
      final r = LevelReading.of(features, m, at: 100, stamp: 's');
      final again = LevelReading.fromJson(jsonDecode(jsonEncode(r.toJson())))!;
      expect(again.known, closeTo(r.known!, 0.001));
      expect(again.automatic, isTrue);
      expect(LevelReading.fromJson({...r.toJson(), 'k': 1.5}), isNull);
      expect(LevelReading.fromJson({...r.toJson(), 'p': double.infinity}), isNull);
      expect(LevelReading.none('it', 5).known, isNull);
    });

    test('a band orders by nearness to its middle, then by load', () {
      LevelReading r(double known, {double perMinute = 150, double newPerMinute = 3, double? hardest}) => LevelReading(
          language: 'en', known: known, automatic: false, newWords: 5, perMinute: perMinute, newPerMinute: newPerMinute, hardestMinute: hardest, at: 0, stamp: '');
      expect(levelVideoScore(VideoLevel.right, r(0.965)), greaterThan(levelVideoScore(VideoLevel.right, r(0.951))));
      expect(levelVideoScore(VideoLevel.right, r(0.96)), greaterThan(levelVideoScore(VideoLevel.right, r(0.96, perMinute: 220))));
      expect(levelVideoScore(VideoLevel.right, r(0.96)), greaterThan(levelVideoScore(VideoLevel.right, r(0.96, newPerMinute: 14))));
      expect(levelVideoScore(VideoLevel.right, r(0.96)), greaterThan(levelVideoScore(VideoLevel.right, r(0.96, hardest: 0.7))));
      expect(r(0.9, perMinute: 100).pace, SpeechPace.slow);
      expect(r(0.9, perMinute: 220).pace, SpeechPace.fast);
      // Broken subtitles sink below every reliable reading.
      LevelReading broken(double known) => LevelReading(
          language: 'en', known: known, automatic: true, newWords: 5, perMinute: 150, newPerMinute: 3, hardestMinute: null, confidence: 40, at: 0, stamp: '');
      expect(levelVideoScore(VideoLevel.right, broken(0.965)), lessThan(levelVideoScore(VideoLevel.right, r(0.80))));
      // A length that suits the level and a channel that fits nudge ahead.
      expect(levelVideoScore(VideoLevel.right, r(0.96), seconds: 300, tier: 0), greaterThan(levelVideoScore(VideoLevel.right, r(0.96), seconds: 7200, tier: 0)));
      expect(levelVideoScore(VideoLevel.right, r(0.96), channelFit: 1), greaterThan(levelVideoScore(VideoLevel.right, r(0.96), channelFit: 0)));
    });

    test('speech is counted in each language\'s own units', () {
      expect(speechUnits('zh', _w('学生们', 'zh')), 3);
      expect(speechUnits('ko', _w('안녕하세요', 'ko')), 5);
      expect(speechUnits('ja', const WordToken('東京', 'とうきょう', isWord: true, language: 'ja')), 4);
      expect(speechUnits('ja', const WordToken('ちょっと', null, isWord: true, language: 'ja')), 3);
      expect(speechUnits('it', _w('casa')), 1);
    });

    test('speaking time counts overlapping lines once', () {
      expect(speechSpan([(0, 2000, 'a'), (1000, 3000, 'b'), (10000, 11000, 'c')]), 4000);
      expect(speechSpan([]), 0);
    });

    test('captions that repeat or race are trusted less', () {
      expect(repeatedShare(['a', 'b', 'c', 'd']), 0);
      expect(repeatedShare(['a', 'a', 'a', 'b']), closeTo(0.75, 1e-9));
      // English: 170 a minute, so more than about 71 words in ten seconds.
      expect(rushedShare('en', [0, 10000], [80, 20]), 0.5);
      LevelFeatures f({bool automatic = false, double repeated = 0, double rushed = 0}) => LevelFeatures(
          language: 'en', automatic: automatic, words: const [], lines: const [], starts: const [], speech: 0, units: 0, repeated: repeated, rushed: rushed);
      expect(f().confidence, 100);
      expect(f(automatic: true).confidence, 90);
      expect(f(automatic: true, repeated: 0.3, rushed: 0.2).confidence, 40);
    });
  });

  group('free videos', () {
    test('the first eight, then three new ones a day; one shown before stays', () {
      final videos = LevelVideos(MockClient((_) async => http.Response('', 404)));
      final ids = [for (var i = 0; i < 12; i++) 'video${i.toString().padLeft(6, '0')}'];
      for (final id in ids.take(8)) {
        expect(videos.showFree(id), isTrue);
      }
      expect(videos.freeLeft, 3);
      for (final id in ids.skip(8).take(3)) {
        expect(videos.showFree(id), isTrue);
      }
      expect(videos.freeLeft, 0);
      expect(videos.showFree(ids.last), isFalse);
      expect(videos.showFree(ids.first), isTrue);
      expect(videos.wasShownFree(ids.last), isFalse);
      videos.dispose();
    });
  });
}

extension on ({String url, String language, bool automatic}) {
  Map<String, Object?> toMap() => {'baseUrl': url, 'languageCode': language, if (automatic) 'kind': 'asr'};
}
