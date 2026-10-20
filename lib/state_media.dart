import 'blocked_groups.dart';

/// Channels of media that a government runs to speak for it, grouped by
/// country, for blocking all at once: propaganda outlets, not public
/// broadcasters with editorial independence (BBC, NHK, PBS and the like
/// stay). Matched against the channel's name only, so a video that merely
/// mentions CGTN stays: a name that is one of these or starts with one
/// followed by a space or sign ("RT Documentary", "CGTN Français") counts.
/// YouTube marks such channels on its site, but that mark does not reach
/// yt-dlp's listings, hence the list.
const stateMedia = <BlockedGroup>[
  BlockedGroup('中国官方媒体', ['CGTN', 'China Global Television', '中国国际电视台', 'CCTV', '央视', '中国中央电视台', '中央电视台', 'China Daily', '中国日报', 'Global Times', '环球时报', '環球時報', 'Xinhua', 'China Xinhua', '新华社', '新華社', '新华网', "People's Daily", 'People’s Daily', '人民日报', '人民日報', '人民网', 'China News Service', '中国新闻网', '中國新聞網', '中新网', '中新社', 'ChinaNews', '国际在线', 'China Plus', 'CRI', 'iPanda', '熊猫频道', '中国军网', '解放军报', '大公报', '大公報', '文汇报', '文匯報', '大公文汇', '大公文匯', 'Ta Kung Pao', 'Wen Wei Po']),
  BlockedGroup('俄罗斯官方媒体', ['RT', 'Russia Today', 'Sputnik', 'TASS', 'Ruptly', 'Россия 1', 'Россия 24', 'РИА Новости', 'RIA Novosti', 'Первый канал', 'Channel One Russia', 'НТВ', 'Вести', '今日俄罗斯', '今日俄羅斯', '卫星通讯社', '衛星通訊社']),
  BlockedGroup('伊朗官方媒体', ['Press TV', 'PressTV', 'IRIB', 'HispanTV', 'Al-Alam', 'Al Alam', 'IRNA', 'Tasnim', 'Mehr News']),
  BlockedGroup('朝鲜官方媒体', ['Uriminzokkiri', '우리민족끼리', 'KCTV', '조선중앙TV', '조선중앙텔레비죤', 'KCNA', '조선중앙통신', 'DPRK Today', '朝鲜中央电视台', '朝鮮中央電視台']),
  BlockedGroup('白俄罗斯官方媒体', ['Belarus 24', 'Беларусь 1', 'Беларусь 24', 'БелТА', 'BelTA', 'ОНТ']),
  BlockedGroup('委内瑞拉和古巴官方媒体', ['teleSUR', 'TeleSUR', 'VTV', 'Venezolana de Televisión', 'Cubadebate', 'Canal Caribe', 'Granma', 'Prensa Latina']),
  BlockedGroup('美国政府国际广播', ['VOA', 'Voice of America', '美国之音', '美國之音', 'Radio Free Asia', 'RFA', '自由亚洲电台', '自由亞洲電台', 'Radio Free Europe', 'RFE/RL', 'Radio Liberty', 'Радио Свобода', 'Current Time', 'Настоящее время', 'Alhurra']),
];

/// The groups left unticked until the user ticks them: YouTube labels
/// these government funded too, but whether they are propaganda is argued.
const stateMediaOffByDefault = ['美国政府国际广播'];

final _lowered = {for (final group in stateMedia) group.name: [for (final word in group.words) word.toLowerCase()]};
final _letter = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Whether a channel called [channel] is one of [stateMedia], other than
/// the groups the user [allowed].
bool isStateMediaChannel(String channel, [Set<String> allowed = const {}]) {
  final name = channel.trim().toLowerCase();
  if (name.isEmpty) return false;
  bool matches(String word) {
    if (!name.startsWith(word)) return false;
    if (name.length == word.length) return true;
    // "RT Documentary" but not "RTL"; a Chinese name may run on ("央视新闻").
    final last = word.codeUnitAt(word.length - 1);
    return last > 0x2E7F || !_letter.hasMatch(name[word.length]);
  }

  return _lowered.entries.any((group) => !allowed.contains(group.key) && group.value.any(matches));
}
