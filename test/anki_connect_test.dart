import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lumtub/learning/anki_connect.dart';
import 'package:lumtub/learning/vocabulary.dart';

Uint8List wav(int rate, int samples, {int dataSize = -1}) {
  final pcm = Uint8List(samples * 2);
  for (var i = 0; i < samples; i++) {
    pcm[i * 2] = i & 0xff;
  }
  final b = BytesBuilder()
    ..add(ascii.encode('RIFF'))
    ..add(Uint8List(4))
    ..add(ascii.encode('WAVE'))
    ..add(ascii.encode('fmt '))
    ..add((ByteData(4)..setUint32(0, 16, Endian.little)).buffer.asUint8List())
    ..add((ByteData(16)
          ..setUint16(0, 1, Endian.little)
          ..setUint16(2, 1, Endian.little)
          ..setUint32(4, rate, Endian.little)
          ..setUint32(8, rate * 2, Endian.little)
          ..setUint16(12, 2, Endian.little)
          ..setUint16(14, 16, Endian.little))
        .buffer
        .asUint8List())
    ..add(ascii.encode('data'))
    ..add((ByteData(4)..setUint32(0, dataSize < 0 ? pcm.length : dataSize, Endian.little)).buffer.asUint8List())
    ..add(pcm);
  return b.toBytes();
}

void main() {
  test('a WAV file keeps its last seconds', () {
    final whole = wav(1000, 3000);
    final tail = Uint8List.fromList(wavTail(whole, 1.0));
    expect(tail.length, 44 + 2000);
    expect(ascii.decode(tail.sublist(36, 40)), 'data');
    expect(ByteData.sublistView(tail).getUint32(40, Endian.little), 2000);
    expect(ByteData.sublistView(tail).getUint32(4, Endian.little), tail.length - 8);
    // The last sample stays the last.
    expect(tail[tail.length - 2], (2999) & 0xff);
    // A size of 0, as a file written while playing may say, reads to the end.
    expect(wavTail(wav(1000, 3000, dataSize: 0), 0.5).length, 44 + 1000);
    expect(wavTail([1, 2, 3], 1), [1, 2, 3]);
  });

  test('words go to Anki through AnkiConnect, with their line', () async {
    final folder = await Directory.systemTemp.createTemp('lumtub-anki');
    addTearDown(() => folder.delete(recursive: true));
    final book = VocabularyBook(File('${folder.path}/vocabulary.json'));
    final word = VocabularyWord(word: 'docteur', language: 'fr', meaning: 'n. 医生', sentence: 'docteur en neurosciences', videoId: 'abc', videoTitle: 'T', at: const Duration(seconds: 9), added: DateTime(2026));
    final other = VocabularyWord(word: 'main', language: 'fr', meaning: 'n. 手', added: DateTime(2026));
    await book.add(word);
    await book.add(other);
    final sound = book.soundOf(word.key);
    await sound.parent.create(recursive: true);
    await sound.writeAsBytes(wav(100, 10));

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final asked = <Map>[];
    server.listen((request) async {
      final body = jsonDecode(await utf8.decodeStream(request)) as Map;
      asked.add(body);
      final params = body['params'] as Map;
      final result = switch (body['action']) {
        'version' => 6,
        'createDeck' => 1,
        'modelNames' => ['Cloze', '问答题'],
        'modelFieldNames' => params['modelName'] == '问答题' ? ['正面', '背面'] : ['Text', 'Extra', 'More'],
        'canAddNotes' => [true, false],
        'addNotes' => [111],
        _ => null,
      };
      request.response.write(jsonEncode({'result': result, 'error': null}));
      await request.response.close();
    });
    final anki = AnkiConnect(client: _Redirect(server.port));
    expect(await anki.send(book.words, book), 1);
    final add = asked.firstWhere((a) => a['action'] == 'addNotes')['params']['notes'] as List;
    expect(add, hasLength(1));
    final note = add.single as Map;
    expect(note['modelName'], '问答题');
    // Newest first: 'main' then 'docteur'; canAddNotes kept the first.
    expect((note['fields'] as Map)['正面'], 'main');
    final docteur = (asked.firstWhere((a) => a['action'] == 'canAddNotes')['params']['notes'] as List)[1] as Map;
    expect((docteur['audio'] as List).single['fields'], ['背面']);
    expect((docteur['fields'] as Map)['背面'], contains('docteur en neurosciences'));
  });

  test('Anki not running reads as such', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close();
    final anki = AnkiConnect(client: _Redirect(port));
    final folder = await Directory.systemTemp.createTemp('lumtub-anki');
    addTearDown(() => folder.delete(recursive: true));
    final book = VocabularyBook(File('${folder.path}/v.json'));
    await expectLater(
      anki.send([VocabularyWord(word: 'x', language: 'fr', added: DateTime(2026))], book),
      throwsA(isA<AnkiException>().having((e) => e.notRunning, 'notRunning', true)),
    );
  });
}

/// Sends AnkiConnect's requests to a test server's port.
class _Redirect extends http.BaseClient {
  _Redirect(this.port);
  final int port;
  final _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final moved = http.Request(request.method, request.url.replace(port: port))
      ..headers.addAll(request.headers)
      ..bodyBytes = (request as http.Request).bodyBytes;
    return _inner.send(moved);
  }
}
