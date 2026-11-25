import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'background_json.dart';
import 'l10n/l10n.dart';
import 'local_db.dart';
import 'native_core.dart';
import 'process_priority.dart';
import 'process_runner.dart';
import 'translation.dart' show TranslationException;

/// 语音识别: subtitles for a video that has none, from its audio sent to an
/// OpenAI-compatible `/audio/transcriptions`. Nothing is decoded here: yt-dlp
/// fetches the smallest audio stream, lumtub_core cuts long ones by
/// copying whole clusters, and the timed text comes back to lumtub_core to become WebVTT.
class SpeechRecognizer {
  SpeechRecognizer(this._client, {required String baseUrl, required this.key, required this.model}) : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');
  final http.Client _client;
  final String baseUrl;
  final String key;
  final String model;

  /// The timed segments of [audio], as `verbose_json` has them.
  Future<Map<String, dynamic>> transcribe(File audio, {String? language}) async {
    final uri = Uri.tryParse('$baseUrl/audio/transcriptions');
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) throw TranslationException(tr('The speech recognition address is not valid'));
    final request = http.MultipartRequest('POST', uri)
      ..fields['model'] = model
      ..fields['response_format'] = 'verbose_json'
      ..fields['timestamp_granularities[]'] = 'segment'
      ..files.add(await http.MultipartFile.fromPath('file', audio.path, filename: audio.uri.pathSegments.last));
    if (language != null && language.isNotEmpty) request.fields['language'] = language;
    if (key.isNotEmpty) request.headers['Authorization'] = 'Bearer $key';
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request)).timeout(const Duration(minutes: 5));
    } on TranslationException {
      rethrow;
    } catch (e) {
      throw TranslationException(tr('Could not reach the speech recognition service: {0}', [e]));
    }
    switch (response.statusCode) {
      case 200:
        break;
      case 401 || 403:
        throw TranslationException(tr('The speech recognition key is not valid'));
      case 404:
        throw TranslationException(tr('The speech recognition address or model name is wrong'));
      case 413:
        throw TranslationException(tr('The audio is too large for the speech recognition service'));
      case 429:
        throw TranslationException(tr('Too many speech recognition requests or the quota is used up; try again later'));
      default:
        throw TranslationException(tr('The speech recognition service failed ({0})', [response.statusCode]));
    }
    final json = await decodeJsonInBackground(utf8.decode(response.bodyBytes, allowMalformed: true));
    if (json is! Map<String, dynamic>) throw TranslationException(tr('The speech recognition service answered with something unreadable'));
    if (json['segments'] is! List) throw TranslationException(tr('This speech recognition service returns no timing, so it cannot make subtitles'));
    return json;
  }
}

/// One stretch of audio to recognize and where in the video it starts.
typedef SpeechPart = ({File file, Duration offset});

/// Audio fetched for 语音识别, cut by lumtub_core into parts each
/// [SpeechAudio.partBytes] or smaller.
class SpeechAudio {
  /// What one request may carry: the services take 25 MB at most.
  static const partBytes = 20 * 1024 * 1024;

  /// About ten minutes of the smallest audio YouTube serves (50 kbit/s
  /// Opus): short requests answer before a read times out and run side
  /// by side.
  static const partLength = Duration(minutes: 10);

  /// yt-dlp arguments that save the smallest audio stream of [videoId] to
  /// [folder] and print its length and path.
  static List<String> arguments(String videoId, Directory folder, {String? proxy, String? cacheDirectory, String? deno}) => [
        '--no-warnings',
        '--no-playlist',
        '--no-progress',
        '--no-part',
        // Left as YouTube sends it, which lumtub_core cuts.
        '--fixup', 'never',
        if (proxy != null) ...['--proxy', proxy],
        if (cacheDirectory != null) ...['--cache-dir', cacheDirectory],
        if (deno != null) ...['--js-runtimes', 'deno:$deno'],
        '--extractor-retries', '3',
        '--format', 'wa[acodec=opus]/wa/ba',
        '--output', '${folder.path}${Platform.pathSeparator}audio.%(ext)s',
        '--print', 'after_move:%(duration)s|%(filepath)s',
        '--', 'https://www.youtube.com/watch?v=$videoId',
      ];

