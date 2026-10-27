import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:http/http.dart' as http;

import 'background_json.dart';
import 'l10n/l10n.dart';
import 'native_core.dart';
import 'process_priority.dart';
import 'process_runner.dart';
import 'translation.dart' show TranslationException;

/// 语音识别: subtitles for a video that has none, from its audio sent to an
/// OpenAI-compatible `/audio/transcriptions`. Nothing is decoded here: yt-dlp
/// fetches the smallest audio stream, ffmpeg cuts long ones by copying
/// packets, and the timed text comes back to lumtub_core to become WebVTT.
class SpeechRecognizer {
  SpeechRecognizer(this._client, {required String baseUrl, required this.key, required this.model}) : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');
  final http.Client _client;
  final String baseUrl;
  final String key;
  final String model;

  /// The timed segments of [audio], as `verbose_json` has them.
  Future<Map<String, dynamic>> transcribe(File audio, {String? language}) async {
    final uri = Uri.tryParse('$baseUrl/audio/transcriptions');
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) throw TranslationException(tr('语音识别接口地址不对'));
    final request = http.MultipartRequest('POST', uri)
      ..fields['model'] = model
      ..fields['response_format'] = 'verbose_json'
      ..fields['timestamp_granularities[]'] = 'segment'
      ..files.add(http.MultipartFile.fromBytes('file', await audio.readAsBytes(), filename: audio.uri.pathSegments.last));
    if (language != null && language.isNotEmpty) request.fields['language'] = language;
    if (key.isNotEmpty) request.headers['Authorization'] = 'Bearer $key';
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request)).timeout(const Duration(minutes: 5));
    } on TranslationException {
      rethrow;
    } catch (e) {
      throw TranslationException(tr('连不上语音识别接口：{0}', [e]));
    }
    switch (response.statusCode) {
      case 200:
        break;
      case 401 || 403:
        throw TranslationException(tr('语音识别接口密钥无效'));
      case 404:
        throw TranslationException(tr('语音识别接口地址或模型名不对'));
      case 413:
        throw TranslationException(tr('音频太大，语音识别接口不接受'));
      case 429:
        throw TranslationException(tr('语音识别接口请求太频繁或额度用完了，稍后再试'));
      default:
        throw TranslationException(tr('语音识别接口出错（{0}）', [response.statusCode]));
    }
    final json = await decodeJsonInBackground(utf8.decode(response.bodyBytes, allowMalformed: true));
    if (json is! Map<String, dynamic>) throw TranslationException(tr('语音识别接口返回的内容看不懂'));
    if (json['segments'] is! List) throw TranslationException(tr('这个语音识别服务不返回时间轴，无法生成字幕'));
    return json;
  }
}

/// One stretch of audio to recognize and where in the video it starts.
typedef SpeechPart = ({File file, Duration offset});

