import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/downloads/download_selection.dart';
import 'package:lumtub/downloads/download_subtitles.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/player_settings.dart';
import 'package:lumtub/subtitle_cues.dart';

SubtitleCue cue(int from, int to, String text) => (start: Duration(milliseconds: from), end: Duration(milliseconds: to), text: text);

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
    expect(bilingualCues(top, bottom), [cue(0, 1500, 'A long top line\nfirst'), cue(1500, 3000, 'A long top line\nsecond')]);
  });

  test('picks are found again, translations made from the video\'s own subtitle', () {
    final choices = SubtitleChoices(
      const [
        SubtitleOption(language: 'en', name: 'English', url: 'https://www.youtube.com/api/timedtext?v=x&lang=en&kind=asr', kind: SubtitleKind.automatic),
        SubtitleOption(language: 'ja', name: '日本語', url: 'https://www.youtube.com/api/timedtext?v=x&lang=ja'),
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
    const settings = PlayerSettings(subtitleColor: 0xFF0000, secondaryColor: 0x00FF00, secondaryOpacity: 1, subtitleBold: true);
    final ass = styledAss(bilingualLines([cue(0, 2000, '你好')], [cue(0, 2000, 'Hello'), cue(3000, 4000, 'Only {below}')]), settings);
    final styles = [for (final l in ass.split('\n')) if (l.startsWith('Style: ')) l.split(',')];
    expect(styles.map((s) => s[0]), ['Style: Default', 'Style: Second']);
    expect(styles[0][3], '&H000000FF', reason: 'red, as ASS writes blue first');
    expect(styles[1][3], '&H0000FF00');
    expect(styles[0][7], '-1');
    expect(ass, contains('Dialogue: 0,0:00:00.00,0:00:02.00,Default,,0,0,0,,你好\\N{\\rSecond}Hello\n'));
    expect(ass, contains('Dialogue: 0,0:00:03.00,0:00:04.00,Default,,0,0,0,,{\\rSecond}Only (below)\n'));
  });
}
