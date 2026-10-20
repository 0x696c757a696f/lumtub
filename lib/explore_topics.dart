import 'package:flutter/widgets.dart' show IconData;
import 'package:flutter/material.dart' show Icons;

import 'faith_topics.dart';
import 'l10n/l10n.dart';
import 'search_options.dart';
import 'video_repository.dart';

/// The parts of the explore page: videos, live streams, and the four tabs
/// of 宗教与信仰.
enum ExploreSection {
  popular('视频'),
  live('直播', isLive: true),
  faith('宗教传统', isFaith: true),
  faithStudy('宗教学术', isFaith: true),
  faithArts('文化艺术', isFaith: true),
  faithLive('宗教直播', isLive: true, isFaith: true);

  const ExploreSection(this._label, {this.isLive = false, this.isFaith = false});
  final String _label;
  String get label => tr(_label);
  /// Shows streams rather than videos.
  final bool isLive;
  /// One of 宗教与信仰's tabs.
  final bool isFaith;

  static const faithTabs = [faith, faithStudy, faithArts, faithLive];
}

/// A sub-category of a zone: its name, the words searched for, and its own
/// sub-categories, if it is split further.
class ExploreSub {
  const ExploreSub(this._label, this.query, {this.subs = const []});
  final String _label;
  String get label => tr(_label);
  final String query;
  final List<ExploreSub> subs;
}

/// One explore zone, as Bilibili's 分区: what it is called, the search
/// behind it and its sub-categories.
class ExploreTopic {
  const ExploreTopic(this._label, this.icon, this.query, {this.subs = const [], this.custom = false, this.opens, this.mix = false, this.personal = false});
  final String _label;
  /// The name shown; a user's own is shown as typed.
  String get label => custom ? _label : tr(_label);
  final IconData icon;
  final String query;
  final List<ExploreSub> subs;
  /// Added by the user; it can be removed.
  final bool custom;
  /// A zone that leads to another part of the page, as 宗教信仰 leads to
  /// the tabs of 宗教与信仰, rather than searching itself.
  final ExploreSection? opens;
  /// 推荐 and 全部: a mix of the other zones rather than a search of its
  /// own; [personal] (推荐) adds the history's interests.
  final bool mix;
  final bool personal;

  /// Names the zone in the saved order and hidden lists; custom zones as
  /// `custom:<label>`.
  String get key => custom ? 'custom:$_label' : _label;
}

/// A category the user added: its name, the words searched for, and which
/// half of the explore page it belongs to.
class CustomTopic {
  const CustomTopic(this.label, this.query, this.section);
  final String label;
  final String query;
  final ExploreSection section;

  ExploreTopic get topic => ExploreTopic(label, Icons.bookmark_rounded, query, custom: true);

  Map<String, dynamic> toJson() => {'label': label, 'query': query, 'section': section.name};

  static CustomTopic? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final label = raw['label']?.toString().trim() ?? '';
    final query = raw['query']?.toString().trim() ?? '';
    if (label.isEmpty || query.isEmpty) return null;
    final section = ExploreSection.values.where((s) => s.name == raw['section']).firstOrNull ?? ExploreSection.popular;
    return CustomTopic(label, query, section);
  }
}

