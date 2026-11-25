import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'anki_card.dart';
import 'vocabulary.dart';

/// Why words could not go to Anki.
class AnkiException implements Exception {
  const AnkiException(this.notRunning, [this.detail = '']);

  /// Anki is not open, or AnkiConnect is not installed.
  final bool notRunning;
  final String detail;

  @override
  String toString() => notRunning ? 'Anki is not reachable' : detail;
}

/// A video's picture for a card: its bytes, and whether they are WebP.
typedef AnkiPictureFile = ({List<int> bytes, bool webp});

/// The picture of the video [videoId], or null when there is none.
typedef AnkiPicture = Future<AnkiPictureFile?> Function(String videoId);

/// Sends vocabulary words straight into Anki through the AnkiConnect
/// add-on (code 2055492159), which listens on this computer only. Each
/// word becomes a note of the Lumtub note type ([AnkiCard]) in the deck
/// [deck], with the line it was heard in as sound where the book kept it.
class AnkiConnect {
  AnkiConnect({http.Client? client}) : _client = client ?? http.Client();

  static final _address = Uri.parse('http://127.0.0.1:8765');
  final http.Client _client;

  Future<Object?> _call(String action, [Map<String, Object?> params = const {}]) async {
    final http.Response response;
    try {
      response = await _client
          .post(_address, headers: {'Content-Type': 'application/json'}, body: jsonEncode({'action': action, 'version': 6, 'params': params}))
          .timeout(const Duration(seconds: 30));
    } on SocketException {
      throw const AnkiException(true);
    } on http.ClientException {
      throw const AnkiException(true);
    }
    if (response.statusCode != 200 || response.bodyBytes.length > 4 << 20) throw AnkiException(false, 'AnkiConnect HTTP ${response.statusCode}');
    final answer = jsonDecode(utf8.decode(response.bodyBytes));
    if (answer is! Map) throw const AnkiException(false, 'AnkiConnect answered oddly');
    if (answer['error'] case final String error) throw AnkiException(false, error);
    return answer['result'];
  }

  /// Makes sure Anki has the Lumtub note type with every field, and
  /// brings its style and templates up to date unless someone changed
  /// them (they deleted [AnkiCard.styleMarker]).
  Future<void> _noteType() async {
    final names = await _call('modelNames');
    if (names is! List) throw const AnkiException(false, 'No note types');
    if (!names.contains(AnkiCard.modelName)) {
      await _call('createModel', {
        'modelName': AnkiCard.modelName,
        'inOrderFields': AnkiCard.fields,
        'css': AnkiCard.css,
        'isCloze': false,
        'cardTemplates': [
          {'Name': AnkiCard.cardName, 'Front': AnkiCard.front, 'Back': AnkiCard.back},
        ],
      });
      return;
    }
    final fields = await _call('modelFieldNames', {'modelName': AnkiCard.modelName});
    if (fields is! List) throw const AnkiException(false, 'The Lumtub note type has no fields');
    for (final (i, field) in AnkiCard.fields.indexed) {
      if (!fields.contains(field)) await _call('modelFieldAdd', {'modelName': AnkiCard.modelName, 'fieldName': field, 'index': i});
    }
    final styling = await _call('modelStyling', {'modelName': AnkiCard.modelName});
    final css = styling is Map ? styling['css'] : null;
    if (css is String && css != AnkiCard.css && css.startsWith(AnkiCard.styleMarker.substring(0, 21))) {
      await _call('updateModelStyling', {
        'model': {'name': AnkiCard.modelName, 'css': AnkiCard.css},
      });
      final templates = await _call('modelTemplates', {'modelName': AnkiCard.modelName});
      if (templates is Map && templates.length == 1) {
        await _call('updateModelTemplates', {
          'model': {
            'name': AnkiCard.modelName,
            'templates': {
              templates.keys.first: {'Front': AnkiCard.front, 'Back': AnkiCard.back},
            },
          },
        });
      }
    }
  }

  /// Sends [words]; the number added. Words already in the deck are left.
  /// [picture] gives the picture of a video, when there is one.
  Future<int> send(List<VocabularyWord> words, VocabularyBook book, {String deck = AnkiCard.deckName, AnkiPicture? picture}) async {
    if (words.isEmpty) return 0;
    await _call('version');
    await _call('createDeck', {'deck': deck});
    await _noteType();
    final notes = <Map<String, Object?>>[
      for (final w in words)
        {
          'deckName': deck,
          'modelName': AnkiCard.modelName,
          'fields': AnkiCard.noteFields(w),
          'tags': AnkiCard.tags(w),
          'options': {'allowDuplicate': false, 'duplicateScope': 'deck'},
        },
    ];
    final can = await _call('canAddNotes', {'notes': notes});
    final fresh = [for (final (i, note) in notes.indexed) if (can is List && i < can.length && can[i] == true) (words[i], note)];
    if (fresh.isEmpty) return 0;
    // Sounds are read only for the words Anki does not have yet.
    for (final (w, note) in fresh) {
      final sound = book.soundOf(w.key);
      if (!await sound.exists()) continue;
      note['audio'] = [
        {'data': base64Encode(await sound.readAsBytes()), 'filename': AnkiCard.soundName(w), 'fields': ['Audio']},
      ];
    }
    if (picture != null) {
      final pictures = <String, AnkiPictureFile?>{};
      for (final (w, note) in fresh) {
        if (w.videoId.isEmpty) continue;
        final file = pictures.containsKey(w.videoId) ? pictures[w.videoId] : pictures[w.videoId] = await picture(w.videoId);
        if (file == null) continue;
        note['picture'] = [
          {'data': base64Encode(file.bytes), 'filename': AnkiCard.pictureName(w.videoId, webp: file.webp), 'fields': ['Picture']},
        ];
      }
    }
    final added = await _call('addNotes', {'notes': [for (final (_, note) in fresh) note]});
    return added is List ? added.where((id) => id != null).length : 0;
  }

  void close() => _client.close();
}
