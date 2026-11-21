import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

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

/// Sends vocabulary words straight into Anki through the AnkiConnect
/// add-on (code 2055492159), which listens on this computer only. Each
/// word becomes a two-sided note in the deck [deck], with the line it
/// was heard in as sound where the book kept it.
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

  /// A note type with two fields, Basic by preference (named in Anki's
  /// own language), and its fields.
  Future<(String, List<String>)> _noteType() async {
    final names = await _call('modelNames');
    if (names is! List) throw const AnkiException(false, 'No note types');
    const preferred = ['Basic', '问答题', '問答題', 'Basique', 'Básico', 'Einfach', 'Base', 'Базовый', '基本'];
    final ordered = [...preferred.where(names.contains), ...names.whereType<String>().where((n) => !preferred.contains(n))];
    for (final name in ordered.take(12)) {
      final fields = await _call('modelFieldNames', {'modelName': name});
      if (fields is List && fields.length == 2 && fields.every((f) => f is String)) return (name, fields.cast<String>());
    }
    throw const AnkiException(false, 'No note type with two fields');
  }

  /// Sends [words]; the number added. Words already in the deck are left.
  Future<int> send(List<VocabularyWord> words, VocabularyBook book, {String deck = 'Lumtub'}) async {
    if (words.isEmpty) return 0;
    await _call('version');
    await _call('createDeck', {'deck': deck});
    final (type, fields) = await _noteType();
    String html(String text) => const HtmlEscape(HtmlEscapeMode.element).convert(text).replaceAll('\n', '<br>');
    final notes = <Map<String, Object?>>[];
    for (final w in words) {
      final front = w.reading.isEmpty || w.reading == w.word ? html(w.word) : '${html(w.word)}<br><small>${html(w.reading)}</small>';
      final back = [
        if (w.meaning.isNotEmpty) html(w.meaning),
        if (w.sentence.isNotEmpty) '<br>${html(w.sentence)}',
        if (w.translation.isNotEmpty) '<small>${html(w.translation)}</small>',
        if (w.link.isNotEmpty) '<small><a href="${html(w.link)}">${html(w.videoTitle.isEmpty ? w.link : w.videoTitle)}</a></small>',
      ].join('<br>');
      final sound = book.soundOf(w.key);
      notes.add({
        'deckName': deck,
        'modelName': type,
        'fields': {fields[0]: front, fields[1]: back},
        'tags': ['lumtub', w.language],
        'options': {'allowDuplicate': false, 'duplicateScope': 'deck'},
        if (await sound.exists())
          'audio': [
            {'data': base64Encode(await sound.readAsBytes()), 'filename': 'lumtub-${sound.uri.pathSegments.last}', 'fields': [fields[1]]},
          ],
      });
    }
    final can = await _call('canAddNotes', {'notes': notes});
    final fresh = [for (final (i, note) in notes.indexed) if (can is List && i < can.length && can[i] == true) note];
    if (fresh.isEmpty) return 0;
    final added = await _call('addNotes', {'notes': fresh});
    return added is List ? added.where((id) => id != null).length : 0;
  }

  /// Sends one sentence card: [front] (the line, with its [sound] when
  /// kept) and [back] (its explanation), both plain text. False when the
  /// same card is in the deck already.
  Future<bool> sendSentence({required String front, required String back, File? sound, String language = '', String deck = 'Lumtub'}) async {
    await _call('version');
    await _call('createDeck', {'deck': deck});
    final (type, fields) = await _noteType();
    String html(String text) => const HtmlEscape(HtmlEscapeMode.element).convert(text).replaceAll('\n', '<br>');
    final note = {
      'deckName': deck,
      'modelName': type,
      'fields': {fields[0]: html(front), fields[1]: html(back)},
      'tags': ['lumtub', 'sentence', if (language.isNotEmpty) language],
      'options': {'allowDuplicate': false, 'duplicateScope': 'deck'},
      if (sound != null && await sound.exists())
        'audio': [
          {'data': base64Encode(await sound.readAsBytes()), 'filename': 'lumtub-${sound.uri.pathSegments.last}', 'fields': [fields[0]]},
        ],
    };
    final can = await _call('canAddNotes', {'notes': [note]});
    if (can is! List || can.isEmpty || can.first != true) return false;
    await _call('addNote', {'note': note});
    return true;
  }

  void close() => _client.close();
}
