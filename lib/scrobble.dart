import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_directories.dart';
import 'app_log.dart';
import 'models.dart';
import 'secure_store.dart';

/// A song as ListenBrainz is told about it.
class ScrobbleTrack {
  const ScrobbleTrack({required this.artist, required this.title, this.album, required this.videoId, this.length});
  final String artist;
  final String title;
  final String? album;
  final String videoId;
  final Duration? length;

  @override
  bool operator ==(Object other) => other is ScrobbleTrack && other.artist == artist && other.title == title && other.album == album && other.videoId == videoId;

  @override
  int get hashCode => Object.hash(artist, title, album, videoId);

  @override
  String toString() => '$artist – $title';
}

/// The song [item] is, or null when it is not clearly one. Only videos that
/// say plainly that they are a song count: YouTube Music's song tags, an
/// auto-generated "Artist - Topic" upload, or a video in YouTube's Music
/// category whose title names the artist or calls itself an official
/// video. Talks, covers explained, mixes and anything live are left out.
ScrobbleTrack? scrobbleTrackOf(VideoItem item, VideoDetails? details, {Duration? length}) {
  if (item.isLive || item.isUpcoming || item.isShortListing) return null;
  final seconds = length?.inSeconds ?? item.duration;
  // Shorter than 30 seconds is not scrobbled by the rules of ListenBrainz
  // and Last.fm; past 15 minutes it is a mix or a whole album.
  if (seconds == null || seconds < 30 || seconds > 15 * 60) return null;
  final duration = Duration(seconds: seconds);
  final title = (details?.title.isNotEmpty ?? false ? details!.title : item.title).trim();
  final channel = (details?.channel.isNotEmpty ?? false ? details!.channel : item.channel).trim();
  final music = details?.music ?? const MusicTags();
  ScrobbleTrack song(String artist, String name, [String? album]) =>
      ScrobbleTrack(artist: artist.trim(), title: name.trim(), album: album?.trim(), videoId: item.id, length: duration);

  if (music.track != null && music.artists.isNotEmpty) return song(music.artists.join(', '), music.track!, music.album);

  final description = details?.description ?? item.description ?? '';
  if (description.startsWith('Provided to YouTube by')) {
    // Auto-generated: "Track · Artist · Artist" on its own line, then the album.
    final lines = const LineSplitter().convert(description).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    for (var i = 1; i < lines.length; i++) {
      final parts = lines[i].split(' · ');
      if (parts.length < 2) continue;
      final album = i + 1 < lines.length && !lines[i + 1].startsWith('℗') ? lines[i + 1] : null;
      return song(parts.skip(1).join(', '), parts.first, album);
    }
  }

  if (channel.endsWith(' - Topic') && channel.length > 8) return song(channel.substring(0, channel.length - 8), cleanSongTitle(title));

  final official = _officialMarker.hasMatch(title);
  if (!music.inMusicCategory && !official) return null;
  if (splitArtistTitle(title) case (final artist, final name)?) return song(artist, name);
  if (!official && !_vevo.hasMatch(channel)) return null;
  final name = cleanSongTitle(title);
  var artist = channel.replaceFirst(RegExp(r'\s*(official|officiel|oficial)$', caseSensitive: false), '').trim();
  // "TaylorSwiftVEVO" names the artist without spaces.
  if (_vevo.hasMatch(artist)) artist = artist.replaceFirst(_vevo, '').replaceAllMapped(RegExp(r'(\p{Ll})(\p{Lu})', unicode: true), (m) => '${m[1]} ${m[2]}');
  if (name.isEmpty || artist.isEmpty) return null;
  return song(artist, name);
}

final _officialMarker = RegExp(r'[(\[【「]\s*(official\s+(music\s+)?(video|audio|lyric video|visuali[sz]er|mv)|music video|lyric video|visuali[sz]er|m/?v)\s*[)\]】」]', caseSensitive: false);
final _vevo = RegExp(r'\s*VEVO$');

/// "Artist - Title (Official Video)" as artist and title, or null when the
/// title names no artist that way.
(String, String)? splitArtistTitle(String title) {
  final match = RegExp(r'^(.+?)\s+[-–—]{1,2}\s+(.+)$').firstMatch(title);
  if (match == null) return null;
  final artist = match[1]!.trim();
  final name = cleanSongTitle(match[2]!);
  if (artist.isEmpty || name.isEmpty || artist.length > 80) return null;
  return (artist, name);
}

/// [title] without the "(Official Video)", "[Lyrics]", "| 4K" and the like
/// that say what the upload is rather than what the song is called. A
/// "(Live)" or "(feat. …)" is part of the song and stays.
String cleanSongTitle(String title) {
  var name = title;
  name = name.replaceAll(RegExp(r'\s*[(\[【「][^)\]】」]*(official|video|audio|lyric|visuali[sz]er|\bm/?v\b|\bhd\b|\bhq\b|\b4k\b|1080p|remaster|color coded)[^)\]】」]*[)\]】」]', caseSensitive: false), '');
  name = name.replaceFirst(RegExp(r'\s+[|｜].*$'), '');
  name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
  // Quotes around the title: Artist - "Song"
  final quoted = RegExp(r'^["“‘](.+)["”’]$').firstMatch(name);
  return quoted == null ? name : quoted[1]!.trim();
}

