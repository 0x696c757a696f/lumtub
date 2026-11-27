import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app_preferences.dart';
import 'package:lumtub/explore_filters.dart';
import 'package:lumtub/explore_topics.dart';
import 'package:lumtub/faith_topics.dart';
import 'package:lumtub/l10n/l10n.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/player_settings.dart';
import 'package:lumtub/video_repository.dart';
import 'package:lumtub/youtube_related.dart';

void main() {
  test('tells a title\'s language from its script and small words', () {
    expect(titleLanguage('【4K】東京の夜景を歩く'), ExploreLanguage.ja);
    expect(titleLanguage('서울 맛집 투어'), ExploreLanguage.ko);
    expect(titleLanguage('中国历史纪录片 第一集'), ExploreLanguage.zh);
    expect(titleLanguage('How to build a PC in 2026'), ExploreLanguage.en);
    expect(titleLanguage('Cómo hacer pan en casa con una receta fácil'), ExploreLanguage.es);
    expect(titleLanguage("Les secrets de la cuisine française, c'est simple"), ExploreLanguage.fr);
    expect(titleLanguage('Die besten Tipps für den Garten und mehr'), ExploreLanguage.de);
    expect(titleLanguage('Como fazer uma receita fácil, não é difícil'), ExploreLanguage.pt);
    expect(titleLanguage('Новости дня'), ExploreLanguage.ru);
    expect(titleLanguage('Hướng dẫn nấu phở'), ExploreLanguage.vi);
    expect(titleLanguage('ข่าววันนี้'), ExploreLanguage.th);
    expect(titleLanguage('1234 !!!'), ExploreLanguage.any);
    expect(ExploreLanguage.any.matches('anything'), isTrue);
    expect(ExploreLanguage.zh.matches('How to cook'), isFalse);
  });

  test('a region search carries only a PREF cookie with the country', () {
    final cookies = VideoRepository.regionCookies('jp');
    expect(cookies, startsWith('# Netscape HTTP Cookie File\n'));
    expect(cookies.trim().split('\n').last.split('\t'), ['.youtube.com', 'TRUE', '/', 'TRUE', '2147483647', 'PREF', 'gl=JP&hl=en']);
    final repository = VideoRepository('yt-dlp');
    expect(repository.listingArguments('u', cookies: 'c.txt'), containsAllInOrder(['--cookies', 'c.txt']));
    expect(repository.listingArguments('u'), isNot(contains('--cookies')));
  });

  test('a mix takes a few lines of each search in turn and skips failed ones', () async {
    Stream<String> lines(String name, int count) => Stream.fromIterable([for (var i = 0; i < count; i++) '$name$i']);
    Stream<String> failing() => Stream.error(StateError('no'));
    final mixed = await VideoRepository.interleave([() => lines('a', 4), failing, () => lines('b', 2), () => lines('c', 5)], run: 2).toList();
    expect(mixed, ['a0', 'a1', 'b0', 'b1', 'c0', 'c1', 'a2', 'a3', 'c2', 'c3', 'c4']);
    expect(VideoRepository.interleave([failing]).toList(), throwsStateError);
  });

  test('a slow search in a mix holds back none of the others', () async {
    final slow = StreamController<String>();
    final mixed = <String>[];
    final reading = VideoRepository.interleave([() => slow.stream, () => Stream.fromIterable(['b0', 'b1', 'b2', 'b3'])], run: 2).listen(mixed.add);
    await pumpEventQueue();
    expect(mixed, ['b0', 'b1', 'b2', 'b3']);
    final ended = reading.asFuture<void>();
    slow.add('a0');
    unawaited(slow.close());
    await ended;
    expect(mixed.last, 'a0');
  });

  test('only words outside the Latin alphabet of a search are translated', () {
    expect(searchPhrasesOf('มวยไทย สด'), ['มวยไทย', 'สด']);
    expect(searchPhrasesOf('живая музыка Blender'), ['живая музыка', 'Blender']);
    expect(searchPhrasesOf('живая музыка Blender').where(isTranslatedPhrase), ['живая музыка']);
    expect(searchPhrasesOf('blender 3D modeling live').where(isTranslatedPhrase), isEmpty);
    expect(searchPhrasesOf('游戏 直播 Minecraft'), ['游戏', '直播', 'Minecraft']);
    expect(searchGlossary['直播'], 'live');
  });

  test('a search in a language other than English puts its English words into it too', () {
    bool italian(String phrase) => translatesInto(phrase, ExploreLanguage.it);
    expect(searchPhrasesOf('哲学 philosophy lecture').where(italian), ['哲学', 'philosophy lecture']);
    expect(searchPhrasesOf('Presocratic philosophers').where(italian), ['Presocratic philosophers']);
    // Names and words titles write the same everywhere stay.
    expect(searchPhrasesOf('游戏 直播 Minecraft').where(italian), ['游戏', '直播']);
    expect(italian('lofi'), isFalse);
    expect(italian('Plato'), isFalse);
    // In English only other scripts are translated.
    expect(searchPhrasesOf('哲学 philosophy lecture').where((p) => translatesInto(p, ExploreLanguage.en)), ['哲学']);
  });

  test('details take the translated title, description and chapter names', () {
    final details = const VideoDetails(
      title: 'Original',
      channel: 'c',
      description: '0:00 Intro\n1:30 Main part',
      chapters: [Chapter(Duration.zero, Duration(seconds: 90), 'Intro'), Chapter(Duration(seconds: 90), Duration.zero, 'Main part')],
    );
    final local = details.localized('翻译标题', '0:00 开场\n01:30 - 正片\n结尾');
    expect(local.title, '翻译标题');
    expect(local.description, startsWith('0:00 开场'));
    expect(local.chapters.map((c) => c.title), ['开场', '正片']);
    expect(identical(details.localized('', ''), details), isTrue);
    final text = YoutubeRelated.localized({
      'contents': [
        {'videoPrimaryInfoRenderer': {'title': {'runs': [{'text': '你好'}, {'text': '世界'}]}}},
        {'videoSecondaryInfoRenderer': {'attributedDescription': {'content': '说明'}}},
      ],
      'frameworkUpdates': {'entityBatchUpdate': {'mutations': [
        {'payload': {'likeCountEntity': {'likeCountIfIndifferentNumber': '1234567', 'likeCountIfLiked': {'content': '1.2M'}}}},
      ]}},
    });
    expect(text?.title, '你好世界');
    expect(text?.description, '说明');
    expect(text?.likes, 1234567);
    expect(details.localized(details.title, details.description, likes: 5).likeCount, 5);
  });

  test('subtitles follow the interface language unless another is chosen', () {
    expect(const PlayerSettings().subtitleLanguage, SubtitleLanguage.auto);
    addTearDown(() => setLanguage(AppLanguage.en));
    setLanguage(AppLanguage.zhHans);
    expect(SubtitleLanguage.auto.mpvLangs, SubtitleLanguage.zh.mpvLangs);
    setLanguage(const AppLanguage('zh-Hant'));
    expect(SubtitleLanguage.auto.resolved, SubtitleLanguage.zhHant);
    setLanguage(const AppLanguage('zh-HK'));
    expect(SubtitleLanguage.auto.translation.code, 'zh-TW');
    setLanguage(const AppLanguage('de'));
    expect(SubtitleLanguage.auto.resolved, SubtitleLanguage.de);
    expect(SubtitleLanguage.auto.translation.code, 'de');
    // Every interface language has subtitles of its own.
    setLanguage(const AppLanguage('he'));
    expect(SubtitleLanguage.auto.translation.code, 'iw');
    expect(SubtitleLanguage.auto.mpvLangs, 'iw,he,en,eng');
    expect(SubtitleLanguage.auto.ytDlpLangs, '(iw|he|en).*');
    setLanguage(const AppLanguage('fil'));
    expect(SubtitleLanguage.auto.translation.code, 'tl');
    setLanguage(const AppLanguage('la'));
    expect(SubtitleLanguage.auto.translation.code, 'la');
    expect(SubtitleLanguage.byName('pl')?.translation.code, 'pl');
    // Windows' language is still known on its own.
    final saved = SubtitleLanguage.systemLocale;
    addTearDown(() => SubtitleLanguage.systemLocale = saved);
    SubtitleLanguage.systemLocale = () => const Locale('zh', 'HK');
    expect(SubtitleLanguage.systemTranslation.code, 'zh-TW');
    SubtitleLanguage.systemLocale = () => const Locale('nb', 'NO');
    expect(SubtitleLanguage.systemTranslation.code, 'no');
    // 简体中文优先, the old default, now follows; a choice saved since stays.
    expect(PlayerSettings.fromJson({'subtitleLanguage': 'zh'}).subtitleLanguage, SubtitleLanguage.auto);
    expect(PlayerSettings.fromJson({'subtitleLanguage': 'ja'}).subtitleLanguage, SubtitleLanguage.ja);
    final chosen = PlayerSettings.fromJson(jsonDecode(jsonEncode(const PlayerSettings(subtitleLanguage: SubtitleLanguage.zh).toJson())));
    expect(chosen.subtitleLanguage, SubtitleLanguage.zh);
  });

  test('explore region and language round-trip through the preferences', () {
    final saved = const AppPreferences().copyWith(exploreRegion: ExploreRegion.jp, exploreLanguage: ExploreLanguage.ja);
    final restored = AppPreferences.fromJson(jsonDecode(jsonEncode(saved.toJson())));
    expect(restored.exploreRegion, ExploreRegion.jp);
    expect(restored.exploreLanguage, ExploreLanguage.ja);
    expect(AppPreferences.fromJson(<String, Object?>{}).exploreRegion, ExploreRegion.any);
  });

  test('a region and a language say what to search in and from where', () {
    expect(ExploreRegion.jp.searchLanguage, ExploreLanguage.ja);
    expect(ExploreRegion.tw.searchLanguage, ExploreLanguage.zh);
    expect(ExploreRegion.mx.searchLanguage, ExploreLanguage.es);
    expect(ExploreRegion.ng.searchLanguage, ExploreLanguage.en);
    expect(ExploreRegion.any.searchLanguage, ExploreLanguage.any);
    expect(ExploreLanguage.turkish.code, 'tr');
    expect(ExploreLanguage.it.homeCountry, 'IT');
    expect(ExploreLanguage.en.homeCountry, isNull);
    expect(ExploreLanguage.fa.homeCountry, isNull, reason: 'searches from Iran bring nothing');
    expect(ExploreLanguage.jv.searchAnchor, 'basa Jawa');
    expect(ExploreLanguage.it.searchAnchor, isNull);
    expect([for (final l in [ExploreLanguage.eo, ExploreLanguage.jv, ExploreLanguage.la, ExploreLanguage.su, ExploreLanguage.ti, ExploreLanguage.tk]) l.youtubeHl], ['en', 'id', 'en', 'id', 'am', 'ru']);
    // Every region's search language is one explore offers.
    for (final region in ExploreRegion.values.skip(1)) {
      expect(region.searchLanguage, isNot(ExploreLanguage.any), reason: region.name);
    }
  });

  test('a search translated word by word keeps each word once', () {
    expect(searchPhrasesOf('科技 数码 评测'), ['科技', '数码', '评测']);
    expect(searchPhrasesOf('stand-up comedy live'), ['stand-up comedy', 'live']);
    expect(searchPhrasesOf('议会 国会 parliament live'), ['议会', '国会', 'parliament', 'live']);
    expect(searchPhrasesOf(' ゲーム 実況  live stream '), ['ゲーム', '実況', 'live', 'stream']);
    expect(searchWordsOf(['giardinaggio', 'giardinaggio']), 'giardinaggio');
    expect(searchWordsOf(['tavola rotonda', 'discussione', 'Tavola rotonda ', '']), 'tavola rotonda discussione');
    expect(searchWordsOf(['tecnologia', 'digitale', 'recensione']), 'tecnologia digitale recensione');
    // Each word once: the Chinese keyword and its English one translate alike.
    expect(searchWordsOf(['forma fisica', 'live', 'forma fisica dal vivo']), 'forma fisica live dal vivo');
    // Keywords a translation word by word takes in another sense go by their English.
    expect(searchPivots['体育'], 'sports');
    expect(englishSearchOf('后端 backend Java Go'), 'back-end backend Java Go');
    // The English beside a keyword is its English, put into other languages too.
    expect(englishSearchOf('基督宗教 Christianity'), 'christianity');
    expect(translatesInto(searchPhrasesOf(englishSearchOf('基督宗教 Christianity')).single, ExploreLanguage.it), isTrue);
    expect(englishSearchOf('天主教 Catholic'), 'catholic');
    // A user's own keywords, which no pivot covers, go into English first.
    expect(unpivotedPhrasesOf('攀岩 直播 bouldering 中世纪 历史'), ['攀岩', '中世纪', '历史']);
    expect(withEnglishOf('攀岩 直播 bouldering 中世纪 历史', ['rock climbing', 'medieval', 'history']), 'rock climbing 直播 bouldering medieval history');
    expect(pivotsThroughEnglish(ExploreLanguage.it), isTrue);
    expect(pivotsThroughEnglish(ExploreLanguage.ja), isFalse);
    expect(englishSearchOf('体育 直播'), 'sports 直播', reason: '直播 is searched as "live" in every language');
    expect(englishSearchOf('AI 论文解读 paper explained'), 'AI paper explained');
    expect(englishSearchOf('聊天 直播 just chatting'), '直播 just chatting');
    expect(englishSearchOf('妇产科学 lecture'), 'obstetrics and gynecology lecture');
    expect(searchWordsOf(searchPhrasesOf(englishSearchOf('健身 训练 workout'))), 'fitness training workout');
  });

  test('every Chinese keyword of every zone and filter has its English', () {
    final missing = <String>{};
    void check(String query) {
      for (final word in query.split(RegExp(r'\s+'))) {
        if (RegExp(r'[\u4e00-\u9fff]').hasMatch(word) && !searchPivots.containsKey(word) && !searchGlossary.containsKey(word)) missing.add(word);
      }
    }

    void sub(ExploreSub s) {
      check(s.query);
      s.subs.forEach(sub);
    }

    for (final filter in <WordFilter>[...ContentFormat.values, ...ContentView.values, ...FaithFormat.values, ...FaithView.values]) {
      check(filter.words);
    }
    for (final section in ExploreSection.values) {
      for (final topic in exploreTopicsOf(section)) {
        check(topic.query);
        topic.subs.forEach(sub);
      }
    }
    expect(missing, isEmpty);
  });
}
