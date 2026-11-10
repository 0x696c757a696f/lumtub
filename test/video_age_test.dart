import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/ui/video_card.dart';
import 'package:lumtub/youtube_related.dart';

void main() {
  test('a related video keeps the age YouTube wrote and shows it after its views', () {
    final item = videoFromCore({'id': 'aaaaaaaaaaa', 'title': 'T', 'channel': 'C', 'live': false, 'viewCount': 1000, 'age': '3 days ago'});
    expect(item.age, '3 days ago');
    expect(VideoItem.fromJson(item.toJson()).age, '3 days ago');
    expect(MetaLine.of(item, style: const TextStyle()).tail, endsWith('3 days ago'));
    final live = videoFromCore({'id': 'aaaaaaaaaaa', 'title': 'T', 'channel': 'C', 'live': true, 'age': '3 days ago'});
    expect(MetaLine.of(live, style: const TextStyle()).tail, isNot(contains('ago')));
  });
}
