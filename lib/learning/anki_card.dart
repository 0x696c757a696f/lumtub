import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'vocabulary.dart';

/// The Anki note type vocabulary words become, the same whether they are
/// sent through AnkiConnect or saved as a package. The front shows the
/// word in its line; the back adds the reading, the meaning, the line's
/// translation and sound, and the moment of the video it came from.
abstract final class AnkiCard {
  static const modelName = 'Lumtub';
  static const deckName = 'Lumtub';

  /// Fixed ids, so a package imported twice updates the same note type
  /// and deck instead of adding copies.
  static const modelId = 1763900000101;
  static const deckId = 1763900000102;

  static const fields = [
    'Word',
    'Reading',
    'Meaning',
    'Sentence',
    'Translation',
    'Audio',
    'Picture',
    'Video',
    'Time',
    'Link',
    'Language',
    'Notes'
  ];

  static const cardName = 'Recognition';

  static const front = '''
<div class="lt lt-front" lang="{{Language}}">
  <div class="lt-head">
    <div class="lt-word">{{Word}}</div>
    <div class="lt-reading">{{Reading}}</div>
  </div>
  {{#Sentence}}<div class="lt-line">{{Sentence}}</div>{{/Sentence}}
</div>''';

  static const back = '''
<div class="lt lt-back" lang="{{Language}}">
  <div class="lt-head">
    <div class="lt-word">{{Word}}</div>
    <div class="lt-reading">{{Reading}}</div>
  </div>
  {{#Sentence}}<div class="lt-line">{{Sentence}}{{#Audio}}<span class="lt-play">{{Audio}}</span>{{/Audio}}</div>{{/Sentence}}
  {{^Sentence}}{{#Audio}}<div class="lt-line"><span class="lt-play">{{Audio}}</span></div>{{/Audio}}{{/Sentence}}
  {{#Translation}}<div class="lt-translation">{{Translation}}</div>{{/Translation}}
  <div id="answer" class="lt-answer">{{#Meaning}}<div class="lt-meaning">{{Meaning}}</div>{{/Meaning}}{{#Notes}}<div class="lt-notes">{{Notes}}</div>{{/Notes}}</div>
  {{#Link}}<a class="lt-source" href="{{Link}}">{{#Picture}}<span class="lt-picture">{{Picture}}</span>{{/Picture}}<span class="lt-video"><span class="lt-title">{{Video}}</span><span class="lt-time">▶&#xFE0E; {{Time}}</span></span></a>{{/Link}}
</div>''';

  /// The first line of [css]. While a note type's style starts with this
  /// line, Lumtub may bring it up to date; anyone who changes the style
  /// deletes the line and keeps their own.
  static const styleMarker =
      '/* Lumtub card style 1. Lumtub updates this style and the card templates while this line is here; delete it to keep your own changes. */';

  static const css = '''
$styleMarker
.card {
  --lt-page: #f6f6f4;
  --lt-panel: #ffffff;
  --lt-text: #1c1c1f;
  --lt-muted: #6b6b73;
  --lt-faint: #a3a3ab;
  --lt-line: #e3e3e0;
  --lt-accent: #4a47d6;
  --lt-mark: rgba(74, 71, 214, 0.16);
  margin: 0;
  padding: 0;
  background: var(--lt-page);
  color: var(--lt-text);
  font-family: system-ui, -apple-system, "Segoe UI", "Helvetica Neue", Arial, "PingFang SC", "Microsoft YaHei UI", sans-serif;
  font-size: 18px;
  line-height: 1.55;
  text-align: left;
}
.card.nightMode, .card.night_mode, .nightMode .card, .night_mode .card {
  --lt-page: #17171a;
  --lt-panel: #212125;
  --lt-text: #ececef;
  --lt-muted: #a2a2ab;
  --lt-faint: #6e6e77;
  --lt-line: #323238;
  --lt-accent: #a5a6ff;
  --lt-mark: rgba(165, 166, 255, 0.22);
  background: var(--lt-page);
  color: var(--lt-text);
}
.lt { max-width: 34rem; margin: 0 auto; padding: 36px 20px 28px; }
.lt:lang(ja) { font-family: "Hiragino Sans", "Hiragino Kaku Gothic ProN", "Yu Gothic UI", "Yu Gothic", Meiryo, "Noto Sans CJK JP", "Noto Sans JP", sans-serif; }
.lt:lang(zh) { font-family: "PingFang SC", "Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "Noto Sans SC", "Source Han Sans SC", sans-serif; }
.lt:lang(ko) { font-family: "Apple SD Gothic Neo", "Malgun Gothic", "Noto Sans CJK KR", "Noto Sans KR", sans-serif; }
.lt-head { text-align: center; }
.lt-word { font-size: 2.4em; font-weight: 600; line-height: 1.2; letter-spacing: 0.01em; overflow-wrap: anywhere; }
.lt-reading { min-height: 1.5em; margin-top: 6px; color: var(--lt-accent); font-size: 1em; letter-spacing: 0.04em; }
.lt-front .lt-reading { visibility: hidden; }
.lt-line { margin: 26px auto 0; text-align: center; font-size: 1.12em; line-height: 1.7; }
.lt-line b { font-weight: 600; color: var(--lt-accent); background: linear-gradient(transparent 62%, var(--lt-mark) 62%); }
.lt-translation { margin-top: 6px; text-align: center; color: var(--lt-muted); font-size: 0.92em; }
.lt-play { display: inline-block; margin-left: 8px; vertical-align: -0.35em; }
.lt-play .replay-button svg, .lt-play .soundLink svg { width: 28px; height: 28px; }
.lt-play .replay-button svg circle { fill: var(--lt-accent); stroke: none; }
.lt-play .replay-button svg path { fill: var(--lt-panel); stroke: none; }
.lt-answer:empty { display: none; }
.lt-answer { margin-top: 26px; padding: 16px 18px; background: var(--lt-panel); border: 1px solid var(--lt-line); border-radius: 12px; }
.lt-meaning { white-space: normal; }
.lt-notes { margin-top: 12px; padding-left: 12px; border-left: 3px solid var(--lt-accent); color: var(--lt-muted); font-size: 0.92em; }
.lt-meaning + .lt-notes { margin-top: 14px; }
.lt-source { display: flex; align-items: center; gap: 12px; margin-top: 14px; padding: 8px; border: 1px solid var(--lt-line); border-radius: 12px; color: inherit; text-decoration: none; }
.lt-source:hover { border-color: var(--lt-faint); }
.lt-picture img { display: block; width: 112px; height: 63px; object-fit: cover; border-radius: 7px; max-width: none; }
.lt-video { display: flex; flex-direction: column; min-width: 0; gap: 2px; padding: 2px 6px; }
.lt-title { font-size: 0.86em; line-height: 1.4; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
.lt-time { color: var(--lt-muted); font-size: 0.8em; font-variant-numeric: tabular-nums; }
.mobile .lt, .lt.mobile { padding: 24px 14px 20px; }
.mobile .lt-word { font-size: 2.1em; }
''';

