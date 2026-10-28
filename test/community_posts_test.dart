import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/app/posts_loader.dart';
import 'package:lumtub/community_posts.dart';
import 'package:lumtub/native_core.dart';
import 'package:lumtub/youtube_comments.dart';
import 'package:lumtub/youtube_tv_sign_in.dart';
import 'package:lumtub/youtube_web_sign_in.dart';
import 'package:lumtub/models.dart';

Map<String, dynamic> _post(String id, {Map<String, dynamic>? attachment}) => {
      'backstagePostThreadRenderer': {
        'post': {
          'backstagePostRenderer': {
            'postId': id,
            'contentText': {'runs': [{'text': '新视频上线了 '}, {'text': '快去看看'}]},
            'publishedTimeText': {'runs': [{'text': '3天前'}]},
            'voteCount': {'simpleText': '1.2万'},
            if (attachment != null) 'backstageAttachment': attachment,
          },
        },
      },
    };

final _page = {
  'contents': {
    'twoColumnBrowseResultsRenderer': {
      'tabs': [
        {
          'tabRenderer': {
            'title': '帖子',
            'content': {
              'sectionListRenderer': {
                'contents': [
                  {
                    'itemSectionRenderer': {
                      'contents': [
                        _post('Ugkx1', attachment: {
                          'postMultiImageRenderer': {
                            'images': [
                              {'backstageImageRenderer': {'image': {'thumbnails': [{'url': 'https://yt3.ggpht.com/a=s288'}, {'url': 'https://yt3.ggpht.com/a=s1080'}]}}},
                              {'backstageImageRenderer': {'image': {'thumbnails': [{'url': '//yt3.ggpht.com/b=s1080'}]}}},
                            ],
                          },
                        }),
                        _post('Ugkx2', attachment: {
                          'videoRenderer': {'videoId': 'dQw4w9WgXcQ', 'title': {'runs': [{'text': 'Never Gonna'}]}, 'lengthText': {'simpleText': '3:33'}},
                        }),
                        _post('Ugkx3', attachment: {
                          'pollRenderer': {'choices': [{'text': {'runs': [{'text': '是'}]}}, {'text': {'runs': [{'text': '否'}]}}]},
                        }),
                        {'continuationItemRenderer': {'continuationEndpoint': {'continuationCommand': {'token': 'NEXT'}}}},
                      ],
                    },
                  },
                ],
              },
            },
          },
        },
      ],
    },
  },
};

