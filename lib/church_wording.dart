import 'faith_traditions.dart';
import 'models.dart';
import 'native_core.dart';

/// Chinese translations of Catholic videos, channels, playlists and posts
/// in the Catholic Church's own wording: the names and terms translation
/// services write the Protestant way (上帝, 圣灵, 彼得, 摩西) as the Church
/// writes them (天主, 圣神, 伯多禄, 梅瑟), from whatever language they were
/// translated. The words themselves are swapped by lumtub_core
/// (church_words.rs); this decides what is Catholic, by the words
/// [FaithTradition.catholic] knows, and remembers recent answers so a
/// list's titles are looked at once, not on every frame.
///
/// Anything that goes wrong leaves the translation as the service gave it.
abstract final class ChurchWording {
  /// Recent answers kept, least recently used dropped first (a Dart map
  /// keeps insertion order).
  static const _remembered = 2048;
  static final _verdicts = <String, bool>{};
  static final _converted = <String, String>{};

  /// Whether [about] (a title, channel name, description, post) speaks of
  /// the Catholic Church at least as much as of any other tradition.
  static bool isCatholicText(String about) {
    if (about.trim().isEmpty) return false;
    final known = _verdicts.remove(about);
    final verdict = known ?? FaithTradition.catholic.admitsText(normalizeFaithText(about), strict: true);
    _remember(_verdicts, about, verdict);
    return verdict;
  }

  /// Whether [item] is a Catholic video (or playlist, or episode), from its
  /// title, channel and [description] (else the one it carries).
  static bool isCatholicVideo(VideoItem item, {String? description}) =>
      isCatholicText('${item.title}\n${item.channel}\n${description ?? item.description ?? ''}');

  /// [translated] in Catholic wording when [catholic] and [target] is
  /// Chinese; else as it is.
  static String apply(String translated, String target, {required bool catholic}) {
    if (!catholic || translated.isEmpty) return translated;
    final traditional = switch (target.toLowerCase().replaceAll('_', '-')) {
      'zh-cn' || 'zh-hans' || 'zh-sg' || 'zh' => false,
      'zh-tw' || 'zh-hant' || 'zh-hk' || 'zh-mo' => true,
      _ => null,
    };
    if (traditional == null) return translated;
    final key = '${traditional ? 1 : 0}$translated';
    final known = _converted.remove(key);
    if (known != null) {
      _converted[key] = known;
      return known;
    }
    String out;
    try {
      out = NativeCore.instance?.churchWords(translated, traditional: traditional) ?? translated;
    } catch (_) {
      out = translated;
    }
    // Subtitle files are long and asked for once; only short texts, which
    // lists show again and again, are kept.
    if (translated.length <= 2000) _remember(_converted, key, out);
    return out;
  }

  static void _remember<T>(Map<String, T> map, String key, T value) {
    map[key] = value;
    if (map.length > _remembered) map.remove(map.keys.first);
  }
}
