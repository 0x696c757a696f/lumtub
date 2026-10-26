import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'l10n/l10n.dart';
import 'translation.dart';

/// The engines a person can pick for translating subtitles and comments.
enum TranslationService {
  google('Google 翻译（免费）'),
  deepl('DeepL'),
  microsoft('微软翻译'),
  libre('LibreTranslate'),
  ai('AI 大模型');

  const TranslationService(this._label);
  final String _label;
  String get label => tr(_label);

  /// Whether an API key must be filled in before it works. LibreTranslate's is
  /// optional, and an AI endpoint on this computer or a custom one may need none.
  bool get needsKey => this == deepl || this == microsoft || this == ai;
}

/// A ready-made AI endpoint.
class AiPreset {
  const AiPreset(this.id, this._label, this.baseUrl, this.model);
  final String id;
  final String _label;
  final String baseUrl;
  final String model;
  String get label => tr(_label);
}

/// A ready-made system prompt. Every one keeps the line-count rule, since
/// subtitles are matched back by line.
class PromptPreset {
  const PromptPreset(this.id, this._label, this.text);
  final String id;
  final String _label;
  final String text;
  String get label => tr(_label);
}

const _lineRule = 'The input has {lines} lines. Output exactly {lines} lines, in the same order, one translation per line. '
    'Do not number the lines, do not add explanations, notes or quotation marks, and do not merge or split lines. ';

/// Network failures and statuses shared by every service.
Future<String> _post(http.Client client, Uri uri, Map<String, String> headers, String body, Map<int, String> errors, Duration timeout) async {
  final http.Response response;
  try {
    response = await client.post(uri, headers: headers, body: body).timeout(timeout);
  } catch (_) {
    throw TranslationException(tr('无法翻译，请检查网络或代理'));
  }
  final status = response.statusCode;
  if (status == 200) return utf8.decode(response.bodyBytes);
  if (errors.containsKey(status)) throw TranslationException(errors[status]!);
  if (status == 429) throw TranslationException(tr('翻译请求太频繁，请稍后再试'));
  throw TranslationException(tr('翻译服务暂时不可用（{0}）', [status]));
}

TranslationException _unrecognized() => TranslationException(tr('翻译服务返回了无法识别的内容'));

Object? _decode(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    throw _unrecognized();
  }
}

abstract class _CachedTranslator implements Translator {
  _CachedTranslator(this.client, {this.cacheSize = 200});
  final http.Client client;
  final int cacheSize;

  // A map keeps insertion order, which is recency: a hit moves the entry to the end.
  final _cache = <String, String>{};

  @override
  Future<String> translate(String text, String target) async {
    if (text.trim().isEmpty) return text;
    final key = '$target\u0000$text';
    final cached = _cache.remove(key);
    if (cached != null) return _cache[key] = cached;
    final result = await translateUncached(text, target);
    _cache[key] = result;
    if (_cache.length > cacheSize) _cache.remove(_cache.keys.first);
    return result;
  }

  Future<String> translateUncached(String text, String target);
}

/// A service that translates a list of lines at a time. Empty lines are not
/// sent and stay where they are, so the line count never changes.
abstract class _LineTranslator extends _CachedTranslator {
  _LineTranslator(super.client, {super.cacheSize});

  int get batchSize;

  Future<List<String>> translateBatch(List<String> lines, String target);

  @override
  Future<String> translateUncached(String text, String target) async {
    final lines = text.split('\n');
    final out = List<String>.of(lines);
    final indexes = [for (var i = 0; i < lines.length; i++) if (lines[i].trim().isNotEmpty) i];
    for (var start = 0; start < indexes.length; start += batchSize) {
      final part = indexes.sublist(start, math.min(start + batchSize, indexes.length));
      final result = await translateBatch([for (final i in part) lines[i]], target);
      if (result.length != part.length) throw _unrecognized();
      for (var k = 0; k < part.length; k++) {
        out[part[k]] = result[k].replaceAll(RegExp(r'\r\n|\r|\n'), ' ');
      }
    }
    return out.join('\n');
  }
}

