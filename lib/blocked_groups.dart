import 'l10n/l10n.dart';
import 'models.dart';

/// Names of groups the user does not want recommended: movements that
/// governments or the mainstream churches have called heretical or
/// destructive, with their founders, aliases and media, in simplified and
/// traditional Chinese and English. A video whose title or channel names
/// one is left out of the home feed, explore, related videos, search
/// results and suggestions, reports about the group included, while
/// AppPreferences.blockGroups is on. Only a search for a channel's exact
/// name finds that channel.
const blockedGroups = <BlockedGroup>[
  BlockedGroup('法轮功', ['法轮功', '法輪功', '法轮大法', '法輪大法', '李洪志', '明慧网', '明慧網', '神韵艺术团', '神韻藝術團', '大纪元', '大紀元', '新唐人', 'Falun Gong', 'Falun Dafa', 'Li Hongzhi', 'Minghui', 'Shen Yun', 'Epoch Times', 'NTD Television']),
  BlockedGroup('全能神', ['全能神', '东方闪电', '東方閃電', '实际神', '實際神', 'Church of Almighty God', 'Eastern Lightning']),
  BlockedGroup('新天地', ['新天地', '李万熙', '李萬熙', 'Shincheonji', 'Lee Man-hee']),
  BlockedGroup('统一教', ['统一教', '統一教', '文鲜明', '文鮮明', '家庭联合', '家庭聯合', '世界和平统一家庭', '世界和平統一家庭', 'Unification Church', 'Sun Myung Moon', 'Moonies', 'Family Federation for World Peace']),
  BlockedGroup('母亲上帝', ['母亲上帝', '母親上帝', '安商洪', '张吉子', '張吉子', '世界福音宣教协会', '世界福音宣教協會', 'World Mission Society', 'Ahnsahnghong', 'Zahng Gil-jah', 'God the Mother']),
  BlockedGroup('万民中央教会', ['万民中央教会', '萬民中央教會', '李载禄', '李載祿', 'Manmin Central Church', 'Jaerock Lee']),
  BlockedGroup('马可楼', ['马可楼', '馬可樓', '世界福音化传道协会', '世界福音化傳道協會', "Mark's Attic", 'Mark’s Attic']),
  BlockedGroup('救赎派', ['救赎派', '救贖派', '朴玉洙', '樸玉洙', '基督教福音浸信会', '基督教福音浸信會', 'Good News Mission', 'Ock Soo Park', 'Guwonpa']),
  BlockedGroup('呼喊派', ['呼喊派', '常受教']),
  BlockedGroup('门徒会', ['门徒会', '門徒會', '三赎基督', '三贖基督', '二两粮', '二兩糧']),
  BlockedGroup('被立王', ['被立王']),
  BlockedGroup('主神教', ['主神教']),
  BlockedGroup('三班仆人派', ['三班仆人', '三班僕人']),
  BlockedGroup('灵灵教', ['灵灵教', '靈靈教']),
  BlockedGroup('华南教会', ['华南教会', '華南教會']),
  BlockedGroup('圆顿法门', ['圆顿法门', '圓頓法門']),
  BlockedGroup('幸福科学', ['幸福科学', '幸福科學', '大川隆法', 'Happy Science', 'Ryuho Okawa']),
  BlockedGroup('耶和华见证人', ['耶和华见证人', '耶和華見證人', '守望台', '守望臺', "Jehovah's Witness", 'Jehovah’s Witness', 'JW.org', 'JW Broadcasting']),
  BlockedGroup('科学教', ['科学神教', '科學神教', '山达基', '山達基', '戴尼提', 'Scientology', 'Dianetics', 'L. Ron Hubbard']),
  BlockedGroup('人民圣殿教', ['人民圣殿', '人民聖殿', '琼斯镇', '瓊斯鎮', 'Peoples Temple', "People's Temple", 'Jonestown', 'Jim Jones', 'People’s Temple']),
  BlockedGroup('大卫教派', ['大卫教派', '大衛教派', '韦科惨案', '韋科慘案', 'Branch Davidian', 'Waco siege', 'David Koresh']),
  BlockedGroup('天堂之门', ['天堂之门', '天堂之門', "Heaven's Gate", 'Heavens Gate', 'Marshall Applewhite', 'Heaven’s Gate']),
  BlockedGroup('太阳圣殿教', ['太阳圣殿', '太陽聖殿', 'Solar Temple']),
  BlockedGroup('曼森家族', ['曼森家族', 'Manson Family', 'Charles Manson']),
  BlockedGroup('天父的儿女', ['天父的儿女', '天父的兒女', 'Family International', 'David Berg']),
  BlockedGroup('雷尔运动', ['雷尔运动', '雷爾運動', 'Raelian', 'Raëlian', 'Rael movement']),
  BlockedGroup('FLDS', ['FLDS', '基本教义派耶稣基督', '基本教義派耶穌基督', 'Warren Jeffs']),
  BlockedGroup('NXIVM', ['NXIVM', 'Keith Raniere']),
  BlockedGroup('奥姆真理教', ['奥姆真理教', '奧姆真理教', 'Aum Shinrikyo', '麻原彰晃']),
];

/// One group: the name shown in settings, and the words that name it.
class BlockedGroup {
  const BlockedGroup(this.name, this.words);
  /// Saved in AppPreferences.allowedGroups when the user unticks it.
  final String name;
  String get label => tr(name);
  final List<String> words;
}

final _lowered = {for (final group in blockedGroups) group.name: [for (final word in group.words) word.toLowerCase()]};

/// Whether [text] names one of [blockedGroups], other than those the user
/// [allowed] by name.
bool textNamesBlockedGroup(String text, [Set<String> allowed = const {}]) {
  final lower = text.toLowerCase();
  return _lowered.entries.any((group) => !allowed.contains(group.key) && group.value.any(lower.contains));
}

/// Whether [item]'s title or channel names one of [blockedGroups], other
/// than those the user [allowed].
bool namesBlockedGroup(VideoItem item, [Set<String> allowed = const {}]) => textNamesBlockedGroup('${item.title}\n${item.channel}', allowed);

/// Whether [query] is [name] exactly, apart from letter case and the spaces
/// around it: one character more or less does not count.
bool isExactName(String name, String? query) {
  final typed = query?.trim().toLowerCase() ?? '';
  return typed.isNotEmpty && typed == name.trim().toLowerCase();
}
