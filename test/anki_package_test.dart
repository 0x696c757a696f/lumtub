import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/learning/anki_card.dart';
import 'package:lumtub/learning/anki_package.dart';
import 'package:lumtub/learning/vocabulary.dart';
import 'package:lumtub/native_core.dart';
import 'package:lumtub/zip_archive.dart';

void main() {
  test('the book becomes an Anki package with sound and pictures', () async {
    final folder = await Directory.systemTemp.createTemp('lumtub-apkg');
    addTearDown(() => folder.delete(recursive: true));
    final book = VocabularyBook(File('${folder.path}/vocabulary.json'));
    final word = VocabularyWord(
        word: '学习',
        language: 'zh',
        reading: 'xué xí',
        meaning: 'to study',
        sentence: '我们一起学习吧',
        videoId: 'abcdefghijk',
        videoTitle: 'T',
        at: const Duration(seconds: 75),
        added: DateTime(2026));
    await book.add(word);
    await book.add(VocabularyWord(
        word: 'main',
        language: 'fr',
        meaning: 'n. 手',
        videoId: 'abcdefghijk',
        added: DateTime(2026)));
    final sound = book.soundOf(word.key);
    await sound.parent.create(recursive: true);
    await sound.writeAsBytes(Uint8List.fromList(ascii.encode('RIFF....WAVEfmt ')));
    final out = File('${folder.path}/book.apkg');
    final asked = <String>[];
    final webp = ascii.encode('RIFF....WEBPVP8 ');
    final error = await writeAnkiPackage(book.words, book, out, picture: (id) async {
      asked.add(id);
      return (bytes: webp, webp: isWebp(webp));
    });
    expect(error, isNull);
    // One picture per video, however many words come from it.
    expect(asked, ['abcdefghijk']);
    final unpacked = Directory('${folder.path}/unpacked');
    final names = await extractZip(out, unpacked);
    expect(names.toSet(), {'collection.anki2', 'media', '0', '1'});
    final media = jsonDecode(await File('${unpacked.path}/media').readAsString()) as Map;
    expect(media.values.toSet(), {AnkiCard.soundName(word), 'lumtub-abcdefghijk.webp'});
  }, skip: NativeCore.instance == null ? 'needs LUMTUB_CORE_DLL' : null);

  test('the note fields keep their HTML safe', () {
    final fields = AnkiCard.noteFields(
      VocabularyWord(
          word: '<i>',
          language: 'en',
          meaning: 'a\nb',
          videoId: 'abcdefghijk',
          videoTitle: '"x" & <y>',
          at: const Duration(seconds: 3),
          added: DateTime(2026)),
      audio: 'a.wav',
      picture: 'p.jpg',
    );
    expect(fields['Word'], '&lt;i&gt;');
    expect(fields['Meaning'], 'a<br>b');
    expect(fields['Video'], '"x" &amp; &lt;y&gt;');
    expect(fields['Link'], 'https://www.youtube.com/watch?v=abcdefghijk&amp;t=2s');
    expect(fields['Audio'], '[sound:a.wav]');
    expect(fields['Picture'], '<img src="p.jpg">');
    expect(fields.keys, AnkiCard.fields);
  });
}