/// DeepL's API. A key ending in `:fx` belongs to the free plan, which has its
/// own address.
class DeepLTranslator extends _LineTranslator {
  DeepLTranslator(super.client, {required this.key, super.cacheSize = 200});
  final String key;

  @override
  int get batchSize => 50;

  Uri get endpoint {
    final host = key.trim().endsWith(':fx') ? 'api-free.deepl.com' : 'api.deepl.com';
    return Uri.https(host, '/v2/translate');
  }

  static String? languageCode(String target) {
    switch (target) {
      case 'zh-CN':
        return 'ZH-HANS';
      case 'zh-TW':
        return 'ZH-HANT';
      case 'en':
        return 'EN-US';
      case 'pt':
        return 'PT-BR';
      case 'vi':
      case 'th':
      case 'hi':
        return null;
      default:
        return target.toUpperCase();
    }
  }

  @override
  Future<List<String>> translateBatch(List<String> lines, String target) async {
    final code = languageCode(target);
    if (code == null) throw TranslationException(tr('DeepL 不支持这种语言'));
    final body = [for (final line in lines) 'text=${Uri.encodeQueryComponent(line)}', 'target_lang=$code'].join('&');
    final reply = await _post(
      client,
      endpoint,
      {'Authorization': 'DeepL-Auth-Key ${key.trim()}', 'Content-Type': 'application/x-www-form-urlencoded'},
      body,
      {403: tr('DeepL 密钥无效'), 456: tr('DeepL 本月额度已用完')},
      const Duration(seconds: 30),
    );
    final data = _decode(reply);
    if (data is Map && data['translations'] is List) {
      final list = data['translations'] as List;
      return [for (final item in list) if (item is Map && item['text'] is String) item['text'] as String];
    }
    throw _unrecognized();
  }
}

/// Microsoft (Azure) Translator, version 3.
class MicrosoftTranslator extends _LineTranslator {
  MicrosoftTranslator(super.client, {required this.key, this.region = '', super.cacheSize = 200});
  final String key;
  final String region;

  @override
  int get batchSize => 100;

  static String languageCode(String target) => switch (target) {
        'zh-CN' => 'zh-Hans',
        'zh-TW' => 'zh-Hant',
        _ => target,
      };

  @override
  Future<List<String>> translateBatch(List<String> lines, String target) async {
    final uri = Uri.https('api.cognitive.microsofttranslator.com', '/translate', {'api-version': '3.0', 'to': languageCode(target)});
    final headers = {
      'Ocp-Apim-Subscription-Key': key.trim(),
      if (region.trim().isNotEmpty) 'Ocp-Apim-Subscription-Region': region.trim(),
      'Content-Type': 'application/json',
    };
    final reply = await _post(
      client,
      uri,
      headers,
      jsonEncode([for (final line in lines) {'Text': line}]),
      {401: tr('微软翻译密钥无效')},
      const Duration(seconds: 30),
    );
    final data = _decode(reply);
    if (data is List) {
      final out = <String>[];
      for (final item in data) {
        final translations = item is Map ? item['translations'] : null;
        if (translations is List && translations.isNotEmpty && translations.first is Map && (translations.first as Map)['text'] is String) {
          out.add((translations.first as Map)['text'] as String);
        }
      }
      return out;
    }
    throw _unrecognized();
  }
}

/// A LibreTranslate server, the person's own or a public one.
class LibreTranslator extends _LineTranslator {
  LibreTranslator(super.client, {required this.server, this.key = '', super.cacheSize = 200});
  final String server;
  final String key;

  @override
  int get batchSize => 100;

  static String languageCode(String target) => switch (target) {
        'zh-CN' => 'zh-Hans',
        'zh-TW' => 'zh-Hant',
        _ => target,
      };

