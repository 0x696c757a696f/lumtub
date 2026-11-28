import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'l10n/l10n.dart';
import 'language_guess.dart';

/// A language text can be translated into. [code] is Google Translate's;
/// [youtube] is the `tlang` YouTube's auto-translated captions use; [tags]
/// are every tag a subtitle in it may carry.
class TranslationLanguage {
  const TranslationLanguage(this.code, this._label, [String? youtube, this._aliases = const []])
      : youtube = youtube ?? code;
  final String code;
  final String youtube;
  final String _label;
  final List<String> _aliases;
  String get label => tr(_label);

  /// The language's name in English, for prompts.
  String get englishName => _label;

  /// [code], [youtube] and the other tags this language goes by.
  Iterable<String> get tags => {code, youtube, ..._aliases};

  /// The default before Windows' language was followed.
  static const defaultCode = 'zh-CN';

  /// One for each interface language, so subtitles and translations can
  /// always be in the language Lumtub is shown in.
  static const all = [
    TranslationLanguage('zh-CN', 'Simplified Chinese', 'zh-Hans'),
    TranslationLanguage('zh-TW', 'Traditional Chinese', 'zh-Hant'),
    TranslationLanguage('en', 'English'),
    TranslationLanguage('ja', 'Japanese'),
    TranslationLanguage('ko', 'Korean'),
    TranslationLanguage('fr', 'French'),
    TranslationLanguage('de', 'German'),
    TranslationLanguage('es', 'Spanish'),
    TranslationLanguage('pt', 'Portuguese'),
    TranslationLanguage('ru', 'Russian'),
    TranslationLanguage('it', 'Italian'),
    TranslationLanguage('vi', 'Vietnamese'),
    TranslationLanguage('th', 'Thai'),
    TranslationLanguage('id', 'Indonesian'),
    TranslationLanguage('ar', 'Arabic'),
    TranslationLanguage('hi', 'Hindi'),
    TranslationLanguage('af', 'Afrikaans'),
    TranslationLanguage('sq', 'Albanian'),
    TranslationLanguage('am', 'Amharic'),
    TranslationLanguage('hy', 'Armenian'),
    TranslationLanguage('as', 'Assamese'),
    TranslationLanguage('az', 'Azerbaijani'),
    TranslationLanguage('eu', 'Basque'),
    TranslationLanguage('be', 'Belarusian'),
    TranslationLanguage('bn', 'Bengali'),
    TranslationLanguage('bs', 'Bosnian'),
    TranslationLanguage('bg', 'Bulgarian'),
    TranslationLanguage('my', 'Burmese'),
    TranslationLanguage('ca', 'Catalan'),
    TranslationLanguage('hr', 'Croatian'),
    TranslationLanguage('cs', 'Czech'),
    TranslationLanguage('da', 'Danish'),
    TranslationLanguage('nl', 'Dutch'),
    TranslationLanguage('eo', 'Esperanto'),
    TranslationLanguage('et', 'Estonian'),
    TranslationLanguage('tl', 'Filipino', 'fil', ['fil']),
    TranslationLanguage('fi', 'Finnish'),
    TranslationLanguage('gl', 'Galician'),
    TranslationLanguage('ka', 'Georgian'),
    TranslationLanguage('el', 'Greek'),
    TranslationLanguage('gu', 'Gujarati'),
    TranslationLanguage('iw', 'Hebrew', 'iw', ['he']),
    TranslationLanguage('hu', 'Hungarian'),
    TranslationLanguage('is', 'Icelandic'),
    TranslationLanguage('jw', 'Javanese', 'jv', ['jv']),
    TranslationLanguage('kn', 'Kannada'),
    TranslationLanguage('kk', 'Kazakh'),
    TranslationLanguage('km', 'Khmer'),
    TranslationLanguage('ky', 'Kyrgyz'),
    TranslationLanguage('lo', 'Lao'),
    TranslationLanguage('la', 'Latin'),
    TranslationLanguage('lv', 'Latvian'),
    TranslationLanguage('lt', 'Lithuanian'),
    TranslationLanguage('mk', 'Macedonian'),
    TranslationLanguage('ms', 'Malay'),
    TranslationLanguage('ml', 'Malayalam'),
    TranslationLanguage('mr', 'Marathi'),
    TranslationLanguage('mn', 'Mongolian'),
    TranslationLanguage('ne', 'Nepali'),
    TranslationLanguage('no', 'Norwegian', 'no', ['nb', 'nn']),
    TranslationLanguage('or', 'Odia'),
    TranslationLanguage('fa', 'Persian'),
    TranslationLanguage('pl', 'Polish'),
    TranslationLanguage('pa', 'Punjabi'),
    TranslationLanguage('ro', 'Romanian'),
    TranslationLanguage('sr', 'Serbian'),
    TranslationLanguage('si', 'Sinhala'),
    TranslationLanguage('sk', 'Slovak'),
    TranslationLanguage('sl', 'Slovenian'),
    TranslationLanguage('su', 'Sundanese'),
    TranslationLanguage('sw', 'Swahili'),
    TranslationLanguage('sv', 'Swedish'),
    TranslationLanguage('ta', 'Tamil'),
    TranslationLanguage('te', 'Telugu'),
    TranslationLanguage('ti', 'Tigrinya'),
    TranslationLanguage('tr', 'Turkish'),
    TranslationLanguage('tk', 'Turkmen'),
    TranslationLanguage('uk', 'Ukrainian'),
    TranslationLanguage('ur', 'Urdu'),
    TranslationLanguage('uz', 'Uzbek'),
    TranslationLanguage('zu', 'Zulu'),
  ];

