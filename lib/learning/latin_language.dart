/// Tells which language in Latin letters subtitles are in, from their
/// common short words and letters. One line says little, so the guess
/// keeps a fading tally over the lines it has seen: a video's subtitles
/// settle on their language within a few lines.
class LatinLanguageGuess {
  static const _words = {
    'en': ['the', 'and', 'is', 'you', 'to', 'of', 'it', 'that', 'what', 'this', 'are', 'was', 'have', 'with', 'i', "i'm", "don't", 'we', 'they', 'not'],
    'es': ['el', 'la', 'que', 'de', 'y', 'los', 'las', 'es', 'por', 'una', 'con', 'no', 'pero', 'muy', 'yo', 'lo', 'para', 'del', 'está', 'qué', 'sé', 'nos', 'cuando', 'como', 'más', 'eso', 'esto', 'hay', 'te', 'mi'],
    'fr': ['le', 'la', 'les', 'et', 'est', 'je', 'vous', 'que', 'des', 'une', 'pas', 'ce', "c'est", 'dans', 'pour', 'qui', 'nous', 'il', 'du', 'avec', 'mais', 'on', 'tu', 'au', 'sur', 'ça', 'très', 'bien', 'fait', 'moi'],
    'de': ['der', 'die', 'und', 'ist', 'ich', 'nicht', 'das', 'ein', 'eine', 'zu', 'es', 'du', 'wir', 'sie', 'mit', 'auf', 'den', 'auch', 'aber', 'wie', 'habe', 'hat', 'mir', 'dich', 'mich', 'noch', 'schon', 'bitte', 'kann', 'einen'],
    'pt': ['o', 'não', 'é', 'um', 'uma', 'os', 'do', 'da', 'em', 'no', 'na', 'você', 'eu', 'mas', 'isso', 'está', 'muito', 'tem', 'ele', 'ela', 'também', 'então', 'aqui', 'mais', 'tudo', 'foi', 'vou', 'pra', 'meu', 'com'],
    'it': ['il', 'che', 'di', 'è', 'e', 'non', 'un', 'una', 'per', 'sono', 'mi', 'gli', 'della', 'ho', 'questo', 'ma', 'anche', 'come', 'cosa', 'perché', 'ci', 'siamo', 'già', 'più', 'quando', 'molto', 'così', 'sei', 'ti', 'tutto'],
  };

  static const _letters = {
    'es': 'ñ¿¡',
    'fr': 'çœêèàùâîôû',
    'de': 'ßäöü',
    'it': 'ìò',
    'pt': 'ãõ',
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
    final line = <String, double>{};
    for (final language in candidates) {
      final common = _words[language] ?? const <String>[];
      var score = words.where(common.contains).length.toDouble();
      for (final letter in (_letters[language] ?? '').split('')) {
        if (letter.isNotEmpty && lower.contains(letter)) score += 2;
      }
      line[language] = score;
    }
    // A line that clearly says another language, such as the first lines
    // of the next video, wins at once rather than after many lines.
    final ranked = line.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = ranked.first;
    final second = ranked.length > 1 ? ranked[1].value : 0.0;
    if (top.value >= 3 && top.value >= 2 * second && (_tally[top.key] ?? 0) < _tally.values.fold(0.0, (a, b) => a > b ? a : b)) {
      for (final key in _tally.keys.toList()) {
        if (key != top.key) _tally[key] = _tally[key]! * 0.2;
      }
    }
    for (final MapEntry(:key, :value) in line.entries) {
      if (value > 0) _tally[key] = (_tally[key] ?? 0) + value;
    }
    String? best;
    for (final language in candidates) {
      final score = _tally[language] ?? 0;
      if (score > 0 && (best == null || score > _tally[best]!)) best = language;
    }
    return best;
  }
}