/// Video zones, each with about 8-14 sub-categories of one level, the most
/// watched first. Searches mix Chinese and English words so that YouTube's
/// videos from other countries come up too.
const popularTopics = <ExploreTopic>[
  ExploreTopic('推荐', Icons.recommend_rounded, '', mix: true, personal: true),
  ExploreTopic('全部', Icons.apps_rounded, '', mix: true),
  ExploreTopic('知识教育', Icons.school_rounded, '知识 科普', subs: [
    ExploreSub('科普', '科普'),
    ExploreSub('历史', '历史 纪录片'),
    ExploreSub('大学课程', '大学 公开课 lecture'),
    ExploreSub('语言学习', '语言学习 英语 日语'),
    ExploreSub('数学', '数学 讲解'),
    ExploreSub('哲学', '哲学 philosophy'),
    ExploreSub('地理', '地理 geography explained'),
    ExploreSub('学习方法', '学习方法 study tips'),
    ExploreSub('职场技能', '职场技能 career skills'),
    ExploreSub('儿童教育', '儿童教育 kids learning'),
  ]),
  ExploreTopic('科技数码', Icons.memory_rounded, '科技 数码 评测', subs: [
    ExploreSub('数码评测', '数码 开箱 评测'),
    ExploreSub('手机', '手机 评测'),
    ExploreSub('电脑硬件', '电脑硬件 显卡 CPU'),
    ExploreSub('笔记本平板', '笔记本 平板 laptop tablet review'),
    ExploreSub('耳机音响', '耳机 音响 headphones review'),
    ExploreSub('智能家居', '智能家居 smart home'),
    ExploreSub('科技资讯', '科技新闻 tech news'),
    ExploreSub('新品发布', '新品发布会 keynote'),
    ExploreSub('操作系统', 'Windows Linux macOS 操作系统'),
    ExploreSub('网络安全', '网络安全 cybersecurity'),
  ]),
  ExploreTopic('人工智能', Icons.auto_awesome_rounded, 'AI 人工智能', subs: [
    ExploreSub('AI 资讯', 'AI 新闻 AI news'),
    ExploreSub('AI 模型', 'AI 大模型 LLM'),
    ExploreSub('AI 工具', 'AI 工具 教程'),
    ExploreSub('AI 编程', 'AI 编程 AI coding Cursor'),
    ExploreSub('AI 绘画视频', 'AI 绘画 AI video generation'),
    ExploreSub('机器学习', '机器学习 深度学习 machine learning'),
    ExploreSub('论文解读', 'AI 论文解读 paper explained'),
    ExploreSub('机器人', '机器人 robotics'),
    ExploreSub('自动驾驶', '自动驾驶 autonomous driving'),
  ]),
  ExploreTopic('编程开发', Icons.code_rounded, '编程 教程', subs: [
    ExploreSub('编程入门', '编程入门 教程 beginner'),
    ExploreSub('Python', 'Python 教程'),
    ExploreSub('前端开发', 'JavaScript 前端 frontend'),
    ExploreSub('后端开发', '后端 backend Java Go'),
    ExploreSub('Rust', 'Rust 编程'),
    ExploreSub('C / C++', 'C++ 编程 教程'),
    ExploreSub('移动开发', 'Android iOS Flutter 开发'),
    ExploreSub('算法', '算法 数据结构 LeetCode'),
    ExploreSub('云与运维', '云计算 DevOps Docker'),
    ExploreSub('开源项目', '开源项目 GitHub'),
    ExploreSub('软件开发', '软件开发 software engineering'),
  ]),
  ExploreTopic('游戏', Icons.sports_esports_rounded, '游戏', subs: [
    ExploreSub('游戏实况', '游戏实况'),
    ExploreSub('游戏资讯', '游戏新闻 game news'),
    ExploreSub('评测', '游戏评测'),
    ExploreSub('攻略', '游戏攻略'),
    ExploreSub('独立游戏', '独立游戏 indie game'),
    ExploreSub('手游', '手游 mobile game'),
    ExploreSub('主机游戏', '主机游戏 PS5 Switch'),
    ExploreSub('我的世界', '我的世界 Minecraft'),
    ExploreSub('电竞', '电竞 esports'),
    ExploreSub('速通', '速通 speedrun'),
  ]),
  ExploreTopic('音乐舞蹈', Icons.music_note_rounded, '音乐', subs: [
    ExploreSub('MV', 'MV 官方'),
    ExploreSub('现场演出', '现场 live concert'),
    ExploreSub('华语流行', '华语流行 C-pop'),
    ExploreSub('欧美流行', '欧美流行 pop music'),
    ExploreSub('日韩音乐', 'J-pop K-pop 日韩'),
    ExploreSub('摇滚金属', '摇滚 rock metal'),
    ExploreSub('说唱', '说唱 hip hop rap'),
    ExploreSub('爵士乐', 'jazz 爵士乐'),
    ExploreSub('电子音乐', '电子音乐 EDM'),
    ExploreSub('古典音乐', '古典音乐 classical music'),
    ExploreSub('乐器', '乐器 演奏'),
    ExploreSub('翻唱', '翻唱 cover'),
    ExploreSub('舞蹈', '舞蹈 dance'),
  ]),
  ExploreTopic('影视动漫', Icons.movie_rounded, '电影 动画', subs: [
    ExploreSub('电影', '电影 movie'),
    ExploreSub('电影解说', '电影解说 movie recap'),
    ExploreSub('电视剧', '电视剧'),
    ExploreSub('美剧', '美剧 TV series'),
    ExploreSub('韩剧日剧', '韩剧 日剧'),
    ExploreSub('动画', '动画 动漫 anime'),
    ExploreSub('国漫', '国漫 国产动画'),
    ExploreSub('漫画', '漫画 manga'),
    ExploreSub('影评', '影评'),
    ExploreSub('预告片', '预告片 trailer'),
    ExploreSub('幕后花絮', '幕后花絮 behind the scenes'),
  ]),
  ExploreTopic('新闻时事', Icons.newspaper_rounded, '新闻', subs: [
    ExploreSub('国际新闻', '国际新闻'),
    ExploreSub('社会热点', '社会热点'),
    ExploreSub('时事评论', '时事评论'),
    ExploreSub('中国新闻', '中国新闻'),
    ExploreSub('港台新闻', '香港 台湾 新闻'),
    ExploreSub('政治', '政治 politics'),
    ExploreSub('战争与冲突', '战争 冲突 conflict news'),
    ExploreSub('调查报道', '调查报道 investigative journalism'),
    ExploreSub('新闻纪录', '新闻纪录 news documentary'),
  ]),
  ExploreTopic('播客访谈', Icons.podcasts_rounded, '播客 访谈', subs: [
    ExploreSub('深度对谈', '深度对谈 podcast'),
    ExploreSub('人物采访', '人物专访 interview'),
    ExploreSub('脱口秀', '脱口秀 talk show'),
    ExploreSub('圆桌讨论', '圆桌 讨论 roundtable'),
    ExploreSub('读书书评', '读书 书评 book review'),
    ExploreSub('商业播客', '商业 播客 business podcast'),
    ExploreSub('科技播客', '科技 播客 tech podcast'),
    ExploreSub('历史人文', '历史 人文 播客 history podcast'),
    ExploreSub('辩论', '辩论 debate'),
  ]),
  ExploreTopic('宗教信仰', Icons.church_rounded, '宗教 信仰', opens: ExploreSection.faith),
  ExploreTopic('科学探索', Icons.science_rounded, '科学', subs: [
    ExploreSub('宇宙', '宇宙 天文'),
    ExploreSub('物理', '物理'),
    ExploreSub('生物', '生物'),
    ExploreSub('化学', '化学 实验'),
    ExploreSub('地球科学', '地球科学 地质 气候'),
    ExploreSub('工程', '工程 engineering'),
    ExploreSub('科学实验', '科学实验 experiment'),
    ExploreSub('前沿科技', '前沿科技 量子 quantum'),
    ExploreSub('能源', '能源 核聚变 energy'),
    ExploreSub('古生物', '古生物 恐龙 paleontology'),
  ]),
  ExploreTopic('财经商业', Icons.show_chart_rounded, '财经', subs: [
    ExploreSub('财经新闻', '财经新闻 markets'),
    ExploreSub('经济', '经济 分析'),
    ExploreSub('股票', '股票 美股 stock'),
    ExploreSub('投资', '投资 理财'),
    ExploreSub('个人理财', '个人理财 personal finance'),
    ExploreSub('加密货币', '加密货币 比特币 crypto'),
    ExploreSub('房地产', '房地产 楼市'),
    ExploreSub('商业分析', '商业分析 案例'),
    ExploreSub('创业', '创业'),
    ExploreSub('营销', '营销 品牌 marketing'),
  ]),
  ExploreTopic('体育健身', Icons.sports_soccer_rounded, '体育', subs: [
    ExploreSub('足球', '足球'),
    ExploreSub('篮球', '篮球 NBA'),
    ExploreSub('赛事集锦', '赛事集锦 highlights'),
    ExploreSub('网球', '网球 tennis'),
    ExploreSub('乒乓羽毛球', '乒乓球 羽毛球'),
    ExploreSub('棒球橄榄球', '棒球 橄榄球 MLB NFL'),
    ExploreSub('格斗', '格斗 UFC 拳击'),
    ExploreSub('赛车', '赛车 F1'),
    ExploreSub('健身', '健身 训练 workout'),
    ExploreSub('跑步', '跑步 马拉松 running'),
    ExploreSub('极限运动', '极限运动 滑雪 冲浪'),
  ]),
  ExploreTopic('汽车交通', Icons.directions_car_rounded, '汽车', subs: [
    ExploreSub('汽车评测', '汽车评测'),
    ExploreSub('电动车', '电动车 EV'),
    ExploreSub('购车指南', '购车 选车 buying guide'),
    ExploreSub('超跑豪车', '超跑 豪车 supercar'),
    ExploreSub('改装', '改装 tuning'),
    ExploreSub('汽车维修', '汽车维修 保养 DIY'),
    ExploreSub('摩托车', '摩托车 motorcycle'),
    ExploreSub('航空', '航空 飞机'),
    ExploreSub('铁路', '铁路 火车'),
    ExploreSub('城市交通', '地铁 公交 subway'),
    ExploreSub('船舶', '船舶 轮船 ship'),
  ]),
  ExploreTopic('美食旅行', Icons.restaurant_rounded, '美食 旅行', subs: [
    ExploreSub('烹饪', '烹饪 做菜'),
    ExploreSub('烘焙', '烘焙 baking'),
    ExploreSub('探店', '探店 美食'),
    ExploreSub('街头小吃', '街头小吃 street food'),
    ExploreSub('各国美食', '各国美食 food around the world'),
    ExploreSub('咖啡茶饮', '咖啡 茶 coffee tea'),
    ExploreSub('旅行', '旅行 vlog'),
    ExploreSub('旅行攻略', '旅行攻略 travel guide'),
    ExploreSub('城市探索', '城市漫步 walking tour'),
    ExploreSub('自驾游', '自驾游 road trip'),
    ExploreSub('酒店体验', '酒店 体验 hotel review'),
  ]),
  ExploreTopic('娱乐生活', Icons.sentiment_very_satisfied_rounded, '生活 vlog', subs: [
    ExploreSub('Vlog', 'vlog 日常'),
    ExploreSub('搞笑', '搞笑'),
    ExploreSub('综艺', '综艺 variety show'),
    ExploreSub('挑战', '挑战 challenge'),
    ExploreSub('宠物', '宠物 猫 狗'),
    ExploreSub('明星娱乐', '明星 娱乐 celebrity'),
    ExploreSub('穿搭美妆', '穿搭 美妆 fashion beauty'),
    ExploreSub('家居装修', '家居 装修 home'),
    ExploreSub('育儿亲子', '育儿 亲子 parenting'),
    ExploreSub('好物分享', '好物分享 haul'),
    ExploreSub('情感', '情感 恋爱'),
  ]),
  ExploreTopic('艺术创作', Icons.brush_rounded, '艺术 创作', subs: [
    ExploreSub('摄影', '摄影 教程'),
    ExploreSub('绘画', '绘画 插画 drawing'),
    ExploreSub('设计', '设计 design'),
    ExploreSub('视频剪辑', '视频剪辑 Premiere'),
    ExploreSub('3D 建模', '3D 建模 Blender'),
    ExploreSub('手工', '手工 DIY'),
    ExploreSub('木工', '木工 woodworking'),
    ExploreSub('书法', '书法 calligraphy'),
    ExploreSub('建筑', '建筑 architecture'),
    ExploreSub('艺术史', '艺术史 美术馆 museum'),
    ExploreSub('写作', '写作 writing'),
  ]),
  ExploreTopic('健康生活', Icons.favorite_rounded, '健康', subs: [
    ExploreSub('医学科普', '医学科普'),
    ExploreSub('心理学', '心理学 心理健康'),
    ExploreSub('营养', '营养 饮食'),
    ExploreSub('减肥', '减肥 weight loss'),
    ExploreSub('睡眠', '睡眠 sleep'),
    ExploreSub('中医养生', '中医 养生'),
    ExploreSub('冥想', '冥想 正念 meditation'),
    ExploreSub('疾病预防', '疾病 症状 预防'),
    ExploreSub('康复理疗', '康复 理疗 rehab'),
    ExploreSub('生活方式', '生活方式 lifestyle'),
  ]),
  ExploreTopic('自然户外', Icons.park_rounded, '自然 纪录片', subs: [
    ExploreSub('动物', '动物 纪录片'),
    ExploreSub('海洋', '海洋 ocean'),
    ExploreSub('生态', '生态 环境'),
    ExploreSub('风光', '风光 4K nature scenery'),
    ExploreSub('露营', '露营 camping'),
    ExploreSub('徒步', '徒步 hiking'),
    ExploreSub('登山', '登山 mountaineering'),
    ExploreSub('荒野求生', '荒野求生 survival'),
    ExploreSub('钓鱼', '钓鱼 fishing'),
    ExploreSub('骑行', '骑行 cycling'),
    ExploreSub('园艺', '园艺 gardening'),
    ExploreSub('田园乡村', '田园 乡村 farm'),
  ]),
];