  /// The language for a saved [code], else simplified Chinese.
  static TranslationLanguage byCode(Object? code) =>
      all.firstWhere((l) => l.code == code, orElse: () => all.first);

  /// The language for a saved [code]; null for none or an unknown one.
  static TranslationLanguage? maybeByCode(Object? code) =>
      all.where((l) => l.code == code).firstOrNull;

  /// The language a language [tag] (an interface language's, Windows' or a
  /// subtitle's) names; Chinese by script, null when none is.
  static TranslationLanguage? ofTag(String tag) {
    final t = tag.toLowerCase().replaceAll('_', '-');
    if (const {'zh', 'zh-hans', 'zh-cn', 'zh-sg'}.contains(t)) return all[0];
    if (const {'zh-hant', 'zh-tw', 'zh-hk', 'zh-mo'}.contains(t)) return all[1];
    final base = t.split('-').first;
    return all.where((l) => l.tags.contains(base)).firstOrNull;
  }
}

/// How a translation shown under its original looks, as KISS Translator
/// offers them.
enum TranslationStyle {
  quote('Quote bar'),
  plain('Plain'),
  highlight('Highlighted'),
  underline('Dashed underline'),
  box('Dashed box'),
  blur('Blurred (hover to reveal)');

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
  const TranslationException(this.message, {this.busy = false});

  /// The service's answer to too many requests (429): the same request may
  /// go through after a pause.
  factory TranslationException.busy() =>
      TranslationException(tr('Too many translation requests. Please try again later.'),
          busy: true);

