import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'explore_filters.dart';
import 'models.dart';
import 'native_core.dart';
import 'youtube_player_probe.dart';

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
  static const parallel = 6;
  static const _kept = 20000;

  static const _fields = 'videoDetails.title,videoDetails.shortDescription,captions.playerCaptionsTracklistRenderer.captionTracks.languageCode,'
      'captions.playerCaptionsTracklistRenderer.captionTracks.kind,streamingData.adaptiveFormats.audioTrack';
  late final _probe = YoutubePlayerProbe(_client);

  Map<String, SpokenVideo>? _known;
  final _waiting = <Completer<void>>[];
  int _running = 0;
  Timer? _save;

  static bool get available => NativeCore.instance != null;

  /// The spoken language of video [id]: null when it could not be asked;
  /// a null language when nothing in the video tells, and
  /// [ExploreLanguage.any] for a language explore does not offer.
  Future<SpokenVideo?> of(String id) async {
    final known = _known ??= await (_loading ??= _load());
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
    final read = await _readInBackground(await _probe.fetch(id, _fields, expect: 'videoDetails'));
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

  Future<Map<String, SpokenVideo>>? _loading;

  Future<Map<String, SpokenVideo>> _load() async {
    final path = file?.path;
    if (path == null) return {};
    return Isolate.run(() {
      final file = File(path);
      if (!file.existsSync()) return <String, SpokenVideo>{};
      try {
        final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        return {
          for (final MapEntry(:key, :value) in raw.entries)
            if (value is Map<String, dynamic>) key: _spoken(value),
        };
      } catch (_) {
        return <String, SpokenVideo>{};
      }
    });
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
    final path = file.path;
    // Thousands of answers: encoded and written off the UI thread.
    unawaited(Isolate.run(() {
      final out = File(path);
      out.parent.createSync(recursive: true);
      out.writeAsStringSync(jsonEncode(raw));
    }).catchError((Object e) => logInfo('Could not save video languages: $e')));
  }

  /// The lines of [lines] whose videos are spoken in [language], each
  /// with the title the uploader wrote; channels and playlists pass.
  /// Every video is asked about: a listed title, translated or the
  /// uploader's own, need not be in the language spoken. A video whose
  /// language could not be asked is judged by its listed title. Each line
  /// goes out as soon as its answer is in, a few lookups ahead of the
  /// reader.
  Stream<String> only(Stream<String> lines, ExploreLanguage language) async* {
    final pending = <_Pending>[];
    var asked = 0, kept = 0, untold = 0;
    Iterable<String> ready() sync* {
      for (final entry in [...pending]) {
        if (!entry.done) continue;
        pending.remove(entry);
        if (entry.out case final line?) yield line;
      }
    }

    try {
    await for (final line in lines) {
      final item = parseListingEntry(line);
      if (item is! VideoItem) {
        yield line;
        continue;
      }
      asked++;
      pending.add(_Pending(of(item.id).then((spoken) {
        if (spoken == null || spoken.language == null) untold++;
        if (spoken == null) return language.matches(item.title) ? line : null;
        if (spoken.language != language) return null;
        kept++;
        if (spoken.title.isEmpty || spoken.title == item.title) return line;
        return jsonEncode({...jsonDecode(line) as Map<String, dynamic>, 'title': spoken.title});
      })));
      yield* Stream.fromIterable(ready());
      while (pending.length >= parallel * 3) {
        await Future.any(pending.map((entry) => entry.future));
        yield* Stream.fromIterable(ready());
      }
    }
    while (pending.isNotEmpty) {
      await Future.any(pending.map((entry) => entry.future));
      yield* Stream.fromIterable(ready());
    }
    } finally {
      if (asked > 0) logInfo('Language ${language.name}: kept $kept of $asked videos ($untold not told)');
    }
  }
}

/// A line waiting for its video's language: [out] is the line to pass on,
/// null when the video is left out.
class _Pending {
  _Pending(Future<String?> answer) {
    future = answer.then((line) {
      out = line;
      done = true;
    });
  }

  late final Future<void> future;
  bool done = false;
  String? out;
}