  /// Stable for a word, so a word exported twice is the same note.
  static String guid(VocabularyWord word) =>
      'lumtub-${sha1.convert(utf8.encode(word.key)).toString().substring(0, 20)}';

  static String _html(String text) =>
      const HtmlEscape(HtmlEscapeMode.element).convert(text).replaceAll(RegExp(r'\r?\n'), '<br>');

  /// Languages written with spaces between words, where a word is marked
  /// only where it stands alone ("run", not the start of "running").
  static const _spaced = {
    'en',
    'fr',
    'de',
    'es',
    'it',
    'pt',
    'nl',
    'ru',
    'uk',
    'pl',
    'sv',
    'da',
    'no',
    'nb',
    'fi',
    'cs',
    'tr',
    'id',
    'vi',
    'la',
    'el',
    'ro',
    'hu'
  };

  /// [sentence] as HTML with each [word] in it bold.
  static String markedLine(String sentence, String word, String language) {
    if (word.trim().isEmpty) return _html(sentence);
    final escaped = RegExp.escape(word);
    final pattern = _spaced.contains(language)
        ? RegExp('(?<![\\p{L}\\p{M}])$escaped(?![\\p{L}\\p{M}])',
            caseSensitive: false, unicode: true)
        : RegExp(escaped, caseSensitive: false, unicode: true);
    final out = StringBuffer();
    var at = 0;
    for (final match in pattern.allMatches(sentence)) {
      out
        ..write(_html(sentence.substring(at, match.start)))
        ..write('<b>${_html(match[0]!)}</b>');
      at = match.end;
    }
    out.write(_html(sentence.substring(at)));
    return out.toString();
  }

  /// The note's fields for [word]; [audio] and [picture] are the media
  /// file names the note uses, when it has them.
  static Map<String, String> noteFields(VocabularyWord word,
          {String audio = '', String picture = ''}) =>
      {
        'Word': _html(word.word),
        'Reading': word.reading == word.word ? '' : _html(word.reading),
        'Meaning': _html(word.meaning),
        'Sentence':
            word.sentence.isEmpty ? '' : markedLine(word.sentence, word.word, word.language),
        'Translation': _html(word.translation),
        'Audio': audio.isEmpty ? '' : '[sound:$audio]',
        'Picture': picture.isEmpty ? '' : '<img src="${_attribute(picture)}">',
        'Video': word.videoId.isEmpty
            ? ''
            : _html(word.videoTitle.isEmpty ? 'YouTube' : word.videoTitle),
        'Time': word.videoId.isEmpty ? '' : clockOf(word.at),
        'Link': _attribute(word.link),
        'Language': _attribute(word.language),
        'Notes': '',
      };

  static String _attribute(String text) => const HtmlEscape(HtmlEscapeMode.attribute).convert(text);

  static List<String> tags(VocabularyWord word) =>
      ['lumtub', if (word.language.isNotEmpty) 'lumtub::${word.language}'];

  /// The media name of [word]'s line, or of its video's picture.
  static String soundName(VocabularyWord word) => '${guid(word)}.wav';
  static String pictureName(String videoId, {required bool webp}) =>
      'lumtub-$videoId.${webp ? 'webp' : 'jpg'}';
}
