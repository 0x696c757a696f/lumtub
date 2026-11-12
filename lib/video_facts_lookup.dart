import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'models.dart';
import 'native_core.dart';
import 'youtube_listing.dart';

/// What a card shows of a video and its listing may leave out: the length,
/// the views and the day it was published.
class VideoFacts {
  const VideoFacts({this.length, this.views, this.published, this.liveStatus, required this.asked});

  final int? length;
  final int? views;
  final DateTime? published;
  /// `is_live` or `is_upcoming` when the video was one when asked; a feed
  /// that does not say so would otherwise show it as a video with no length.
  final String? liveStatus;
  /// When YouTube was asked; views grow, so old answers are asked again.
  final DateTime asked;

  VideoItem fill(VideoItem item) => item.filledIn(length: length, views: views, publishedAt: published, liveStatus: liveStatus);

  List<Object?> toJson() => [length, views, published?.toUtc().toIso8601String(), asked.toUtc().toIso8601String(), if (liveStatus != null) liveStatus];

  static VideoFacts? fromJson(Object? raw) {
    if (raw is! List || raw.length < 4 || raw.length > 5) return null;
    final asked = DateTime.tryParse('${raw[3]}');
    if (asked == null) return null;
    return VideoFacts(
      length: raw[0] is int ? raw[0] as int : null,
      views: raw[1] is int ? raw[1] as int : null,
      published: raw[2] is String ? DateTime.tryParse(raw[2] as String) : null,
      liveStatus: raw.length == 5 && (raw[4] == 'is_live' || raw[4] == 'is_upcoming') ? raw[4] as String : null,
      asked: asked,
    );
  }

  static final _length = RegExp(r'"lengthSeconds"\s*:\s*"(\d+)"');
  static final _views = RegExp(r'"viewCount"\s*:\s*"(\d+)"');
  static final _published = RegExp(r'"(?:publishDate|uploadDate)"\s*:\s*"([^"]+)"');
  static final _live = RegExp(r'"isLive"\s*:\s*true');
  static final _upcoming = RegExp(r'"isUpcoming"\s*:\s*true');
  static final _streamLength = RegExp(r'"approxDurationMs"\s*:\s*"(\d+)"');

