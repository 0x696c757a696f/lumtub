import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumtub/ai_filter.dart';
import 'package:lumtub/models.dart';

void main() {
  VideoItem video(String id, String channelId) => VideoItem(id: id, title: id, channel: 'Channel', url: 'https://www.youtube.com/watch?v=$id', channelId: channelId);

  Map<String, Object?> next({required bool ai}) => {
        'contents': {
          'twoColumnWatchNextResults': {
            'results': {
              'results': {
                'contents': [
                  {
                    'videoPrimaryInfoRenderer': {
                      'badges': [
                        if (ai)
                          {
                            'metadataBadgeRenderer': {
                              'style': 'BADGE_STYLE_TYPE_SIMPLE',
                              'icon': {'iconType': 'INFO'},
                              'label': 'AI',
                            },
                          },
                      ],
                    },
                  },
                ],
              },
            },
          },
        },
      };

  test('hides videos YouTube labels as AI and the listed channels', () async {
    final folder = await Directory.systemTemp.createTemp('ai_filter');
    addTearDown(() => folder.delete(recursive: true));
    final asked = <String>[];
    final client = MockClient((request) async {
      if (request.url.host == 'api.killslop.app') {
        return http.Response(jsonEncode({
          'license': 'CC-BY-SA-4.0',
          'channels': [
            {'id': 'UClisted0000000000000000', 'score': 0},
          ],
        }), 200);
      }
      expect(request.url.path, '/youtubei/v1/next');
      final id = (jsonDecode(request.body) as Map)['videoId'] as String;
      asked.add(id);
      return http.Response(jsonEncode(next(ai: id == 'aaaaaaaaaaa')), 200);
    });
    final filter = AiFilter(client, labelsFile: File('${folder.path}/labels.json'), channelsFile: File('${folder.path}/channels.json'));
    final labeled = video('aaaaaaaaaaa', 'UCother00000000000000000');
    final plain = video('bbbbbbbbbbb', 'UCother00000000000000000');
    final listed = video('ccccccccccc', 'UClisted0000000000000000');

    await filter.setMode(AiFilterMode.labeled);
    expect(filter.hides(listed), isFalse);
    filter.check([labeled, plain]);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(asked, unorderedEquals(['aaaaaaaaaaa', 'bbbbbbbbbbb']));
    expect(filter.hides(labeled), isTrue);
    expect(filter.hides(plain), isFalse);

    // Answers are kept: a video is asked about once.
    filter.check([labeled, plain]);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(asked, hasLength(2));

    await filter.setMode(AiFilterMode.labeledAndList);
    expect(filter.hides(listed), isTrue);

    await filter.setMode(AiFilterMode.off);
    expect(filter.hides(labeled), isFalse);
  }, skip: !AiFilter.available ? 'needs the native core' : false);
}
