import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/downloads/download_selection.dart';
import 'package:lumtub/downloads/download_subtitles.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/player_settings.dart';
import 'package:lumtub/subtitle_cues.dart';

SubtitleCue cue(int from, int to, String text) =>
    (start: Duration(milliseconds: from), end: Duration(milliseconds: to), text: text);

void main() {
  test('a bilingual track puts each top line over the bottom line shown with it', () {
    final top = [cue(0, 2000, '你好'), cue(2000, 4000, '世界'), cue(9000, 10000, '只有上面')];
    final bottom = [cue(0, 2000, 'Hello'), cue(2000, 4010, 'world'), cue(5000, 6000, 'Only below')];
    expect(bilingualCues(top, bottom), [
      cue(0, 2000, '你好\nHello'),
      cue(2000, 4000, '世界\nworld'),
      cue(5000, 6000, 'Only below'),
      cue(9000, 10000, '只有上面'),
    ]);
  });

  test('lines that change at different times split the track where either changes', () {
    final top = [cue(0, 3000, 'A long top line')];
    final bottom = [cue(0, 1500, 'first'), cue(1500, 3000, 'second')];
    expect(bilingualCues(top, bottom),
        [cue(0, 1500, 'A long top line\nfirst'), cue(1500, 3000, 'A long top line\nsecond')]);
  });

  test('overlapping lines join in their own order, as a scan of every line joined them', () async {
    final random = Random(7);
    List<SubtitleCue> track(String name) => [
          for (var i = 0; i < 300; i++)
            if ((random.nextInt(600) * 100, random.nextInt(30) * 100)
                case (final from, final length))
              cue(from, from + length, '$name$i'),
        ];
    final top = track('t'), bottom = track('b');
    String at(List<SubtitleCue> cues, Duration from, Duration to) => [
          for (final c in cues)
            if (c.start <= from && c.end >= to) c.text
        ].join(' ');
    final marks = <Duration>{
      for (final c in [...top, ...bottom]) ...[c.start, c.end]
    }.toList()
      ..sort();
    final lines = await bilingualLinesInBackground(top, bottom);
    expect(lines, isNotEmpty);
    for (final l in lines) {
      final from = marks.firstWhere((m) => m >= l.start), to = marks.firstWhere((m) => m > from);
      expect((l.top, l.bottom), (at(top, from, to), at(bottom, from, to)));
    }
  });

  test('picks are found again, translations made from the video\'s own subtitle', () {
    final choices = SubtitleChoices(
      const [
        SubtitleOption(
            language: 'en',
            name: 'English',
            url: 'https://www.youtube.com/api/timedtext?v=x&lang=en&kind=asr',
            kind: SubtitleKind.automatic),
        SubtitleOption(
            language: 'ja', name: '日本語', url: 'https://www.youtube.com/api/timedtext?v=x&lang=ja'),
      ],
      language: 'en',
    );
    expect(choices.resolve(const SubtitlePick('ja', SubtitleKind.uploaded))!.name, '日本語');
    expect(choices.resolve(const SubtitlePick('ja', SubtitleKind.automatic)), isNull);
    final translated = choices.resolve(const SubtitlePick('zh-Hans', SubtitleKind.translated))!;
    expect(Uri.parse(translated.url).queryParameters, containsPair('tlang', 'zh-Hans'));
    expect(Uri.parse(translated.url).queryParameters, containsPair('lang', 'en'));
    expect(choices.inLanguage('ja')!.kind, SubtitleKind.uploaded);
    expect(choices.inLanguage('de')!.kind, SubtitleKind.translated);
    expect(choices.original!.language, 'en');
  });

  test('the styled copy uses the subtitle settings, the second language in its own style', () {
    const settings = PlayerSettings(
        subtitleColor: 0xFF0000, secondaryColor: 0x00FF00, secondaryOpacity: 1, subtitleBold: true);
    final ass = styledAss(
        bilingualLines(
            [cue(0, 2000, '你好')], [cue(0, 2000, 'Hello'), cue(3000, 4000, 'Only {below}')]),
        settings);
    final styles = [
      for (final l in ass.split('\n'))
        if (l.startsWith('Style: ')) l.split(',')
    ];
    expect(styles.map((s) => s[0]), ['Style: Default', 'Style: Second']);
    expect(styles[0][3], '&H000000FF', reason: 'red, as ASS writes blue first');
    expect(styles[1][3], '&H0000FF00');
    expect(styles[0][7], '-1');
    expect(
        ass, contains('Dialogue: 0,0:00:00.00,0:00:02.00,Default,,0,0,0,,你好\\N{\\rSecond}Hello\n'));
    expect(ass,
        contains('Dialogue: 0,0:00:03.00,0:00:04.00,Default,,0,0,0,,{\\rSecond}Only (below)\n'));
  });

  test('a styled ASS kept beside a download moves past stretches cut out', () {
    const ass =
        '[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
        'Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,before\n'
        'Dialogue: 0,0:00:03.00,0:00:04.00,Default,,0,0,0,,inside, cut\n'
        'Dialogue: 0,0:00:07.50,0:00:09.00,Default,,0,0,0,,after\n';
    Duration shift(Duration at) => at <= const Duration(seconds: 2)
        ? at
        : at < const Duration(seconds: 6)
            ? const Duration(seconds: 2)
            : at - const Duration(seconds: 4);
    final shifted = shiftAss(ass, shift);
    expect(shifted, contains('Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,before'));
    expect(shifted, isNot(contains('inside')));
    expect(shifted, contains('Dialogue: 0,0:00:03.50,0:00:05.00,Default,,0,0,0,,after'));
    expect(shifted, startsWith('[Events]\nFormat:'));
  });
}