/// Live zones, streams that are on now; about 6-10 sub-categories each, as
/// fewer streams are on at a time.
const liveTopics = <ExploreTopic>[
  ExploreTopic('推荐', Icons.recommend_rounded, '', mix: true, personal: true),
  ExploreTopic('全部', Icons.apps_rounded, '', mix: true),
  ExploreTopic('宗教信仰', Icons.church_rounded, '宗教 直播', opens: ExploreSection.faithLive),
  ExploreTopic('游戏直播', Icons.sports_esports_rounded, '游戏 直播', subs: [
    ExploreSub('游戏实况', 'gameplay live'),
    ExploreSub('单机游戏', '单机游戏 直播'),
    ExploreSub('网络游戏', '网游 MMO 直播'),
    ExploreSub('手游', '手游 直播'),
    ExploreSub('FPS 射击', 'FPS live Valorant CS2'),
    ExploreSub('MOBA', 'MOBA live LOL Dota'),
    ExploreSub('我的世界', 'Minecraft live'),
    ExploreSub('主机游戏', 'console gaming live'),
    ExploreSub('速通', 'speedrun live'),
  ]),
  ExploreTopic('电竞赛事', Icons.emoji_events_rounded, 'esports live', subs: [
    ExploreSub('职业电竞', '电竞 比赛 esports tournament live'),
    ExploreSub('比赛解说', '电竞 解说 直播'),
    ExploreSub('英雄联盟', 'LoL Esports LCK LPL live'),
    ExploreSub('无畏契约 CS2', 'Valorant CS2 tournament live'),
    ExploreSub('Dota 2', 'Dota 2 tournament live'),
    ExploreSub('格斗游戏', 'fighting game tournament EVO live'),
    ExploreSub('手游电竞', '手游 电竞 比赛 live'),
  ]),
  ExploreTopic('音乐现场', Icons.music_note_rounded, '音乐 直播', subs: [
    ExploreSub('演唱会', 'concert live'),
    ExploreSub('音乐节', 'music festival live'),
    ExploreSub('唱歌直播', '唱歌 直播 singing live'),
    ExploreSub('乐器演奏', '乐器 直播'),
    ExploreSub('DJ', 'DJ set live'),
    ExploreSub('古典音乐会', 'classical concert live'),
    ExploreSub('街头演出', 'busking 街头艺人 live'),
    ExploreSub('点歌', '点歌 直播'),
  ]),
  ExploreTopic('聊天互动', Icons.forum_rounded, '聊天 直播', subs: [
    ExploreSub('聊天', '聊天 直播 just chatting'),
    ExploreSub('问答', 'Q&A live'),
    ExploreSub('谈话节目', 'talk show live'),
    ExploreSub('脱口秀', 'stand-up comedy live'),
    ExploreSub('日常生活', '日常 生活 直播 daily life live'),
    ExploreSub('电话连线', 'call-in show live'),
  ]),
  ExploreTopic('虚拟主播', Icons.face_retouching_natural_rounded, 'vtuber', subs: [
    ExploreSub('VTuber', 'vtuber live'),
    ExploreSub('Hololive 彩虹社', 'hololive nijisanji live'),
    ExploreSub('中文虚拟主播', '虚拟主播 直播'),
    ExploreSub('歌回', '歌回 vtuber singing'),
    ExploreSub('游戏 VTuber', 'vtuber gaming live'),
    ExploreSub('虚拟演出', 'virtual concert live'),
    ExploreSub('虚拟电台', 'vtuber radio'),
  ]),
  ExploreTopic('体育赛事', Icons.sports_soccer_rounded, '体育 直播', subs: [
    ExploreSub('体育直播', 'sports live'),
    ExploreSub('足球', '足球 直播 football live'),
    ExploreSub('篮球', '篮球 NBA live'),
    ExploreSub('棒球', '棒球 MLB live'),
    ExploreSub('网球', '网球 tennis live'),
    ExploreSub('赛车', 'F1 racing live'),
    ExploreSub('格斗', 'UFC boxing live'),
    ExploreSub('赛事评论', '赛事 评论 直播'),
    ExploreSub('赛前节目', 'pre-game show live'),
  ]),
  ExploreTopic('新闻现场', Icons.newspaper_rounded, 'news live', subs: [
    ExploreSub('新闻直播', '新闻 直播'),
    ExploreSub('国际新闻', 'world news live'),
    ExploreSub('重大事件', 'breaking news live'),
    ExploreSub('政治与议会', '议会 国会 parliament live'),
    ExploreSub('财经市场', '财经 盘面 markets live'),
    ExploreSub('发布会', '新闻发布会 直播'),
    ExploreSub('天气灾害', 'weather severe live'),
  ]),
  ExploreTopic('科技活动', Icons.memory_rounded, '科技 发布会 直播', subs: [
    ExploreSub('新品发布会', 'launch event live'),
    ExploreSub('开发者大会', 'developer conference keynote live'),
    ExploreSub('展会', 'CES MWC expo live'),
    ExploreSub('AI 大会', 'AI summit keynote live'),
    ExploreSub('技术讲座', 'tech talk live'),
    ExploreSub('安全大会', 'security conference live'),
    ExploreSub('开箱评测', 'unboxing review live'),
  ]),
  ExploreTopic('学习工作', Icons.menu_book_rounded, 'study with me live', subs: [
    ExploreSub('Study with Me', 'study with me live'),
    ExploreSub('工作陪伴', 'work with me pomodoro live'),
    ExploreSub('编程直播', 'live coding'),
    ExploreSub('线上课堂', '线上课堂 直播'),
    ExploreSub('公开课', 'lecture 公开课 live'),
    ExploreSub('语言学习', 'language learning live'),
    ExploreSub('创作过程', 'drawing 绘画 创作 live'),
  ]),
  ExploreTopic('户外实况', Icons.landscape_rounded, '户外 直播', subs: [
    ExploreSub('IRL 直播', 'IRL stream'),
    ExploreSub('旅行直播', 'travel live stream'),
    ExploreSub('街头漫步', 'walking live'),
    ExploreSub('徒步登山', 'hiking live'),
    ExploreSub('露营', 'camping live'),
    ExploreSub('钓鱼', 'fishing live'),
    ExploreSub('骑行', 'cycling live'),
    ExploreSub('节庆活动', 'festival parade live'),
  ]),
  ExploreTopic('电台助眠', Icons.radio_rounded, 'lofi radio 24/7', subs: [
    ExploreSub('Lo-Fi', 'lofi hip hop radio'),
    ExploreSub('24 小时音乐', '24/7 music live'),
    ExploreSub('ASMR', 'ASMR live'),
    ExploreSub('白噪音', 'white noise live'),
    ExploreSub('雨声', 'rain sounds live'),
    ExploreSub('睡眠音乐', 'sleep music live'),
    ExploreSub('爵士电台', 'jazz radio 24/7'),
    ExploreSub('古典电台', 'classical music radio 24/7'),
    ExploreSub('冥想音乐', 'meditation music live'),
  ]),
  ExploreTopic('自然实况', Icons.videocam_rounded, 'live cam 24/7', subs: [
    ExploreSub('动物观察', 'animal live cam'),
    ExploreSub('太空直播', 'space live ISS'),
    ExploreSub('城市摄像头', 'city live cam'),
    ExploreSub('鸟类', 'bird feeder live cam'),
    ExploreSub('海洋水族', 'aquarium ocean live cam'),
    ExploreSub('铁路', 'train cam railway live'),
    ExploreSub('港口船舶', 'harbor ship cam live'),
    ExploreSub('风景', 'scenic live cam 4K'),
    ExploreSub('火山与天气', 'volcano weather live cam'),
  ]),
];

