import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'translation.dart';
import 'youtube_web.dart';

/// Subtitles fetched by the app and handed to mpv as files.
///
/// mpv's own requests go out without retrying, and YouTube often answers a
/// caption request, above all a translated one (`tlang=`), with 429. Here
/// a 429 is retried after a pause, and a translation YouTube still refuses
/// is made from the original track with [_translator], one request per
/// stretch of lines, as the 翻译 button does for comments.
class SubtitleFiles {
  SubtitleFiles(this._client, this._folder, this._translator, {this.pauses = const [Duration(seconds: 2), Duration(seconds: 5)]});
  final http.Client _client;
  final Directory _folder;
  final Translator _translator;
  final List<Duration> pauses;

  final _paths = <String, Future<String>>{};
  bool _cleared = false;

  /// A file holding [option], fetched once per address.
  Future<String> pathFor(SubtitleOption option) {
    final pending = _paths[option.url] ??= _fetch(option);
    pending.ignore();
    return pending.catchError((Object e) {
      _paths.remove(option.url);
      throw e;
    });
  }

  Future<String> _fetch(SubtitleOption option) async {
    String text;
    try {
      text = await _get(option.url);
    } on _Refused {
      final source = _sourceOf(option);
      if (source == null) rethrow;
      text = await _translate(await _get(source.url), source.target);
    }
    if (!_cleared) {
      _cleared = true;
      // Files of earlier launches: their addresses have expired anyway.
      try {
        if (await _folder.exists()) await _folder.delete(recursive: true);
      } catch (_) {}
    }
    await _folder.create(recursive: true);
    final file = File('${_folder.path}${Platform.pathSeparator}${_name(option.url)}.vtt');
    await file.writeAsString(text);
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

  Future<String> _translate(String vtt, String target) async {
    final cues = WebVtt.cues(vtt);
    if (cues.isEmpty) return vtt;
    // Line groups of one request each, so a reply that drops the line break
    // at a request's end cannot shift every line after it.
    final lines = <String>[];
    for (var start = 0; start < cues.length;) {
      var end = start;
      var length = 0;
      while (end < cues.length && (end == start || length + cues[end].text.length < GoogleTranslator.chunkLength)) {
        length += cues[end++].text.length + 1;
      }
      final group = cues.sublist(start, end);
      final translated = (await _translator.translate(group.map((c) => c.text).join('\n'), target)).trim().split('\n');
      if (translated.length != group.length) throw const TranslationException('Translated subtitles lost their line breaks');
      lines.addAll(translated);
      start = end;
    }
    return WebVtt.write([for (final (i, cue) in cues.indexed) (timing: cue.timing, text: lines[i].trim())]);
  }

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
