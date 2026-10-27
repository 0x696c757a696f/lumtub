import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/app/app_controller.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/player_option_applicator.dart';
import 'package:lumtub/player_settings.dart';

void main() {
  const en = SubtitleOption(language: 'en', name: 'English', url: 'https://yt.example/en.vtt');
  const jaAuto = SubtitleOption(language: 'ja', name: '', url: 'https://yt.example/ja.vtt', kind: SubtitleKind.automatic);
  const zh = SubtitleOption(language: 'zh-Hans', name: '', url: 'https://yt.example/ja.vtt&tlang=zh-Hans', kind: SubtitleKind.translated);

  late AppController controller;
  setUp(() {
    controller = AppController();
    controller.details = const VideoDetails(title: 't', channel: 'c', language: 'ja', subtitles: [en, jaAuto, zh]);
  });

  test('the first subtitle chosen comes back on the next video', () async {
    await controller.rememberSubtitleChoice(primary: true, option: jaAuto);
    expect(controller.settings.subtitleMode, SubtitleMode.always);
    expect(controller.settings.subtitleOriginal, isTrue);
    expect(PlayerOptionApplicator.ytdlRawOptions(controller.settings), contains('sub-langs=.*-orig'));

    await controller.rememberSubtitleChoice(primary: true, option: en);
    expect(controller.settings.subtitleOriginal, isFalse);
    expect(controller.settings.subtitleLanguage.resolved, SubtitleLanguage.en);

    await controller.rememberSubtitleChoice(primary: true);
    expect(controller.settings.subtitleMode, SubtitleMode.off);
  });

  test('the second subtitle chosen comes back too, and turns subtitles on', () async {
    await controller.rememberSubtitleChoice(primary: false, option: zh);
    expect(controller.settings.secondarySubtitleLanguage, 'zh-CN');
    expect(controller.settings.subtitleMode, SubtitleMode.always);
    await controller.rememberSubtitleChoice(primary: false, option: jaAuto);
    expect(controller.settings.secondarySubtitleLanguage, PlayerSettings.originalSubtitle);
    await controller.rememberSubtitleChoice(primary: false);
    expect(controller.settings.secondarySubtitleLanguage, '');
  });

  test('the original-language choice survives a restart', () {
    final saved = const PlayerSettings(subtitleOriginal: true).toJson();
    expect(PlayerSettings.fromJson(saved).subtitleOriginal, isTrue);
  });
}
