import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../app_log.dart';
import '../local_db.dart' show callCoreJson;
import '../native_core.dart';
import '../native_http.dart';

/// Who reads a word aloud on a word card.
enum VoiceService {
  /// Edge's online voices, as Microsoft Edge reads aloud: natural, free,
  /// nothing to set up; the system's voice when they cannot be reached.
  edge,

  /// Azure's neural voices through Lumtub's server, when the server has
  /// a key; tried after [edge] fails, not offered on its own.
  lumtub,

  /// The system's own voices, offline and free; Windows may need the
  /// language's voice added in its settings.
  system,

  /// Azure's neural voices, with the learner's own key and region.
  azure,

  /// Google Cloud's voices, with the learner's own key.
  google,
}

/// The names [VoiceService]'s keys are kept under among the API keys.
const azureVoiceKey = 'azure-tts';
const azureVoiceRegion = 'azure-tts-region';
const googleVoiceKey = 'google-tts';

/// Why a word could not be read.
class VoiceException implements Exception {
  const VoiceException(this.noVoice, [this.detail = '']);

  /// The system has no voice for the language.
  final bool noVoice;
  final String detail;

  @override
  String toString() => noVoice ? 'no voice' : detail;
}

/// Reads words and lines aloud into sound files, kept in [cache] so each
/// is made once.
class WordVoice {
  WordVoice(this.cache);

  final Directory cache;
  http.Client? _client;

  /// The neural voice for each language, by Azure's name, which Edge's
  /// online voices share.
  static const azureVoices = {
    'en': 'en-US-JennyNeural',
    'zh': 'zh-CN-XiaoxiaoNeural',
    'ja': 'ja-JP-NanamiNeural',
    'ko': 'ko-KR-SunHiNeural',
    'es': 'es-ES-ElviraNeural',
    'fr': 'fr-FR-DeniseNeural',
    'de': 'de-DE-KatjaNeural',
    'it': 'it-IT-ElsaNeural',
    'ru': 'ru-RU-SvetlanaNeural',
    'pt': 'pt-BR-FranciscaNeural',
    'pt-BR': 'pt-BR-FranciscaNeural',
    'pt-PT': 'pt-PT-RaquelNeural',
    'es-ES': 'es-ES-ElviraNeural',
    'es-MX': 'es-MX-DaliaNeural',
  };

  /// Google's language codes.
  static const googleLanguages = {
    'en': 'en-US',
    'zh': 'cmn-CN',
    'ja': 'ja-JP',
    'ko': 'ko-KR',
    'es': 'es-ES',
    'fr': 'fr-FR',
    'de': 'de-DE',
    'it': 'it-IT',
    'ru': 'ru-RU',
    'pt': 'pt-BR',
    'pt-BR': 'pt-BR',
    'pt-PT': 'pt-PT',
    'es-ES': 'es-ES',
    'es-MX': 'es-US',
  };

  /// [language] as the subtitles' region says it: Portuguese from
  /// Portugal or Brazil, Spanish from Spain or Latin America. [codes] are
  /// the shown subtitles' language codes (`pt-PT`, `es-419`); with no
  /// region in them, Brazil and Latin America, whose videos YouTube has
  /// most of.
  static String variantOf(String language, Iterable<String?> codes) {
    if (language != 'pt' && language != 'es') return language;
    for (final code in codes) {
      final tag = (code ?? '').toLowerCase().replaceAll('_', '-');
      if (!tag.startsWith('$language-')) continue;
      final region = tag.substring(language.length + 1);
      if (language == 'pt') return region == 'pt' || region == 'ao' || region == 'mz' ? 'pt-PT' : 'pt-BR';
      return region == 'es' ? 'es-ES' : 'es-MX';
    }
    return language == 'pt' ? 'pt-BR' : 'es-MX';
  }

  static bool _provides(String symbol) => NativeCore.instance?.library.providesSymbol(symbol) ?? false;

  /// Whether the system has a voice for [language].
  static Future<bool> systemHasVoice(String language) async {
    if (!_provides('lumtub_speech_voice')) return false;
    final ask = jsonEncode({'language': language});
    final answer = await Isolate.run(() => callCoreJson('lumtub_speech_voice', ask));
    return answer['voice'] == true;
  }

