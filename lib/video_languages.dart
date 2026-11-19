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
      'captions.playerCaptionsTracklistRenderer.captionTracks.kind,streamingData.adaptiveFormats.audioTrack,streamingData.adaptiveFormats.xtags,playabilityStatus.status,'
      'videoDetails.viewCount,microformat.playerMicroformatRenderer.publishDate';
  late final _probe = YoutubePlayerProbe(_client);

  Map<String, SpokenVideo>? _known;
  /// Answers without audio or captions, by video and language asked in.
  /// Those told by their texts are kept on disk for [textKeptFor] (when
  /// they were asked is in [_textAt]), the rest for this run only: YouTube
  /// may tell by audio or captions next time.
  final _unheard = <String, SpokenVideo>{};
  final _textAt = <String, int>{};

  /// Views and when published (seconds since 1970), as the `/player`
  /// answers give them in any language: a search asked in another language
  /// than English writes both its own way, which listings read only in
  /// English. When published is kept on disk with the answer.
  final _views = <String, int>{};
  final _published = <String, int>{};
  static const _unheardKept = 5000;
  static const textKeptFor = Duration(days: 7);

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
        if (_unheard.length >= _unheardKept) {
          final oldest = _unheard.keys.first;
          _unheard.remove(oldest);
          _textAt.remove(oldest);
        }
        _unheard['$id $hl'] = found;
        if (found.source == 'text') {
          _textAt['$id $hl'] = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          _save ??= Timer(const Duration(seconds: 5), _write);
        }
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
    _published.remove(id);
    _views.remove(id);
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
      final bytes = await _probe.fetchAs(client, id, _fields, expect: 'videoDetails', hl: hl);
      final read = await _readInBackground(bytes);
      if (read is! Map<String, dynamic>) return null;
      _factsOf(id, bytes);
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
      if (best != null && _rank(best) == 3 && _othersTold <= -_othersGiveUp && --_othersTold % _othersGiveUp != 0) break;
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
      if (best == null || _rank(read) > _rank(best)) best = read;
    }
    _answered(withVideo);
    return best?.spoken;
  }

  static final _viewCount = RegExp(r'"viewCount"\s*:\s*"(\d+)"');
  static final _publishDate = RegExp(r'"publishDate"\s*:\s*"([^"]+)"');

  void _factsOf(String id, List<int> bytes) {
    // Masked answers are a few kilobytes; a whole one is looked through once.
    final text = utf8.decode(bytes, allowMalformed: true);
    if (_views.length >= _kept) _views.remove(_views.keys.first);
    if (_viewCount.firstMatch(text)?[1] case final views?) _views[id] = int.parse(views);
    if (_publishDate.firstMatch(text)?[1] case final date?) {
      if (DateTime.tryParse(date) case final at?) _published[id] = at.millisecondsSinceEpoch ~/ 1000;
    }
  }

  /// [line] with the views of its video [id] as its answer gave them, and
  /// when it was published where the line lacks it.
  String _withFacts(String line, String id) {
    final views = _views[id];
    final published = _published[id];
    if (views == null && published == null) return line;
    final entry = jsonDecode(line) as Map<String, dynamic>;
    var changed = false;
    // The answer's count is exact; a listing asked in another language may
    // have written it in a way read wrongly ("1,2 Mln").
    if (views != null && entry['view_count'] != views) {
      entry['view_count'] = views;
      changed = true;
    }
    if (published != null && entry['timestamp'] == null && entry['release_timestamp'] == null) {
      entry['timestamp'] = published;
      changed = true;
    }
    return changed ? jsonEncode(entry) : line;
  }

  /// How much an answer that does not tell by captions or audio is worth:
  /// one with the video's title (which the texts are read from) over one
  /// without, then one YouTube would play over one it would not. Some apps
  /// answer a live stream with empty video details.
  static int _rank(_Read read) => (read.spoken.title.isEmpty ? 0 : 2) + (read.playable ? 1 : 0);

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
    final texts = _textFile(path);
    final oldest = DateTime.now().subtract(textKeptFor).millisecondsSinceEpoch ~/ 1000;
    final read = await Isolate.run(() {
      try {
        final raw = jsonDecode(File(texts).readAsStringSync()) as Map<String, dynamic>;
        return {
          for (final MapEntry(:key, :value) in raw.entries)
            if (value is Map<String, dynamic> && (value['at'] as num? ?? 0) >= oldest && value['source'] == 'text') key: value,
        };
      } catch (_) {
        return <String, Map<String, dynamic>>{};
      }
    });
    for (final MapEntry(:key, :value) in read.entries) {
      _unheard[key] = _spoken(value);
      _textAt[key] = (value['at'] as num).toInt();
    }
    final (known, channels, published) = await Isolate.run(() {
      final file = File(path);
      final none = (<String, SpokenVideo>{}, <String, String>{}, <String, int>{});
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
          {
            for (final MapEntry(:key, :value) in heard.entries)
              if (value['published'] case final num at) key: at.toInt(),
          },
        );
      } catch (_) {
        return none;
      }
    });
    for (final MapEntry(:key, :value) in channels.entries) {
      _count(key, value, known[key]?.language);
    }
    _published.addAll(published);
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
          ..._encode(value),
          if (_channelOf[key] case final channel?) 'channel': channel,
          if (_published[key] case final at?) 'published': at,
        },
    };
    final texts = {
      for (final MapEntry(:key, :value) in _textAt.entries)
        if (_unheard[key] case final spoken?) key: {..._encode(spoken), 'at': value},
    };
    final path = file.path;
    final textPath = _textFile(path);
    // Thousands of answers: encoded and written off the UI thread.
    unawaited(Isolate.run(() {
      void write(String path, Object value) {
        final out = File(path);
        out.parent.createSync(recursive: true);
        // Written beside and then swapped in, so a crash mid-write leaves
        // the last whole file.
        final next = File('$path.tmp')..writeAsStringSync(jsonEncode(value), flush: true);
        next.renameSync(path);
      }

      write(path, raw);
      write(textPath, texts);
    }).catchError((Object e) => logWarn('Could not save video languages: $e')));
  }

  /// Where the answers told by texts are kept, beside [path]'s.
  static String _textFile(String path) => '${File(path).parent.path}${Platform.pathSeparator}text_languages.json';

  static Map<String, Object> _encode(SpokenVideo spoken) => {
        'language': switch (spoken.language) {
          null => 0,
          ExploreLanguage.any => -1,
          final language => language.index,
        },
        'title': spoken.title,
        'source': spoken.source,
      };

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
  ///
  /// [listedInLanguage]: the listing was asked in [language], so its titles
  /// are already the reader's. Each video is then asked about in English,
  /// for [passes] to compare titles given in two languages.
  Stream<String> only(
    Stream<String> lines,
    ExploreLanguage language, {
    bool listedInLanguage = false,
    int giveUpAfter = giveUpAfterDefault,
    int heldUpTo = 12,
    void Function(LanguageCheck check)? done,
  }) async* {
    final pending = <_Pending>[];
    final held = <String>[];
    var asked = 0, kept = 0, heard = 0, byChannel = 0;
    // How long the reader waited: for the first video shown, and in all.
    final clock = Stopwatch()..start();
    int? firstShown;
    final told = <String, int>{};
    Iterable<String> ready() sync* {
      // As answered: a slow answer holds back no other.
      for (final done in pending.where((p) => p.done).toList()) {
        pending.remove(done);
        switch (done.out) {
          case (final line, heard: true):
            firstShown ??= clock.elapsedMilliseconds;
            yield line;
          case (final line, heard: false):
            held.add(line);
          case null:
        }
      }
      if (held.length >= heldUpTo) {
        firstShown ??= clock.elapsedMilliseconds;
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
        // A quarter of that, nearly all answered as another language: the
        // search brings videos in other languages, and reading on costs
        // seconds for nothing (Italian 基督宗教 read 240, all English, four
        // times over, 2026-11-19). A wider search takes over.
        final answered = asked - pending.length;
        if (kept == 0 && answered >= giveUpAfter ~/ 4 && (heard + byChannel) * 4 >= answered * 3) break;
        asked++;
        if (item.channelId case final channel?) {
          // Plainly in another language: none of its videos is asked about.
          if (channelSpeaks(channel) case final spoken? when spoken != language) {
            told.update('channel ${spoken.name}', (n) => n + 1, ifAbsent: () => 1);
            byChannel++;
            continue;
          }
        }
        final asking = listedInLanguage ? ExploreLanguage.any : language;
        pending.add(_Pending(of(item.id, asking: asking, channel: item.channelId).then((spoken) {
          if (spoken != null && spoken.heard) heard++;
          final key = spoken == null ? 'no answer' : '${spoken.source} ${spoken.language?.code ?? '?'}';
          told.update(key, (n) => n + 1, ifAbsent: () => 1);
          if (!passes(spoken, language, listed: item.title)) return null;
          kept++;
          final titled = listedInLanguage || spoken == null || spoken.title.isEmpty || spoken.title == item.title ? line : jsonEncode({...jsonDecode(line) as Map<String, dynamic>, 'title': spoken.title});
          final shown = _withFacts(titled, item.id);
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
      if (held.isNotEmpty) firstShown ??= clock.elapsedMilliseconds;
      yield* Stream.fromIterable([...held]);
      held.clear();
    } finally {
      done?.call((asked: asked, kept: kept, heard: heard));
      if (asked > 0) {
        final by = [for (final MapEntry(:key, :value) in told.entries) '$key $value'].join(', ');
        final seconds = clock.elapsedMilliseconds / 1000;
        final pace = seconds > 0 ? (asked / seconds).toStringAsFixed(1) : '-';
        final first = firstShown == null ? 'none shown' : 'first shown after ${(firstShown! / 1000).toStringAsFixed(1)} s';
        logInfo('Language ${language.name}: kept $kept of $asked videos in ${seconds.toStringAsFixed(1)} s ($pace a second, $first), '
            '$heard told by audio or captions; $by');
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
  ///   the same listed in English as asked in [language] (or listed in
  ///   [language] as asked in English). A title the
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
