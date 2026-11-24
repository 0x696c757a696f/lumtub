import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumtub/models.dart';
import 'package:lumtub/native_core.dart';
import 'package:lumtub/youtube_account_feed.dart';
import 'package:lumtub/youtube_web_account.dart';
import 'package:lumtub/youtube_web_sign_in.dart';

class _FakeWeb implements WebInnerTube {
  _FakeWeb(this.pages);
  final List<Map<String, Object?>> pages;
  final asked = <(Map<String, Object?>, String?)>[];

  @override
  bool get signedIn => true;

  @override
  Future<SignedAnswer?> post(String endpoint, Map<String, Object?> body, {bool ask = false, String? hl}) async {
    asked.add((body, hl));
    return (status: 200, body: Uint8List.fromList(utf8.encode(jsonEncode(pages[asked.length - 1]))));
  }
}

Map<String, Object?> _video(String id) => {'videoRenderer': {'videoId': id, 'title': {'simpleText': 'Title $id'}, 'lengthText': {'simpleText': '3:00'}}};

void main() {
  test('reads the day labels of the watch history in English', () {
    final wednesday = DateTime(2026, 11, 18, 21);
    expect(YoutubeAccountFeed.daysAgo('Today', now: wednesday), 0);
    expect(YoutubeAccountFeed.daysAgo('Yesterday', now: wednesday), 1);
    expect(YoutubeAccountFeed.daysAgo('Monday', now: wednesday), 2);
    expect(YoutubeAccountFeed.daysAgo('Thursday', now: wednesday), 6);
    expect(YoutubeAccountFeed.daysAgo('Nov 1', now: wednesday), 17);
    expect(YoutubeAccountFeed.daysAgo('Dec 24', now: wednesday), 329, reason: 'a date ahead is last year\'s');
    expect(YoutubeAccountFeed.daysAgo('Nov 12, 2025', now: wednesday), 371);
    expect(YoutubeAccountFeed.daysAgo('Watched', now: wednesday), isNull);
  });

  test('reads the history page after page, in English, with each video\'s day', () async {
    final web = _FakeWeb([
      {'contents': {'twoColumnBrowseResultsRenderer': {'tabs': [{'tabRenderer': {'selected': true, 'content': {'sectionListRenderer': {'contents': [
        {'itemSectionRenderer': {'header': {'itemSectionHeaderRenderer': {'title': {'runs': [{'text': 'Today'}]}}}, 'contents': [_video('aaaaaaaaaaa')]}},
        {'continuationItemRenderer': {'continuationEndpoint': {'continuationCommand': {'token': 'NEXT'}}}},
      ]}}}}]}}},
      {'onResponseReceivedActions': [{'appendContinuationItemsAction': {'continuationItems': [
        {'itemSectionRenderer': {'header': {'itemSectionHeaderRenderer': {'title': {'simpleText': 'Yesterday'}}}, 'contents': [_video('bbbbbbbbbbb'), _video('aaaaaaaaaaa')]}},
      ]}}]},
    ]);
    final feed = YoutubeAccountFeed(web);
    final items = await feed.videos(YoutubeAccountFeed.history);
    expect(items.map((v) => v.id), ['aaaaaaaaaaa', 'bbbbbbbbbbb']);
    expect(web.asked.map((a) => (a.$1['browseId'] ?? a.$1['continuation'], a.$2)), [('FEhistory', 'en'), ('NEXT', 'en')]);
    expect(feed.historyDays, {'aaaaaaaaaaa': 0, 'bbbbbbbbbbb': 1});
    expect(items.first, isA<VideoItem>());
  }, skip: NativeCore.instance == null);

  test('puts a YouTube playlist in order with the fewest moves, and uploads in batches', () async {
    final ids = [for (var i = 0; i < 6; i++) 'video${i}xxxx'];
    Map<String, Object?> entry(int i) => {'playlistVideoRenderer': {'videoId': ids[i], 'setVideoId': 'SET$i', 'title': {'simpleText': 'Title $i'}}};
    final web = _FakeWeb([
      {'contents': {'twoColumnBrowseResultsRenderer': {'tabs': [{'tabRenderer': {'selected': true, 'content': {'sectionListRenderer': {'contents': [
        {'itemSectionRenderer': {'contents': [{'playlistVideoListRenderer': {'contents': [for (var i = 0; i < 6; i++) entry(i)]}}]}},
      ]}}}}]}}},
      {},
      {},
      {},
    ]);
    final api = WebAccountApi(web);
    expect(await api.feed.playlistEntries('PLx'), [for (var i = 0; i < 6; i++) (ids[i], 'SET$i')]);
    web.asked.clear();

    // Move the last video to the top and swap two in the middle.
    final wanted = [ids[5], ids[0], ids[1], ids[3], ids[2], ids[4]];
    final web2 = _FakeWeb(web.pages);
    final moved = await WebAccountApi(web2).reorderPlaylist('PLx', wanted);
    expect(moved, 2);
    final actions = web2.asked[1].$1['actions']! as List;
    expect(web2.asked[1].$1['playlistId'], 'PLx');
    // Play the moves on the playlist as YouTube would.
    final list = [for (var i = 0; i < 6; i++) 'SET$i'];
    for (final action in actions.cast<Map<String, Object?>>()) {
      final set = action['setVideoId']! as String;
      list.remove(set);
      if (action['action'] == 'ACTION_MOVE_VIDEO_AFTER') {
        list.insert(list.indexOf(action['movedSetVideoIdPredecessor']! as String) + 1, set);
      } else {
        list.insert(list.indexOf(action['movedSetVideoIdSuccessor']! as String), set);
      }
    }
    expect(list, ['SET5', 'SET0', 'SET1', 'SET3', 'SET2', 'SET4']);

    final web3 = _FakeWeb([{}, {}, {}]);
    await WebAccountApi(web3).addAllToPlaylist('PLy', [for (var i = 0; i < 250; i++) 'v$i']);
    expect(web3.asked.length, 3, reason: '250 videos in requests of 100');
    expect((web3.asked.last.$1['actions']! as List).length, 50);
  }, skip: NativeCore.instance == null);
}