void main() {
  test('reads posts, images, videos, polls and the next token', () {
    final page = CommunityPosts.parse(_page);
    expect(page.posts.map((p) => p.id), ['Ugkx1', 'Ugkx2', 'Ugkx3']);
    expect(page.posts[0].text, '新视频上线了 快去看看');
    expect(page.posts[0].published, '3天前');
    expect(page.posts[0].likes, '1.2万');
    expect(page.posts[0].images, ['https://yt3.ggpht.com/a=s1080', 'https://yt3.ggpht.com/b=s1080']);
    expect(page.posts[1].video?.id, 'dQw4w9WgXcQ');
    expect(page.posts[1].video?.duration, 213);
    expect(page.posts[2].poll, ['是', '否']);
    expect(page.continuation, 'NEXT');
  });

  test('finds ytInitialData in the page despite braces inside strings', () {
    final html = '<script>var ytInitialData = ${jsonEncode({'a': '};{', 'b': {'c': 1}})};</script>';
    expect(CommunityPosts.read(html)?.posts, isEmpty);
    expect(CommunityPosts.read('<html></html>'), isNull);
  });

  test('loads the first page from HTML and the next from the browse endpoint', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET') {
        return http.Response.bytes(utf8.encode('<script>ytcfg.set({"INNERTUBE_API_KEY":"KEY","INNERTUBE_CLIENT_VERSION":"2.2026"});var ytInitialData = ${jsonEncode(_page)};</script>'), 200);
      }
      return http.Response.bytes(utf8.encode(jsonEncode({'onResponseReceivedEndpoints': [{'appendContinuationItemsAction': {'continuationItems': [_post('Ugkx4')]}}]})), 200);
    });
    final posts = CommunityPosts(client);
    final first = await posts.first(const ChannelRef('UCuAXFkgsw1L7xaCfnd5JJOw', 'Rick'));
    expect(requests.single.url.toString(), 'https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw/posts?hl=zh-CN');
    final next = await posts.next(first.continuation!);
    expect(next.posts.single.id, 'Ugkx4');
    expect(next.continuation, isNull);
    expect(requests.last.url.queryParameters['key'], 'KEY');
    final body = jsonDecode(requests.last.body) as Map;
    expect(body['continuation'], 'NEXT');
    expect(body['context']['client']['clientVersion'], '2.2026');
  });

  test('with the cookie sign-in, posts load as the website signed in and polls can be voted in', () async {
    final web = _FakeWeb()..answer = (endpoint, body) => (status: 200, body: Uint8List.fromList(utf8.encode(jsonEncode(_signedInPoll))));
    final comments = YoutubeComments(MockClient((request) async => fail('signed out request')))..web = web;
    final posts = CommunityPosts(MockClient((request) async => fail('signed out request')), signIn: comments);
    final page = await posts.first(const ChannelRef('UCuAXFkgsw1L7xaCfnd5JJOw', 'Rick'));
    expect(web.bodies.first.$2['browseId'], 'UCuAXFkgsw1L7xaCfnd5JJOw');
    final post = page.posts.single;
    expect(post.votes, '1.2K 票');
    expect(post.choices.map((c) => (c.text, c.selected, c.percent)), [('是', false, ''), ('否', true, '40%')]);

    final loader = PostsLoader(posts, const ChannelRef('UCuAXFkgsw1L7xaCfnd5JJOw', 'Rick'));
    expect(loader.voteOf(post), 1);
    expect(await loader.vote(post, 0), isNull);
    expect(loader.voteOf(post), 0);
    expect((web.bodies.last.$1, web.bodies.last.$3), ('comment/perform_comment_action', true));
    expect(web.bodies.last.$2, {'actions': ['S1']});
    expect(await loader.vote(post, 0), isNull);
    expect(web.bodies.last.$2, {'actions': ['D1']});
    expect(loader.voteOf(post), -1);

    web.answer = (endpoint, body) => (status: 403, body: Uint8List(0));
    expect(await loader.vote(post, 1), isNotNull);
    expect(loader.voteOf(post), -1);
  }, skip: NativeCore.instance == null);
}

class _FakeWeb implements WebInnerTube {
  final bodies = <(String, Map<String, Object?>, bool)>[];
  SignedAnswer Function(String endpoint, Map<String, Object?> body) answer = (endpoint, body) => (status: 200, body: Uint8List.fromList(utf8.encode('{}')));

  @override
  bool get signedIn => true;

  @override
  Future<SignedAnswer?> post(String endpoint, Map<String, Object?> body, {bool ask = false}) async {
    bodies.add((endpoint, body, ask));
    return answer(endpoint, body);
  }
}

Map<String, dynamic> _vote(String action) => {'commandExecutorCommand': {'commands': [{'performCommentActionEndpoint': {'action': action}}]}};

final _signedInPoll = {
  'contents': [
    _post('Ugkx5', attachment: {
      'pollRenderer': {
        'totalVotes': {'simpleText': '1.2K 票'},
        'choices': [
          {'text': {'runs': [{'text': '是'}]}, 'selected': false, 'selectServiceEndpoint': _vote('S1'), 'deselectServiceEndpoint': _vote('D1')},
          {'text': {'runs': [{'text': '否'}]}, 'selected': true, 'voteRatio': 0.4, 'votePercentage': {'simpleText': '40%'}, 'selectServiceEndpoint': _vote('S2'), 'deselectServiceEndpoint': _vote('D2')},
        ],
      },
    }),
  ],
};
