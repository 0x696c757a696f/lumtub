import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/channel_sort.dart';

void main() {
  test('reads sort chip tokens from a chip cloud', () {
    final response = {
      'contents': {
        'richGridRenderer': {
          'header': {
            'feedFilterChipBarRenderer': {
              'contents': [
                {'chipCloudChipRenderer': {'text': {'simpleText': 'Latest'}, 'isSelected': true}},
                {'chipCloudChipRenderer': {'text': {'simpleText': 'Popular'}, 'navigationEndpoint': {'continuationCommand': {'token': 'POP'}}}},
                {'chipCloudChipRenderer': {'text': {'runs': [{'text': 'Old'}, {'text': 'est'}]}, 'navigationEndpoint': {'commandMetadata': {}, 'continuationCommand': {'token': 'OLD'}}}},
              ],
            },
          },
        },
      },
    };
    expect(sortChipTokens(response), {'Popular': 'POP', 'Oldest': 'OLD'});
  });

  test('reads sort chip tokens from chip view models', () {
    final response = [
      {
        'chipViewModel': {
          'text': 'Popular',
          'tapCommand': {'innertubeCommand': {'continuationCommand': {'token': 'POP2'}}},
        },
      },
    ];
    expect(sortChipTokens(response), {'Popular': 'POP2'});
    expect(sortChipTokens({'a': 1}), isEmpty);
  });
}
