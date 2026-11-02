import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'explore_filters.dart';
import 'models.dart';
import 'native_core.dart';
import 'youtube_player_probe.dart';

/// What a video is spoken in, and its title as the uploader wrote it.
/// [source] says what told: audio, captions, text or none.
typedef SpokenVideo = ({ExploreLanguage? language, String title, String source});

/// One `/player` answer as the Rust core read it.
typedef _Read = ({SpokenVideo spoken, bool playable});

extension on SpokenVideo {
  /// Told by the video's audio or automatic captions, not its text.
  bool get heard => source == 'audio' || source == 'captions';
}

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
  static const giveUpAfterDefault = 240;

  static const _fields = 'videoDetails.title,videoDetails.shortDescription,captions.playerCaptionsTracklistRenderer.captionTracks.languageCode,'
      'captions.playerCaptionsTracklistRenderer.captionTracks.kind,streamingData.adaptiveFormats.audioTrack,playabilityStatus.status';
  late final _probe = YoutubePlayerProbe(_client);

  Map<String, SpokenVideo>? _known;
  /// The language the texts of a known answer were asked in, when not
  /// English.
  final _askedIn = <String, String>{};
  final _waiting = <Completer<void>>[];
  int _running = 0;
  Timer? _save;

  static bool get available => NativeCore.instance != null;

  /// The spoken language of video [id]: null when it could not be asked;
  /// a null language when nothing in the video tells, and
  /// [ExploreLanguage.any] for a language explore does not offer.
  ///
  /// [asking] is the language looked for. The title and description are
  /// asked in it: asked in English, an uploader's English translation of
  /// the title would make an Italian video read as English when nothing
  /// else tells.
  Future<SpokenVideo?> of(String id, {ExploreLanguage asking = ExploreLanguage.any}) async {
    final known = _known ??= await (_loading ??= _load());
    final hl = asking == ExploreLanguage.any ? 'en' : asking.code;
    if (known[id] case final found?) {
      // Told by text read in English before titles were asked in the
      // language looked for: asked again.
      final stale = found.source == 'text' && found.language == ExploreLanguage.en && hl != 'en' && (_askedIn[id] ?? 'en') == 'en';
      if (!stale) return found;
    }
    while (_running >= parallel) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    _running++;
    try {
        final found = await _ask(id, hl);
        if (found != null && (found.heard || found.language != null)) {
          if (known.length >= _kept) {
            final oldest = known.keys.first;
            known.remove(oldest);
            _askedIn.remove(oldest);
          }
          known[id] = found;
          if (hl == 'en') {
            _askedIn.remove(id);
          } else {
            _askedIn[id] = hl;
          }
          _save ??= Timer(const Duration(seconds: 5), _write);
        }
        return found;
      } catch (e) {
        logWarn('Could not tell the language of $id: $e');
        return null;
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }

  /// Whether answers come whole: set once a whole answer has captions its
  /// masked one left out.
  static bool _maskDrops = false;

  /// Whether the TV app is asked first: set once it has captions where
  /// the website answered without them.
  static bool _tvFirst = false;

  /// Answers without captions asked again another way, a few each run:
  /// whole, and of the other app.
  static int _compared = 0;
  static const _compare = 8;

  @visibleForTesting
  static void reset() {
    _maskDrops = false;
    _tvFirst = false;
    _compared = 0;
  }

  Future<_Read?> _fetch(String id, String hl, {required bool tv, bool whole = false}) async {
    final read = await _readInBackground(await _probe.fetch(id, whole || _maskDrops ? null : _fields, expect: 'videoDetails', tv: tv, hl: hl));
    if (read is! Map<String, dynamic>) return null;
    return (spoken: _spoken(read), playable: read['playable'] != false);
  }

  Future<SpokenVideo?> _ask(String id, String hl) async {
    final read = await _fetch(id, hl, tv: _tvFirst);
    if (read == null) {
      // No video in the answer at all, as when YouTube wants this app to
      // prove it is not a bot: the other one is asked.
      final other = await _fetch(id, hl, tv: !_tvFirst);
      if (other != null && other.spoken.heard) {
        _tvFirst = !_tvFirst;
        logInfo('Video languages: ${_tvFirst ? 'the website' : 'the TV app'} answered without the video; asking ${_tvFirst ? 'the TV app' : 'the website'} first');
      }
      return other?.spoken;
    }
    if (read.spoken.heard || _compared >= _compare) return read.spoken;
    // Most spoken videos have automatic captions. An answer without them
    // may have lost them to the field mask, or to YouTube answering this
    // app less than the other.
    _compared++;
    if (!_maskDrops && _probe.masks(_fields)) {
      final whole = await _fetch(id, hl, tv: _tvFirst, whole: true);
      if (whole != null && whole.spoken.heard) {
        _maskDrops = true;
        logInfo('The /player field mask left out captions; asking for whole answers');
        return whole.spoken;
      }
    }
    final other = await _fetch(id, hl, tv: !_tvFirst);
    if (other != null && other.spoken.heard) {
      _tvFirst = !_tvFirst;
      logInfo('Video languages: ${_tvFirst ? 'the TV app' : 'the website'} answers with captions where ${_tvFirst ? 'the website' : 'the TV app'} does not; asking it first');
      return other.spoken;
    }
    if (_compared == _compare) logInfo('Video languages: $_compare answers without captions had none asked whole or of the other app either');
    return !read.playable && other != null && other.playable ? other.spoken : read.spoken;
  }

  static SpokenVideo _spoken(Map<String, dynamic> read) {
    final index = (read['language'] as num?)?.toInt() ?? 0;
    final language = index < 0
        ? ExploreLanguage.any
        : index == 0 || index >= ExploreLanguage.values.length
            ? null
            : ExploreLanguage.values[index];
    return (language: language, title: read['title']?.toString() ?? '', source: read['source']?.toString() ?? 'audio');
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
    final (known, askedIn) = await Isolate.run(() {
      final file = File(path);
      final none = (<String, SpokenVideo>{}, <String, String>{});
      if (!file.existsSync()) return none;
      try {
        final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        return (
          {
            for (final MapEntry(:key, :value) in raw.entries)
              if (value is Map<String, dynamic>) key: _spoken(value),
          },
          {
            for (final MapEntry(:key, :value) in raw.entries)
              if (value is Map<String, dynamic> && value['hl'] is String) key: value['hl'] as String,
          },
        );
      } catch (_) {
        return none;
      }
    });
    _askedIn.addAll(askedIn);
    return known;
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
          'source': value.source,
          if (_askedIn[key] case final hl?) 'hl': hl,
        },
    };
    final path = file.path;
    // Thousands of answers: encoded and written off the UI thread.
    unawaited(Isolate.run(() {
      final out = File(path);
      out.parent.createSync(recursive: true);
      // Written beside and then swapped in, so a crash mid-write leaves
      // the last whole file.
      final next = File('$path.tmp')..writeAsStringSync(jsonEncode(raw), flush: true);
      next.renameSync(path);
    }).catchError((Object e) => logWarn('Could not save video languages: $e')));
  }

  /// The lines of [lines] whose videos are spoken in [language], each
  /// with the title the uploader wrote; channels and playlists pass.
  /// Every video is asked about: a listed title, translated or the
  /// uploader's own, need not be in the language spoken. A video whose
  /// language could not be asked is judged by its listed title. Each line
  /// goes out as soon as its answer is in, a few lookups ahead of the
  /// reader.
  ///
  /// With [heardOnly], a video only passes when its audio or automatic
  /// captions say so. After [giveUpAfter] videos with none kept, it stops;
  /// [done] hears how many were asked about and kept.
  Stream<String> only(
    Stream<String> lines,
    ExploreLanguage language, {
    bool heardOnly = false,
    int giveUpAfter = giveUpAfterDefault,
    void Function(int asked, int kept)? done,
  }) async* {
    final pending = <_Pending>[];
    var asked = 0, kept = 0, untold = 0;
    final told = <String, int>{};
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
      // Nothing in the first few hundred: the search found none to show.
      if (asked >= giveUpAfter && kept == 0) break;
      asked++;
      pending.add(_Pending(of(item.id, asking: language).then((spoken) {
        if (spoken == null || spoken.language == null) untold++;
        told.update(spoken == null ? 'error' : spoken.heard ? spoken.source : '${spoken.source} ${spoken.language?.name ?? '?'}', (n) => n + 1, ifAbsent: () => 1);
        if (spoken == null) return language.matches(item.title) ? line : null;
        if (spoken.language != language || (heardOnly && !spoken.heard)) return null;
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
      done?.call(asked, kept);
      if (asked > 0) {
        final by = [for (final MapEntry(:key, :value) in told.entries) '$key $value'].join(', ');
        logInfo('Language ${language.name}: kept $kept of $asked videos ($untold not told; by $by)');
      }
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
