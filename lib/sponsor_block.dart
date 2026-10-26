import 'dart:convert';

import 'package:http/http.dart' as http;

import 'native_core.dart';
import 'player_settings.dart';

/// A part of a video that SponsorBlock users marked, in seconds.
class SkipSegment {
  const SkipSegment(this.start, this.end, this.category);
  final Duration start;
  final Duration end;
  final String category;

  bool contains(Duration position) => position >= start && position < end - const Duration(milliseconds: 500);
}

/// Labels for the categories Lumtub can skip.
final sponsorCategories = {for (final entry in sponsorCategoryNames.entries) entry.key: entry.value.$1};

/// Looks up skip segments from the public SponsorBlock API.
///
/// Only the first four hex digits of the video id's SHA-256 are sent, so the
/// server cannot tell which video is being watched: it answers with the
/// segments of every video sharing that prefix, and the match happens here.
class SponsorBlock {
  SponsorBlock(this._client);
  final http.Client _client;

  static String hashPrefix(String videoId) {
    final core = NativeCore.instance!;
    return core.take(core.withText(videoId, core.hashPrefix))!;
  }

  static Uri requestUri(String videoId, [Set<String> categories = PlayerSettings.defaultSponsorCategories]) =>
      Uri.https('sponsor.ajay.app', '/api/skipSegments/${hashPrefix(videoId)}', {
        'categories': jsonEncode(categories.toList()),
      });

  /// Answers of this session, so replaying or going back to a video, or
  /// downloading it, asks once.
  final _known = <String, List<SkipSegment>>{};

  Future<List<SkipSegment>> segments(String videoId, [Set<String> categories = PlayerSettings.defaultSponsorCategories]) async {
    if (categories.isEmpty || NativeCore.instance == null) return const [];
    final key = '$videoId ${(categories.toList()..sort()).join(',')}';
    if (_known[key] case final known?) return known;
    final found = await _fetch(videoId, categories);
    if (_known.length >= 200) _known.remove(_known.keys.first);
    return _known[key] = found;
  }

  Future<List<SkipSegment>> _fetch(String videoId, Set<String> categories) async {
    final response = await _client.get(requestUri(videoId, categories), headers: {'User-Agent': 'Lumtub-Windows/0.1'}).timeout(const Duration(seconds: 10));
    // 404 means no video with this prefix has segments.
    if (response.statusCode == 404) return const [];
    if (response.statusCode != 200) throw StateError('SponsorBlock HTTP ${response.statusCode}');
    return parse(response.body, videoId, categories);
  }

  static List<SkipSegment> parse(String body, String videoId, [Set<String> categories = PlayerSettings.defaultSponsorCategories]) {
    final core = NativeCore.instance;
    if (core == null) return const [];
    final ask = jsonEncode({'answer': body, 'videoId': videoId, 'categories': categories.toList()});
    final answer = jsonDecode(core.take(core.withText(ask, core.sponsorSegments)) ?? '[]') as List;
    return [
      for (final s in answer.cast<Map<String, dynamic>>()) SkipSegment(Duration(milliseconds: s['start'] as int), Duration(milliseconds: s['end'] as int), s['category'] as String),
    ];
  }
}
