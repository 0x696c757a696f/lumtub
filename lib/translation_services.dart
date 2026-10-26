import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' show md5;
import 'package:http/http.dart' as http;

import 'l10n/l10n.dart';
import 'translation.dart';
import 'translation_cache.dart';

/// The engines a person can pick for translating subtitles and comments.
enum TranslationService {
  google('Google 翻译（免费）'),
  microsoft('微软翻译（免费，可填密钥）'),
  deepl('DeepL'),
  deeplx('DeepLX（免密钥）'),
  baidu('百度翻译'),
  libre('LibreTranslate'),
  ai('AI 大模型');

  const TranslationService(this._label);
  final String _label;
  String get label => tr(_label);

  /// Whether an API key must be filled in before it works. LibreTranslate's,
  /// DeepLX's and Microsoft's are optional, and an AI endpoint on this
  /// computer or a custom one may need none.
  bool get needsKey => this == deepl || this == baidu || this == ai;
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

/// Microsoft (Azure) Translator, version 3. Without a key it uses the free
/// endpoint Microsoft Edge translates pages with, signing in with a short
/// token Edge's own address hands out.
class MicrosoftTranslator extends _LineTranslator {
  MicrosoftTranslator(super.client, {this.key = '', this.region = '', super.cacheSize = 200});
  final String key;
  final String region;

  String? _token;
  DateTime _tokenUntil = DateTime.fromMillisecondsSinceEpoch(0);

  Future<String> _edgeToken() async {
    final token = _token;
    if (token != null && DateTime.now().isBefore(_tokenUntil)) return token;
    final http.Response response;
    try {
      response = await client.get(Uri.https('edge.microsoft.com', '/translate/auth')).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw TranslationException(tr('无法翻译，请检查网络或代理'));
    }
    if (response.statusCode != 200 || response.body.trim().isEmpty) throw TranslationException(tr('翻译服务暂时不可用（{0}）', [response.statusCode]));
    _tokenUntil = DateTime.now().add(const Duration(minutes: 8));
    return _token = response.body.trim();
  }

  @override
  int get batchSize => 100;

  static String languageCode(String target) => switch (target) {
        'zh-CN' => 'zh-Hans',
        'zh-TW' => 'zh-Hant',
        _ => target,
      };

