/// A word of a subtitle line with its reading, or the text between
/// words ([isWord] false).
class WordToken {
  const WordToken(this.text, this.reading, {required this.isWord, this.lookup, this.language});
  final String text;

  /// Pinyin for Chinese; null where nothing goes above the word.
  final String? reading;
  final bool isWord;

  /// The form to look up, when it differs from [text], such as lower case.
  final String? lookup;

  /// The dictionary's language, when the text alone does not tell it.
  final String? language;

  String get key => lookup ?? text;
}
