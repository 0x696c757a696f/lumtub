import 'dart:convert';

import 'package:http/http.dart' as http;

import 'l10n/l10n.dart';

/// A language text can be translated into. [code] is Google Translate's;
/// [youtube] is the `tlang` YouTube's auto-translated captions use.
class TranslationLanguage {
  const TranslationLanguage(this.code, this._label, [String? youtube]) : youtube = youtube ?? code;
  final String code;
  final String youtube;
  final String _label;
  String get label => tr(_label);

  /// The default before Windows' language was followed.
  static const defaultCode = 'zh-CN';

  static const all = [
    TranslationLanguage('zh-CN', '简体中文', 'zh-Hans'),
    TranslationLanguage('zh-TW', '繁體中文', 'zh-Hant'),
    TranslationLanguage('en', '英语'),
    TranslationLanguage('ja', '日语'),
    TranslationLanguage('ko', '韩语'),
    TranslationLanguage('fr', '法语'),
    TranslationLanguage('de', '德语'),
    TranslationLanguage('es', '西班牙语'),
    TranslationLanguage('pt', '葡萄牙语'),
    TranslationLanguage('ru', '俄语'),
    TranslationLanguage('it', '意大利语'),
    TranslationLanguage('vi', '越南语'),
    TranslationLanguage('th', '泰语'),
    TranslationLanguage('id', '印尼语'),
    TranslationLanguage('ar', '阿拉伯语'),
    TranslationLanguage('hi', '印地语'),
  ];

  /// The language for a saved [code], else simplified Chinese.
  static TranslationLanguage byCode(Object? code) => all.firstWhere((l) => l.code == code, orElse: () => all.first);

  /// The language for a saved [code]; null for none or an unknown one.
  static TranslationLanguage? maybeByCode(Object? code) => all.where((l) => l.code == code).firstOrNull;
}

/// How a translation shown under its original looks, as KISS Translator
/// offers them.
enum TranslationStyle {
  quote('引用竖线'),
  plain('无样式'),
  highlight('背景高亮'),
  underline('虚线下划线'),
  box('虚线框'),
  blur('模糊（悬停显示）');

  const TranslationStyle(this._label);
  final String _label;
  String get label => tr(_label);
}

/// Something that turns text into another language.
abstract class Translator {
  /// [text] in [target] (a [TranslationLanguage.code]); throws
  /// [TranslationException] with a short message when it cannot.
  Future<String> translate(String text, String target);
}

class TranslationException implements Exception {
  const TranslationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Google Translate's public web endpoint, which needs no key. It is called
/// only when a person taps 翻译, and sends just the text being translated.
/// Requests go through [_client], so they follow the app's proxy.
class GoogleTranslator implements Translator {
  GoogleTranslator(this._client, {this.cacheSize = 200});
  final http.Client _client;
  final int cacheSize;

  /// Text beyond this is sent in several requests; the address holds it all.
  static const chunkLength = 1200;

  // A map keeps insertion order, which is recency: a hit moves the entry to the end.
  final _cache = <String, String>{};

  @override
  Future<String> translate(String text, String target) async {
    if (text.trim().isEmpty) return text;
    final key = '$target\u0000$text';
    final cached = _cache.remove(key);
    if (cached != null) return _cache[key] = cached;
    final parts = [for (final chunk in splitText(text)) await _request(chunk, target)];
    final result = parts.join();
    _cache[key] = result;
    if (_cache.length > cacheSize) _cache.remove(_cache.keys.first);
    return result;
  }

  Future<String> _request(String chunk, String target) async {
    if (chunk.trim().isEmpty) return chunk;
    final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {'client': 'gtx', 'sl': 'auto', 'tl': target, 'dt': 't', 'q': chunk});
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 429) throw TranslationException(tr('翻译请求太频繁，请稍后再试'));
      if (response.statusCode != 200) throw TranslationException(tr('翻译服务暂时不可用（{0}）', [response.statusCode]));
      return parseResponse(utf8.decode(response.bodyBytes));
    } on TranslationException {
      rethrow;
    } catch (_) {
      throw TranslationException(tr('无法翻译，请检查网络或代理'));
    }
  }

  /// The translated text of the endpoint's `[[["译文","原文",…],…],…]` reply.
  static String parseResponse(String body) {
    try {
      final data = jsonDecode(body);
      if (data is List && data.isNotEmpty && data.first is List) {
        return [for (final segment in data.first as List) if (segment is List && segment.isNotEmpty && segment.first is String) segment.first as String].join();
      }
    } on FormatException {
      // Falls through to the error below.
    }
    throw TranslationException(tr('翻译服务返回了无法识别的内容'));
  }

  /// [text] cut into pieces of at most [max] characters, at line ends and
  /// then spaces where it can, so that joining the pieces gives [text].
  static List<String> splitText(String text, {int max = chunkLength}) {
    final chunks = <String>[];
    var rest = text;
    while (rest.length > max) {
      var cut = rest.lastIndexOf('\n', max - 1);
      if (cut < max ~/ 2) cut = rest.lastIndexOf(' ', max - 1);
      cut = cut < max ~/ 2 ? max : cut + 1;
      chunks.add(rest.substring(0, cut));
      rest = rest.substring(cut);
    }
    if (rest.isNotEmpty) chunks.add(rest);
    return chunks;
  }
}

/// [text] in [target], translating only the lines not already in it, so a
/// comment written in two languages gets its foreign half translated
/// instead of coming back unchanged. [isTarget] tells which lines are.
/// Lines are sent together in one request.
Future<String> translateForeignLines(Translator translator, String text, String target, bool Function(String line) isTarget) async {
  final lines = text.split('\n');
  final foreign = [
    for (final (i, line) in lines.indexed)
      if (line.trim().isNotEmpty && !isTarget(line)) i,
  ];
  if (foreign.isEmpty || foreign.length == lines.where((l) => l.trim().isNotEmpty).length) return translator.translate(text, target);
  final translated = (await translator.translate([for (final i in foreign) lines[i]].join('\n'), target)).split('\n');
  final out = [...lines];
  if (translated.length == foreign.length) {
    for (final (k, i) in foreign.indexed) {
      out[i] = translated[k];
    }
  } else {
    // The service joined or split lines: its text stands where the first
    // foreign line was.
    out[foreign.first] = translated.join('\n');
    for (final i in foreign.skip(1).toList().reversed) {
      out.removeAt(i);
    }
  }
  return out.join('\n');
}