/// The built-in zones of [section], then the user's own.
List<ExploreTopic> exploreTopicsOf(ExploreSection section, [List<CustomTopic> custom = const []]) => [
      ...switch (section) {
        ExploreSection.popular => popularTopics,
        ExploreSection.live => liveTopics,
        ExploreSection.faith => faithTraditionTopics,
        ExploreSection.faithStudy => faithStudyTopics,
        ExploreSection.faithArts => faithArtsTopics,
        ExploreSection.faithLive => faithLiveTopics,
      },
      for (final topic in custom)
        if (topic.section == section) topic.topic,
    ];

/// [topics] in the user's [order] (zone keys, the first ones pinned), with
/// [hidden] ones left out. Zones the order does not name keep their place
/// after the ones it does.
List<ExploreTopic> arrangeTopics(List<ExploreTopic> topics, List<String> order, Set<String> hidden) {
  final rank = {for (final (i, key) in order.indexed) key: i};
  final indexed = topics.indexed.toList()
    ..sort((a, b) {
      final ra = rank[a.$2.key];
      final rb = rank[b.$2.key];
      if (ra != null && rb != null) return ra.compareTo(rb);
      if (ra != null) return -1;
      if (rb != null) return 1;
      return a.$1.compareTo(b.$1);
    });
  final shown = [for (final (_, topic) in indexed) if (!hidden.contains(topic.key)) topic];
  // Never leave the strip empty.
  return shown.isEmpty ? [indexed.first.$2] : shown;
}

