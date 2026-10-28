import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'explore_filters.dart';
import 'models.dart';
import 'native_core.dart';
import 'youtube_web.dart';

/// What a video is spoken in, and its title as the uploader wrote it.
typedef SpokenVideo = ({ExploreLanguage? language, String title});

/// Looks up the language a video is spoken in, which YouTube's listings do
/// not say: they show titles machine-translated into the listing's
/// language. Each answer comes from the video's own `/player` response
/// (see `spoken_language` in the Rust core) and is kept on disk, so a
/// video is asked about once.
class VideoLanguages {
  VideoLanguages(this._client, {this.file});

  final http.Client _client;
  final File? file;

  /// Lookups running at once.
  static const parallel = 4;
  static const _kept = 20000;

  Map<String, SpokenVideo>? _known;
  final _waiting = <Completer<void>>[];
  int _running = 0;
  Timer? _save;

  static bool get available => NativeCore.instance != null;

  /// The spoken language of video [id]: null when it could not be asked;
  /// a null language when nothing in the video tells, and
  /// [ExploreLanguage.any] for a language explore does not offer.
  Future<SpokenVideo?> of(String id) async {
    final known = _known ??= _load();
    if (known[id] case final found?) return found;
    while (_running >= parallel) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    _running++;
    try {
      final found = await _ask(id);
      if (found != null) {
        if (known.length >= _kept) known.remove(known.keys.first);
        known[id] = found;
        _save ??= Timer(const Duration(seconds: 5), _write);
      }
      return found;
    } catch (e) {
      logInfo('Could not tell the language of $id: $e');
      return null;
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }

  Future<SpokenVideo?> _ask(String id) async {
    final response = await _client
        .post(
          Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false'),
          headers: YoutubeWeb.apiHeaders(),
          body: jsonEncode({
            'context': {
              'client': {'clientName': 'WEB', 'clientVersion': YoutubeWeb.clientVersion, 'hl': 'en', 'timeZone': 'UTC', 'utcOffsetMinutes': 0},
            },
            'videoId': id,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw StateError('player answered HTTP ${response.statusCode}');
    final read = await _readInBackground(response.bodyBytes);
    if (read is! Map<String, dynamic>) return null;
    return _spoken(read);
  }

  static SpokenVideo _spoken(Map<String, dynamic> read) {
    final index = (read['language'] as num?)?.toInt() ?? 0;
    final language = index < 0
        ? ExploreLanguage.any
        : index == 0 || index >= ExploreLanguage.values.length
            ? null
            : ExploreLanguage.values[index];
    return (language: language, title: read['title']?.toString() ?? '');
  }

  // A player response runs to a few hundred kilobytes.
  static Future<Object?> _readInBackground(List<int> bytes) => Isolate.run(() {
        final core = NativeCore.instance!;
        return jsonDecode(core.take(core.withBytes(bytes, core.spokenLanguage)) ?? 'null');
      });

  Map<String, SpokenVideo> _load() {
    final file = this.file;
    if (file == null || !file.existsSync()) return {};
    try {
      final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return {
        for (final MapEntry(:key, :value) in raw.entries)
          if (value is Map<String, dynamic>) key: _spoken(value),
      };
    } catch (_) {
      return {};
    }
  }

  void _write() {
    _save = null;
    final file = this.file;
    final known = _known;
    if (file == null || known == null) return;
    final raw = {
      for (final MapEntry(:key, :value) in known.entries)
        key: {
          'language': switch (value.language) {
            null => 0,
            ExploreLanguage.any => -1,
            final language => language.index,
          },
          'title': value.title,
        },
    };
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(raw));
    } catch (e) {
      logInfo('Could not save video languages: $e');
    }
  }

  /// The lines of [lines] whose videos are spoken in [language], each
  /// with the title the uploader wrote; channels and playlists pass. A
  /// video whose language could not be asked is judged by its listed
  /// title, as before. Lookups run ahead of the reader, in order.
  Stream<String> only(Stream<String> lines, ExploreLanguage language) async* {
    final ahead = <(Map<String, dynamic>?, String, Future<SpokenVideo?>?)>[];
    Stream<String> settle(int keep) async* {
      while (ahead.length > keep) {
        final (entry, line, lookup) = ahead.removeAt(0);
        if (entry == null || lookup == null) {
          yield line;
          continue;
        }
        final spoken = await lookup;
        if (spoken == null) {
          if (language.matches(entry['title']?.toString() ?? '')) yield line;
          continue;
        }
        if (spoken.language != language) continue;
        if (spoken.title.isNotEmpty && spoken.title != entry['title']) {
          yield jsonEncode({...entry, 'title': spoken.title});
        } else {
          yield line;
        }
      }
    }

    await for (final line in lines) {
      final item = parseListingEntry(line);
      if (item is VideoItem) {
        ahead.add((jsonDecode(line) as Map<String, dynamic>, line, of(item.id)));
      } else {
        ahead.add((null, line, null));
      }
      yield* settle(parallel * 2);
    }
    yield* settle(0);
  }
}