  @override
  Future<List<String>> translateBatch(List<String> lines, String target) async {
    final free = key.trim().isEmpty;
    final uri = Uri.https(free ? 'api-edge.cognitive.microsofttranslator.com' : 'api.cognitive.microsofttranslator.com', '/translate', {'api-version': '3.0', 'to': languageCode(target)});
    final headers = {
      if (free) 'Authorization': 'Bearer ${await _edgeToken()}' else 'Ocp-Apim-Subscription-Key': key.trim(),
      if (!free && region.trim().isNotEmpty) 'Ocp-Apim-Subscription-Region': region.trim(),
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

/// A DeepLX server (an open-source bridge to DeepL's web translator), the
/// person's own or one they trust. Lines go in one request, joined.
class DeepLXTranslator extends _LineTranslator {
  DeepLXTranslator(super.client, {required this.server, this.key = '', super.cacheSize = 200});
  final String server;
  final String key;

  @override
  int get batchSize => 30;

  Uri get endpoint {
    final uri = Uri.tryParse(server.trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
      throw TranslationException(tr('请填写 DeepLX 服务器地址'));
    }
    return uri.path.isEmpty || uri.path == '/' ? uri.replace(path: '/translate') : uri;
  }

  @override
  Future<List<String>> translateBatch(List<String> lines, String target) async {
    final code = DeepLTranslator.languageCode(target);
    if (code == null) throw TranslationException(tr('DeepL 不支持这种语言'));
    Future<String> one(String text) async {
      final reply = await _post(
        client,
        endpoint,
        {'Content-Type': 'application/json', if (key.trim().isNotEmpty) 'Authorization': 'Bearer ${key.trim()}'},
        jsonEncode({'text': text, 'source_lang': 'auto', 'target_lang': code == 'ZH-HANS' || code == 'ZH-HANT' ? 'ZH' : code.split('-').first}),
        {401: tr('DeepLX 密钥无效')},
        const Duration(seconds: 30),
      );
      final data = _decode(reply);
      if (data is Map && data['data'] is String) return data['data'] as String;
      throw _unrecognized();
    }

    final joined = (await one(lines.join('\n'))).split('\n');
    if (joined.length == lines.length) return joined;
    return [for (final line in lines) await one(line)];
  }
}

/// Baidu's general translation API, signed with the app ID and key.
class BaiduTranslator extends _LineTranslator {
  BaiduTranslator(super.client, {required this.appId, required this.key, super.cacheSize = 200});
  final String appId;
  final String key;

  @override
  int get batchSize => 50;

  static String languageCode(String target) => switch (target) {
        'zh-CN' => 'zh',
        'zh-TW' => 'cht',
        'ja' => 'jp',
        'ko' => 'kor',
        'fr' => 'fra',
        'es' => 'spa',
        'vi' => 'vie',
        'ar' => 'ara',
        _ => target,
      };

  @override
  Future<List<String>> translateBatch(List<String> lines, String target) async {
    if (appId.trim().isEmpty) throw TranslationException(tr('请先在设置里填写百度翻译的 APP ID'));
    final query = lines.join('\n');
    final salt = '${DateTime.now().millisecondsSinceEpoch}';
    final sign = md5.convert(utf8.encode('${appId.trim()}$query$salt${key.trim()}')).toString();
    final body = {'q': query, 'from': 'auto', 'to': languageCode(target), 'appid': appId.trim(), 'salt': salt, 'sign': sign};
    final reply = await _post(
      client,
      Uri.https('fanyi-api.baidu.com', '/api/trans/vip/translate'),
      {'Content-Type': 'application/x-www-form-urlencoded'},
      body.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&'),
      const {},
      const Duration(seconds: 30),
    );
    final data = _decode(reply);
    if (data is Map && data['error_code'] != null && '${data['error_code']}' != '52000') {
      throw TranslationException(switch ('${data['error_code']}') {
        '52003' || '54001' => tr('百度翻译的 APP ID 或密钥无效'),
        '54003' || '54005' => tr('翻译请求太频繁，请稍后再试'),
        '54004' => tr('百度翻译账户余额不足'),
        final code => tr('翻译服务暂时不可用（{0}）', [code]),
      });
    }
    if (data is Map && data['trans_result'] is List) {
      return [for (final item in data['trans_result'] as List) if (item is Map && item['dst'] is String) item['dst'] as String];
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

/// A translation style the AI is asked to write in, as KISS Translator
/// offers them.
class AiTone {
  const AiTone(this.id, this._label, this.instruction);
  final String id;
  final String _label;
  final String instruction;
  String get label => tr(_label);

  static const all = [
    AiTone('default', '跟随提示词', ''),
    AiTone('neutral', '中性', 'Use a neutral, plain tone.'),
    AiTone('casual', '口语', 'Use a casual, spoken tone, as people talk.'),
    AiTone('formal', '正式', 'Use a formal, polite tone.'),
    AiTone('literal', '直译', 'Stay as close to the original wording as the target language allows.'),
    AiTone('idiomatic', '意译', 'Convey the meaning freely with idiomatic expressions rather than the original wording.'),
    AiTone('technical', '技术', 'Use precise technical terminology.'),
    AiTone('academic', '学术', 'Use an academic, precise register.'),
    AiTone('literary', '文学', 'Use a literary, expressive style.'),
    AiTone('humorous', '幽默', 'Keep jokes, puns and humour working in the target language.'),
  ];

  static AiTone byId(String id) => all.firstWhere((t) => t.id == id, orElse: () => all.first);
}

/// Any OpenAI-compatible Chat Completions endpoint.
class AiTranslator extends _CachedTranslator {
  AiTranslator(
    super.client, {
    required this.baseUrl,
    this.key = '',
    required this.model,
    required this.prompt,
    this.tone = '',
    this.glossary = '',
    this.temperature = 0.2,
    this.contextLines = 0,
    super.cacheSize = 200,
  });
  final String baseUrl;
  final String key;
  final String model;
  final String prompt;
  /// [AiTone.instruction], added to the system prompt.
  final String tone;
  /// Terms and their translations, one `原文=译文` per line.
  final String glossary;
  final double temperature;
  /// How many lines before each request are sent along as context (for
  /// subtitles, the earlier cues), to be read but not translated.
  final int contextLines;

  /// The last lines sent, the context for the next request.
  List<String> _recent = const [];

  /// Text beyond this is sent in several requests, cut at line ends.
  static const requestLength = 3000;

  static const aiPresets = [
    AiPreset('openai', 'OpenAI', 'https://api.openai.com/v1', 'gpt-4o-mini'),
    AiPreset('deepseek', 'DeepSeek', 'https://api.deepseek.com/v1', 'deepseek-chat'),
    AiPreset('anthropic', 'Anthropic Claude', 'https://api.anthropic.com/v1', 'claude-haiku-5-5'),
    AiPreset('gemini', 'Google Gemini', 'https://generativelanguage.googleapis.com/v1beta/openai', 'gemini-2.5-flash'),
    AiPreset('qwen', '通义千问', 'https://dashscope.aliyuncs.com/compatible-mode/v1', 'qwen-plus'),
    AiPreset('zhipu', '智谱 GLM', 'https://open.bigmodel.cn/api/paas/v4', 'glm-4-flash'),
    AiPreset('siliconflow', '硅基流动', 'https://api.siliconflow.cn/v1', 'Qwen/Qwen2.5-7B-Instruct'),
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
    final context = contextLines <= 0 ? const <String>[] : _recent.sublist(_recent.length > contextLines ? _recent.length - contextLines : 0);
    if (contextLines > 0) {
      final recent = [..._recent, ...lines];
      _recent = recent.sublist(recent.length > contextLines ? recent.length - contextLines : 0);
    }
    final first = _split(await _ask(input, lines.length, target, null, context));
    if (first.length == lines.length) return first;
    final second = _split(await _ask(input, lines.length, target, 'Return exactly ${lines.length} lines.', context));
    if (second.length == lines.length) return second;
    throw TranslationException(tr('AI 返回的行数不对，无法对齐字幕'));
  }

  /// The system prompt with the target, line count, style and terms filled in.
  String systemPrompt(String target, int count, List<String> context) {
    final parts = [
      prompt.replaceAll('{target}', TranslationLanguage.byCode(target).label).replaceAll('{lines}', '$count'),
      if (tone.isNotEmpty) tone,
      if (glossaryLines.isNotEmpty) 'Always translate these terms as given (original = translation):\n${glossaryLines.join('\n')}',
      if (context.isNotEmpty) 'For context only, these lines came just before; do not translate or repeat them:\n${context.join('\n')}',
    ];
    return parts.join('\n\n');
  }

  List<String> get glossaryLines => [
        for (final line in glossary.split(RegExp(r'[\n;；]')))
          if (line.contains(RegExp('[=＝]')) && line.trim().length > 2) line.trim(),
      ];

  static List<String> _split(String reply) => reply.split('\n');

  Future<String> _ask(String input, int count, String target, String? note, List<String> context) async {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse('$base/chat/completions');
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
      throw TranslationException(tr('AI 接口地址或模型名不对'));
    }
    final system = systemPrompt(target, count, context);
    final body = {
      'model': model,
      'temperature': temperature,
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

  /// The models [baseUrl] lists at `/models`, for picking one.
  static Future<List<String>> listModels(http.Client client, String baseUrl, String key) async {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse('$base/models');
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) throw TranslationException(tr('AI 接口地址或模型名不对'));
    final http.Response response;
    try {
      response = await client.get(uri, headers: {if (key.trim().isNotEmpty) 'Authorization': 'Bearer ${key.trim()}'}).timeout(const Duration(seconds: 20));
    } catch (_) {
      throw TranslationException(tr('无法翻译，请检查网络或代理'));
    }
    if (response.statusCode == 401) throw TranslationException(tr('AI 接口密钥无效'));
    if (response.statusCode != 200) throw TranslationException(tr('翻译服务暂时不可用（{0}）', [response.statusCode]));
    final data = _decode(utf8.decode(response.bodyBytes));
    final list = data is Map ? data['data'] ?? data['models'] : data;
    if (list is! List) throw _unrecognized();
    final ids = <String>{
      for (final item in list)
        if (item is Map && item['id'] is String) item['id'] as String else if (item is Map && item['name'] is String) (item['name'] as String).replaceFirst('models/', ''),
    }.toList()
      ..sort();
    return ids;
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
    this.deeplxServer = '',
    this.baiduAppId = '',
    this.aiPreset = 'openai',
    this.aiBaseUrl = '',
    this.aiModel = '',
    this.promptPreset = 'subtitle',
    this.customPrompt = '',
    this.aiTone = 'default',
    this.aiGlossary = '',
    this.aiTemperature = 0.2,
    this.aiContext = 3,
  });

  final TranslationService service;
  final String libreServer;
  final String microsoftRegion;
  final String deeplxServer;
  final String baiduAppId;
  final String aiPreset;
  final String aiBaseUrl;
  final String aiModel;
  final String promptPreset;
  final String customPrompt;
  /// An [AiTone.id].
  final String aiTone;
  /// One `原文=译文` per line.
  final String aiGlossary;
  final double aiTemperature;
  /// Earlier subtitle lines sent along as context, 0 for none.
  final int aiContext;

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
    String? deeplxServer,
    String? baiduAppId,
    String? aiPreset,
    String? aiBaseUrl,
    String? aiModel,
    String? promptPreset,
    String? customPrompt,
    String? aiTone,
    String? aiGlossary,
    double? aiTemperature,
    int? aiContext,
  }) =>
      TranslationConfig(
        service: service ?? this.service,
        libreServer: libreServer ?? this.libreServer,
        microsoftRegion: microsoftRegion ?? this.microsoftRegion,
        deeplxServer: deeplxServer ?? this.deeplxServer,
        baiduAppId: baiduAppId ?? this.baiduAppId,
        aiPreset: aiPreset ?? this.aiPreset,
        aiBaseUrl: aiBaseUrl ?? this.aiBaseUrl,
        aiModel: aiModel ?? this.aiModel,
        promptPreset: promptPreset ?? this.promptPreset,
        customPrompt: customPrompt ?? this.customPrompt,
        aiTone: aiTone ?? this.aiTone,
        aiGlossary: aiGlossary ?? this.aiGlossary,
        aiTemperature: aiTemperature ?? this.aiTemperature,
        aiContext: aiContext ?? this.aiContext,
      );

  Map<String, Object?> toJson() => {
        'service': service.name,
        'libreServer': libreServer,
        'microsoftRegion': microsoftRegion,
        'deeplxServer': deeplxServer,
        'baiduAppId': baiduAppId,
        'aiPreset': aiPreset,
        'aiBaseUrl': aiBaseUrl,
        'aiModel': aiModel,
        'promptPreset': promptPreset,
        'customPrompt': customPrompt,
        'aiTone': aiTone,
        'aiGlossary': aiGlossary,
        'aiTemperature': aiTemperature,
        'aiContext': aiContext,
      };

  factory TranslationConfig.fromJson(Object? json) {
    if (json is! Map) return const TranslationConfig();
    String text(String name, String fallback) => json[name] is String ? json[name] as String : fallback;
    final service = TranslationService.values.firstWhere((s) => s.name == json['service'], orElse: () => TranslationService.google);
    final aiPreset = text('aiPreset', 'openai');
    final promptPreset = text('promptPreset', 'subtitle');
    final temperature = json['aiTemperature'];
    final context = json['aiContext'];
    return TranslationConfig(
      service: service,
      libreServer: text('libreServer', ''),
      microsoftRegion: text('microsoftRegion', ''),
      deeplxServer: text('deeplxServer', ''),
      baiduAppId: text('baiduAppId', ''),
      aiPreset: AiTranslator.aiPresets.any((p) => p.id == aiPreset) ? aiPreset : 'openai',
      aiBaseUrl: text('aiBaseUrl', ''),
      aiModel: text('aiModel', ''),
      promptPreset: promptPreset == 'custom' || AiTranslator.promptPresets.any((p) => p.id == promptPreset) ? promptPreset : 'subtitle',
      customPrompt: text('customPrompt', ''),
      aiTone: AiTone.byId(text('aiTone', 'default')).id,
      aiGlossary: text('aiGlossary', ''),
      aiTemperature: temperature is num ? temperature.toDouble().clamp(0.0, 1.5) : 0.2,
      aiContext: context is int ? context.clamp(0, 10) : 3,
    );
  }

  List<Object?> get _fields => [
        service, libreServer, microsoftRegion, deeplxServer, baiduAppId, aiPreset, aiBaseUrl, aiModel, //
        promptPreset, customPrompt, aiTone, aiGlossary, aiTemperature, aiContext,
      ];

  /// Names the service and every setting that changes its answers, so
  /// cached translations are kept apart.
  String get cacheScope => jsonEncode(service == TranslationService.google ? ['google'] : _fields.map((f) => f is TranslationService ? f.name : f).toList());

  @override
  bool operator ==(Object other) => other is TranslationConfig && _listEquals(other._fields, _fields);

  @override
  int get hashCode => Object.hashAll(_fields);
}

bool _listEquals(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
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
      return MicrosoftTranslator(client, key: key, region: config.microsoftRegion);
    case TranslationService.deeplx:
      return DeepLXTranslator(client, server: config.deeplxServer, key: key);
    case TranslationService.baidu:
      if (key.isEmpty) return _FailingTranslator(tr('请先在设置里填写 {0} 的密钥', [service.label]));
      return BaiduTranslator(client, appId: config.baiduAppId, key: key);
    case TranslationService.libre:
      return LibreTranslator(client, server: config.libreServer, key: key);
    case TranslationService.ai:
      final baseUrl = config.effectiveAiBaseUrl;
      final keyOptional = config.aiPreset == 'ollama' || config.aiPreset == 'custom' || _isLocalUrl(baseUrl);
      if (key.isEmpty && !keyOptional) return _FailingTranslator(tr('请先在设置里填写 {0} 的密钥', [service.label]));
      return AiTranslator(
        client,
        baseUrl: baseUrl,
        key: key,
        model: config.effectiveAiModel,
        prompt: config.effectivePrompt,
        tone: AiTone.byId(config.aiTone).instruction,
        glossary: config.aiGlossary,
        temperature: config.aiTemperature,
        contextLines: config.aiContext,
      );
  }
}

/// How many characters of text to hand [translator] at a time.
int chunkLengthOf(Translator translator) {
  if (translator is CachingTranslator) return chunkLengthOf(translator.inner);
  if (translator is AiTranslator) return 3000;
  if (translator is DeepLXTranslator || translator is BaiduTranslator) return 2000;
  if (translator is DeepLTranslator || translator is MicrosoftTranslator || translator is LibreTranslator) return 5000;
  return GoogleTranslator.chunkLength;
}
