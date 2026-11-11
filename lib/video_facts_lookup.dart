import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'native_core.dart';

/// What a card shows of a video and its listing may leave out: the length,
/// the views and the day it was published.
class VideoFacts {
  const VideoFacts({this.length, this.views, this.published, required this.asked});

  final int? length;
  final int? views;
  final DateTime? published;
  /// When YouTube was asked; views grow, so old answers are asked again.
  final DateTime asked;

  VideoItem fill(VideoItem item) => item.filledIn(length: length, views: views, publishedAt: published);

  List<Object?> toJson() => [length, views, published?.toUtc().toIso8601String(), asked.toUtc().toIso8601String()];

  static VideoFacts? fromJson(Object? raw) {
    if (raw is! List || raw.length != 4) return null;
    final asked = DateTime.tryParse('${raw[3]}');
    if (asked == null) return null;
    return VideoFacts(
      length: raw[0] is int ? raw[0] as int : null,
      views: raw[1] is int ? raw[1] as int : null,
      published: raw[2] is String ? DateTime.tryParse(raw[2] as String) : null,
      asked: asked,
    );
  }

  static final _length = RegExp(r'"lengthSeconds"\s*:\s*"(\d+)"');
  static final _views = RegExp(r'"viewCount"\s*:\s*"(\d+)"');
  static final _published = RegExp(r'"(?:publishDate|uploadDate)"\s*:\s*"([^"]+)"');

  /// The facts of a /player answer, read without decoding the whole of it;
  /// null when it has none (an error page). A length of 0 is a live's.
  static VideoFacts? ofPlayer(String answer, DateTime asked) {
    final length = int.tryParse(_length.firstMatch(answer)?.group(1) ?? '');
    final views = int.tryParse(_views.firstMatch(answer)?.group(1) ?? '');
    final published = DateTime.tryParse(_published.firstMatch(answer)?.group(1) ?? '');
    if (length == null && views == null && published == null) return null;
    return VideoFacts(length: length == 0 ? null : length, views: views, published: published, asked: asked);
  }
}

/// [VideoFacts] of videos whose listing gave too little (subscription
/// feeds, some tiles of the TV home), asked of YouTube once each and kept on
/// disk, so a card fills in after a moment instead of never.
class VideoFactsLookup extends ChangeNotifier {
  VideoFactsLookup._();
  static final instance = VideoFactsLookup._();

  /// Videos kept; the oldest go first.
  static const keep = 5000;
  /// Lookups at once.
  static const parallel = 2;
  /// Cards waiting at most; the ones asked for longest ago are dropped,
  /// as they have most likely scrolled away.
  static const waitingAtMost = 40;
  /// Views older than this are asked again when a card needs them.
  static const freshFor = Duration(days: 2);

  Future<VideoFacts?> Function(String id)? _source;
  File? _file;
  final _known = <String, VideoFacts>{};
  final _tried = <String>{};
  final _waiting = <String>[];
  var _running = 0;
  Timer? _save;
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  void configure(http.Client client, File file) => use((id) => askYoutube(client, id), file);

  @visibleForTesting
  void use(Future<VideoFacts?> Function(String id) source, File? file) {
    _source = source;
    _file = file;
    if (file == null) return;
    try {
      final saved = jsonDecode(file.readAsStringSync());
      if (saved is Map) {
        for (final entry in saved.entries) {
          final id = entry.key.toString();
          final facts = VideoFacts.fromJson(entry.value);
          if (_videoId.hasMatch(id) && facts != null) _known[id] = facts;
        }
      }
    } catch (_) {
      // Not saved yet, or unreadable: looked up again.
    }
  }

  static bool _lacks(VideoItem item) => item.duration == null || item.viewCount == null || (item.published == null && item.age == null);

  /// Whether [of] may fill anything in for [item].
  bool needs(VideoItem item) => _source != null && !item.isLive && !item.isUpcoming && _lacks(item) && _videoId.hasMatch(item.id);

  /// [item] with what it lacked filled in from what is known, asking
  /// YouTube (once) when something is missing. Lives and upcoming lives are
  /// left as they are.
  VideoItem of(VideoItem item) {
    if (item.isLive || item.isUpcoming || !_lacks(item) || !_videoId.hasMatch(item.id)) return item;
    final known = _known[item.id];
    final filled = known?.fill(item) ?? item;
    final stale = known == null || (item.viewCount == null && now().difference(known.asked) > freshFor);
    if (stale && _source != null && _tried.add(item.id)) {
      _waiting.add(item.id);
      while (_waiting.length > waitingAtMost) {
        _tried.remove(_waiting.removeAt(0));
      }
      scheduleMicrotask(_pump);
    }
    return filled;
  }

  void _pump() {
    final source = _source;
    while (source != null && _running < parallel && _waiting.isNotEmpty) {
      final id = _waiting.removeLast();
      _running++;
      source(id).then((facts) {
        if (facts != null) {
          _put(id, facts);
          notifyListeners();
        }
      }, onError: (Object _) {
        // Offline or refused: tried again next session.
      }).whenComplete(() {
        _running--;
        _pump();
      });
    }
  }

  void _put(String id, VideoFacts facts) {
    _known.remove(id);
    _known[id] = facts;
    while (_known.length > keep) {
      _known.remove(_known.keys.first);
    }
    _save?.cancel();
    _save = Timer(const Duration(seconds: 2), write);
  }

  @visibleForTesting
  Future<void> write() async {
    final file = _file;
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({for (final e in _known.entries) e.key: e.value.toJson()}));
    } catch (_) {
      // Kept in memory; written again with the next answer.
    }
  }

  static final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// The facts YouTube's /player gives for [id], asked the way a quick
  /// start asks.
  static Future<VideoFacts?> askYoutube(http.Client client, String id) async {
    final request = NativeCore.instance?.quickRequest(id);
    if (request == null) return null;
    final parts = jsonDecode(request) as Map<String, dynamic>;
    final response = await client
        .post(
          Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false'),
          headers: {'Content-Type': 'application/json', ...(parts['headers'] as Map).cast<String, String>()},
          body: jsonEncode(parts['body']),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    return VideoFacts.ofPlayer(utf8.decode(response.bodyBytes, allowMalformed: true), DateTime.now());
  }

  @visibleForTesting
  void reset() {
    _source = null;
    _file = null;
    _known.clear();
    _tried.clear();
    _waiting.clear();
    _running = 0;
    _save?.cancel();
    now = DateTime.now;
  }
}
