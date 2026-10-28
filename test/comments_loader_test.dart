import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lumtub/app/comments_loader.dart';
import 'package:lumtub/native_core.dart';
import 'package:lumtub/youtube_comments.dart';
import 'package:lumtub/youtube_tv_sign_in.dart';

class _FakeSignIn implements SignedInnerTube {
  _FakeSignIn(this.answer);
  final Map<String, Object?> Function(String endpoint, Map<String, Object?> body) answer;
  final actions = <Object?>[];

  @override
  bool get signedIn => true;

  @override
  Future<SignedAnswer?> post(String endpoint, Map<String, Object?> body) async {
    if (endpoint == 'comment/perform_comment_action') actions.add((body['actions'] as List).single);
    return (status: 200, body: Uint8List.fromList(utf8.encode(jsonEncode(answer(endpoint, body)))));
  }
}

/// A protobuf message `{1: 5, 3: id}`, base64, as a like action names its
/// comment.
String _action(String id) {
  final bytes = [0x08, 0x05, 0x1a, id.length, ...utf8.encode(id)];
  return base64.encode(bytes);
}

Map<String, Object?> _comment(String id, {bool buttons = false, String? detail}) => {
      'commentThreadRenderer': {
        'comment': {
          'commentRenderer': {
            'commentId': id,
            'contentText': {'simpleText': id},
            if (detail != null)
              'detailViewEndpoint': {'engagementPanelEndpoint': {'content': {'sectionListRenderer': {'contents': [
                {'itemSectionRenderer': {'continuations': [{'nextContinuationData': {'continuation': detail}}]}},
              ]}}}},
            if (buttons)
              'actionButtons': {'commentActionButtonsRenderer': {
                'likeButton': {'toggleButtonRenderer': {
                  'defaultServiceEndpoint': {'performCommentActionEndpoint': {'action': _action(id)}},
                }},
              }},
          },
        },
      },
    };

Map<String, Object?> _page(List<Map<String, Object?>> comments) => {'continuationContents': {'itemSectionContinuation': {'contents': comments}}};

void main() {
  test('likes comments whose buttons the TV app leaves out of its lists', () async {
    final sign = _FakeSignIn((endpoint, body) => switch (body['continuation'] ?? body['videoId']) {
          'dQw4w9WgXcQ' => {'engagementPanels': [
              {'engagementPanelSectionListRenderer': {'panelIdentifier': 'comment-item-section', 'header': {'engagementPanelTitleHeaderRenderer': {'menu': {'sortFilterSubMenuRenderer': {'subMenuItems': [
                {'continuation': {'reloadContinuationData': {'continuation': 'TOP'}}},
              ]}}}}}},
            ]},
          'TOP' => _page([_comment('UgxParent', detail: 'DETAIL')]),
          'DETAIL' => _page([_comment('UgxParent', buttons: true, detail: 'DETAIL'), _comment('UgxParent.reply')]),
          _ => const {},
        });
    final source = YoutubeComments(MockClient((request) async => fail('signed out request')))..signIn = sign;
    final loader = CommentsLoader(source, videoId: 'dQw4w9WgXcQ');
    await loader.loadMore();
    final parent = loader.comments.single;
    expect(parent.rating, isNull);
    expect(loader.canRate(parent), isTrue);

    expect(await loader.rate(parent, 'like'), isNull);
    expect(sign.actions, [_action('UgxParent')]);
    expect(loader.ratingOf(parent), 'like');

    await loader.loadReplies(parent);
    final replies = loader.replies[parent.id]!.replies;
    expect(replies.map((c) => c.id), ['UgxParent.reply'], reason: 'the page starts with the comment itself');
    expect(loader.canRate(replies.single), isTrue);
    expect(await loader.rate(replies.single, 'like'), isNull);
    expect(sign.actions.last, _action('UgxParent.reply'));
  }, skip: NativeCore.instance == null);
}