  /// [text] in [language] read by [service], as a sound file.
  /// [server] gives Lumtub's server and this device's id, for [VoiceService.lumtub].
  Future<File> read(String text, String language, VoiceService service, Map<String, String> keys, {Future<(Uri, String)?> Function()? server}) async {
    final name = sha1.convert(utf8.encode('${service.name}\n$language\n$text')).toString();
    final file = File('${cache.path}${Platform.pathSeparator}$name.${service == VoiceService.system ? 'wav' : 'mp3'}');
    if (await file.exists() && await file.length() > 0) return file;
    await cache.create(recursive: true);
    switch (service) {
      case VoiceService.system:
        if (!_provides('lumtub_speak')) throw const VoiceException(true);
        var ask = jsonEncode({'text': text, 'language': language, 'out': file.path});
        var answer = await Isolate.run(() => callCoreJson('lumtub_speak', ask));
        // No voice for the region (pt-PT): any of the language's.
        if (answer['error'] == 'no voice' && language.contains('-')) {
          ask = jsonEncode({'text': text, 'language': language.split('-').first, 'out': file.path});
          answer = await Isolate.run(() => callCoreJson('lumtub_speak', ask));
        }
        final error = answer['error'];
        if (error is String) throw VoiceException(error == 'no voice', error);
      case VoiceService.edge:
        final voice = azureVoices[language];
        if (voice == null) throw const VoiceException(true);
        if (!_provides('lumtub_speak_online')) throw const VoiceException(false, 'Edge voice needs a newer core');
        final ask = jsonEncode({'text': text, 'voice': voice, 'out': file.path});
        final answer = await Isolate.run(() => callCoreJson('lumtub_speak_online', ask));
        final error = answer['error'];
        if (error is String) throw VoiceException(false, error);
      case VoiceService.lumtub:
        final where = await server?.call();
        if (where == null) throw const VoiceException(false, 'server unknown');
        await file.writeAsBytes(await _lumtub(text, language, where.$1, where.$2), flush: true);
      case VoiceService.azure:
        await file.writeAsBytes(await _azure(text, language, keys[azureVoiceKey] ?? '', keys[azureVoiceRegion] ?? ''), flush: true);
      case VoiceService.google:
        await file.writeAsBytes(await _google(text, language, keys[googleVoiceKey] ?? ''), flush: true);
    }
    return file;
  }

  Future<List<int>> _lumtub(String text, String language, Uri server, String device) async {
    if (!azureVoices.containsKey(language)) throw const VoiceException(true);
    final response = await (_client ??= appHttpClient())
        .post(server.resolve('/speak'), headers: {'content-type': 'application/json'}, body: jsonEncode({'text': text, 'language': language, 'device': device}))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 || !(response.headers['content-type'] ?? '').startsWith('audio/')) throw VoiceException(false, 'Lumtub voice HTTP ${response.statusCode}');
    return response.bodyBytes;
  }

  Future<List<int>> _azure(String text, String language, String key, String region) async {
    final voice = azureVoices[language];
    if (key.isEmpty || region.isEmpty) throw const VoiceException(false, 'Azure key or region missing');
    if (voice == null) throw const VoiceException(true);
    if (!RegExp(r'^[a-z0-9]+$').hasMatch(region)) throw const VoiceException(false, 'Azure region looks wrong');
    final escaped = const HtmlEscape(HtmlEscapeMode.element).convert(text);
    final ssml = '<speak version="1.0" xml:lang="${voice.substring(0, 5)}"><voice name="$voice">$escaped</voice></speak>';
    final response = await (_client ??= appHttpClient())
        .post(
          Uri.https('$region.tts.speech.microsoft.com', '/cognitiveservices/v1'),
          headers: {
            'Ocp-Apim-Subscription-Key': key,
            'Content-Type': 'application/ssml+xml',
            'X-Microsoft-OutputFormat': 'audio-24khz-48kbitrate-mono-mp3',
            'User-Agent': 'Lumtub',
          },
          body: utf8.encode(ssml),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw VoiceException(false, 'Azure HTTP ${response.statusCode}');
    return response.bodyBytes;
  }

  Future<List<int>> _google(String text, String language, String key) async {
    final code = googleLanguages[language];
    if (key.isEmpty) throw const VoiceException(false, 'Google key missing');
    if (code == null) throw const VoiceException(true);
    final response = await (_client ??= appHttpClient())
        .post(
          Uri.https('texttospeech.googleapis.com', '/v1/text:synthesize'),
          headers: {'X-Goog-Api-Key': key, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'input': {'text': text},
            'voice': {'languageCode': code},
            'audioConfig': {'audioEncoding': 'MP3'},
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw VoiceException(false, 'Google HTTP ${response.statusCode}');
    final audio = (jsonDecode(response.body) as Map)['audioContent'];
    if (audio is! String) throw const VoiceException(false, 'Google sent no sound');
    return base64Decode(audio);
  }

  /// Removes sound files older than a month.
  Future<void> tidy() async {
    try {
      if (!await cache.exists()) return;
      final old = DateTime.now().subtract(const Duration(days: 30));
      await for (final entry in cache.list()) {
        if (entry is File && (await entry.lastModified()).isBefore(old)) await entry.delete();
      }
    } catch (e) {
      logWarn('Could not tidy the word sounds: $e');
    }
  }
}
