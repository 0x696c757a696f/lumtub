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
  /// Answers after which the filter stops when none of them told by audio
  /// or captions.
  static const unheardAfter = 40;

  static const _fields = 'videoDetails.title,videoDetails.shortDescription,captions.playerCaptionsTracklistRenderer.captionTracks.languageCode,'
      'captions.playerCaptionsTracklistRenderer.captionTracks.kind,streamingData.adaptiveFormats.audioTrack,streamingData.adaptiveFormats.xtags,playabilityStatus.status';
  late final _probe = YoutubePlayerProbe(_client);

  Map<String, SpokenVideo>? _known;
  final _waiting = <Completer<void>>[];
  int _running = 0;
  Timer? _save;

  static bool get available => NativeCore.instance != null;

  /// The spoken language of video [id]: null when it could not be asked;
  /// a null language when nothing in the video tells, and
  /// [ExploreLanguage.any] for a language explore does not offer.
  ///
  /// [asking] is the language looked for: the title comes in it, as the
  /// person reading the list would want it.
  ///
  /// Only what audio or captions told is kept: an answer without either
  /// is asked again next time, when YouTube may tell.
  Future<SpokenVideo?> of(String id, {ExploreLanguage asking = ExploreLanguage.any}) async {
    final known = _known ??= await (_loading ??= _load());
    final hl = asking == ExploreLanguage.any ? 'en' : asking.code;
    if (known[id] case final found?) return found;
    // YouTube stopped answering this app for now: asking more would only
    // keep it refusing, playback included.
    if (_resting case final until? when DateTime.now().isBefore(until)) return null;
    while (_running >= parallel) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    _running++;
    try {
      final found = await _ask(id, hl);
      if (found != null && found.heard) {
        if (known.length >= _kept) known.remove(known.keys.first);
        known[id] = found;
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

  /// The app asked first: the one that last told a video by its captions
  /// or audio. The others are asked when it does not tell.
  static PlayerClient _first = PlayerClient.quick;

  /// Until when no video is asked about, after YouTube left the video out
  /// of half of the last answers.
  static DateTime? _resting;
  static final _recent = <bool>[];
  static const rest = Duration(minutes: 10);

  static void _answered(bool withVideo) {
    _recent.add(withVideo);
    if (_recent.length > 20) _recent.removeAt(0);
    if (_recent.length < 20 || _recent.where((v) => !v).length < 10) return;
    _recent.clear();
    _resting = DateTime.now().add(rest);
    logWarn('Video languages: YouTube left the video out of half of the last 20 answers; asking none for ${rest.inMinutes} minutes');
  }

  @visibleForTesting
  static void reset() {
    _resting = null;
    _recent.clear();
    _first = PlayerClient.quick;
  }

  Future<_Read?> _fetch(String id, String hl, PlayerClient client) async {
    try {
      final read = await _readInBackground(await _probe.fetchAs(client, id, _fields, expect: 'videoDetails', hl: hl));
      if (read is! Map<String, dynamic>) return null;
      return (spoken: _spoken(read), playable: read['playable'] != false);
    } catch (e) {
      logDebug(() => 'Video languages: ${client.name} gave no answer for $id: $e');
      return null;
    }
  }

  /// Each app in turn until one tells by captions or audio: YouTube gives
  /// them to one app and leaves them out for another, and which one
  /// changes. An answer that does not tell is still better than none.
  Future<SpokenVideo?> _ask(String id, String hl) async {
    _Read? best;
    var withVideo = false;
    for (final client in [_first, ...PlayerClient.values.where((c) => c != _first)]) {
      final read = await _fetch(id, hl, client);
      if (read == null) continue;
      withVideo = true;
      if (read.spoken.heard) {
        if (client != _first) {
          logInfo('Video languages: the ${client.name} app tells by captions or audio where the ${_first.name} app does not; asking it first');
          _first = client;
        }
        _answered(true);
        return read.spoken;
      }
      if (best == null || (!best.playable && read.playable)) best = read;
    }
    _answered(withVideo);
    return best?.spoken;
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
  /// A masked answer of a few kilobytes is read here: starting an isolate
  /// and copying it there takes longer than reading it. A whole one goes
  /// to the background.
  static Future<Object?> _readInBackground(List<int> bytes) async => bytes.length < 32 << 10 ? _read(bytes) : Isolate.run(() => _read(bytes));

  static Object? _read(List<int> bytes) {
    final core = NativeCore.instance!;
    return jsonDecode(core.take(core.withBytes(bytes, core.spokenLanguage)) ?? 'null');
  }

  Future<Map<String, SpokenVideo>>? _loading;

  Future<Map<String, SpokenVideo>> _load() async {
    final path = file?.path;
    if (path == null) return {};
    return Isolate.run(() {
      final file = File(path);
      if (!file.existsSync()) return <String, SpokenVideo>{};
      try {
        final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        // Answers kept by earlier versions include guesses from titles,
        // which no longer decide: only what audio or captions told is
        // read back.
        return {
          for (final MapEntry(:key, :value) in raw.entries)
            if (value is Map<String, dynamic> && _spoken(value).heard) key: _spoken(value),
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
          'source': value.source,
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
  /// with the title YouTube gives in [language]; channels and playlists
  /// pass. Lines go out as their answers come in, a few lookups ahead of
  /// the reader. What decides is set out in docs/specs/explore-language.md
  /// and in [passes].
  ///
  /// It stops after [giveUpAfter] videos with none kept, and after
  /// [unheardAfter] answers of which none told by audio or captions;
  /// [done] hears how many were asked about, kept and heard.
  Stream<String> only(
    Stream<String> lines,
    ExploreLanguage language, {
    int giveUpAfter = giveUpAfterDefault,
    void Function(LanguageCheck check)? done,
  }) async* {
    final pending = <_Pending>[];
    var asked = 0, answered = 0, kept = 0, heard = 0;
    final told = <String, int>{};
    Iterable<String> ready() sync* {
      // As answered: a slow answer holds back no other.
      for (final done in pending.where((p) => p.done).toList()) {
        pending.remove(done);
        if (done.out case final line?) yield line;
      }
    }

    bool deaf() => heard == 0 && answered >= unheardAfter;

    try {
      await for (final line in lines) {
        final item = parseListingEntry(line);
        if (item is! VideoItem) {
          yield line;
          continue;
        }
        // Nothing in the first few hundred: the search found none to show.
        if (asked >= giveUpAfter && kept == 0) break;
        if (deaf()) break;
        asked++;
        pending.add(_Pending(of(item.id, asking: language).then((spoken) {
          answered++;
          if (spoken != null && spoken.heard) heard++;
          final key = spoken == null ? 'no answer' : '${spoken.source} ${spoken.language?.name ?? '?'}';
          told.update(key, (n) => n + 1, ifAbsent: () => 1);
          if (!passes(spoken, language)) return null;
          kept++;
          return spoken == null || spoken.title.isEmpty || spoken.title == item.title ? line : jsonEncode({...jsonDecode(line) as Map<String, dynamic>, 'title': spoken.title});
        })));
        yield* Stream.fromIterable(ready());
        while (pending.length >= parallel * 3) {
          await Future.any([for (final p in pending) p.future]);
          yield* Stream.fromIterable(ready());
        }
      }
      while (pending.isNotEmpty) {
        await Future.any([for (final p in pending) p.future]);
        yield* Stream.fromIterable(ready());
      }
    } finally {
      done?.call((asked: asked, kept: kept, heard: heard));
      if (asked > 0) {
        final by = [for (final MapEntry(:key, :value) in told.entries) '$key $value'].join(', ');
        logInfo('Language ${language.name}: kept $kept of $asked videos, '
            '$heard told by audio or captions${deaf() ? ', stopped as none was' : ''}; $by');
      }
    }
  }

  /// Whether a video answered with [spoken] (null when YouTube did not
  /// answer) is shown for [language]: only when its original audio track
  /// or its automatic captions say so. Titles and descriptions never
  /// decide, as uploaders and YouTube translate them.
  @visibleForTesting
  static bool passes(SpokenVideo? spoken, ExploreLanguage language) => spoken != null && spoken.heard && spoken.language == language;
}

/// What a language check went over: videos asked about, kept, and told
/// by their audio or captions.
typedef LanguageCheck = ({int asked, int kept, int heard});

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
