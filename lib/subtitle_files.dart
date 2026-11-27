import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'native_core.dart';
import 'translation.dart';
import 'translation_cache.dart';
import 'translation_services.dart';
import 'youtube_web.dart';
import 'app_log.dart';
import 'scripts.dart';

/// Subtitles fetched by the app and handed to mpv as files.
///
/// mpv's own requests go out without retrying, and YouTube often answers a
/// caption request, above all a translated one (`tlang=`), with 429. Here
/// a 429 is retried after a pause, and a translation YouTube still refuses
/// is made from the original track with [_translator], one request per
/// stretch of lines, as the 翻译 button does for comments. When
/// [byTranslator] says so, every translation is made that way and YouTube's
/// is not asked for.
///
/// A track translated here is translated only around playback, [ahead] of
/// it and a little [behind], and follows it from there, so a long video
/// watched in part, or skimmed, costs only the requests for what is seen.
/// The whole track is translated when it is asked for whole.
class SubtitleFiles {
  SubtitleFiles(this._client, this._folder, this._translator,
      {this.pauses = const [Duration(seconds: 2), Duration(seconds: 5)], this.busyPauses = const [Duration(seconds: 2), Duration(seconds: 5)], this.byTranslator = _never, this.concurrency = 3, Duration Function()? position, Object? Function()? playing, this.wording, this.onUpdated, this.poll = const Duration(seconds: 5)})
      : _position = position ?? _start,
        _playing = playing ?? _nothing;
  final http.Client _client;
  final Directory _folder;
  /// The translator chosen now; a new one translates again.
  final Translator Function() _translator;

  /// Last words on a translation into [target] before it is shown, given
  /// the [original] where it is known (each cue's own, for the tracks
  /// translated here): the Church's wording for a Catholic video
  /// ([ChurchWording]).
  final String Function(String text, String target, String original)? wording;
  final List<Duration> pauses;

  /// Pauses before asking a translation service again that answered it
  /// had too many requests.
  final List<Duration> busyPauses;
  final bool Function() byTranslator;
  /// Translation requests in flight at once for one track.
  final int concurrency;
  /// Where playback is, so a track Lumtub translates starts there.
  final Duration Function() _position;
  /// What is playing now, such as the video's id: a track that followed
  /// another video stops once this changes, as [_position] is no longer its.
  final Object? Function() _playing;
  /// Called with a file's path each time more of a translation, begun at
  /// [_position], has been written to it; false once the track is no
  /// longer shown, which stops translating it.
  final Future<bool> Function(String path)? onUpdated;
  /// How often a translation following playback looks where it is.
  final Duration poll;

  static const ahead = Duration(minutes: 5);
  static const behind = Duration(seconds: 30);
  /// After a file is first handed out, how long its track may take to be
  /// loaded before [onUpdated]'s false is believed.
  static const _grace = Duration(seconds: 30);

  static Duration _start() => Duration.zero;

  static bool _never() => false;

  static Object? _nothing() => null;

  final _paths = <String, Future<String>>{};
  /// Translations still being finished in the background, by key.
  final _finishing = <String, Future<void>>{};
  /// Keys of translations asked for whole, and how to wake one waiting for
  /// playback to move.
  final _whole = <String>{};
  final _wake = <String, Completer<void>>{};
  Future<void>? _cleared;

  /// A file holding [option], fetched once per address.
  Future<String> pathFor(SubtitleOption option) {
    final (key, translator) = _keyOf(option);
    final pending = _paths[key] ??= _fetch(option, key, translator);
    pending.ignore();
    return pending.catchError((Object e) {
      _paths.remove(key);
      throw e;
    });
  }

  (String, Translator?) _keyOf(SubtitleOption option) {
    final source = _sourceOf(option);
    // YouTube translates automatic captions fragment by fragment, words of
    // one sentence apart; here they are translated whole sentences at a time.
    final translator = source != null && (byTranslator() || Uri.parse(source.url).queryParameters['kind'] == 'asr') ? _translator() : null;
    return (translator == null ? option.url : '${option.url}\u0000${identityHashCode(translator)}', translator);
  }

  /// The file of [option] with every line in it, waiting for a translation
  /// still being finished; for saving or listing the whole track.
  Future<String> wholePathFor(SubtitleOption option) async {
    final key = _keyOf(option).$1;
    _whole.add(key);
    final path = await pathFor(option);
    _wake.remove(key)?.complete();
    await _finishing[key];
    return path;
  }