  final String message;
  final bool busy;
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
    final result = await _ask(chunk, target, 'auto');
    // Its guess at the language sometimes goes wrong (chatty text with
    // emoji), and the text comes back as it was: once more, in the language
    // the letters say it is in.
    if (!_unchanged(result, chunk)) return result;
    final source = _guessSource(chunk, target);
    return source == null ? result : _ask(chunk, target, source);
  }

  /// The language [text] seems to be written in, other than [target]: from
  /// its script, and English from its common words. Null when the letters
  /// can't tell (French and German share English's).
  static String? _guessSource(String text, String target) {
    for (final code in const ['ja', 'ko', 'ru', 'ar', 'th', 'hi', 'zh-CN', 'zh-TW', 'en']) {
      if (code == target || (code.startsWith('zh') && target.startsWith('zh'))) continue;
      if (looksLike(text, code)) return code;
    }
    // Mostly Latin letters but no common English word seen: English is still
    // the likeliest for a YouTube comment.
    return target != 'en' && _latin(text) && !looksLike(text, target) ? 'en' : null;
  }

  static bool _unchanged(String a, String b) =>
      a.replaceAll(RegExp(r'\s+'), ' ').trim() == b.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Mostly Latin letters, as English is written.
  static bool _latin(String text) {
    final letters = RegExp(r'\p{L}', unicode: true).allMatches(text).length;
    return letters >= 4 && RegExp(r'[A-Za-z]').allMatches(text).length >= letters * 0.8;
  }

  /// When the next request to the endpoint may go out, shared by every
  /// translator in the app: requests are spaced [_spacing] apart, and after
  /// a 429 none go out for a while, longer each time it answers so, so a
  /// refusal is not met with a burst of asking again.
  static DateTime _next = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime _coolUntil = DateTime.fromMillisecondsSinceEpoch(0);
  static int _refusals = 0;

  /// Whether the endpoint said it was busy a moment ago: until then a
  /// request fails at once, so another service can take it.
  static bool get coolingDown => DateTime.now().isBefore(_coolUntil);
  static const _spacing = Duration(milliseconds: 300);
  static const _cooldowns = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 45),
    Duration(minutes: 2)
  ];

  /// Forgets earlier refusals and spacing, for tests.
  static void resetPacing() {
    _next = DateTime.fromMillisecondsSinceEpoch(0);
    _coolUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _refusals = 0;
  }

  static Future<void> _turn() async {
    final now = DateTime.now();
    final at = _next.isAfter(now) ? _next : now;
    _next = at.add(_spacing);
    if (at.isAfter(now)) await Future<void>.delayed(at.difference(now));
  }

  static void _refused() {
    final cooldown = _cooldowns[_refusals.clamp(0, _cooldowns.length - 1)];
    _refusals++;
    final until = DateTime.now().add(cooldown);
    _coolUntil = until;
    if (until.isAfter(_next)) _next = until;
    logWarn('Google Translate refused a request (429); pausing ${cooldown.inSeconds} s');
  }

  Future<String> _ask(String chunk, String target, String source) async {
    final uri = Uri.https('translate.googleapis.com', '/translate_a/single',
        {'client': 'gtx', 'sl': source, 'tl': target, 'dt': 't', 'q': chunk});
    if (coolingDown) throw TranslationException.busy();
    try {
      await _turn();
      final response = await _client.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 429) {
        _refused();
        throw TranslationException.busy();
      }
      _refusals = 0;
      if (response.statusCode != 200) {
        throw TranslationException(
            tr('Translation service temporarily unavailable ({0})', [response.statusCode]));
      }
      return parseResponse(utf8.decode(response.bodyBytes));
    } on TranslationException {
      rethrow;
    } catch (_) {
      throw TranslationException(tr('Translation failed. Check your network or proxy.'));
    }
  }

  /// The translated text of the endpoint's `[[["译文","原文",…],…],…]` reply.
  static String parseResponse(String body) {
    try {
      final data = jsonDecode(body);
      if (data is List && data.isNotEmpty && data.first is List) {
        return [
          for (final segment in data.first as List)
            if (segment is List && segment.isNotEmpty && segment.first is String)
              segment.first as String
        ].join();
      }
    } on FormatException {
      // Falls through to the error below.
    }
    throw TranslationException(tr('Translation service returned unrecognized content'));
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
Future<String> translateForeignLines(
    Translator translator, String text, String target, bool Function(String line) isTarget) async {
  final lines = text.split('\n');
  final foreign = [
    for (final (i, line) in lines.indexed)
      if (line.trim().isNotEmpty && !isTarget(line)) i,
  ];
  if (foreign.isEmpty || foreign.length == lines.where((l) => l.trim().isNotEmpty).length) {
    return translator.translate(text, target);
  }
  final translated =
      (await translator.translate([for (final i in foreign) lines[i]].join('\n'), target))
          .split('\n');
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
