import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/native_core.dart';
import 'package:lumtub/video_repository.dart';
import 'package:lumtub/youtube_listing.dart';

Map<String, Object> _video(String id) => {
      'videoRenderer': {
        'videoId': id,
        'title': {'runs': [{'text': 'Video $id'}]},
        'ownerText': {'runs': [{'text': 'Chan'}]},
        'shortBylineText': {'runs': [{'text': 'Chan', 'navigationEndpoint': {'browseEndpoint': {'browseId': 'UCxxxxxxxxxxxxxxxxxxxxxx'}}}]},
        'lengthText': {'simpleText': '1:05'},
        'viewCountText': {'simpleText': '1,234 views'},
      },
    };

void main() {
  final skip = NativeCore.instance == null ? 'needs lumtub_core (LUMTUB_CORE_DLL)' : null;

  test('searches page by page through the web API', () async {
    final bodies = <Map>[];
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map;
      bodies.add(body);
      expect(request.url.path, '/youtubei/v1/search');
      if (body['continuation'] == null) {
        return http.Response(jsonEncode({
          'contents': {'twoColumnSearchResultsRenderer': {'primaryContents': {'sectionListRenderer': {'contents': [
            {'itemSectionRenderer': {'contents': [_video('aaaaaaaaaaa'), _video('bbbbbbbbbbb')]}},
            {'continuationItemRenderer': {'continuationEndpoint': {'continuationCommand': {'token': 'NEXT'}}}},
          ]}}}},
        }), 200);
      }
      return http.Response(jsonEncode({
        'onResponseReceivedCommands': [{'appendContinuationItemsAction': {'continuationItems': [
          {'itemSectionRenderer': {'contents': [_video('bbbbbbbbbbb'), _video('ccccccccccc')]}},
        ]}}],
      }), 200);
    });
    final repository = VideoRepository('/no/yt-dlp', client: client);
    final listing = repository.search(' cats ', filter: SearchFilter.videos, region: 'jp');
    final items = (await listing.next(10).toList()).cast<VideoItem>();
    expect(items.map((v) => v.id), ['aaaaaaaaaaa', 'bbbbbbbbbbb', 'ccccccccccc']);
    expect((items.first.title, items.first.channel, items.first.channelId, items.first.duration, items.first.viewCount), ('Video aaaaaaaaaaa', 'Chan', 'UCxxxxxxxxxxxxxxxxxxxxxx', 65, 1234));
    expect(bodies.first['query'], 'cats');
    expect(bodies.first['params'], 'EgIQAQ%3D%3D');
    expect((bodies.first['context'] as Map)['client'], containsPair('gl', 'JP'));
    expect(bodies.last['continuation'], 'NEXT');
    expect(listing.done, isTrue);
  }, skip: skip);

  test('reads a channel tab with its params', () async {
    String? params;
    final client = MockClient((request) async {
      params = (jsonDecode(request.body) as Map)['params'] as String?;
      return http.Response(jsonEncode({
        'contents': {'twoColumnBrowseResultsRenderer': {'tabs': [
          {'tabRenderer': {'selected': true, 'content': {'richGridRenderer': {'contents': [
            {'richItemRenderer': {'content': _video('ddddddddddd')}},
          ]}}}},
        ]}},
      }), 200);
    });
    const channel = ChannelRef('UCxxxxxxxxxxxxxxxxxxxxxx', 'Chan');
    final items = await VideoRepository('/no/yt-dlp', client: client).channelTab(channel, ChannelTab.shorts).next(5).toList();
    expect(items.cast<VideoItem>().single.id, 'ddddddddddd');
    expect(params, 'EgZzaG9ydHPyBgUKA5oBAA%3D%3D');
  }, skip: skip);

  test('falls back when the web API fails or finds nothing, not after it listed something', () async {
    Stream<String> fallback() => Stream.fromIterable(['fallback']);
    expect(await YoutubeListing.orElse(() => Stream.error(StateError('HTTP 500')), fallback).toList(), ['fallback']);
    expect(await YoutubeListing.orElse(() => const Stream.empty(), fallback).toList(), ['fallback']);
    Stream<String> partial() async* {
      yield 'web';
      throw StateError('later');
    }

    await expectLater(YoutubeListing.orElse(partial, fallback), emitsInOrder(['web', emitsError(isStateError)]));
  });
}