  Future<String> _fetch(SubtitleOption option, String key, Translator? translator) async {
    ({String text, Future<String?>? rest}) result;
    final source = _sourceOf(option);
    final file = File('${_folder.path}${Platform.pathSeparator}${_name(key)}.vtt');
    // When the first text was written, which every later write waits for.
    final handedOut = Completer<DateTime>();
    // More of a translation following playback: written, and the track
    // reloaded; false once it is no longer shown.
    // YouTube's own translations, which come without their original line
    // by line, get their last words as a whole; the tracks translated here
    // got them cue by cue.
    final target = source?.target;
    var fromYoutube = false;
    String worded(String text) => !fromYoutube || target == null || wording == null ? text : wording!(text, target, '');
    Future<bool> save(String text) async {
      final since = await handedOut.future;
      await file.writeAsString(text);
      final shown = await (onUpdated?.call(file.path) ?? Future.value(true));
      return shown || _whole.contains(key) || DateTime.now().difference(since) < _grace;
    }

    if (translator != null && source != null) {
      final original = await _get(source.url);
      try {
        result = await _translate(original, source.target, translator, key, save, asr: _isAsr(source.url));
      } on TranslationException catch (e) {
        // The service still refuses after its pauses: YouTube's own
        // translation, fragment by fragment, rather than none.
        if (!e.busy || Uri.parse(option.url).scheme == 'file') rethrow;
        logWarn('Translation service busy; using YouTube\'s translation of ${option.language}');
        final String text;
        try {
          text = await _get(option.url);
        } on _Refused {
          throw e;
        }
        // In the lines of the original, so the two still go together.
        result = (text: _isAsr(option.url) ? WebVtt.asLinesOf(original, text) : text, rest: null);
        fromYoutube = true;
      }
    } else {
      try {
        final text = await _get(option.url);
        // Automatic captions roll on fragment by fragment; they are shown
        // as sentences, as their translation is.
        result = (text: _isAsr(option.url) ? WebVtt.asLines(text) : text, rest: null);
        fromYoutube = true;
      } on _Refused {
        if (source == null) rethrow;
        result = await _translate(await _get(source.url), source.target, _translator(), key, save, asr: _isAsr(source.url));
      }
    }
    final text = worded(result.text);
    // Files of earlier launches: their addresses have expired anyway. Every
    // fetch waits for this, so a file written meanwhile is not deleted.
    await (_cleared ??= () async {
      try {
        if (await _folder.exists()) await _folder.delete(recursive: true);
      } catch (e) {
        logDebug(() => 'Could not clear the subtitle folder: $e');
      }
    }());
    await _folder.create(recursive: true);
    await file.writeAsString(text);
    handedOut.complete(DateTime.now());
    if (result.rest case final rest?) {
      _finishing[key] = rest.then((whole) async {
        if (whole == null) {
          // No longer shown: what is translated stays in the cache, and the
          // track is followed again when it is next asked for.
          _paths.remove(key);
          return;
        }
        await file.writeAsString(whole);
        await onUpdated?.call(file.path);
      }).catchError((Object e) {
        // The lines translated so far stay; the track is asked again next time.
        _paths.remove(key);
      }).whenComplete(() {
        _finishing.remove(key);
        _whole.remove(key);
      });
    }
    return file.path;
  }

