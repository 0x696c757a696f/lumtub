import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'translation.dart';
import 'translation_cache.dart';
import 'translation_services.dart';
import 'youtube_web.dart';

/// Subtitles fetched by the app and handed to mpv as files.
///
/// mpv's own requests go out without retrying, and YouTube often answers a
/// caption request, above all a translated one (`tlang=`), with 429. Here
/// a 429 is retried after a pause, and a translation YouTube still refuses
/// is made from the original track with [_translator], one request per
/// stretch of lines, as the 翻译 button does for comments. When
/// [byTranslator] says so, every translation is made that way and YouTube's
/// is not asked for.
class SubtitleFiles {
  SubtitleFiles(this._client, this._folder, this._translator, {this.pauses = const [Duration(seconds: 2), Duration(seconds: 5)], this.byTranslator = _never, this.concurrency = 3, Duration Function()? position, this.onUpdated}) : _position = position ?? _start;
  final http.Client _client;
  final Directory _folder;
  /// The translator chosen now; a new one translates again.
  final Translator Function() _translator;
  final List<Duration> pauses;
  final bool Function() byTranslator;
  /// Translation requests in flight at once for one track.
  final int concurrency;
  /// Where playback is, so a track Lumtub translates starts there.
  final Duration Function() _position;
  /// Called with a file's path once the rest of a translation, begun at
  /// [_position], has been written to it.
  final void Function(String path)? onUpdated;

  static Duration _start() => Duration.zero;

  static bool _never() => false;

