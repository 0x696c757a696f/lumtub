import 'blocked_channels.dart';
import 'l10n/l10n.dart';
import 'models.dart';

/// Names of groups the user does not want recommended: movements that
/// governments or the mainstream churches have called heretical or
/// destructive, with their founders, aliases and media, in simplified and
/// traditional Chinese and English. A video whose channel is one of them
/// (by name, @handle or id) is left out of the home feed, explore, related
/// videos and search results while AppPreferences.blockGroups is on. Titles
/// and descriptions are never matched: other channels' reports about the
/// group, and searches for its names, stay. Only a search for a channel's
/// exact name, letter case included, finds that channel.
const blockedGroups = <BlockedGroup>[
  BlockedGroup('法轮功', ['法轮功', '法輪功', '法轮大法', '法輪大法', '李洪志', '明慧网', '明慧網', '神韵艺术团', '神韻藝術團', '大纪元', '大紀元', 'The Epoch Times', '新唐人', 'Falun Gong', 'Falun Dafa', 'Li Hongzhi', 'Minghui', 'Shen Yun', 'Epoch Times', 'NTD Television']),
  // Matched by channel only (blocked_channels.dart): their names are
  // ordinary words that would hide unrelated videos if titles counted.
  BlockedGroup('法轮功相关自媒体', []),
  BlockedGroup('法轮功相关（待核实）', []),
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
  const BlockedGroup(this.name, this.words, {this.onByDefault = true, this.exact = const [], this.note});
  /// Saved in the preferences when the user ticks or unticks it.
  final String name;
  String get label => tr(name);
  final List<String> words;
  /// Channel names matched only in full: abbreviations such as RT, AA or
  /// NTV would otherwise catch unrelated channels that start with them.
  final List<String> exact;
  /// How the group's members relate to a government, shown in settings.
  final String? note;
  /// Groups that are not proven to belong start unticked.
  final bool onByDefault;

  /// Everything matched for this group, each of which can be unticked:
  /// its [words] as channel names, then the channels of blocked_channels.dart.
  List<BlockEntry> entries() {
    final channels = blockedChannels[name];
    return [
      for (final word in words) BlockEntry(name, BlockKind.channel, [word]),
      for (final word in exact) BlockEntry(name, BlockKind.exact, [word]),
      if (channels != null) ...[
        for (final forms in channels.names) BlockEntry(name, BlockKind.channel, forms),
        for (final handle in channels.handles) BlockEntry(name, BlockKind.handle, [handle]),
        for (final id in channels.ids) BlockEntry(name, BlockKind.id, [id]),
      ],
    ];
  }
}

/// How an entry of a block list is matched.
enum BlockKind {
  /// A channel's name, or the start of it ("RT Documentary" for RT).
  channel('频道名'),
  /// A channel's whole name and nothing longer.
  exact('完整频道名'),
  handle('@账号'),
  id('频道 ID');

  const BlockKind(this._label);
  final String _label;
  String get label => tr(_label);
}

/// One name, handle or id of a block list; [forms] are its spellings, the
/// first shown.
class BlockEntry {
  const BlockEntry(this.group, this.kind, this.forms);
  final String group;
  final BlockKind kind;
  final List<String> forms;
  String get label => forms.first;
  /// Saved in AppPreferences.allowedEntries when the user unticks it.
  String get key => '$group/${kind.name}/${forms.first}';
}

/// Tests videos and channels against block lists, leaving out the groups
/// and entries the user unticked. Built once per preferences.
class BlockMatcher {
  BlockMatcher(List<BlockedGroup> groups, {Set<String> allowedGroups = const {}, Set<String> allowedEntries = const {}}) {
    for (final group in groups) {
      if (allowedGroups.contains(group.name)) continue;
      for (final entry in group.entries()) {
        if (allowedEntries.contains(entry.key)) continue;
        final forms = [for (final form in entry.forms) entry.kind == BlockKind.id ? form : form.toLowerCase()];
        switch (entry.kind) {
          case BlockKind.channel:
            _channels.addAll(forms);
          case BlockKind.exact:
            _exact.addAll(forms);
          case BlockKind.handle:
            _handles.addAll(forms);
          case BlockKind.id:
            _ids.addAll(forms);
        }
      }
    }
  }

  final _channels = <String>[];
  final _exact = <String>{};
  final _handles = <String>{};
  final _ids = <String>{};

  bool get isEmpty => _channels.isEmpty && _exact.isEmpty && _handles.isEmpty && _ids.isEmpty;

  /// Whether a channel called [name], with [id] or [handle] if known, is
  /// listed.
  bool channel(String name, {String? id, String? handle}) {
    if (id != null && _ids.contains(id)) return true;
    if (handle != null && handle.isNotEmpty && _handles.contains((handle.startsWith('@') ? handle : '@$handle').toLowerCase())) return true;
    final lower = name.trim().toLowerCase();
    return lower.isNotEmpty && (_exact.contains(lower) || _channels.any((word) => channelNameStartsWith(lower, word)));
  }
}

final _letter = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Whether channel [name] is [word] or starts with it as a whole word:
/// "RT Documentary" for RT but not "RTL"; a Chinese name may run on
/// ("央视新闻"). Both lower case.
bool channelNameStartsWith(String name, String word) {
  if (!name.startsWith(word)) return false;
  if (name.length == word.length) return true;
  final last = word.codeUnitAt(word.length - 1);
  return last > 0x2E7F || !_letter.hasMatch(name[word.length]);
}

final _all = BlockMatcher(blockedGroups.where((g) => g.onByDefault).toList());

/// Whether [item]'s channel is one of [blockedGroups]' channels. Its title
/// and description do not count.
bool namesBlockedGroup(VideoItem item) => _all.channel(item.channel, id: item.channelId);

/// Whether [query] is [name] exactly, letter case included, apart from the
/// spaces around it: one character more or less does not count.
bool isExactName(String name, String? query) {
  final typed = query?.trim() ?? '';
  return typed.isNotEmpty && typed == name.trim();
}