  Future<String> _get(String url) async {
    final uri = Uri.parse(url);
    if (uri.scheme == 'file') {
      // 语音识别's own file. Asked in another language it is refused like
      // a YouTube translation, so the chosen service translates it.
      if (uri.queryParameters.containsKey('tlang')) throw const _Refused(0);
      return File(Uri.parse(url.split('?').first).toFilePath()).readAsString();
    }
    for (var attempt = 0;; attempt++) {
      final response = await _client.get(Uri.parse(url), headers: {'User-Agent': YoutubeWeb.userAgent}).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) return utf8.decode(response.bodyBytes, allowMalformed: true);
      if (response.statusCode != 429 || attempt >= pauses.length) throw _Refused(response.statusCode);
      await Future<void>.delayed(pauses[attempt]);
    }
  }

  /// The original of a YouTube translation and the language asked for.
  static ({String url, String target})? _sourceOf(SubtitleOption option) {
    final uri = Uri.parse(option.url);
    final target = uri.queryParameters['tlang'];
    if (target == null || target.isEmpty) return null;
    return (url: uri.replace(queryParameters: {...uri.queryParameters}..remove('tlang')).toString(), target: target);
  }

  /// [vtt] translated into [tlang]. The pieces around [_position] come
  /// first: the text has those lines, enough to start with, and [rest]
  /// follows playback, handing each new stretch to [save], and completes
  /// with the whole track, or with null once [save] says it is no longer
  /// shown. [rest] is null when the text is all there.
  static bool _isAsr(String url) => Uri.parse(url).queryParameters['kind'] == 'asr';

  Future<({String text, Future<String?>? rest})> _translate(String vtt, String tlang, Translator translator, String key, Future<bool> Function(String text) save, {bool asr = false}) async {
    // Whole sentences, not the fragments captions show, so each is
    // translated with all its words and never split between two requests.
    // A sentence of a track's own cues shown as several of them has its
    // translation cut at the places nearest to where those cues end, each
    // piece at its cue's time. Automatic captions are translated in the
    // lines they show in ([captionLines]), each line as itself, so a line
    // and its translation always say the same thing; the lines of one
    // sentence go in one request, and AI also reads the lines before.
    final List<({String timing, String text})> cues;
    final List<List<({String timing, int weight})>> pieces;
    // The sentence each cue is part of, for automatic captions.
    var sentenceOf = const <int>[];
    if (asr) {
      final lines = WebVtt.captionLines(vtt);
      if (lines.isEmpty) return (text: vtt, rest: null);
      cues = [for (final l in lines) (timing: '${WebVtt._stamp(l.start)} --> ${WebVtt._stamp(l.end)}', text: l.text)];
      pieces = [for (final c in cues) [(timing: c.timing, weight: 1)]];
      sentenceOf = [for (final l in lines) l.sentence];
    } else {
      final plan = WebVtt.plan(vtt);
      if (plan.cues.isEmpty) return (text: vtt, rest: null);
      cues = plan.cues;
      pieces = plan.pieces;
    }
    // How many cues before a request AI reads: more of the short lines.
    final context = asr ? 2 * contextSentences : contextSentences;
    final target = TranslationLanguage.all.where((l) => l.youtube == tlang).firstOrNull?.code ?? tlang;
    final chunkLength = chunkLengthOf(translator);
    // Line groups of one request each, so a reply that drops the line break
    // at a request's end cannot shift every line after it.
    final groups = <(int, int)>[];
    for (var start = 0; start < cues.length;) {
      var end = start;
      var length = 0;
      // The lines of one sentence go in one request, so the translator
      // reads the sentence whole, up to twice the usual length.
      bool sameSentence(int k) => sentenceOf.isNotEmpty && sentenceOf[k] == sentenceOf[k - 1] && length + cues[k].text.length < 2 * chunkLength;
      while (end < cues.length && (end == start || length + cues[end].text.length < chunkLength || sameSentence(end))) {
        length += cues[end++].text.length + 1;
      }
      groups.add((start, end));
      start = end;
    }
    // Read once, not on every look at where playback is.
    final starts = [for (final (start, _) in groups) WebVtt.startOf(cues[start].timing)];
    final ends = [for (final (_, end) in groups) WebVtt.endOf(cues[end - 1].timing)];
    // The pieces from the one playing at [now] onwards, then those before.
    List<int> order(Duration now) {
      final at = starts.lastIndexWhere((start) => start <= now).clamp(0, groups.length - 1);
      return [for (var i = at; i < groups.length; i++) i, for (var i = 0; i < at; i++) i];
    }

    // Whether a piece is near enough to [now] to be needed soon.
    bool near(int i, Duration now) {
      return ends[i] >= now - behind && starts[i] <= now + ahead;
    }

    final translated = List<List<String>?>.filled(groups.length, null);
    bool done() => translated.every((t) => t != null);
    // [pieces] translated, a few requests at a time: a long stretch is
    // ready several times sooner, without the burst that gets a free
    // service to answer 429.
    Future<void> run(List<int> pieces) {
      var next = 0;
      Future<void> worker() async {
        while (next < pieces.length) {
          final i = pieces[next++];
          final (start, end) = groups[i];
          // The sentences just before the piece go along for AI to read.
          final before = [for (final cue in cues.sublist(start > context ? start - context : 0, start)) cue.text];
          final originals = [for (final cue in cues.sublist(start, end)) cue.text];
          final lines = await _patiently(() => _translateLines(originals, target, translator, before));
          final last = wording;
          translated[i] = last == null ? lines : [for (final (k, line) in lines.indexed) last(line, target, k < originals.length ? originals[k] : '')];
        }
      }

      return Future.wait([for (var i = 0; i < concurrency && i < pieces.length; i++) worker()]);
    }

    // The pieces still to do that are wanted now, in [order].
    List<int> wanted() {
      final now = _position();
      final whole = _whole.contains(key);
      return [for (final i in order(now)) if (translated[i] == null && (whole || near(i, now))) i];
    }

    // The translation [text] of sentence [c] as the lines it shows in.
    // The lines of each translated piece, worked out once: [write] runs
    // again on every stretch that comes in, over every piece done so far.
    final shown = List<List<({String timing, String text})>?>.filled(groups.length, null);
    List<({String timing, String text})> shownOf(int i, List<String> lines) {
      if (shown[i] case final done?) return done;
      final (start, end) = groups[i];
      final texts = [for (var c = start; c < end; c++) lines[c - start].trim()];
      // Translations of sentences shown as several cues, cut like those
      // cues, all of the piece in one go.
      final asks = [
        for (var c = start; c < end; c++)
          if (texts[c - start].isNotEmpty && pieces[c].length > 1) (texts[c - start], [for (final l in pieces[c]) l.weight]),
      ];
      final parts = asks.isEmpty ? const <List<String>>[] : WebVtt.splitMany(asks);
      var k = 0;
      return shown[i] = [
        for (var c = start; c < end; c++)
          if (texts[c - start] case final text when text.isNotEmpty)
            if (pieces[c].length < 2)
              (timing: cues[c].timing, text: text)
            else if (parts[k++] case final cut when cut.length == pieces[c].length)
              for (final (n, part) in cut.indexed) (timing: pieces[c][n].timing, text: part)
            else
              (timing: cues[c].timing, text: text),
      ];
    }

    String write() => WebVtt.write([
          for (final (i, _) in groups.indexed)
            if (translated[i] case final lines?) ...shownOf(i, lines),
        ]);

    // Enough to start with: the piece playing now and the next few.
    final playing = _playing();
    final start = order(_position());
    final first = wanted();
    await run((first.isEmpty ? start : first).take(concurrency).toList());
    if (done()) return (text: write(), rest: null);

    Future<String?> follow() async {
      while (true) {
        if (!_whole.contains(key) && _playing() != playing) return null;
        final pieces = wanted();
        if (pieces.isNotEmpty) {
          await run(pieces);
          if (done()) return write();
          if (!await save(write())) return null;
          continue;
        }
        final wake = _wake[key] ??= Completer<void>();
        await Future.any([Future<void>.delayed(poll), wake.future]);
        if (identical(_wake[key], wake)) _wake.remove(key);
      }
    }

    return (text: write(), rest: follow());
  }

  /// [texts] translated line for line. A reply with more or fewer lines
  /// (machine translation joins short caption fragments) is asked again in
  /// halves, down to single lines.
  /// [ask] again after each of [busyPauses] while the service answers that
  /// it has too many requests; free services (Google's public endpoint
  /// above all) refuse a burst for a short while.
  Future<T> _patiently<T>(Future<T> Function() ask) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await ask();
      } on TranslationException catch (e) {
        if (!e.busy || attempt >= busyPauses.length) rethrow;
        logDebug(() => 'Translation service busy; asking again in ${busyPauses[attempt].inSeconds} s');
        await Future<void>.delayed(busyPauses[attempt]);
      }
    }
  }

  static Future<List<String>> _translateLines(List<String> texts, String target, Translator translator, List<String> before) async {
    final ai = _aiOf(translator);
    final text = texts.join('\n');
    final reply = (await (ai != null && before.isNotEmpty ? ai.translateInContext(text, target, before) : translator.translate(text, target))).trim();
    if (texts.length == 1) return [reply.replaceAll('\n', ' ')];
    final lines = reply.split('\n');
    if (lines.length == texts.length) {
      // A line left empty (its words moved to a neighbour) is asked alone,
      // so no line goes without its translation.
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trim().isEmpty && texts[i].trim().isNotEmpty) {
          lines[i] = (await _translateLines([texts[i]], target, translator, [...before, ...texts.sublist(0, i)])).single;
        }
      }
      return lines;
    }
    final half = texts.length ~/ 2;
    return [
      ...await _translateLines(texts.sublist(0, half), target, translator, before),
      ...await _translateLines(texts.sublist(half), target, translator, [...before, ...texts.sublist(0, half)]),
    ];
  }

  /// How many sentences before a request AI is shown.
  static const contextSentences = 3;

  /// How long and how wide a sentence sent for translation may grow.
  static const sentenceTime = Duration(seconds: 30);
  static const sentenceWidth = 400;

  static AiTranslator? _aiOf(Translator translator) => switch (translator) {
        AiTranslator() => translator.contextLines > 0 ? translator : null,
        CachingTranslator(:final inner) => _aiOf(inner),
        _ => null,
      };

  static String _name(String url) {
    var hash = 0xcbf29ce484222325;
    for (final unit in url.codeUnits) {
      hash = ((hash ^ unit) * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16);
  }
}

