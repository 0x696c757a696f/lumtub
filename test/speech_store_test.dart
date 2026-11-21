import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/local_db.dart';
import 'package:lumtub/speech_subtitles.dart';

void main() {
  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('lumtub-speech-store'));
  tearDown(() => root.delete(recursive: true));

  Directory sub(String name) => Directory('${root.path}${Platform.pathSeparator}$name');

  test('without the database recognized subtitles stay files', () async {
    final store = SpeechSubtitleStore(sub('speech'), keep: 2);
    await store.save('aaaaaaaaaaa', 'en', 'WEBVTT\n\nA');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await store.save('bbbbbbbbbbb', 'en', 'WEBVTT\n\nB');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await store.save('ccccccccccc', 'ja', 'WEBVTT\n\nC');
    expect(await store.of('aaaaaaaaaaa'), isNull);
    final found = await store.of('ccccccccccc');
    expect(found!.language, 'ja');
    expect(await found.file.readAsString(), 'WEBVTT\n\nC');
  });

  group('in lumtub.db', () {
    LocalDb.enabledForTesting = true;
    final skip = LocalDbTexts.available ? false : 'needs lumtub_core (LUMTUB_CORE_DLL)';

    test('they are kept as machine-made and read back for the player', () async {
      final db = LocalDb('${sub('data').path}${Platform.pathSeparator}lumtub.db');
      await sub('data').create();
      final store = SpeechSubtitleStore(sub('speech'), db: db, cache: sub('cache'));
      final file = await store.save('aaaaaaaaaaa', 'en', 'WEBVTT\n\nA', model: 'whisper-1');
      expect(file.path, startsWith(sub('cache').path));
      expect(sub('speech').existsSync(), isFalse);
      await file.delete();
      final found = await store.of('aaaaaaaaaaa');
      expect(found!.language, 'en');
      expect(await found.file.readAsString(), 'WEBVTT\n\nA');
      final kept = await db.transcripts('aaaaaaaaaaa');
      expect(kept.single.origin, 'machine-cloud');
      expect(kept.single.model, 'whisper-1');
    }, skip: skip);

    test('files from before the database are moved into it', () async {
      await sub('data').create();
      await sub('speech').create();
      await File('${sub('speech').path}${Platform.pathSeparator}aaaaaaaaaaa.de.vtt').writeAsString('WEBVTT\n\nalt');
      final db = LocalDb('${sub('data').path}${Platform.pathSeparator}lumtub.db');
      final store = SpeechSubtitleStore(sub('speech'), db: db, cache: sub('cache'));
      final found = await store.of('aaaaaaaaaaa');
      expect(found!.language, 'de');
      expect(await found.file.readAsString(), 'WEBVTT\n\nalt');
      expect(sub('speech').listSync(), isEmpty);
      expect((await db.transcripts('aaaaaaaaaaa')).single.body, 'WEBVTT\n\nalt');
    }, skip: skip);

    test('summaries round-trip by video and language', () async {
      await sub('data').create();
      final db = LocalDb('${sub('data').path}${Platform.pathSeparator}lumtub.db');
      expect(await db.summary('v', 'zh-Hans'), isNull);
      await db.putSummary('v', 'zh-Hans', 'cloud:deepseek-chat', '要点');
      expect(await db.summary('v', 'zh-Hans'), '要点');
      expect(await db.summary('v', 'en'), isNull);
      await db.forgetSummaries(video: 'v');
      expect(await db.summary('v', 'zh-Hans'), isNull);
    }, skip: skip);
  });
}