/// How the explore page picks and orders a zone's videos.
enum ExploreMode {
  curated('精选', live: false),
  forYou('为你推荐', live: false),
  popular('热门', live: false),
  latest('最新', live: false),
  gems('冷门宝藏', live: false),
  long('长视频', live: false),
  liveViewers('观看最多', live: true),
  liveLatest('最新开播', live: true),
  liveUpcoming('即将开播', live: true),
  liveReplay('直播回放', live: true);

  const ExploreMode(this._label, {required this.live});
  final String _label;
  String get label => tr(_label);
  final bool live;

  /// The modes [section] offers; 精选 is only for 宗教与信仰.
  static List<ExploreMode> of(ExploreSection section) =>
      values.where((m) => m.live == section.isLive && (m != curated || section.isFaith)).toList();
  static ExploreMode defaultOf(ExploreSection section) => section.isLive
      ? liveViewers
      : section.isFaith
          ? curated
          : popular;

  /// Whether the period chips apply.
  bool get hasPeriod => this == popular;
}

/// 冷门宝藏: videos of at least four minutes with at most this many views.
const gemMaxViews = 50000;

/// The periods popular videos can be counted over.
const explorePeriods = [SearchUploadDate.today, SearchUploadDate.week, SearchUploadDate.month, SearchUploadDate.year];

