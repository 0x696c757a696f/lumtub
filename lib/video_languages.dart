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
      'captions.playerCaptionsTracklistRenderer.captionTracks.kind,streamingData.adaptiveFormats.audioTrack,streamingData.adaptiveFormats.xtags,playabilityStatus.status';
  late final _probe = YoutubePlayerProbe(_client);

  Map<String, SpokenVideo>? _known;
  /// Answers without audio or captions, by video and language asked in,
  /// for this run only: YouTube may tell next time.
  final _unheard = <String, SpokenVideo>{};
  static const _unheardKept = 5000;

  /// The channel of each known video, when the listing gave it.
  final _channelOf = <String, String>{};
  /// How many known videos of each channel are spoken in each language.
  final _channels = <String, Map<ExploreLanguage?, int>>{};
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
  /// Only what audio or captions told is kept on disk: an answer without
  /// either is kept until Lumtub is closed, and asked again after that, as
  /// YouTube may tell by then.
  Future<SpokenVideo?> of(String id, {ExploreLanguage asking = ExploreLanguage.any, String? channel}) async {
    final known = _known ??= await (_loading ??= _load());
    final hl = asking == ExploreLanguage.any ? 'en' : asking.code;
    if (known[id] case final found?) {
      if (channel != null && !_channelOf.containsKey(id)) _count(id, channel, found.language);
      return found;
    }
    if (_unheard['$id $hl'] case final found?) return found;
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
        if (known.length >= _kept) _forget(known.keys.first);
        known[id] = found;
        if (channel != null) _count(id, channel, found.language);
        _save ??= Timer(const Duration(seconds: 5), _write);
      } else if (found != null) {
        if (_unheard.length >= _unheardKept) _unheard.remove(_unheard.keys.first);
        _unheard['$id $hl'] = found;
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

  void _count(String id, String channel, ExploreLanguage? language) {
    _channelOf[id] = channel;
    final counts = _channels.putIfAbsent(channel, () => {});
    counts[language] = (counts[language] ?? 0) + 1;
  }

  void _forget(String id) {
    final language = _known?.remove(id)?.language;
    final channel = _channelOf.remove(id);
    final counts = channel == null ? null : _channels[channel];
    if (counts == null) return;
    if ((counts[language] = (counts[language] ?? 1) - 1) <= 0) counts.remove(language);
    if (counts.isEmpty) _channels.remove(channel);
  }

  /// Videos of a channel heard, all in one language, before its other
  /// videos are taken to be in it too.
  static const channelSure = 3;

  /// The language every video heard of [channel] is spoken in, once at
  /// least [channelSure] were; null while that is not plain. Explore
  /// leaves out a channel plainly in another language without asking
  /// about its videos.
  ExploreLanguage? channelSpeaks(String channel) {
    final counts = _channels[channel];
    if (counts == null || counts.length != 1) return null;
    final MapEntry(:key, :value) = counts.entries.single;
    return value >= channelSure ? key : null;
  }

  /// Less than zero: how many times in a row the other apps were asked
  /// about a video the first one answered without captions, and did not
  /// tell either.
  static int _othersTold = 0;
  static const _othersGiveUp = 20;

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
    _othersTold = 0;
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
      // The first app answered whole, and asking the others has not told
      // more for a while: most videos in Chinese and many other languages
      // have no automatic captions in any app. One video in
      // [_othersGiveUp] still asks them, in case that changed.
      if (best != null && best.playable && _othersTold <= -_othersGiveUp && --_othersTold % _othersGiveUp != 0) break;
      final read = await _fetch(id, hl, client);
      if (read == null) continue;
      withVideo = true;
      if (read.spoken.heard) {
        if (client != _first) {
          logInfo('Video languages: the ${client.name} app tells by captions or audio where the ${_first.name} app does not; asking it first');
          _first = client;
          _othersTold = 0;
        }
        _answered(true);
        return read.spoken;
      }
      if (best != null) _othersTold--;
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
    final (known, channels) = await Isolate.run(() {
      final file = File(path);
      final none = (<String, SpokenVideo>{}, <String, String>{});
      if (!file.existsSync()) return none;
      try {
        final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        // Answers kept by earlier versions include guesses from titles,
        // which no longer decide: only what audio or captions told is
        // read back.
        final heard = {
          for (final MapEntry(:key, :value) in raw.entries)
            if (value is Map<String, dynamic> && _spoken(value).heard) key: value,
        };
        return (
          {for (final MapEntry(:key, :value) in heard.entries) key: _spoken(value)},
          {
            for (final MapEntry(:key, :value) in heard.entries)
              if (value['channel'] case final String channel) key: channel,
          },
        );
      } catch (_) {
        return none;
      }
    });
    for (final MapEntry(:key, :value) in channels.entries) {
      _count(key, value, known[key]?.language);
    }
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
          if (_channelOf[key] case final channel?) 'channel': channel,
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
  /// pass. What decides is set out in docs/specs/explore-language.md and
  /// in [passes].
  ///
  /// Videos confirmed by audio or captions go out as their answers come
  /// in, a few lookups ahead of the reader. Videos without either, let in
  /// by their own texts, wait behind them: they go out [heldUpTo] at a
  /// time, or at the end.
  ///
  /// It stops after [giveUpAfter] videos with none kept; [done] hears how
  /// many were asked about, kept and heard.
  Stream<String> only(
    Stream<String> lines,
    ExploreLanguage language, {
    int giveUpAfter = giveUpAfterDefault,
    int heldUpTo = 12,
    void Function(LanguageCheck check)? done,
  }) async* {
    final pending = <_Pending>[];
    final held = <String>[];
    var asked = 0, kept = 0, heard = 0;
    final told = <String, int>{};
    Iterable<String> ready() sync* {
      // As answered: a slow answer holds back no other.
      for (final done in pending.where((p) => p.done).toList()) {
        pending.remove(done);
        switch (done.out) {
          case (final line, heard: true):
            yield line;
          case (final line, heard: false):
            held.add(line);
          case null:
        }
      }
      if (held.length >= heldUpTo) {
        final out = [...held];
        held.clear();
        yield* out;
      }
    }

    _known ??= await (_loading ??= _load());
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
        if (item.channelId case final channel?) {
          // Plainly in another language: none of its videos is asked about.
          if (channelSpeaks(channel) case final spoken? when spoken != language) {
            told.update('channel ${spoken.name}', (n) => n + 1, ifAbsent: () => 1);
            continue;
          }
        }
        pending.add(_Pending(of(item.id, asking: language, channel: item.channelId).then((spoken) {
          if (spoken != null && spoken.heard) heard++;
          final key = spoken == null ? 'no answer' : '${spoken.source} ${spoken.language?.name ?? '?'}';
          told.update(key, (n) => n + 1, ifAbsent: () => 1);
          if (!passes(spoken, language, listed: item.title)) return null;
          kept++;
          final shown = spoken == null || spoken.title.isEmpty || spoken.title == item.title ? line : jsonEncode({...jsonDecode(line) as Map<String, dynamic>, 'title': spoken.title});
          return (shown, heard: spoken!.heard);
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
      yield* Stream.fromIterable([...held]);
      held.clear();
    } finally {
      done?.call((asked: asked, kept: kept, heard: heard));
      if (asked > 0) {
        final by = [for (final MapEntry(:key, :value) in told.entries) '$key $value'].join(', ');
        logInfo('Language ${language.name}: kept $kept of $asked videos, $heard told by audio or captions; $by');
      }
    }
  }

  /// Whether a video listed as [listed] and answered with [spoken] (null
  /// when YouTube did not answer) is shown for [language]:
  ///
  /// * Its original audio track or automatic captions decide when YouTube
  ///   gives either, whatever its texts say.
  /// * Without either (YouTube makes no automatic captions for Chinese and
  ///   many other languages), its own title and description decide, read
  ///   together, and only when they are not a translation: the title is
  ///   the same listed in English as asked in [language]. A title the
  ///   uploader or YouTube translated differs between the two.
  /// * Without an answer it is left out.
  @visibleForTesting
  static bool passes(SpokenVideo? spoken, ExploreLanguage language, {required String listed}) {
    if (spoken == null) return false;
    if (spoken.heard) return spoken.language == language;
    return spoken.source == 'text' && spoken.language == language && spoken.title.trim() == listed.trim();
  }
}

/// What a language check went over: videos asked about, kept, and told
/// by their audio or captions.
typedef LanguageCheck = ({int asked, int kept, int heard});

/// A line waiting for its video's language: [out] is the line to pass on
/// and whether audio or captions told, null when the video is left out.
class _Pending {
  _Pending(Future<(String, {bool heard})?> answer) {
    future = answer.then((out) {
      this.out = out;
      done = true;
    });
  }

  late final Future<void> future;
  bool done = false;
  (String, {bool heard})? out;
}
