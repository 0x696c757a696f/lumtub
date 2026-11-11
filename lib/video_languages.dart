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
  /// Videos answered before hearing alone is given up on, when fewer than
  /// one in ten of them could be heard.
  static const unheardAfter = 40;

  static const _fields = 'videoDetails.title,videoDetails.shortDescription,captions.playerCaptionsTracklistRenderer.captionTracks.languageCode,'
      'captions.playerCaptionsTracklistRenderer.captionTracks.kind,streamingData.adaptiveFormats.audioTrack,streamingData.adaptiveFormats.xtags,playabilityStatus.status';
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
    // YouTube stopped answering this app for now: asking more would only
    // keep it refusing, playback included. Videos pass unchecked meanwhile.
    if (_resting case final until? when DateTime.now().isBefore(until)) return null;
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

  /// Answers without captions asked again whole, to learn whether the
  /// field mask loses them: a few each run. Every one is still asked of
  /// the other app.
  static int _compared = 0;
  static const _compare = 8;

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
    logWarn('Video languages: YouTube left the video out of half of the last 20 answers; asking none for ${rest.inMinutes} minutes, videos pass unchecked meanwhile');
  }

  @visibleForTesting
  static void reset() {
    _resting = null;
    _recent.clear();
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
      _answered(other != null);
      return other?.spoken;
    }
    _answered(true);
    if (read.spoken.heard) return read.spoken;
    // Most spoken videos have automatic captions. An answer without them
    // may have lost them to the field mask, or to YouTube answering this
    // app less than the other.
    if (!_maskDrops && _compared < _compare && _probe.masks(_fields)) {
      _compared++;
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
  /// language could not be asked at all is kept unless [heardOnly] or its
  /// listed title is plainly in a third language: listings are asked in
  /// English, so an English title says nothing, and judging by it would
  /// leave out every video while YouTube does not answer. Lines go out as
  /// their answers come in, a few lookups ahead of the reader.
  ///
  /// With [heardOnly], a video passes when its audio or automatic captions
  /// say so. Only when YouTube hardly ever tells does a title judge, and
  /// then only one that is the same asked in English and in [language], so
  /// never a translation, and [judgingByTitle] hears it, so the person can
  /// be told. After [giveUpAfter] videos with none kept, it stops;
  /// [done] hears how many were asked about and kept.
  Stream<String> only(
    Stream<String> lines,
    ExploreLanguage language, {
    bool heardOnly = false,
    int giveUpAfter = giveUpAfterDefault,
    void Function(int asked, int kept)? done,
    void Function()? judgingByTitle,
  }) async* {
    final pending = <_Pending>[];
    var asked = 0, kept = 0, untold = 0, heard = 0, unasked = 0;
    // YouTube often leaves captions and audio tracks out of the answers it
    // gives this app: then hardly any video can be heard, and only
    // hearing would keep none. Once that is plain, titles judge again, and
    // the videos held back for want of hearing are let through.
    var strict = heardOnly;
    final held = <String>[];
    final told = <String, int>{};
    Iterable<String> ready() sync* {
      // As answered: a slow answer holds back no other.
      for (final done in pending.where((p) => p.done).toList()) {
        pending.remove(done);
        if (done.out case final line?) yield line;
      }
    }

    Iterable<String> unstrict(int after) sync* {
      final answered = asked - pending.length;
      if (!strict || answered < after || heard * 10 >= answered) return;
      strict = false;
      judgingByTitle?.call();
      logInfo('Language ${language.name}: YouTube told $heard of $answered videos by captions or audio; judging by title too');
      kept += held.length;
      yield* held;
      held.clear();
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
        if (spoken != null && spoken.heard) heard++;
        told.update(spoken == null ? 'error' : spoken.heard ? spoken.source : '${spoken.source} ${spoken.language?.name ?? '?'}', (n) => n + 1, ifAbsent: () => 1);
        final shown = spoken == null || spoken.title.isEmpty || spoken.title == item.title ? line : jsonEncode({...jsonDecode(line) as Map<String, dynamic>, 'title': spoken.title});
        if (spoken == null) unasked++;
        final byText = spoken == null ? _mayBe(item.title, language) : spoken.language == language;
        if (!byText) return null;
        if (spoken != null && spoken.heard) {
          kept++;
          return shown;
        }
        // Asked in English and in [language], YouTube named the video
        // differently: a translated title, which says nothing of the
        // speech. Without hearing, such a video never passes.
        if (heardOnly && (spoken == null || (spoken.title.isNotEmpty && spoken.title != item.title))) return null;
        if (strict) {
          held.add(shown);
          return null;
        }
        kept++;
        return shown;
      })));
      yield* Stream.fromIterable(ready());
      yield* Stream.fromIterable(unstrict(unheardAfter));
      while (pending.length >= parallel * 3) {
        await Future.any([for (final p in pending) p.future]);
        yield* Stream.fromIterable(ready());
      }
    }
    while (pending.isNotEmpty) {
      await Future.any([for (final p in pending) p.future]);
      yield* Stream.fromIterable(ready());
    }
    yield* Stream.fromIterable(unstrict(10));
    } finally {
      done?.call(asked, kept);
      if (asked > 0) {
        final by = [for (final MapEntry(:key, :value) in told.entries) '$key $value'].join(', ');
        logInfo('Language ${language.name}: kept $kept of $asked videos ($untold not told, $unasked kept unchecked; by $by)');
      }
    }
  }
}

/// Whether a video listed as [title] may be spoken in [language] when
/// nothing else tells: an English title may be YouTube's translation.
bool _mayBe(String title, ExploreLanguage language) {
  if (language.matches(title)) return true;
  final read = titleLanguage(title);
  return read == ExploreLanguage.en || read == ExploreLanguage.any;
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
