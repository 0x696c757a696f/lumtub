import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/portrait_thumbnails.dart';

/// A 160×120 thumbnail: noise where [busy] says, flat grey elsewhere.
Uint8List picture(bool Function(int x, int y) busy) {
  const w = PortraitThumbnails.width, h = PortraitThumbnails.height;
  final random = Random(7);
  final rgba = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = busy(x, y) ? random.nextInt(256) : 40;
      rgba.setAll((y * w + x) * 4, [v, v, v, 255]);
    }
  }
  return rgba;
}

String line(String id) => jsonEncode({'_type': 'url', 'ie_key': 'Youtube', 'id': id, 'title': id, 'url': 'https://www.youtube.com/watch?v=$id'});

void main() {
  const w = PortraitThumbnails.width, h = PortraitThumbnails.height;

  test('a portrait frame between flat or blurred sides is told apart from an ordinary picture', () {
    expect(PortraitThumbnails.judge(picture((x, y) => x > w * 0.34 && x < w * 0.66), w, h), isTrue);
    // A blurred background still changes a little.
    expect(PortraitThumbnails.judge(picture((x, y) => (x > w * 0.34 && x < w * 0.66) || (x + y) % 23 == 0), w, h), isTrue);
    expect(PortraitThumbnails.judge(picture((x, y) => true), w, h), isFalse);
    // Busy on one side only, as a speaker beside a slide.
    expect(PortraitThumbnails.judge(picture((x, y) => x > w * 0.3), w, h), isFalse);
    // A flat title card says nothing either way.
    expect(PortraitThumbnails.judge(picture((x, y) => false), w, h), isFalse);
  });

  test('portrait videos leave a listing in order, other lines stay, and few thumbnails are looked at once', () async {
    final asked = <String>[];
    var open = 0, most = 0;
    final answers = <String, Completer<bool>>{};
    Future<bool> portrait(String id) {
      asked.add(id);
      open++;
      most = max(most, open);
      return (answers[id] = Completer<bool>()).future.whenComplete(() => open--);
    }

    final ids = [for (var i = 0; i < 12; i++) 'video${i.toString().padLeft(6, '0')}'];
    final source = StreamController<String>();
    final shown = <String>[];
    final done = Completer<void>();
    PortraitThumbnails.drop(source.stream, portrait, parallel: 3).listen(shown.add, onDone: done.complete);
    for (final id in ids) {
      source.add(line(id));
    }
    source.add('{"_type": "playlist"}');
    unawaited(source.close());
    // Answered last to first: nothing shows until the first is answered.
    for (var round = 0; round < 10 && asked.length < ids.length; round++) {
      await pumpEventQueue();
      for (final id in asked.reversed) {
        final answer = answers[id]!;
        if (!answer.isCompleted) answer.complete(ids.indexOf(id).isOdd);
      }
    }
    await done.future;
    expect(most, lessThanOrEqualTo(3));
    expect(shown, [for (final (i, id) in ids.indexed) if (i.isEven) line(id), '{"_type": "playlist"}']);
  });

  test('a thumbnail that fails to load or check keeps its video', () async {
    final shown = await PortraitThumbnails.drop(Stream.fromIterable([line('aaaaaaaaaaa'), line('bbbbbbbbbbb')]), (id) async => id.startsWith('a') ? throw StateError('offline') : false).toList();
    expect(shown, hasLength(2));
  });
}