  Uri get endpoint {
    final base = server.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse('$base/translate');
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
      throw TranslationException(tr('请填写 LibreTranslate 服务器地址'));
    }
    return uri;
  }

  @override
  Future<List<String>> translateBatch(List<String> lines, String target) async {
    final uri = endpoint;
    final body = {
      'q': lines,
      'source': 'auto',
      'target': languageCode(target),
      'format': 'text',
      if (key.trim().isNotEmpty) 'api_key': key.trim(),
    };
    final reply = await _post(client, uri, {'Content-Type': 'application/json'}, jsonEncode(body), const {}, const Duration(seconds: 30));
    final data = _decode(reply);
    if (data is Map) {
      final result = data['translatedText'];
      if (result is String) return [result];
      if (result is List && result.every((e) => e is String)) return result.cast<String>();
    }
    throw _unrecognized();
  }
}

/// Any OpenAI-compatible Chat Completions endpoint.
class AiTranslator extends _CachedTranslator {
  AiTranslator(super.client, {required this.baseUrl, this.key = '', required this.model, required this.prompt, super.cacheSize = 200});
  final String baseUrl;
  final String key;
  final String model;
  final String prompt;

  /// Text beyond this is sent in several requests, cut at line ends.
  static const requestLength = 3000;

  static const aiPresets = [
    AiPreset('openai', 'OpenAI', 'https://api.openai.com/v1', 'gpt-4o-mini'),
    AiPreset('deepseek', 'DeepSeek', 'https://api.deepseek.com/v1', 'deepseek-chat'),
    AiPreset('anthropic', 'Anthropic Claude', 'https://api.anthropic.com/v1', 'claude-haiku-5-5'),
    AiPreset('gemini', 'Google Gemini', 'https://generativelanguage.googleapis.com/v1beta/openai', 'gemini-2.5-flash'),
    AiPreset('qwen', '通义千问', 'https://dashscope.aliyuncs.com/compatible-mode/v1', 'qwen-plus'),
    AiPreset('openrouter', 'OpenRouter', 'https://openrouter.ai/api/v1', 'openai/gpt-4o-mini'),
    AiPreset('ollama', 'Ollama（本机）', 'http://localhost:11434/v1', 'qwen2.5'),
    AiPreset('custom', '自定义', '', ''),
  ];

  static const promptPresets = [
    PromptPreset(
      'subtitle',
      '字幕翻译（逐行对应）',
      'You are a professional subtitle translator. Translate the user\'s text into {target}. $_lineRule'
          'Keep names and terms consistent throughout, and keep each line short and natural, like a subtitle.',
    ),
    PromptPreset(
      'natural',
      '自然口语',
      'You are a translator who writes natural, conversational language. Translate the user\'s text into {target} the way a native speaker would say it, '
          'using idiomatic expressions instead of word-for-word renderings. $_lineRule'
          'Keep names and terms consistent throughout, and keep each line short.',
    ),
    PromptPreset(
      'faithful',
      '忠实直译',
      'You are a precise translator. Translate the user\'s text into {target} as literally and faithfully as possible without adding or omitting anything. $_lineRule'
          'Keep proper nouns and technical terms in the original language in parentheses after their translation on first use, and keep them consistent afterwards.',
    ),
  ];

  @override
  Future<String> translateUncached(String text, String target) async {
    final lines = text.split('\n');
    final out = List<String>.of(lines);
    final indexes = [for (var i = 0; i < lines.length; i++) if (lines[i].trim().isNotEmpty) i];
    var start = 0;
    while (start < indexes.length) {
      var end = start;
      var length = 0;
      while (end < indexes.length && (end == start || length + lines[indexes[end]].length + 1 <= requestLength)) {
        length += lines[indexes[end]].length + 1;
        end++;
      }
      final part = indexes.sublist(start, end);
      final result = await _translatePiece([for (final i in part) lines[i]], target);
      for (var k = 0; k < part.length; k++) {
        out[part[k]] = result[k];
      }
      start = end;
    }
    return out.join('\n');
  }

  Future<List<String>> _translatePiece(List<String> lines, String target) async {
    final input = lines.join('\n');
    final first = _split(await _ask(input, lines.length, target, null));
    if (first.length == lines.length) return first;
    final second = _split(await _ask(input, lines.length, target, 'Return exactly ${lines.length} lines.'));
    if (second.length == lines.length) return second;
    throw TranslationException(tr('AI 返回的行数不对，无法对齐字幕'));
  }