  /// The audio of [videoId] in parts.
  static Future<List<SpeechPart>> fetch(
    String videoId,
    Directory folder, {
    required String ytDlp,
    required Map<String, String> environment,
    String? proxy,
    String? cacheDirectory,
    String? deno,
  }) async {
    await folder.create(recursive: true);
    // What an earlier try fetched.
    final fetched = File('${folder.path}${Platform.pathSeparator}audio.txt');
    var printed = await fetched.exists() ? (await fetched.readAsString()).trim() : null;
    if (printed == null || !await File(printed.substring(printed.indexOf('|') + 1)).exists()) {
      // A try stopped part way leaves audio that yt-dlp (with --no-part)
      // would take as already downloaded.
      await _removeAudio(folder);
      final result = await runWithTimeout(
        ytDlp,
        arguments(videoId, folder, proxy: proxy, cacheDirectory: cacheDirectory, deno: deno),
        timeout: const Duration(minutes: 15),
        environment: environment,
        onStart: (process) => lowerPriority(process.pid),
      );
      printed = const LineSplitter().convert(result.stdout.toString()).where((l) => l.contains('|')).lastOrNull;
      if (result.exitCode != 0 || printed == null) {
        await _removeAudio(folder);
        throw TranslationException(tr("Could not download this video's audio"));
      }
      await fetched.writeAsString(printed);
    }
    final split = printed.indexOf('|');
    final seconds = double.tryParse(printed.substring(0, split)) ?? 0;
    final audio = File(printed.substring(split + 1).trim());
    if (!await audio.exists()) throw TranslationException(tr("Could not download this video's audio"));
    final size = await audio.length();
    final length = Duration(milliseconds: (seconds * 1000).round());
    final count = max((size / partBytes).ceil(), (length.inSeconds / partLength.inSeconds).ceil());
    if (count <= 1) return [(file: audio, offset: Duration.zero)];
    final every = Duration(seconds: (length.inSeconds / count).ceil() + 1);
    final stem = '${folder.path}${Platform.pathSeparator}part';
    final cut = await Isolate.run(() => NativeCore.cutAudio(audio.path, stem, every));
    final parts = cut.parts;
    if (parts == null) {
      logWarn('Speech audio not cut: ${cut.error}');
      throw TranslationException(tr('Could not split the audio'));
    }
    return [for (final p in parts) (file: File(p.path), offset: Duration(milliseconds: (p.start * 1000).round()))];
  }

  static Future<void> _removeAudio(Directory folder) async {
    await for (final entry in folder.list()) {
      final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => '');
      if (entry is! File || !name.startsWith('audio.')) continue;
      try {
        await entry.delete();
      } on FileSystemException {
        // Tried again next time.
      }
    }
  }
}

/// WebVTT of the answers to each part, by lumtub_core.
Future<String> speechVtt(List<({Duration offset, Map<String, dynamic> answer})> parts) async {
  if (NativeCore.instance == null) throw TranslationException(NativeCore.missingMessage);
  final input = jsonEncode({
    'parts': [
      for (final p in parts) {'offset': p.offset.inMilliseconds, 'segments': p.answer['segments']},
    ],
  });
  final vtt = await Isolate.run(() {
    final core = NativeCore.instance!;
    final convert = core.library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_speech_vtt');
    return core.take(core.withText(input, convert));
  });
  return vtt ?? 'WEBVTT\n\n';
}

/// A language tag for what Whisper calls the language it heard ("english"
/// from OpenAI, "English" from Groq, or a tag already).
String? speechLanguageTag(Object? language) {
  if (language is! String || language.trim().isEmpty) return null;
  final name = language.trim().toLowerCase();
  if (RegExp(r'^[a-z]{2,3}(-[a-z0-9]+)*$').hasMatch(name) && name.length <= 3) return name;
  return _whisperLanguages[name];
}

