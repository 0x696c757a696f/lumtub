import 'dart:io';
import 'dart:isolate';

import '../native_core.dart';
import 'anki_card.dart';
import 'anki_connect.dart' show AnkiPicture;
import 'vocabulary.dart';

/// Writes [words] to [out] as an Anki package (.apkg): the Lumtub deck,
/// the Lumtub note type and a note for each word, with the sound of its
/// line and the picture of its video where there are. Opening the file
/// in Anki imports it; importing it again updates the same notes.
/// Null, or why it could not.
Future<String?> writeAnkiPackage(List<VocabularyWord> words, VocabularyBook book, File out,
    {AnkiPicture? picture}) async {
  final scratch = await Directory.systemTemp.createTemp('lumtub-anki');
  try {
    final media = <Map<String, String>>[];
    final pictures = <String, String>{};
    final notes = <Map<String, Object?>>[];
    for (final w in words) {
      var audio = '';
      final sound = book.soundOf(w.key);
      if (await sound.exists()) {
        audio = AnkiCard.soundName(w);
        media.add({'name': audio, 'path': sound.path});
      }
      var image = '';
      if (picture != null && w.videoId.isNotEmpty) {
        if (!pictures.containsKey(w.videoId)) {
          final file = await picture(w.videoId).catchError((Object _) => null);
          var name = '';
          if (file != null && file.bytes.isNotEmpty) {
            name = AnkiCard.pictureName(w.videoId, webp: file.webp);
            final path = '${scratch.path}${Platform.pathSeparator}$name';
            await File(path).writeAsBytes(file.bytes);
            media.add({'name': name, 'path': path});
          }
          pictures[w.videoId] = name;
        }
        image = pictures[w.videoId]!;
      }
      final fields = AnkiCard.noteFields(w, audio: audio, picture: image);
      notes.add({
        'guid': AnkiCard.guid(w),
        'fields': [for (final name in AnkiCard.fields) fields[name] ?? ''],
        'tags': AnkiCard.tags(w),
        'modified': w.added.millisecondsSinceEpoch ~/ 1000,
      });
    }
    final package = {
      'out': out.path,
      'model': {
        'id': AnkiCard.modelId,
        'name': AnkiCard.modelName,
        'fields': AnkiCard.fields,
        'templates': [
          {'name': AnkiCard.cardName, 'front': AnkiCard.front, 'back': AnkiCard.back},
        ],
        'css': AnkiCard.css,
      },
      'deck': {'id': AnkiCard.deckId, 'name': AnkiCard.deckName},
      'notes': notes,
      'media': media,
    };
    return await Isolate.run(() => NativeCore.ankiPackage(package));
  } finally {
    await scratch.delete(recursive: true).catchError((Object _) => scratch);
  }
}

/// Whether [bytes] are a WebP picture rather than a JPEG.
bool isWebp(List<int> bytes) =>
    bytes.length > 12 &&
    String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
    String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