class _Refused implements Exception {
  const _Refused(this.status);
  final int status;
  @override
  String toString() => 'HTTP $status';
}

/// Just enough WebVTT to translate a track cue by cue.
/// One line automatic captions show in: its times, the sentence it is
/// part of, and its text.
typedef CaptionLine = ({Duration start, Duration end, int sentence, String text});

class WebVtt {
  static final _timing = RegExp(r'^\s*[\d:.]+\s+-->\s+[\d:.]+');
  static final _tag = RegExp(r'<[^>]*>');

  /// The cues of [vtt], each with its text on one line and without the
  /// word timings of automatic captions. Automatic captions repeat the
  /// line before as the first line of the next cue; only new lines stay.
  static List<({String timing, String text})> cues(String vtt) {
    final json = NativeCore.instance?.vttCues(jsonEncode({'vtt': vtt}));
    return json == null ? dartCues(vtt) : _cuesOf(json);
  }

  static List<({String timing, String text})> _cuesOf(String json) => [
        for (final c in jsonDecode(json) as List) (timing: c[0] as String, text: c[1] as String),
      ];

  /// [cues] without the native core.
  static List<({String timing, String text})> dartCues(String vtt) {
    final cues = <({String timing, String text})>[];
    final blocks = vtt.replaceAll('\r\n', '\n').split(RegExp(r'\n{2,}'));
    String? previous;
    for (final block in blocks) {
      final lines = block.split('\n');
      final at = lines.indexWhere(_timing.hasMatch);
      if (at < 0) continue;
      var text = [
        for (final line in lines.skip(at + 1))
          if (_unescape(line.replaceAll(_tag, '')).trim() case final clean when clean.isNotEmpty) clean,
      ];
      if (text.isNotEmpty && text.first == previous) text = text.sublist(1);
      if (text.isEmpty) continue;
      previous = text.last;
      cues.add((timing: lines[at].trim(), text: text.join(' ')));
    }
    return cues;
  }

