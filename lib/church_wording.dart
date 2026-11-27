import 'dart:io';

import 'faith_traditions.dart';
import 'l10n/l10n.dart';
import 'models.dart';
import 'native_core.dart';

/// The rite of something Catholic, whose Chinese words differ in places:
/// the Byzantine (Eastern Catholic) rite keeps 神圣礼仪, 傅油 and 大斋期
/// where the Latin rite says 弥撒, 坚振 and 四旬期.
enum ChurchRite { latin, byzantine }

/// Chinese translations of Catholic videos, channels, playlists and posts
/// in the Catholic Church's own wording: the names and terms translation
/// services write the Protestant way (上帝, 圣灵, 彼得, 摩西) as the Church
/// writes them (天主, 圣神, 伯多禄, 梅瑟), from whatever language they were
/// translated, in simplified Chinese or as Taiwan or Hong Kong write it.
/// The words themselves are swapped by lumtub_core (church_words.rs), which
/// also reads the original where there is one: 圣父 becomes 教宗 only when
/// the original said Santo Padre. This decides what is Catholic, by the
/// words [FaithTradition.catholic] knows (Eastern Catholic included,
/// Orthodox not), and remembers recent answers so a list's titles are
/// looked at once, not on every frame.
///
/// Anything that goes wrong leaves the translation as the service gave it.
abstract final class ChurchWording {
  /// Recent answers kept, least recently used dropped first (a Dart map
  /// keeps insertion order).
  static const _remembered = 2048;
  static final _rites = <String, ChurchRite?>{};
  static final _converted = <String, String>{};

  /// Whether Traditional Chinese is written the Hong Kong way: the
  /// interface or the system is in Hong Kong or Macau Chinese.
  static bool Function() hongKong = () => currentLanguage.tag == 'zh-HK' || RegExp(r'^zh.*[-_](HK|MO)\b').hasMatch(Platform.localeName);

  /// The rite [about] (a title, channel name, description, post) speaks of,
  /// when it speaks of the Catholic Church at least as much as of any other
  /// tradition; null otherwise.
  static ChurchRite? riteOf(String about) {
    if (about.trim().isEmpty) return null;
    if (_rites.containsKey(about)) {
      final known = _rites.remove(about);
      _rites[about] = known;
      return known;
    }
    final text = normalizeFaithText(about);
    final rite = FaithTradition.easternCatholic.admitsText(text, strict: true)
        ? ChurchRite.byzantine
        : FaithTradition.catholic.admitsText(text, strict: true)
            ? ChurchRite.latin
            : null;
    _remember(_rites, about, rite);
    return rite;
  }

  /// Whether [about] speaks of the Catholic Church ([riteOf]).
  static bool isCatholicText(String about) => riteOf(about) != null;

  /// The rite of [item], a video (or playlist, or episode), from its title,
  /// channel and [description] (else the one it carries); null when it is
  /// not Catholic.
  static ChurchRite? riteOfVideo(VideoItem item, {String? description}) =>
      riteOf('${item.title}\n${item.channel}\n${description ?? item.description ?? ''}');

  static bool isCatholicVideo(VideoItem item, {String? description}) => riteOfVideo(item, description: description) != null;

  /// lumtub_core's number for [target]'s Chinese and [rite]; null when
  /// [target] is not Chinese.
  static int? variantOf(String target, ChurchRite rite) {
    final region = switch (target.toLowerCase().replaceAll('_', '-')) {
      'zh-cn' || 'zh-hans' || 'zh-sg' || 'zh' => 0,
      'zh-hk' || 'zh-mo' => 2,
      'zh-tw' || 'zh-hant' => hongKong() ? 2 : 1,
      _ => null,
    };
    if (region == null) return null;
    return region + (rite == ChurchRite.byzantine ? 4 : 0);
  }

  /// [translated] (of [original], when known) in Catholic wording when
  /// [rite] is set and [target] is Chinese; else as it is.
  static String apply(String translated, String target, {required ChurchRite? rite, String original = ''}) {
    if (rite == null || translated.isEmpty) return translated;
    final int? variant;
    try {
      variant = variantOf(target, rite);
    } catch (_) {
      return translated;
    }
    if (variant == null) return translated;
    final key = '$variant\u0000$original\u0000$translated';
    final known = _converted.remove(key);
    if (known != null) {
      _converted[key] = known;
      return known;
    }
    String out;
    try {
      out = NativeCore.instance?.churchWords(translated, variant: variant, original: original) ?? translated;
    } catch (_) {
      out = translated;
    }
    // Long texts are asked for once; only short ones, which lists show
    // again and again, are kept.
    if (key.length <= 2000) _remember(_converted, key, out);
    return out;
  }

  static void _remember<T>(Map<String, T> map, String key, T value) {
    map[key] = value;
    if (map.length > _remembered) map.remove(map.keys.first);
  }
}