  static List<String> _split(String reply) => reply.split('\n');

  Future<String> _ask(String input, int count, String target, String? note) async {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse('$base/chat/completions');
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
      throw TranslationException(tr('AI 接口地址或模型名不对'));
    }
    final system = prompt.replaceAll('{target}', TranslationLanguage.byCode(target).label).replaceAll('{lines}', '$count');
    final body = {
      'model': model,
      'temperature': 0.2,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': input},
        if (note != null) {'role': 'user', 'content': note},
      ],
    };
    final reply = await _post(
      client,
      uri,
      {
        'Content-Type': 'application/json',
        if (key.trim().isNotEmpty) 'Authorization': 'Bearer ${key.trim()}',
      },
      jsonEncode(body),
      {401: tr('AI 接口密钥无效'), 404: tr('AI 接口地址或模型名不对')},
      const Duration(seconds: 60),
    );
    final data = _decode(reply);
    if (data is Map && data['choices'] is List && (data['choices'] as List).isNotEmpty) {
      final choice = (data['choices'] as List).first;
      final message = choice is Map ? choice['message'] : null;
      final content = message is Map ? message['content'] : null;
      if (content is String) return cleanReply(content);
    }
    throw _unrecognized();
  }

  /// [reply] without a surrounding ``` fence and trailing line breaks.
  static String cleanReply(String reply) {
    var text = reply.replaceAll('\r\n', '\n').trim();
    if (text.startsWith('```') && text.endsWith('```') && text.length >= 6) {
      final firstBreak = text.indexOf('\n');
      if (firstBreak >= 0 && firstBreak < text.length - 3) {
        text = text.substring(firstBreak + 1, text.length - 3);
      } else {
        text = text.substring(3, text.length - 3);
      }
    }
    return text.replaceAll(RegExp(r'\n+$'), '');
  }
}

/// The settings of the translation service that are not secret. API keys are
/// kept apart from these.
class TranslationConfig {
  const TranslationConfig({
    this.service = TranslationService.google,
    this.libreServer = '',
    this.microsoftRegion = '',
    this.aiPreset = 'openai',
    this.aiBaseUrl = '',
    this.aiModel = '',
    this.promptPreset = 'subtitle',
    this.customPrompt = '',
  });

  final TranslationService service;
  final String libreServer;
  final String microsoftRegion;
  final String aiPreset;
  final String aiBaseUrl;
  final String aiModel;
  final String promptPreset;
  final String customPrompt;

  AiPreset get _aiPreset => AiTranslator.aiPresets.firstWhere((p) => p.id == aiPreset, orElse: () => AiTranslator.aiPresets.first);

  String get effectiveAiBaseUrl => aiBaseUrl.trim().isNotEmpty ? aiBaseUrl.trim() : _aiPreset.baseUrl;

  String get effectiveAiModel => aiModel.trim().isNotEmpty ? aiModel.trim() : _aiPreset.model;

  String get effectivePrompt {
    if (promptPreset == 'custom' && customPrompt.trim().isNotEmpty) return customPrompt;
    return AiTranslator.promptPresets.firstWhere((p) => p.id == promptPreset, orElse: () => AiTranslator.promptPresets.first).text;
  }

  TranslationConfig copyWith({
    TranslationService? service,
    String? libreServer,
    String? microsoftRegion,
    String? aiPreset,
    String? aiBaseUrl,
    String? aiModel,
    String? promptPreset,
    String? customPrompt,
  }) =>
      TranslationConfig(
        service: service ?? this.service,
        libreServer: libreServer ?? this.libreServer,
        microsoftRegion: microsoftRegion ?? this.microsoftRegion,
        aiPreset: aiPreset ?? this.aiPreset,
        aiBaseUrl: aiBaseUrl ?? this.aiBaseUrl,
        aiModel: aiModel ?? this.aiModel,
        promptPreset: promptPreset ?? this.promptPreset,
        customPrompt: customPrompt ?? this.customPrompt,
      );