  /// The facts of a /player answer, read without decoding the whole of it;
  /// null when it has none (an error page). A live has no length; a live
  /// that has just ended says 0 until YouTube has processed it, so its
  /// length is then taken from its streams.
  static VideoFacts? ofPlayer(String answer, DateTime asked) {
    var length = int.tryParse(_length.firstMatch(answer)?.group(1) ?? '');
    final views = int.tryParse(_views.firstMatch(answer)?.group(1) ?? '');
    final published = DateTime.tryParse(_published.firstMatch(answer)?.group(1) ?? '');
    final liveStatus = _live.hasMatch(answer) ? 'is_live' : _upcoming.hasMatch(answer) ? 'is_upcoming' : null;
    if (liveStatus != null) {
      length = null;
    } else if (length == null || length == 0) {
      final streams = [for (final m in _streamLength.allMatches(answer)) int.parse(m.group(1)!)];
      length = streams.isEmpty ? null : streams.reduce((a, b) => a > b ? a : b) ~/ 1000;
    }
    if (length == null && views == null && published == null && liveStatus == null) return null;
    return VideoFacts(length: length == 0 ? null : length, views: views, published: published, liveStatus: liveStatus, asked: asked);
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
  /// A video that had no length yet (live, upcoming, or a live just ended)
  /// is asked again after this.
  static const lengthlessFor = Duration(minutes: 20);

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
    final since = known == null ? null : now().difference(known.asked);
    final stale = since == null || (item.viewCount == null && since > freshFor) || (filled.duration == null && since > lengthlessFor);
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
        // Still without a length: may be asked again once lengthlessFor has passed.
        if (facts?.length == null) _tried.remove(id);
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
  /// start asks, and when that client is refused, the way the signed-out
  /// TV client asks. Where YouTube wants both signed in (it takes some
  /// addresses for bots), the video is looked up by its id in search
  /// instead, and /player is left alone for a while.
  static Future<VideoFacts?> askYoutube(http.Client client, String id) async {
    final refused = _playerRefused;
    if (refused != null && DateTime.now().difference(refused) < playerRestFor) return ofSearch(client, id);
    final request = NativeCore.instance?.quickRequest(id);
    if (request == null) return null;
    final parts = jsonDecode(request) as Map<String, dynamic>;
    final first = await _ask(client, parts);
    final facts = first == null ? null : VideoFacts.ofPlayer(first, DateTime.now());
    if (facts != null || parts['tv'] is! Map) return facts;
    final second = await _ask(client, (parts['tv'] as Map).cast<String, dynamic>());
    final tv = second == null ? null : VideoFacts.ofPlayer(second, DateTime.now());
    if (tv != null) return tv;
    final searched = await ofSearch(client, id);
    if (!_toldWhy) {
      _toldWhy = true;
      logInfo('Video facts of $id: quick start client gave none (${first == null ? 'no answer' : playerWhy(first)}), TV client neither (${second == null ? 'no answer' : playerWhy(second)}), search ${searched == null ? 'neither' : 'did'}');
    }
    if (second != null && second.contains('"LOGIN_REQUIRED"')) _playerRefused = DateTime.now();
    return searched;
  }

  /// How long /player is left alone once it wants sign-in.
  static const playerRestFor = Duration(minutes: 30);
  static DateTime? _playerRefused;

  /// The facts of [id] as a search for it lists them: length, views and
  /// about when it came out; null when the search does not find it.
  static Future<VideoFacts?> ofSearch(http.Client client, String id) async {
    if (!YoutubeListing.available) return null;
    try {
      var seen = 0;
      await for (final line in YoutubeListing(client).search(id).timeout(const Duration(seconds: 10))) {
        final facts = factsOfListing(line, id, DateTime.now());
        if (facts != null) return facts;
        // The video, when found, is among the first results.
        if (++seen >= 5) break;
      }
    } catch (e) {
      logDebug(() => 'Video facts of $id from search: $e');
    }
    return null;
  }

  /// The facts in a listing [line] (as `yt-dlp --flat-playlist` prints
  /// one) when it is video [id]'s.
  @visibleForTesting
  static VideoFacts? factsOfListing(String line, String id, DateTime asked) {
    final Object? item;
    try {
      item = jsonDecode(line);
    } catch (_) {
      return null;
    }
    if (item is! Map<String, dynamic> || item['id'] != id) return null;
    final length = (item['duration'] as num?)?.round();
    final views = (item['view_count'] as num?)?.toInt();
    final stamp = (item['timestamp'] as num?)?.toInt();
    final live = item['live_status'];
    final liveStatus = live == 'is_live' || live == 'is_upcoming' ? live as String : null;
    if (length == null && views == null && stamp == null && liveStatus == null) return null;
    return VideoFacts(
      length: liveStatus != null || length == 0 ? null : length,
      views: views,
      published: stamp == null ? null : DateTime.fromMillisecondsSinceEpoch(stamp * 1000, isUtc: true),
      liveStatus: liveStatus,
      asked: asked,
    );
  }

  static var _toldWhy = false;

  static Future<String?> _ask(http.Client client, Map<String, dynamic> parts) async {
    final response = await client
        .post(
          Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false'),
          headers: {'Content-Type': 'application/json', ...(parts['headers'] as Map).cast<String, String>()},
          body: jsonEncode(parts['body']),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return 'HTTP ${response.statusCode}';
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  static final _status = RegExp(r'"playabilityStatus"\s*:\s*\{\s*"status"\s*:\s*"([A-Z_]+)"(?:\s*,\s*"reason"\s*:\s*"([^"]{0,120}))?');

  /// Why a /player answer had nothing, in a few words for the log.
  static String playerWhy(String answer) {
    if (answer.startsWith('HTTP ')) return answer;
    final m = _status.firstMatch(answer);
    return m == null ? 'no playability status' : [m.group(1), if (m.group(2) != null) m.group(2)].join(': ');
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
    _playerRefused = null;
    now = DateTime.now;
  }
}