  static final _sentenceEnd = RegExp(r'[.!?。！？…؟۔।॥։።။།‼⁇]["”’」』»)）]*$');

  /// [cues] joined into sentences: a cue runs on into the next while it has
  /// no sentence end, the next follows within [gap], and the sentence stays
  /// short enough to read ([maxWidth], characters of Chinese, Japanese, Thai and other scripts without spaces counting double) and
  /// within [maxLength] on screen. Each spans from its first cue's start to
  /// its last cue's end.
  static List<({String timing, String text})> sentencesOf(String vtt, {
    Duration maxLength = const Duration(seconds: 7),
    int maxWidth = 90,
  }) {
    final json = NativeCore.instance?.vttCues(jsonEncode({'vtt': vtt, 'sentences': true, 'time': maxLength.inMilliseconds, 'width': maxWidth}));
    return json == null ? sentences(dartCues(vtt), maxLength: maxLength, maxWidth: maxWidth) : _cuesOf(json);
  }

  /// [sentencesOf] the cues [cues], without the native core.
  static List<({String timing, String text})> sentences(
    List<({String timing, String text})> cues, {
    Duration gap = const Duration(milliseconds: 1200),
    Duration maxLength = const Duration(seconds: 7),
    int maxWidth = 90,
  }) =>
      [
        for (final (i, j) in sentenceSpans(cues, gap: gap, maxLength: maxLength, maxWidth: maxWidth))
          j == i + 1
              ? cues[i]
              : (
                  timing: '${_stamp(startOf(cues[i].timing))} --> ${_stamp(endOf(cues[j - 1].timing))}',
                  text: [for (final c in cues.sublist(i, j)) c.text].reduce(_join),
                ),
      ];