/// When a song has been listened to long enough to count: half its length
/// or four minutes, whichever comes first, as ListenBrainz and Last.fm ask.
Duration scrobbleThreshold(Duration length) {
  final half = Duration(milliseconds: length.inMilliseconds ~/ 2);
  return half < const Duration(minutes: 4) ? half : const Duration(minutes: 4);
}

class ScrobbleException implements Exception {
  const ScrobbleException(this.message, {this.badToken = false, this.retry = false});
  final String message;
  /// The token was refused: nothing more is sent until it is replaced.
  final bool badToken;
  /// Worth sending again later: no network, a busy server.
  final bool retry;

  @override
  String toString() => message;
}

/// The ListenBrainz API (listenbrainz.org, or a server of its kind).
class ListenBrainzApi {
  ListenBrainzApi(this._client, {this.host = 'api.listenbrainz.org', this.version = ''});
  final http.Client _client;
  final String host;
  final String version;

  Map<String, String> _headers(String token) => {
        'Authorization': 'Token ${token.trim()}',
        'Content-Type': 'application/json',
        'User-Agent': 'Lumtub/$version',
      };

  /// The user name the token belongs to.
  Future<String> validate(String token) async {
    final http.Response response;
    try {
      response = await _client.get(Uri.https(host, '/1/validate-token'), headers: _headers(token)).timeout(const Duration(seconds: 15));
    } catch (e) {
      throw ScrobbleException('$e', retry: true);
    }
    final data = _json(response.body);
    if (response.statusCode == 200 && data['valid'] == true && data['user_name'] is String) return data['user_name'] as String;
    if (response.statusCode == 200 || response.statusCode == 401) throw const ScrobbleException('The token was not accepted', badToken: true);
    throw ScrobbleException('ListenBrainz HTTP ${response.statusCode}', retry: response.statusCode == 429 || response.statusCode >= 500);
  }

  /// Sends [listens] as [type]: playing_now, single or import.
  Future<void> submit(String token, String type, List<Map<String, dynamic>> listens) async {
    final http.Response response;
    try {
      response = await _client
          .post(Uri.https(host, '/1/submit-listens'), headers: _headers(token), body: jsonEncode({'listen_type': type, 'payload': listens}))
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      throw ScrobbleException('$e', retry: true);
    }
    if (response.statusCode == 200) return;
    final reason = _json(response.body)['error'];
    final message = 'ListenBrainz HTTP ${response.statusCode}${reason is String ? ': $reason' : ''}';
    if (response.statusCode == 401) throw ScrobbleException(message, badToken: true);
    throw ScrobbleException(message, retry: response.statusCode == 429 || response.statusCode >= 500);
  }

  static Map<String, dynamic> _json(String body) {
    try {
      final data = jsonDecode(body);
      return data is Map<String, dynamic> ? data : const {};
    } catch (_) {
      return const {};
    }
  }

  /// One listen of [track], begun at [at]; without [at] it is what is playing now.
  static Map<String, dynamic> listen(ScrobbleTrack track, {DateTime? at, String version = ''}) => {
        if (at != null) 'listened_at': at.millisecondsSinceEpoch ~/ 1000,
        'track_metadata': {
          'artist_name': track.artist,
          'track_name': track.title,
          if (track.album != null) 'release_name': track.album,
          'additional_info': {
            'media_player': 'Lumtub',
            if (version.isNotEmpty) 'media_player_version': version,
            'submission_client': 'Lumtub',
            if (version.isNotEmpty) 'submission_client_version': version,
            'music_service': 'youtube.com',
            'music_service_name': 'YouTube',
            'origin_url': 'https://www.youtube.com/watch?v=${track.videoId}',
            if (track.length != null) 'duration_ms': track.length!.inMilliseconds,
          },
        },
      };
}

/// 听歌记录: tells the user's ListenBrainz account which songs were
/// listened to. Off until a token is given; the token is kept sealed like
/// the sign-ins. Listens that could not be sent wait in a file and go with
/// the next one that can.
class Scrobbler {
  Scrobbler(http.Client client, {this.version = '', DateTime Function()? clock})
      : _api = ListenBrainzApi(client, version: version),
        _clock = clock ?? DateTime.now;
  final ListenBrainzApi _api;
  final String version;
  final DateTime Function() _clock;

  SecureJsonFile? accountFile;
  File? queueFile;

  String? _token;
  String? user;
  /// Set when ListenBrainz refused the token after it was saved.
  bool tokenRefused = false;
  final _queue = <Map<String, dynamic>>[];
  static const _queueLimit = 1000;
  bool _sending = false;

  bool get connected => _token != null;
  int get waiting => _queue.length;

