import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/live_chat.dart';
import 'package:lumtub/live_chat_feed.dart';

Map<String, Object?> _text(String id, String text) => {
      'addChatItemAction': {
        'item': {
          'liveChatTextMessageRenderer': {
            'id': id,
            'message': {'simpleText': text},
            'authorName': {'simpleText': 'a'},
          },
        },
      },
    };

Map<String, Object?> _chat({List<Object?> actions = const [], String? next, bool header = false, String? restricted}) => {
      'continuationContents': {
        'liveChatContinuation': {
          'actions': actions,
          if (next != null)
            'continuations': [
              {'timedContinuationData': {'continuation': next, 'timeoutMs': 1}},
            ],
          if (header)
            'header': {
              'liveChatHeaderRenderer': {
                'viewSelector': {
                  'sortFilterSubMenuRenderer': {
                    'subMenuItems': [
                      {'title': 'Top chat', 'selected': true, 'continuation': {'reloadContinuationData': {'continuation': 'top'}}},
                      {'title': 'Live chat', 'selected': false, 'continuation': {'reloadContinuationData': {'continuation': 'all'}}},
                    ],
                  },
                },
              },
            },
          if (restricted != null)
            'actionPanel': {
              'liveChatRestrictedParticipationRenderer': {'message': {'simpleText': restricted}},
            },
        },
      },
    };

void main() {
  final skip = LiveChatFeed.available ? null : 'needs the native core (LUMTUB_CORE_DLL)';

  test('follows every message of a live chat when asked', () async {
    final asked = <String>[];
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final endpoint = request.url.path.split('/v1/').last;
      asked.add('$endpoint ${body['continuation'] ?? body['videoId']}');
      expect(request.url.host, 'www.youtube.com');
      final answer = switch ((endpoint, body['continuation'])) {
        ('next', _) => {
            'responseContext': {'visitorData': 'v1'},
            'contents': {
              'twoColumnWatchNextResults': {
                'conversationBar': {
                  'liveChatRenderer': {
                    'continuations': [
                      {'reloadContinuationData': {'continuation': 'start'}},
                    ],
                  },
                },
              },
            },
          },
        (_, 'start') => _chat(actions: [_text('t1', 'top only')], next: 'top2', header: true, restricted: 'Members-only mode'),
        (_, 'all') => _chat(actions: [_text('a1', 'first'), _text('a2', 'second')], next: 'all2', header: true),
        (_, 'all2') => _chat(actions: [
            _text('a3', 'third'),
            {'markChatItemAsDeletedAction': {'targetItemId': 'a2'}},
          ]),
        _ => throw StateError('unexpected ${request.body}'),
      };
      if (endpoint != 'next') expect((((body['context'] as Map<String, dynamic>)['client']) as Map<String, dynamic>)['visitorData'], 'v1');
      return http.Response(jsonEncode(answer), 200);
    });
    final batches = await LiveChatFeed(client).follow('abcdefghijk', ChatView.all).toList();
    expect(asked, ['next abcdefghijk', 'live_chat/get_live_chat start', 'live_chat/get_live_chat all', 'live_chat/get_live_chat all2']);
    expect([for (final b in batches) for (final m in b.messages) m.id], ['a1', 'a2', 'a3']);
    expect(batches.first.view, ChatView.all);
    expect(batches.first.restricted, 'Members-only mode');
    expect(batches.last.removed, {'a2'});
  }, skip: skip);

  test('stays on Top chat without asking again, and reads replays by offset', () async {
    final asked = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      asked.add(body);
      final answer = switch (body['continuation']) {
        null => {
            'contents': {
              'twoColumnWatchNextResults': {
                'conversationBar': {
                  'liveChatRenderer': {
                    'isReplay': true,
                    'continuations': [
                      {'reloadContinuationData': {'continuation': 'start'}},
                    ],
                  },
                },
              },
            },
          },
        'start' => {
            'continuationContents': {
              'liveChatContinuation': {
                ...((_chat(header: true)['continuationContents']! as Map)['liveChatContinuation'] as Map),
                'continuations': [
                  {'liveChatReplayContinuationData': {'continuation': 'more'}},
                ],
                'actions': [
                  {
                    'replayChatItemAction': {
                      'videoOffsetTimeMsec': '60000',
                      'actions': [_text('r1', 'one')],
                    },
                  },
                ],
              },
            },
          },
        _ => _chat(),
      };
      return http.Response(jsonEncode(answer), 200);
    });
    final batches = await LiveChatFeed(client).follow('abcdefghijk', ChatView.top).toList();
    expect(batches.first.messages.single.offset, const Duration(minutes: 1));
    expect(batches.first.view, ChatView.top);
    expect(asked.map((b) => b['continuation']), [null, 'start', 'more']);
    expect(asked.last['currentPlayerState'], {'playerOffsetMs': '55000'});
  }, skip: skip);

  test('a video without chat, a refused request and an oversized answer', () async {
    final none = MockClient((_) async => http.Response('{"contents": {}}', 200));
    await expectLater(LiveChatFeed(none).follow('abcdefghijk', ChatView.top).toList(), throwsA(isA<NoLiveChat>()));
    final refused = MockClient((_) async => http.Response('', 429));
    await expectLater(LiveChatFeed(refused).follow('abcdefghijk', ChatView.top).toList(), throwsA(isA<http.ClientException>()));
    final huge = MockClient.streaming((request, _) async => http.StreamedResponse(Stream.value(List.filled(LiveChatFeed.maxBytes + 1, 32)), 200));
    await expectLater(LiveChatFeed(huge).follow('abcdefghijk', ChatView.top).toList(), throwsA(isA<http.ClientException>()));
  }, skip: skip);

  test('cancelling stops the requests', () async {
    var asked = 0;
    final client = MockClient((request) async {
      asked++;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['continuation'] == null) {
        return http.Response(
            jsonEncode({
              'contents': {
                'twoColumnWatchNextResults': {
                  'conversationBar': {
                    'liveChatRenderer': {
                      'continuations': [
                        {'reloadContinuationData': {'continuation': 'start'}},
                      ],
                    },
                  },
                },
              },
            }),
            200);
      }
      return http.Response(jsonEncode(_chat(actions: [_text('m$asked', 'x')], next: 'again$asked')), 200);
    });
    final first = await LiveChatFeed(client).follow('abcdefghijk', ChatView.top).first;
    expect(first.messages.single.id, 'm2');
    final before = asked;
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(asked, before);
  }, skip: skip);
}