  Map<String, Object?> toJson() => {
        'service': service.name,
        'libreServer': libreServer,
        'microsoftRegion': microsoftRegion,
        'aiPreset': aiPreset,
        'aiBaseUrl': aiBaseUrl,
        'aiModel': aiModel,
        'promptPreset': promptPreset,
        'customPrompt': customPrompt,
      };

  factory TranslationConfig.fromJson(Object? json) {
    if (json is! Map) return const TranslationConfig();
    String text(String name, String fallback) => json[name] is String ? json[name] as String : fallback;
    final service = TranslationService.values.firstWhere((s) => s.name == json['service'], orElse: () => TranslationService.google);
    final aiPreset = text('aiPreset', 'openai');
    final promptPreset = text('promptPreset', 'subtitle');
    return TranslationConfig(
      service: service,
      libreServer: text('libreServer', ''),
      microsoftRegion: text('microsoftRegion', ''),
      aiPreset: AiTranslator.aiPresets.any((p) => p.id == aiPreset) ? aiPreset : 'openai',
      aiBaseUrl: text('aiBaseUrl', ''),
      aiModel: text('aiModel', ''),
      promptPreset: promptPreset == 'custom' || AiTranslator.promptPresets.any((p) => p.id == promptPreset) ? promptPreset : 'subtitle',
      customPrompt: text('customPrompt', ''),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TranslationConfig &&
      other.service == service &&
      other.libreServer == libreServer &&
      other.microsoftRegion == microsoftRegion &&
      other.aiPreset == aiPreset &&
      other.aiBaseUrl == aiBaseUrl &&
      other.aiModel == aiModel &&
      other.promptPreset == promptPreset &&
      other.customPrompt == customPrompt;

  @override
  int get hashCode => Object.hash(service, libreServer, microsoftRegion, aiPreset, aiBaseUrl, aiModel, promptPreset, customPrompt);
}

class _FailingTranslator implements Translator {
  const _FailingTranslator(this.message);
  final String message;

  @override
  Future<String> translate(String text, String target) async {
    if (text.trim().isEmpty) return text;
    throw TranslationException(message);
  }
}

bool _isLocalUrl(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  return host == 'localhost' || host == '127.0.0.1' || host == '::1' || host == '[::1]';
}

/// The translator [config] asks for, with its secret from [keys] (by
/// [TranslationService.name]). Google's is [fallback].
Translator translatorFor(TranslationConfig config, Map<String, String> keys, http.Client client, {required Translator fallback}) {
  final service = config.service;
  final key = (keys[service.name] ?? '').trim();
  switch (service) {
    case TranslationService.google:
      return fallback;
    case TranslationService.deepl:
      if (key.isEmpty) return _FailingTranslator(tr('请先在设置里填写 {0} 的密钥', [service.label]));
      return DeepLTranslator(client, key: key);
    case TranslationService.microsoft:
      if (key.isEmpty) return _FailingTranslator(tr('请先在设置里填写 {0} 的密钥', [service.label]));
      return MicrosoftTranslator(client, key: key, region: config.microsoftRegion);
    case TranslationService.libre:
      return LibreTranslator(client, server: config.libreServer, key: key);
    case TranslationService.ai:
      final baseUrl = config.effectiveAiBaseUrl;
      final keyOptional = config.aiPreset == 'ollama' || config.aiPreset == 'custom' || _isLocalUrl(baseUrl);
      if (key.isEmpty && !keyOptional) return _FailingTranslator(tr('请先在设置里填写 {0} 的密钥', [service.label]));
      return AiTranslator(client, baseUrl: baseUrl, key: key, model: config.effectiveAiModel, prompt: config.effectivePrompt);
  }
}

/// How many characters of text to hand [translator] at a time.
int chunkLengthOf(Translator translator) {
  if (translator is AiTranslator) return 3000;
  if (translator is DeepLTranslator || translator is MicrosoftTranslator || translator is LibreTranslator) return 5000;
  return GoogleTranslator.chunkLength;
}