  /// Where the sentences of [sentences] start and end in [cues], as
  /// (first cue, cue after the last).
  static List<(int, int)> sentenceSpans(
    List<({String timing, String text})> cues, {
    Duration gap = const Duration(milliseconds: 1200),
    Duration maxLength = const Duration(seconds: 7),
    int maxWidth = 90,
  }) {
    // Widths add up as fragments join, and a sentence end is looked for in
    // the last fragment only: one pass over the track.
    final out = <(int, int)>[];
    for (var i = 0; i < cues.length;) {
      final start = startOf(cues[i].timing);
      var end = endOf(cues[i].timing);
      var wide = width(cues[i].text);
      var last = cues[i].text;
      var j = i + 1;
      while (j < cues.length && !_sentenceEnd.hasMatch(last)) {
        final next = cues[j];
        final joined = wide + width(next.text) + (_spaced(last, next.text) ? 1 : 0);
        final nextEnd = endOf(next.timing);
        if (startOf(next.timing) - end > gap || nextEnd - start > maxLength || joined > maxWidth) break;
        wide = joined;
        end = nextEnd;
        if (next.text.isNotEmpty) last = next.text;
        j++;
      }
      out.add((i, j));
      i = j;
    }
    return out;
  }

  static final _clauseTail = RegExp(r'[;:,；：，、…)）」』"”»،؛፣၊]$');

  /// How long and how wide a line of automatic captions may grow.
  static const lineTime = Duration(seconds: 7);
  static const lineWidth = 84;

  /// How wide [text] shows, in Latin letters: a letter of a script written
  /// without spaces is about two.
  static int width(String text) => text.length + unspacedScript.allMatches(text).length;

  /// [text] cut into as many pieces as [weights], each about as wide as its
  /// share: after punctuation where one is near, else at a space, else
  /// between two letters of a script written without spaces. Just [text]
  /// when there is nowhere to cut.
  static List<String> splitLike(String text, List<int> weights) {
    text = text.trim();
    final total = weights.fold(0, (a, b) => a + b);
    if (weights.length < 2 || total <= 0) return [text];
    final chars = text.runes.map(String.fromCharCode).toList();
    // Width of the text before each character.
    final before = <int>[0];
    for (final c in chars) {
      before.add(before.last + width(c));
    }
    final full = before.last;
    int quality(int k) {
      final prev = chars[k - 1], next = chars[k];
      if (_cjkStop.hasMatch(prev) && next.trim().isNotEmpty) return 3;
      if (next.trim().isEmpty) return prev.trim().isEmpty ? 0 : (_clauseTail.hasMatch(prev) || _sentenceEnd.hasMatch(prev) ? 3 : 2);
      if (_unspaced(prev, next)) return 1;
      return 0;
    }

    final share = full / weights.length;
    final cuts = <int>[];
    var used = 0;
    for (var i = 0; i < weights.length - 1; i++) {
      used += weights[i];
      final target = full * used / total;
      int? best;
      var bestCost = double.infinity;
      final last = cuts.isEmpty ? 0 : cuts.last;
      for (var k = last + 1; k < chars.length; k++) {
        final q = quality(k);
        if (q == 0) continue;
        final cost = (before[k] - target).abs() + (3 - q) * 0.15 * share;
        if (cost < bestCost) {
          bestCost = cost;
          best = k;
        }
      }
      if (best == null) return [text];
      cuts.add(best);
    }
    final parts = <String>[];
    var from = 0;
    for (final k in [...cuts, chars.length]) {
      parts.add(chars.sublist(from, k).join().trim());
      from = k;
    }
    return parts.any((p) => p.isEmpty) ? [text] : parts;
  }

  /// [splitLike] for each of [asks] at once.
  static List<List<String>> splitMany(List<(String, List<int>)> asks) {
    final json = NativeCore.instance?.vttSplit(jsonEncode([for (final (text, weights) in asks) [text, weights]]));
    if (json != null) {
      final out = [for (final parts in jsonDecode(json) as List) (parts as List).cast<String>()];
      if (out.length == asks.length) return out;
    }
    return [for (final (text, weights) in asks) splitLike(text, weights)];
  }

