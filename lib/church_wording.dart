import 'dart:async';
import 'dart:convert';
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
/// looked at once, not on every frame. It also remembers Catholic channels
/// (in a file), so a Catholic creator's video that names nothing Catholic
/// is still theirs.
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
  /// channel and [description] (else the one it carries), else from its
  /// channel when that is known to be Catholic ([riteOfChannel]); null when
  /// it is not Catholic. What its own words say counts towards its channel.
  static ChurchRite? riteOfVideo(VideoItem item, {String? description, bool byChannel = true}) {
    final own = riteOf('${item.title}\n${item.channel}\n${description ?? item.description ?? ''}');
    _count(item.channelId, item.id, own);
    return own ?? (byChannel ? riteOfChannel(item.channelId) : null);
  }

  /// Channels whose page or name said they are Catholic, by id: the rite.
  static final _sure = <String, ChurchRite>{};
  /// Other channels' videos seen: [seen, Latin, Byzantine].
  static final _tallies = <String, List<int>>{};
  /// The videos counted since start, so one shown again is not counted
  /// again; what they counted as.
  static final _counted = <String, ChurchRite?>{};
  static const _channelsKept = 5000;
  static File? _file;
  static Timer? _save;

  /// Reads what was learned of channels before from [file], and keeps it
  /// there.
  static Future<void> configure(File file) async {
    _file = file;
    try {
      final saved = jsonDecode(await file.readAsString());
      if (saved is! Map) return;
      if (saved['sure'] case final Map<Object?, Object?> sure) {
        for (final MapEntry(:key, :value) in sure.entries) {
          if (key is String && value is int && value >= 0 && value < ChurchRite.values.length) _sure.putIfAbsent(key, () => ChurchRite.values[value]);
        }
      }
      if (saved['seen'] case final Map<Object?, Object?> seen) {
        for (final MapEntry(:key, :value) in seen.entries) {
          if (key is String && value is List && value.length == 3 && value.every((n) => n is int && n >= 0)) {
            _tallies.putIfAbsent(key, () => [for (final n in value) n as int]);
          }
        }
      }
    } catch (_) {}
  }

  /// The rite of the channel [id] when it is known to be Catholic: its page
  /// or name said so ([noteChannel]), or at least three of its videos seen
  /// said so and they make up a quarter of those seen.
  static ChurchRite? riteOfChannel(String? id) {
    if (id == null || id.isEmpty) return null;
    if (_sure[id] case final rite?) return rite;
    final tally = _tallies[id];
    if (tally == null) return null;
    final catholic = tally[1] + tally[2];
    if (catholic < 3 || catholic * 4 < tally[0]) return null;
    return tally[2] > tally[1] ? ChurchRite.byzantine : ChurchRite.latin;
  }

  /// Remembers that the channel [id] is Catholic, of [rite]: its name or
  /// its page said so.
  static void noteChannel(String? id, ChurchRite rite) {
    if (id == null || id.isEmpty || _sure[id] == rite) return;
    _sure.remove(id);
    _sure[id] = rite;
    while (_sure.length > _channelsKept) {
      _sure.remove(_sure.keys.first);
    }
    _saveSoon();
  }

  static void _count(String? channel, String video, ChurchRite? rite) {
    if (channel == null || channel.isEmpty || video.isEmpty) return;
    final key = '$channel\u0000$video';
    final before = _counted[key];
    final known = _counted.containsKey(key);
    if (known && (before != null || rite == null)) return;
    _counted[key] = rite;
    if (_counted.length > 20000) _counted.remove(_counted.keys.first);
    final tally = _tallies.remove(channel) ?? [0, 0, 0];
    _tallies[channel] = tally;
    if (!known) tally[0]++;
    if (rite != null) tally[rite == ChurchRite.byzantine ? 2 : 1]++;
    while (_tallies.length > _channelsKept) {
      _tallies.remove(_tallies.keys.first);
    }
    _saveSoon();
  }

  static void _saveSoon() {
    if (_file == null) return;
    _save?.cancel();
    _save = Timer(const Duration(seconds: 5), () {
      final file = _file;
      if (file == null) return;
      final json = jsonEncode({
        'sure': {for (final MapEntry(:key, :value) in _sure.entries) key: value.index},
        'seen': _tallies,
      });
      unawaited(file.writeAsString(json).then((_) {}, onError: (_) {}));
    });
  }

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
