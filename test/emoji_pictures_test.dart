import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/emoji_pictures.dart';

void main() {
  tearDown(EmojiPictures.reset);

  test("YouTube's own emoji written without a picture take one seen before", () {
    expect(EmojiPictures.fill('hi :face-red-heart-shape:', const {}), isEmpty);
    EmojiPictures.learn({':face-red-heart-shape:': 'https://yt3/heart', ':_channel:': 'https://yt3/c'});
    expect(EmojiPictures.fill('谢谢:face-red-heart-shape:', const {}), {':face-red-heart-shape:': 'https://yt3/heart'});
    // A channel's own emoji means something else on each channel.
    expect(EmojiPictures.fill('a :_channel:', const {}), isEmpty);
    final given = {':x:': 'https://yt3/x'};
    expect(EmojiPictures.fill('no shortcut here', given), same(given));
  });

  test('what was learned is read back next time', () async {
    final dir = await Directory.systemTemp.createTemp('emoji');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/emoji_pictures.json');
    await file.writeAsString('{":hand-pink-waving:": "https://yt3/wave", "bad": 3}');
    await EmojiPictures.configure(file);
    expect(EmojiPictures.fill(':hand-pink-waving:', const {}), {':hand-pink-waving:': 'https://yt3/wave'});
  });
}