  /// What to translate in a track's own cues (automatic captions go by
  /// [captionLines]): its sentences, each from its first cue's start to
  /// its last cue's end, and for each the cues it shows in with how wide
  /// the original is there.
  static ({List<({String timing, String text})> cues, List<List<({String timing, int weight})>> pieces}) plan(String vtt) {
    final json = NativeCore.instance?.vttPlan(vtt);
    if (json == null) return dartPlan(vtt);
    final map = jsonDecode(json) as Map<String, dynamic>;
    return (
      cues: _cuesOf(jsonEncode(map['cues'])),
      pieces: [
        for (final p in map['pieces'] as List) [for (final l in p as List) (timing: l[0] as String, weight: l[1] as int)],
      ],
    );
  }

  /// [plan] without the native core.
  static ({List<({String timing, String text})> cues, List<List<({String timing, int weight})>> pieces}) dartPlan(String vtt) {
    final fragments = dartCues(vtt);
    final spans = sentenceSpans(fragments, maxLength: SubtitleFiles.sentenceTime, maxWidth: SubtitleFiles.sentenceWidth);
    return (
      cues: [for (final (from, to) in spans) (timing: '${_stamp(startOf(fragments[from].timing))} --> ${_stamp(endOf(fragments[to - 1].timing))}', text: textOf(fragments, from, to))],
      pieces: [
        for (final (from, to) in spans) [for (var k = from; k < to; k++) (timing: fragments[k].timing, weight: width(fragments[k].text))],
      ],
    );
  }

  static final _cjkStop = RegExp(r'[，。、！？；：…）」』]');

  /// The text of [cues] from [from] up to [to] as one line.
  static String textOf(List<({String timing, String text})> cues, int from, int to) => [for (final c in cues.sublist(from, to)) c.text].reduce(_join);

  /// Sentence [span] of [cues] as the lines to show it in: all of it when
  /// it fits [lineWidth] and [lineTime], else lines that do, each ending
  /// after a comma where one is near the end, as (first cue, cue after
  /// the last).
  static List<(int, int)> lineSpans(List<({String timing, String text})> cues, (int, int) span) {
    final (from, to) = span;
    final out = <(int, int)>[];
    for (var i = from; i < to;) {
      final start = startOf(cues[i].timing);
      var wide = width(cues[i].text);
      var last = cues[i].text;
      var j = i + 1;
      // Where the line could end after a comma, and how wide it is there.
      var comma = -1;
      var commaWidth = 0;
      while (j < to) {
        final joined = wide + width(cues[j].text) + (_spaced(last, cues[j].text) ? 1 : 0);
        if (joined > lineWidth || endOf(cues[j].timing) - start > lineTime) break;
        if (_clauseTail.hasMatch(last)) {
          comma = j;
          commaWidth = wide;
        }
        wide = joined;
        if (cues[j].text.isNotEmpty) last = cues[j].text;
        j++;
      }
      if (j < to && comma > i && commaWidth * 2 >= wide) j = comma;
      out.add((i, j));
      i = j;
    }
    return out;
  }

  /// The times of [lines] of [cues]: from the first cue's start to the last
  /// one's end, or to the next line's start where automatic captions run
  /// on over it, so two lines never show at once.
  static List<String> lineTimings(List<({String timing, String text})> cues, List<(int, int)> lines) => [
        for (final (k, (a, b)) in lines.indexed)
          () {
            final start = startOf(cues[a].timing);
            var end = endOf(cues[b - 1].timing);
            if (k + 1 < lines.length) {
              final next = startOf(cues[lines[k + 1].$1].timing);
              if (next < end && next > start) end = next;
            }
            return '${_stamp(start)} --> ${_stamp(end)}';
          }(),
      ];

  /// The lines automatic captions [vtt] show in: fragments joined into
  /// sentences, a long one cut into [lineSpans]. The native core works
  /// them out when it is there.
  static List<CaptionLine> captionLines(String vtt) {
    final json = NativeCore.instance?.captionLines(vtt);
    if (json != null) return _linesOf(json);
    return dartCaptionLines(vtt);
  }

  /// [captionLines] without the native core.
  static List<CaptionLine> dartCaptionLines(String vtt) {
    final cues = dartCues(vtt);
    final lines = <(int, int)>[];
    final sentence = <int>[];
    for (final (s, span) in sentenceSpans(cues, maxLength: SubtitleFiles.sentenceTime, maxWidth: SubtitleFiles.sentenceWidth).indexed) {
      for (final line in lineSpans(cues, span)) {
        lines.add(line);
        sentence.add(s);
      }
    }
    final timings = lineTimings(cues, lines);
    return [for (final (k, (a, b)) in lines.indexed) (start: startOf(timings[k]), end: endOf(timings[k]), sentence: sentence[k], text: textOf(cues, a, b))];
  }

