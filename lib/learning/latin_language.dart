/// Tells which language in Latin letters subtitles are in, from their
/// common short words and letters. One line says little, so the guess
/// keeps a fading tally over the lines it has seen: a video's subtitles
/// settle on their language within a few lines.
class LatinLanguageGuess {
  static const _words = {
    'en': ['the', 'and', 'is', 'you', 'to', 'of', 'it', 'that', 'what', 'this', 'are', 'was', 'have', 'with', 'i', "i'm", "don't", 'we', 'they', 'not'],
    'es': ['el', 'la', 'que', 'de', 'y', 'los', 'las', 'es', 'por', 'una', 'con', 'no', 'pero', 'muy', 'yo', 'lo', 'para', 'del', 'está', 'qué'],
    'fr': ['le', 'la', 'les', 'et', 'est', 'je', 'vous', 'que', 'des', 'une', 'pas', 'ce', "c'est", 'dans', 'pour', 'qui', 'nous', 'il', 'du', 'avec'],
    'de': ['der', 'die', 'und', 'ist', 'ich', 'nicht', 'das', 'ein', 'eine', 'zu', 'es', 'du', 'wir', 'sie', 'mit', 'auf', 'den', 'auch', 'aber', 'wie'],
    'it': ['il', 'che', 'di', 'è', 'e', 'non', 'un', 'una', 'per', 'sono', 'mi', 'gli', 'della', 'ho', 'questo', 'ma', 'anche', 'come', 'cosa', 'perché'],
  };

  static const _letters = {
    'es': 'ñ¿¡',
    'fr': 'çœêèàùâîôû',
    'de': 'ßäöü',
    'it': 'ìò',
  };

  final _tally = <String, double>{};

  /// The language of [text] among [languages], or null when it shows
  /// none of them yet.
  String? guess(String text, Iterable<String> languages) {
    final candidates = languages.toList();
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.single;
    for (final key in _tally.keys.toList()) {
      _tally[key] = _tally[key]! * 0.9;
    }
    final lower = text.toLowerCase();
    final words = RegExp(r"[\p{L}']+", unicode: true).allMatches(lower.replaceAll('’', "'")).map((m) => m[0]!).toList();
    for (final language in candidates) {
      final common = _words[language] ?? const <String>[];
      var score = words.where(common.contains).length.toDouble();
      for (final letter in (_letters[language] ?? '').split('')) {
        if (letter.isNotEmpty && lower.contains(letter)) score += 2;
      }
      if (score > 0) _tally[language] = (_tally[language] ?? 0) + score;
    }
    String? best;
    for (final language in candidates) {
      final score = _tally[language] ?? 0;
      if (score > 0 && (best == null || score > _tally[best]!)) best = language;
    }
    return best;
  }
}