  final _paths = <String, Future<String>>{};
  /// Translations still being finished in the background, by key.
  final _finishing = <String, Future<void>>{};
  bool _cleared = false;

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
    final translator = _sourceOf(option) != null && byTranslator() ? _translator() : null;
    return (translator == null ? option.url : '${option.url}\u0000${identityHashCode(translator)}', translator);
  }

  /// The file of [option] with every line in it, waiting for a translation
  /// still being finished; for saving or listing the whole track.
  Future<String> wholePathFor(SubtitleOption option) async {
    final path = await pathFor(option);
    await _finishing[_keyOf(option).$1];
    return path;
  }

  Future<String> _fetch(SubtitleOption option, String key, Translator? translator) async {
    ({String text, Future<String>? rest}) result;
    final source = _sourceOf(option);
    if (translator != null && source != null) {
      result = await _translate(await _get(source.url), source.target, translator);
    } else {
      try {
        result = (text: await _get(option.url), rest: null);
      } on _Refused {
        if (source == null) rethrow;
        result = await _translate(await _get(source.url), source.target, _translator());
      }
    }
    final text = result.text;
    if (!_cleared) {
      _cleared = true;
      // Files of earlier launches: their addresses have expired anyway.
      try {
        if (await _folder.exists()) await _folder.delete(recursive: true);
      } catch (_) {}
    }
    await _folder.create(recursive: true);
    final file = File('${_folder.path}${Platform.pathSeparator}${_name(key)}.vtt');
    await file.writeAsString(text);
    if (result.rest case final rest?) {
      _finishing[key] = rest.then((whole) async {
        await file.writeAsString(whole);
        onUpdated?.call(file.path);
      }).catchError((Object e) {
        // The lines translated so far stay; the track is asked again next time.
        _paths.remove(key);
      }).whenComplete(() {
        _finishing.remove(key);
      });
    }
    return file.path;
  }

  Future<String> _get(String url) async {
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
  /// completes with the whole track, or is null when it is all there.
  Future<({String text, Future<String>? rest})> _translate(String vtt, String tlang, Translator translator) async {
    // Whole sentences, not the fragments captions show, so each is
    // translated with all its words and never split between two requests.
    final cues = WebVtt.sentences(WebVtt.cues(vtt));
    if (cues.isEmpty) return (text: vtt, rest: null);
    final target = TranslationLanguage.all.where((l) => l.youtube == tlang).firstOrNull?.code ?? tlang;
    final chunkLength = chunkLengthOf(translator);
    // Line groups of one request each, so a reply that drops the line break
    // at a request's end cannot shift every line after it.
    final groups = <(int, int)>[];
    for (var start = 0; start < cues.length;) {
      var end = start;
      var length = 0;
      while (end < cues.length && (end == start || length + cues[end].text.length < chunkLength)) {
        length += cues[end++].text.length + 1;
      }
      groups.add((start, end));
      start = end;
    }
    // From the piece playing now onwards, then the ones before it.
    final now = _position();
    final at = groups.lastIndexWhere((g) => WebVtt.startOf(cues[g.$1].timing) <= now).clamp(0, groups.length - 1);
    final order = [for (var i = at; i < groups.length; i++) i, for (var i = 0; i < at; i++) i];
    final translated = List<List<String>?>.filled(groups.length, null);
    var next = 0;
    // A few requests at a time: a long track is ready several times sooner,
    // without the burst that gets a free service to answer 429.
    Future<void> worker(int stop) async {
      while (next < stop) {
        final i = order[next++];
        final (start, end) = groups[i];
        // The sentences just before the piece go along for AI to read.
        final before = [for (final cue in cues.sublist(start > contextSentences ? start - contextSentences : 0, start)) cue.text];
        translated[i] = await _translateLines([for (final cue in cues.sublist(start, end)) cue.text], target, translator, before);
      }
    }

    Future<void> run(int stop) => Future.wait([for (var i = 0; i < concurrency && i < stop; i++) worker(stop)]);

    String write() => WebVtt.write([
          for (final (i, (start, end)) in groups.indexed)
            if (translated[i] case final lines?)
              for (var c = start; c < end; c++) (timing: cues[c].timing, text: lines[c - start].trim()),
        ]);

    final first = order.length <= concurrency ? order.length : concurrency;
    await run(first);
    if (first == order.length) return (text: write(), rest: null);
    final partial = write();
    return (text: partial, rest: run(order.length).then((_) => write()));
  }

  /// [texts] translated line for line. A reply with more or fewer lines
  /// (machine translation joins short caption fragments) is asked again in
  /// halves, down to single lines.
  static Future<List<String>> _translateLines(List<String> texts, String target, Translator translator, List<String> before) async {
    final ai = _aiOf(translator);
    final text = texts.join('\n');
    final reply = (await (ai != null && before.isNotEmpty ? ai.translateInContext(text, target, before) : translator.translate(text, target))).trim();
    if (texts.length == 1) return [reply.replaceAll('\n', ' ')];
    final lines = reply.split('\n');
    if (lines.length == texts.length) return lines;
    final half = texts.length ~/ 2;
    return [
      ...await _translateLines(texts.sublist(0, half), target, translator, before),
      ...await _translateLines(texts.sublist(half), target, translator, [...before, ...texts.sublist(0, half)]),
    ];
  }

  /// How many sentences before a request AI is shown.
  static const contextSentences = 3;

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
class WebVtt {
  static final _timing = RegExp(r'^\s*[\d:.]+\s+-->\s+[\d:.]+');
  static final _tag = RegExp(r'<[^>]*>');

  /// The cues of [vtt], each with its text on one line and without the
  /// word timings of automatic captions. Automatic captions repeat the
  /// line before as the first line of the next cue; only new lines stay.
  static List<({String timing, String text})> cues(String vtt) {
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

  static final _sentenceEnd = RegExp(r'[.!?。！？…]["”’」』)）]*$');
  static final _cjk = RegExp(r'[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af\uf900-\ufaff]');

  /// [cues] joined into sentences: a cue runs on into the next while it has
  /// no sentence end, the next follows within [gap], and the sentence stays
  /// short enough to read ([maxWidth], CJK characters counting double) and
  /// within [maxLength] on screen. Each spans from its first cue's start to
  /// its last cue's end.
  static List<({String timing, String text})> sentences(
    List<({String timing, String text})> cues, {
    Duration gap = const Duration(milliseconds: 1200),
    Duration maxLength = const Duration(seconds: 7),
    int maxWidth = 90,
  }) {
    int width(String text) => text.length + _cjk.allMatches(text).length;
    final out = <({String timing, String text})>[];
    for (var i = 0; i < cues.length;) {
      final start = startOf(cues[i].timing);
      var end = endOf(cues[i].timing);
      var text = cues[i].text;
      var j = i + 1;
      while (j < cues.length && !_sentenceEnd.hasMatch(text)) {
        final next = cues[j];
        final joined = _join(text, next.text);
        final nextEnd = endOf(next.timing);
        if (startOf(next.timing) - end > gap || nextEnd - start > maxLength || width(joined) > maxWidth) break;
        text = joined;
        end = nextEnd;
        j++;
      }
      out.add(j == i + 1 ? cues[i] : (timing: '${_stamp(start)} --> ${_stamp(end)}', text: text));
      i = j;
    }
    return out;
  }

  /// [a] and [b] as one line: with a space, except between CJK characters.
  static String _join(String a, String b) {
    if (a.isEmpty || b.isEmpty) return a + b;
    final cjk = _cjk.hasMatch(a[a.length - 1]) && _cjk.hasMatch(b[0]);
    return cjk ? '$a$b' : '$a $b';
  }

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