const _whisperLanguages = {
  'english': 'en', 'chinese': 'zh', 'japanese': 'ja', 'korean': 'ko', 'spanish': 'es', 'french': 'fr', 'german': 'de',
  'russian': 'ru', 'portuguese': 'pt', 'italian': 'it', 'dutch': 'nl', 'arabic': 'ar', 'hindi': 'hi', 'turkish': 'tr',
  'vietnamese': 'vi', 'thai': 'th', 'indonesian': 'id', 'malay': 'ms', 'polish': 'pl', 'ukrainian': 'uk', 'swedish': 'sv',
  'czech': 'cs', 'greek': 'el', 'hebrew': 'he', 'persian': 'fa', 'finnish': 'fi', 'danish': 'da', 'norwegian': 'no',
  'hungarian': 'hu', 'romanian': 'ro', 'tagalog': 'tl', 'cantonese': 'yue', 'bengali': 'bn', 'tamil': 'ta', 'urdu': 'ur',
};

/// Recognized subtitles, kept so a video is sent once: in `lumtub.db`
/// with the core ([db]), marked as machine-made, else in [folder] as
/// `<video id>.<language>.vtt`. Files from before the database are moved
/// into it when their video is next looked up. Past [keep], the oldest go.
class SpeechSubtitleStore {
  SpeechSubtitleStore(this.folder, {this.keep = 300, this.db, Directory? cache}) : cache = cache ?? folder;
  final Directory folder;
  final int keep;
  final LocalDb? db;

  /// Where subtitles read from [db] are written for the player.
  final Directory cache;

  /// The origins recognized subtitles are kept under.
  static const origins = ['machine-local', 'machine-cloud'];

  /// The file and language of [videoId]'s recognized subtitles, if any.
  Future<({File file, String language})?> of(String videoId) async {
    final db = this.db;
    if (db != null) {
      try {
        final found = (await db.transcripts(videoId, origins: origins)).firstOrNull;
        if (found != null) return (file: await _forPlayer(videoId, found.lang, found.body), language: found.lang);
      } on LocalDbException catch (e) {
        logWarn('Could not read recognized subtitles from lumtub.db: $e');
      }
    }
    final old = await _fileOf(videoId);
    if (old == null || db == null) return old;
    try {
      final vtt = await old.file.readAsString();
      await db.putTranscript(videoId, old.language, 'machine-cloud', vtt, keep: keep);
      await old.file.delete();
      return (file: await _forPlayer(videoId, old.language, vtt), language: old.language);
    } catch (e) {
      logDebug(() => 'Could not move a speech subtitle file into lumtub.db: $e');
      return old;
    }
  }

  Future<({File file, String language})?> _fileOf(String videoId) async {
    try {
      if (!await folder.exists()) return null;
      await for (final entity in folder.list()) {
        final name = entity.uri.pathSegments.last;
        if (entity is File && name.startsWith('$videoId.') && name.endsWith('.vtt')) {
          return (file: entity, language: name.substring(videoId.length + 1, name.length - 4));
        }
      }
    } catch (e) {
      logDebug(() => 'Could not look for a speech subtitle file: $e');
    }
    return null;
  }

  Future<File> _forPlayer(String videoId, String language, String vtt) async {
    await cache.create(recursive: true);
    final file = File('${cache.path}${Platform.pathSeparator}$videoId.$language.vtt');
    await file.writeAsString(vtt);
    return file;
  }

  /// Keeps [vtt] as [videoId]'s subtitles in [language], made by [model]
  /// on this device or a service ([origin]).
  Future<File> save(String videoId, String language, String vtt, {String origin = 'machine-cloud', String model = ''}) async {
    final db = this.db;
    if (db != null) {
      try {
        await db.putTranscript(videoId, language, origin, vtt, model: model, keep: keep);
        return await _forPlayer(videoId, language, vtt);
      } on LocalDbException catch (e) {
        logWarn('Could not keep recognized subtitles in lumtub.db: $e');
      }
    }
    await folder.create(recursive: true);
    final file = File('${folder.path}${Platform.pathSeparator}$videoId.$language.vtt');
    await file.writeAsString(vtt);
    try {
      final files = folder.listSync().whereType<File>().toList();
      if (files.length > keep) {
        files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
        for (final old in files.take(files.length - keep)) {
          await old.delete();
        }
      }
    } catch (e) {
      logDebug(() => 'Could not clear old speech subtitle files: $e');
    }
    return file;
  }
}
