import 'package:flutter_test/flutter_test.dart';
import 'package:ytplus/models.dart';

void main() {
  test('yt-dlp flat search entries become video cards', () {
    const jsonLine = '{"id":"dQw4w9WgXcQ","title":"Example","channel":"Demo","duration":125}';
    final videos = VideoItem.fromJsonLines('$jsonLine\n');
    expect(videos, hasLength(1));
    expect(videos.first.url, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    expect(videos.first.durationLabel, '2:05');
    expect(videos.first.channel, 'Demo');
  });

  test('duplicates and non-video entries are skipped', () {
    const valid = '{"id":"dQw4w9WgXcQ","title":"Example","channel":"Demo"}';
    final videos = VideoItem.fromJsonLines('$valid\n$valid\n{"id":"playlist"}\n');
    expect(videos, hasLength(1));
  });
}
