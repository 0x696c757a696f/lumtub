/// A guess from the script alone at whether text is in a language already,
/// so 翻译 can skip it without asking a service. Latin-script languages
/// cannot be told apart this way and are never skipped, except English
/// text for English.
bool looksLike(String text, String target) {
  final letters = text.runes.where(_isLetter).toList();
  if (letters.length < 2) return false;
  int count(bool Function(int) test) => letters.where(test).length;
  final share = letters.length * 0.6;
  final han = count(_han);
  final kana = count((c) => (c >= 0x3040 && c <= 0x30FF) || (c >= 0x31F0 && c <= 0x31FF));
  final hangul = count((c) => (c >= 0xAC00 && c <= 0xD7AF) || (c >= 0x1100 && c <= 0x11FF) || (c >= 0x3130 && c <= 0x318F));
  switch (target) {
    case 'zh-CN':
    case 'zh-TW':
      if (han < share || kana > 0) return false;
      final simplified = text.runes.where(_simplifiedOnly.contains).length;
      final traditional = text.runes.where(_traditionalOnly.contains).length;
      return target == 'zh-CN' ? simplified >= traditional : traditional >= simplified && (traditional > 0 || simplified == 0);
    case 'ja':
      return kana > 0 && han + kana >= share;
    case 'ko':
      return hangul >= share;
    case 'ru':
      return count((c) => c >= 0x0400 && c <= 0x04FF) >= share;
    case 'ar':
      return count((c) => c >= 0x0600 && c <= 0x06FF) >= share;
    case 'th':
      return count((c) => c >= 0x0E00 && c <= 0x0E7F) >= share;
    case 'hi':
      return count((c) => c >= 0x0900 && c <= 0x097F) >= share;
    case 'en':
      if (count(_basicLatin) < share) return false;
      final words = RegExp(r"[A-Za-z']+").allMatches(text.toLowerCase()).map((m) => m[0]!).toList();
      if (words.length < 3) return false;
      return words.where(_englishWords.contains).length >= words.length * 0.2;
  }
  return false;
}

bool _isLetter(int c) {
  if (c < 0x80) return (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
  if (c >= 0x2000 && c <= 0x2BFF) return false; // punctuation, symbols, arrows
  if (c >= 0x3000 && c <= 0x303F) return false; // CJK punctuation
  if (c >= 0xFF00 && c <= 0xFF20) return false; // full-width punctuation and digits
  if (c >= 0x1F000) return false; // emoji
  return true;
}

bool _basicLatin(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

bool _han(int c) => (c >= 0x4E00 && c <= 0x9FFF) || (c >= 0x3400 && c <= 0x4DBF) || (c >= 0xF900 && c <= 0xFAFF);

/// Common characters written one way in simplified and another in
/// traditional Chinese.
final _simplifiedOnly = '这们来时会说为国后还与对过开关体学发点从个们么见长门问间听车东边头实现话让认没给经样张导书买卖钱电视频网层万东专业亿'.runes.toSet();
final _traditionalOnly = '這們來時會說為國後還與對過開關體學發點從個們麼見長門問間聽車東邊頭實現話讓認沒給經樣張導書買賣錢電視頻網層萬東專業億'.runes.toSet();

const _englishWords = {
  'the', 'a', 'an', 'and', 'or', 'but', 'is', 'are', 'was', 'were', 'be', 'been', 'to', 'of', 'in', 'on', 'at', 'for', 'with', 'this', 'that',
  'it', 'i', 'you', 'he', 'she', 'we', 'they', 'my', 'your', 'not', 'no', 'so', 'just', 'have', 'has', 'do', 'does', 'did', 'what', 'how',
  'can', 'will', 'would', 'if', 'all', 'from', 'like', 'me', 'his', 'her', 'their', 'there', 'about', 'one', 'more', 'video', 'when', 'love',
  "it's", "i'm", "don't", 'really', 'great', 'thanks', 'good', 'very', 'who', 'why', 'out', 'up', 'get', 'know', 'see', 'think',
};
