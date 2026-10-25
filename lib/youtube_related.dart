import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'l10n/l10n.dart';
import 'models.dart';
import 'native_core.dart';
import 'youtube_web.dart';

/// The videos YouTube suggests next to a video, from the same request the
/// watch page makes. No account is involved.
class YoutubeRelated {
  YoutubeRelated(this._client);
  final http.Client _client;

  static Map<String, String> get _headers => {
    ...YoutubeWeb.apiHeaders(acceptLanguage: youtubeAcceptLanguage),
  };

  /// What was read from each response, not the response itself: a `/next`
  /// response decodes to megabytes of maps, of which a few fields are used.
  final _cache = <String, Future<({List<VideoItem> related, ({String title, String description, int? likes})? text})>>{};

  /// YouTube's `/next` response for [videoId], in the interface language;
  /// the related videos and the translated title both come from it.
  Future<({List<VideoItem> related, ({String title, String description, int? likes})? text})> _next(String videoId) {
    if (_cache.length > 40) _cache.remove(_cache.keys.first);
    return _cache[videoId] ??= () async {
      final response = await _client
          .post(
            Uri.parse('https://www.youtube.com/youtubei/v1/next?prettyPrint=false'),
            headers: _headers,
            body: jsonEncode({
              'context': {
                'client': {'clientName': 'WEB', 'clientVersion': YoutubeWeb.clientVersion, 'hl': youtubeHl},
              },
              'videoId': videoId,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw StateError(tr('YouTube 返回 {0}', [response.statusCode]));
      return readNext(utf8.decode(response.bodyBytes));
    }()
      ..ignore();
  }

  Future<List<VideoItem>> forVideo(String videoId) async {
    try {
      return (await _next(videoId)).related.where((item) => item.id != videoId).toList();
    } catch (_) {
      _cache.remove(videoId);
      rethrow;
    }
  }

  /// [videoId]'s title and description as YouTube shows them in the
  /// interface language: the uploader's translation where there is one.
  Future<({String title, String description, int? likes})?> textFor(String videoId) async {
    try {
      return (await _next(videoId)).text;
    } catch (_) {
      _cache.remove(videoId);
      return null;
    }
  }

  /// The related videos and the localized text of a `/next` response
  /// [body], read by the native core; nothing without it.
  static ({List<VideoItem> related, ({String title, String description, int? likes})? text}) readNext(String body) {
    final core = NativeCore.instance;
    final answer = core == null ? null : jsonDecode(core.take(core.withText(body, core.youtubeNext)) ?? 'null');
    if (answer is! Map<String, dynamic>) return (related: const <VideoItem>[], text: null);
    final text = answer['text'] as Map<String, dynamic>?;
    return (
      related: [for (final v in (answer['related'] as List).cast<Map<String, dynamic>>()) videoFromCore(v)],
      text: text == null ? null : (title: text['title'] as String, description: text['description'] as String, likes: (text['likes'] as num?)?.toInt()),
    );
  }

  @visibleForTesting
  static List<VideoItem> parse(Object? data) => readNext(jsonEncode(data)).related;

  @visibleForTesting
  static ({String title, String description, int? likes})? localized(Object? data) => readNext(jsonEncode(data)).text;
}

/// A video the native core read from a YouTube response.
VideoItem videoFromCore(Map<String, dynamic> v) {
  final id = v['id'] as String;
  return VideoItem(
    id: id,
    title: v['title'] as String,
    channel: v['channel'] as String,
    channelId: v['channelId'] as String?,
    duration: (v['duration'] as num?)?.toInt(),
    viewCount: (v['viewCount'] as num?)?.toInt(),
    url: 'https://www.youtube.com/watch?v=$id',
    liveStatus: v['live'] == true ? 'is_live' : null,
  );
}