/// YouTube's `sp` for a zone shown by [mode]: the most viewed of [period],
/// the newest, the most relevant (of the year, or of all time for 精选;
/// ranked or filtered here afterwards), long videos, or live streams. Search
/// cannot ask for upcoming or past streams, so those come from the newest
/// videos, kept here by their live status.
String exploreParams(
  ExploreMode mode, {
  SearchUploadDate period = SearchUploadDate.month,
  SearchDuration duration = SearchDuration.any,
  SearchQuality quality = SearchQuality.any,
}) =>
    switch (mode) {
      ExploreMode.curated => searchParams(type: SearchFilter.videos, duration: duration, quality: quality)!,
      ExploreMode.popular => searchParams(type: SearchFilter.videos, sort: SearchSort.views, date: period, duration: duration, quality: quality)!,
      ExploreMode.latest => searchParams(type: SearchFilter.videos, sort: SearchSort.date, duration: duration, quality: quality)!,
      ExploreMode.forYou => searchParams(type: SearchFilter.videos, date: SearchUploadDate.month, duration: duration, quality: quality)!,
      ExploreMode.gems => searchParams(type: SearchFilter.videos, date: SearchUploadDate.year, duration: duration, quality: quality)!,
      ExploreMode.long => searchParams(type: SearchFilter.videos, sort: SearchSort.views, date: SearchUploadDate.year, duration: SearchDuration.long, quality: quality)!,
      ExploreMode.liveViewers => searchParams(type: SearchFilter.live, sort: SearchSort.views, quality: quality)!,
      ExploreMode.liveLatest => searchParams(type: SearchFilter.live, sort: SearchSort.date, quality: quality)!,
      ExploreMode.liveUpcoming || ExploreMode.liveReplay => searchParams(type: SearchFilter.videos, sort: SearchSort.date, quality: quality)!,
    };
