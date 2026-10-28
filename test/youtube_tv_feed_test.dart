import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/native_core.dart';
import 'package:lumtub/youtube_tv_feed.dart';
import 'package:lumtub/youtube_tv_sign_in.dart';

class _FakeSignIn implements SignedInnerTube {
  _FakeSignIn(this.pages);
  final List<Map<String, Object?>> pages;
  final asked = <Map<String, Object?>>[];

  @override
  bool get signedIn => true;

  @override
  Future<SignedAnswer?> post(String endpoint, Map<String, Object?> body) async {
    asked.add(body);
    final page = pages[asked.length - 1];
    return (status: 200, body: Uint8List.fromList(utf8.encode(jsonEncode(page))));
  }
}

Map<String, Object?> _tile(String id, {String type = 'TILE_CONTENT_TYPE_VIDEO', String? browse}) => {
      'tileRenderer': {
        'contentId': id,
        'contentType': type,
        if (browse != null) 'onSelectCommand': {'browseEndpoint': {'browseId': browse}},
        'metadata': {
          'tileMetadataRenderer': {
            'title': {'simpleText': 'Title $id'},
            'lines': [
              {'lineRenderer': {'items': [{'lineItemRenderer': {'text': {'simpleText': 'Channel'}}}]}},
            ],
          },
        },
      },
    };

void main() {
  final core = NativeCore.instance != null;

  test('reads the account pages page after page', () async {
    final sign = _FakeSignIn([
      {
        'contents': {'tvBrowseRenderer': {'content': {'tvSurfaceContentRenderer': {'content': {'sectionListRenderer': {
          'contents': [{'shelfRenderer': {'content': {'horizontalListRenderer': {'items': [_tile('aaaaaaaaaaa'), _tile('bbbbbbbbbbb')]}}}}],
          'continuations': [{'nextContinuationData': {'continuation': 'NEXT'}}],
        }}}}}},
      },
      {
        'continuationContents': {'sectionListContinuation': {
          'contents': [{'shelfRenderer': {'content': {'horizontalListRenderer': {'items': [_tile('bbbbbbbbbbb'), _tile('ccccccccccc')]}}}}],
        }},
      },
    ]);
    final feed = YoutubeTvFeed(sign);
    final items = await feed.videos(YoutubeTvFeed.home);
    expect(items.map((item) => item.id), ['aaaaaaaaaaa', 'bbbbbbbbbbb', 'ccccccccccc']);
    expect(items.first.title, 'Title aaaaaaaaaaa');
    expect(sign.asked, [
      {'browseId': 'default'},
      {'continuation': 'NEXT'},
    ]);
  }, skip: !core);

  test('lists the account playlists as playlists', () async {
    final sign = _FakeSignIn([
      {
        'contents': {'tvBrowseRenderer': {'content': {'tvSurfaceContentRenderer': {'content': {'gridRenderer': {'items': [
          _tile('PLxxxxxxxxxxxxxxxx', type: 'TILE_CONTENT_TYPE_PLAYLIST', browse: 'VLPLxxxxxxxxxxxxxxxx'),
          _tile('WL', type: 'TILE_CONTENT_TYPE_PLAYLIST', browse: 'VLWL'),
        ]}}}}}},
      },
    ]);
    final lists = await YoutubeTvFeed(sign).accountPlaylists();
    expect(lists.map((list) => (list.id, list.title)), [('PLxxxxxxxxxxxxxxxx', 'Title PLxxxxxxxxxxxxxxxx')]);
    expect(lists.single, isA<PlaylistResult>());
  }, skip: !core);
}