/// Audio fetched for 语音识别, cut into parts each [SpeechAudio.partBytes] or
/// smaller when ffmpeg is there.
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
        if (proxy != null) ...['--proxy', proxy],
        if (cacheDirectory != null) ...['--cache-dir', cacheDirectory],
        if (deno != null) ...['--js-runtimes', 'deno:$deno'],
        '--extractor-retries', '3',
        '--format', 'wa[acodec=opus]/wa/ba',
        '--output', '${folder.path}${Platform.pathSeparator}audio.%(ext)s',
        '--print', 'after_move:%(duration)s|%(filepath)s',
        '--', 'https://www.youtube.com/watch?v=$videoId',
      ];

  /// The audio of [videoId] in parts. Without ffmpeg a long video stays
  /// whole, when it is small enough for one request.
  static Future<List<SpeechPart>> fetch(
    String videoId,
    Directory folder, {
    required String ytDlp,
    required Map<String, String> environment,
    String? proxy,
    String? cacheDirectory,
    String? deno,
    String? ffmpeg,
  }) async {
    await folder.create(recursive: true);
    final result = await runWithTimeout(
      ytDlp,
      arguments(videoId, folder, proxy: proxy, cacheDirectory: cacheDirectory, deno: deno),
      timeout: const Duration(minutes: 15),
      environment: environment,
      onStart: (process) => lowerPriority(process.pid),
    );
    final printed = const LineSplitter().convert(result.stdout.toString()).where((l) => l.contains('|')).lastOrNull;
    if (result.exitCode != 0 || printed == null) throw TranslationException(tr('没能下载这个视频的音频'));
    final split = printed.indexOf('|');
    final seconds = double.tryParse(printed.substring(0, split)) ?? 0;
    final audio = File(printed.substring(split + 1).trim());
    if (!await audio.exists()) throw TranslationException(tr('没能下载这个视频的音频'));
    final size = await audio.length();
    final length = Duration(milliseconds: (seconds * 1000).round());
    final count = max((size / partBytes).ceil(), (length.inSeconds / partLength.inSeconds).ceil());
    if (count <= 1) return [(file: audio, offset: Duration.zero)];
    if (ffmpeg == null) {
      if (size <= partBytes) return [(file: audio, offset: Duration.zero)];
      throw TranslationException(tr('视频较长，需要 ffmpeg 才能分段识别。可以在“设置 › 组件管理”里安装 ffmpeg。'));
    }
    return _cut(audio, folder, ffmpeg, Duration(seconds: (length.inSeconds / count).ceil() + 1));
  }

  /// [audio] cut every [every] by copying packets, with each part's start
  /// as ffmpeg's segment list gives it.
  static Future<List<SpeechPart>> _cut(File audio, Directory folder, String ffmpeg, Duration every) async {
    final extension = audio.path.substring(audio.path.lastIndexOf('.'));
    final sep = Platform.pathSeparator;
    final list = File('${folder.path}${sep}parts.csv');
    final result = await runWithTimeout(
      ffmpeg,
      [
        '-hide_banner', '-loglevel', 'error', '-nostdin', '-y',
        '-i', audio.path,
        '-map', '0:a:0', '-c', 'copy',
        '-f', 'segment', '-segment_time', '${every.inSeconds}', '-reset_timestamps', '1',
        '-segment_list', list.path, '-segment_list_type', 'csv',
        '${folder.path}${sep}part%03d$extension',
      ],
      timeout: const Duration(minutes: 5),
      onStart: (process) => lowerPriority(process.pid),
    );
    if (result.exitCode != 0 || !await list.exists()) throw TranslationException(tr('没能把音频分段'));
    return parseSegmentList(await list.readAsString(), folder);
  }

  /// The parts ffmpeg's csv segment list names: `file,start,end` a line.
  static List<SpeechPart> parseSegmentList(String csv, Directory folder) => [
        for (final line in const LineSplitter().convert(csv))
          if (line.split(',') case [final name, final start, ...] when double.tryParse(start) != null)
            (file: File('${folder.path}${Platform.pathSeparator}$name'), offset: Duration(milliseconds: (double.parse(start) * 1000).round())),
      ];
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

/// Recognized subtitles kept in [folder] as `<video id>.<language>.vtt`, so
/// a video is sent once; the oldest go past [keep].
class SpeechSubtitleStore {
  SpeechSubtitleStore(this.folder, {this.keep = 300});
  final Directory folder;
  final int keep;

  /// The file and language of [videoId]'s recognized subtitles, if any.
  Future<({File file, String language})?> of(String videoId) async {
    try {
      if (!await folder.exists()) return null;
      await for (final entity in folder.list()) {
        final name = entity.uri.pathSegments.last;
        if (entity is File && name.startsWith('$videoId.') && name.endsWith('.vtt')) {
          return (file: entity, language: name.substring(videoId.length + 1, name.length - 4));
        }
      }
    } catch (_) {}
    return null;
  }

  Future<File> save(String videoId, String language, String vtt) async {
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
    } catch (_) {}
    return file;
  }
}