  Future<void> load() async {
    _queue.clear();
    final saved = await accountFile?.read();
    if (saved?['listenBrainzToken'] case final String token when token.isNotEmpty) {
      _token = token;
      user = saved?['listenBrainzUser'] as String?;
    }
    final file = queueFile;
    if (file == null || !await file.exists()) return;
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is List) _queue.addAll(data.whereType<Map<String, dynamic>>());
    } catch (e) {
      await setBrokenFileAside(file, e);
    }
  }

  /// Checks [token] with ListenBrainz and keeps it. Returns the user name.
  Future<String> connect(String token) async {
    final name = await _api.validate(token);
    _token = token.trim();
    user = name;
    tokenRefused = false;
    await accountFile?.write({'listenBrainzToken': _token, 'listenBrainzUser': name});
    unawaited(_sendWaiting());
    return name;
  }

  Future<void> disconnect() async {
    _token = null;
    user = null;
    tokenRefused = false;
    _queue.clear();
    await accountFile?.delete();
    await _saveQueue();
  }

  // The song being listened to.
  ScrobbleTrack? _track;
  DateTime? _startedAt;
  Duration _listened = Duration.zero;
  DateTime? _tick;
  Duration _lastPosition = Duration.zero;
  bool _announced = false;
  bool _scrobbled = false;
  String? _videoId;

  /// A new video started: what was counted for the last one is dropped.
  void begin(String videoId) {
    _videoId = videoId;
    _track = null;
    _restart();
  }

  void _restart() {
    _startedAt = null;
    _listened = Duration.zero;
    _tick = null;
    _lastPosition = Duration.zero;
    _announced = false;
    _scrobbled = false;
  }

  /// Follows playback of [item]: called as its position moves. [track] is
  /// what [scrobbleTrackOf] made of it, null when it is not a song.
  void observe(ScrobbleTrack? track, {required Duration position, required bool playing}) {
    if (!connected || tokenRefused) return;
    if (track == null || track.videoId != _videoId) {
      _tick = null;
      return;
    }
    if (_track != track) _track = track;
    final length = track.length;
    // Looped or played again from the start after nearly finishing: a new listen.
    if (length != null && position < const Duration(seconds: 3) && _lastPosition > length - const Duration(seconds: 10)) _restart();
    _lastPosition = position;
    final now = _clock();
    final last = _tick;
    _tick = playing ? now : null;
    if (!playing) return;
    _startedAt ??= now;
    if (last != null) {
      final gap = now.difference(last);
      // A long gap is a sleep or a stall, not listening.
      if (gap > Duration.zero && gap < const Duration(seconds: 5)) _listened += gap;
    }
    if (!_announced && _listened >= const Duration(seconds: 5)) {
      _announced = true;
      unawaited(_send('playing_now', [ListenBrainzApi.listen(track, version: version)]));
    }
    if (!_scrobbled && length != null && _listened >= scrobbleThreshold(length)) {
      _scrobbled = true;
      logInfo('Scrobbling a song to ListenBrainz');
      final listen = ListenBrainzApi.listen(track, at: _startedAt, version: version);
      unawaited(() async {
        final sent = await _send('single', [listen]);
        if (sent == _Sent.later) {
          _queue.add(listen);
          if (_queue.length > _queueLimit) _queue.removeRange(0, _queue.length - _queueLimit);
          await _saveQueue();
        } else if (sent == _Sent.yes) {
          await _sendWaiting();
        }
      }());
    }
  }

  /// Sends the listens that could not be sent before, oldest first.
  Future<void> _sendWaiting() async {
    if (_queue.isEmpty || _sending) return;
    _sending = true;
    try {
      while (_queue.isNotEmpty) {
        final batch = _queue.take(100).toList();
        final sent = await _send('import', batch);
        if (sent == _Sent.later) return;
        // Refused for what is in it, not for the network: sending it again
        // would be refused again, and hold back the rest.
        if (sent == _Sent.no) logWarn('Dropped ${batch.length} listens ListenBrainz refused');
        _queue.removeRange(0, batch.length);
        await _saveQueue();
      }
    } finally {
      _sending = false;
    }
  }

  /// Retries the listens waiting, after the network came back or at start.
  Future<void> retryWaiting() => _sendWaiting();

  /// Whether ListenBrainz took [listens]. A refused token stops sending
  /// and keeps what waits, for when the token is replaced.
  Future<_Sent> _send(String type, List<Map<String, dynamic>> listens) async {
    final token = _token;
    if (token == null || tokenRefused) return _Sent.later;
    try {
      await _api.submit(token, type, listens);
      return _Sent.yes;
    } on ScrobbleException catch (e) {
      if (e.badToken) tokenRefused = true;
      logWarn('ListenBrainz did not take the $type listen: ${e.message}');
      return e.badToken || e.retry ? _Sent.later : _Sent.no;
    }
  }

  Future<void> _saveQueue() async {
    final file = queueFile;
    if (file == null) return;
    try {
      if (_queue.isEmpty) {
        if (await file.exists()) await file.delete();
        return;
      }
      await file.writeAsString(jsonEncode(_queue), flush: true);
    } catch (e) {
      logWarn('Could not save the listens waiting for ListenBrainz: $e');
    }
  }
}

enum _Sent { yes, later, no }
