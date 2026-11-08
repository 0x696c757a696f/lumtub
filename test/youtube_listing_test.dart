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

Map<String, Object> _tab(List<Object> sections) => {
      'contents': {
        'twoColumnBrowseResultsRenderer': {
          'tabs': [
            {
              'tabRenderer': {
                'selected': true,
                'content': {'sectionListRenderer': {'contents': sections}},
              },
            },
          ],
        },
      },
    };

Map<String, Object> _playlist(String id) => {'lockupViewModel': {'contentId': id, 'contentType': 'LOCKUP_CONTENT_TYPE_PLAYLIST'}};

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

  test('a page with no new videos does not end a search that goes on', () async {
    var pages = 0;
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map;
      pages++;
      final token = body['continuation'] as String?;
      final items = switch (token) {
        null => [_video('aaaaaaaaaaa')],
        'P1' => [_video('aaaaaaaaaaa')],
        _ => [_video('bbbbbbbbbbb')],
      };
      final next = switch (token) { null => 'P1', 'P1' => 'P2', _ => 'P1' };
      return http.Response(jsonEncode({
        'onResponseReceivedCommands': [{'appendContinuationItemsAction': {'continuationItems': [
          {'itemSectionRenderer': {'contents': items}},
          {'continuationItemRenderer': {'continuationEndpoint': {'continuationCommand': {'token': next}}}},
        ]}}],
      }), 200);
    });
    final repository = VideoRepository('/no/yt-dlp', client: client);
    final items = (await repository.search('cats', filter: SearchFilter.videos).next(10).toList()).cast<VideoItem>();
    expect(items.map((v) => v.id), ['aaaaaaaaaaa', 'bbbbbbbbbbb']);
    expect(pages, 3, reason: 'a token seen before ends it');
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

  test('a playlists tab made of rows lists each whole row after the rows', () async {
    final asked = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      asked.add(body);
      final answer = body['params'] == 'ROW'
          ? _tab([
              {
                'itemSectionRenderer': {
                  'contents': [
                    {'gridRenderer': {'items': [_playlist('PLrowrowrow1'), _playlist('PLrowrowrow2'), _playlist('PLrowrowrow3')]}},
                  ],
                },
              },
            ])
          : _tab([
              {
                'itemSectionRenderer': {
                  'contents': [
                    {
                      'shelfRenderer': {
                        'endpoint': {'browseEndpoint': {'browseId': 'UCaaaaaaaaaaaaaaaaaaaaaa', 'params': 'ROW'}},
                        'content': {'horizontalListRenderer': {'items': [_playlist('PLrowrowrow1')]}},
                      },
                    },
                  ],
                },
              },
            ]);
      return http.Response(jsonEncode(answer), 200);
    });
    final lines = await YoutubeListing(client).channelTab('UCaaaaaaaaaaaaaaaaaaaaaa', ChannelTab.playlists).toList();
    final ids = [for (final line in lines) (jsonDecode(line) as Map)['id']];
    expect(ids, ['PLrowrowrow1', 'PLrowrowrow2', 'PLrowrowrow3']);
    expect([for (final b in asked) b['params']], ['EglwbGF5bGlzdHPyBgQKAkIA', 'ROW']);
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