  static List<CaptionLine> _linesOf(String json) => [
        for (final line in jsonDecode(json) as List)
          if (line case [final int start, final int end, final int sentence, final String text]) (start: Duration(milliseconds: start), end: Duration(milliseconds: end), sentence: sentence, text: text),
      ];

  static String _writeLines(List<CaptionLine> lines) => write([for (final l in lines) (timing: '${_stamp(l.start)} --> ${_stamp(l.end)}', text: l.text)]);

  /// Automatic captions [vtt] in the lines of [captionLines]: the way their
  /// translations are shown, so each original line has its translation
  /// beside it.
  static String asLines(String vtt) {
    final lines = captionLines(vtt);
    return lines.isEmpty ? vtt : _writeLines(lines);
  }

  /// YouTube's translation [translated] of automatic captions [original]
  /// in the lines [asLines] shows the original in: each translated cue
  /// goes into the line it starts in, so the two tracks change together.
  static String asLinesOf(String original, String translated) {
    final json = NativeCore.instance?.captionTranslationLines(original, translated);
    if (json != null) {
      final lines = _linesOf(json);
      return lines.isEmpty ? translated : _writeLines(lines);
    }
    return dartAsLinesOf(original, translated);
  }

  /// [asLinesOf] without the native core.
  static String dartAsLinesOf(String original, String translated) {
    final pieces = dartCues(translated);
    final lines = dartCaptionLines(original);
    if (lines.isEmpty || pieces.isEmpty) return asLines(translated);
    final texts = List<String>.filled(lines.length, '');
    // Pieces in time order walk the lines once.
    final sorted = [...pieces]..sort((a, b) => startOf(a.timing).compareTo(startOf(b.timing)));
    var k = 0;
    for (final piece in sorted) {
      final at = startOf(piece.timing);
      while (k + 1 < lines.length && lines[k + 1].start <= at) {
        k++;
      }
      texts[k] = texts[k].isEmpty ? piece.text : _join(texts[k], piece.text);
    }
    return _writeLines([for (final (k, l) in lines.indexed) if (texts[k].isNotEmpty) (start: l.start, end: l.end, sentence: l.sentence, text: texts[k])]);
  }

  /// [a] and [b] as one line: with a space, except between letters of
  /// scripts written without spaces (Chinese, Japanese, Thai…).
  static String _join(String a, String b) => _spaced(a, b) ? '$a $b' : a + b;

  /// Whether [a] and [b] join with a space.
  static bool _spaced(String a, String b) => a.isNotEmpty && b.isNotEmpty && !_unspaced(a[a.length - 1], b[0]);

  static final _hangul = RegExp(r'[ᄀ-ᇿ㄰-㆏가-힯]');

  /// Whether letters [a] and [b] go together without a space: both of a
  /// script written without spaces. Korean is spaced between words, and
  /// automatic captions break between words.
  static bool _unspaced(String a, String b) => unspacedScript.hasMatch(a) && unspacedScript.hasMatch(b) && !(_hangul.hasMatch(a) && _hangul.hasMatch(b));

  static String _stamp(Duration d) {
    String two(int n, [int width = 2]) => n.toString().padLeft(width, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}.${two(d.inMilliseconds % 1000, 3)}';
  }

  /// When a cue with [timing] ends.
  static Duration endOf(String timing) {
    final parts = timing.split('-->');
    return parts.length < 2 ? startOf(timing) : startOf(parts[1]);
  }

  /// When a cue with [timing] (`00:01:02.500 --> …`) starts.
  static Duration startOf(String timing) {
    final parts = timing.trim().split(RegExp(r'\s'))[0].split(':');
    final seconds = double.tryParse(parts.last) ?? 0;
    final minutes = parts.length > 1 ? int.tryParse(parts[parts.length - 2]) ?? 0 : 0;
    final hours = parts.length > 2 ? int.tryParse(parts[parts.length - 3]) ?? 0 : 0;
    return Duration(hours: hours, minutes: minutes, milliseconds: (seconds * 1000).round());
  }

  static String write(List<({String timing, String text})> cues) {
    final out = StringBuffer('WEBVTT\n\n');
    for (final cue in cues) {
      out
        ..writeln(cue.timing)
        ..writeln(cue.text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;'))
        ..writeln();
    }
    return out.toString();
  }

  static String _unescape(String text) => text.replaceAll('&nbsp;', ' ').replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&amp;', '&');
}
