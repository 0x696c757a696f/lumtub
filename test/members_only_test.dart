import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/youtube_related.dart';

void main() {
  test("reads yt-dlp's subscriber_only availability and keeps it", () {
    final item = VideoItem.fromJson({'id': 'aaaaaaaaaaa', 'title': 'Members', 'availability': 'subscriber_only'});
    expect(item.membersOnly, isTrue);
    expect(VideoItem.fromJson(item.toJson()).membersOnly, isTrue);
    expect(item.withLiveStatus('is_live').membersOnly, isTrue);
    expect(item.withChannel(const ChannelRef('UCabcdefghijklmnopqrstuv', 'Chan')).membersOnly, isTrue);
    expect(VideoItem.fromJson({'id': 'bbbbbbbbbbb', 'title': 'Public', 'availability': 'public'}).membersOnly, isFalse);
    expect(VideoItem.fromJson({'id': 'ccccccccccc', 'title': 'Old'}).toJson().containsKey('availability'), isFalse);
  });

  test('reads the mark the native core gives', () {
    expect(videoFromCore({'id': 'aaaaaaaaaaa', 'title': 'T', 'channel': 'C', 'live': false, 'membersOnly': true}).membersOnly, isTrue);
    expect(videoFromCore({'id': 'aaaaaaaaaaa', 'title': 'T', 'channel': 'C', 'live': false}).membersOnly, isFalse);
  });
}
