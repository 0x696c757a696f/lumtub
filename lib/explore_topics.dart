import 'package:flutter/widgets.dart' show IconData;
import 'package:flutter/material.dart' show Icons;

import 'search_options.dart';
import 'video_repository.dart';

/// The two halves of the explore page.
enum ExploreSection {
  popular('视频'),
  live('直播');

  const ExploreSection(this.label);
  final String label;
}

/// A sub-category of a zone: its name and the words searched for.
class ExploreSub {
  const ExploreSub(this.label, this.query);
  final String label;
  final String query;
}

/// One explore zone, as Bilibili's 分区: what it is called, the search
/// behind it and its sub-categories.
class ExploreTopic {
  const ExploreTopic(this.label, this.icon, this.query, {this.subs = const [], this.custom = false});
  final String label;
  final IconData icon;
  final String query;
  final List<ExploreSub> subs;
  /// Added by the user; it can be removed.
  final bool custom;

  /// Names the zone in the saved order and hidden lists; custom zones as
  /// `custom:<label>`.
  String get key => custom ? 'custom:$label' : label;
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

/// Video zones. Searches mix Chinese and English words so that YouTube's
/// videos from other countries come up too.
const popularTopics = <ExploreTopic>[
  ExploreTopic('知识教育', Icons.school_rounded, '知识 科普', subs: [
    ExploreSub('科普', '科普'),
    ExploreSub('历史', '历史 纪录片'),
    ExploreSub('数学', '数学 讲解'),
    ExploreSub('语言学习', '语言学习 英语 日语'),
    ExploreSub('大学课程', '大学 公开课 lecture'),
  ]),
  ExploreTopic('科技数码', Icons.memory_rounded, '科技 数码 评测', subs: [
    ExploreSub('电脑硬件', '电脑硬件 显卡 CPU'),
    ExploreSub('手机', '手机 评测'),
    ExploreSub('数码评测', '数码 开箱 评测'),
    ExploreSub('操作系统', 'Windows Linux macOS 操作系统'),
    ExploreSub('网络安全', '网络安全 cybersecurity'),
  ]),
  ExploreTopic('人工智能', Icons.auto_awesome_rounded, 'AI 人工智能', subs: [
    ExploreSub('AI 模型', 'AI 大模型 LLM'),
    ExploreSub('AI 工具', 'AI 工具 教程'),
    ExploreSub('机器学习', '机器学习 machine learning'),
    ExploreSub('机器人', '机器人 robotics'),
  ]),
  ExploreTopic('编程开发', Icons.code_rounded, '编程 教程', subs: [
    ExploreSub('Rust', 'Rust 编程'),
    ExploreSub('Python', 'Python 教程'),
    ExploreSub('开源项目', '开源项目 GitHub'),
    ExploreSub('软件开发', '软件开发 software engineering'),
    ExploreSub('技术教程', '技术教程 编程'),
  ]),
  ExploreTopic('游戏', Icons.sports_esports_rounded, '游戏', subs: [
    ExploreSub('游戏实况', '游戏实况'),
    ExploreSub('攻略', '游戏攻略'),
    ExploreSub('评测', '游戏评测'),
    ExploreSub('独立游戏', '独立游戏 indie game'),
  ]),
  ExploreTopic('音乐舞蹈', Icons.music_note_rounded, '音乐', subs: [
    ExploreSub('MV', 'MV 官方'),
    ExploreSub('现场演出', '现场 live concert'),
    ExploreSub('乐器', '乐器 演奏'),
    ExploreSub('爵士乐', 'jazz 爵士乐'),
    ExploreSub('电子音乐', '电子音乐 EDM'),
    ExploreSub('舞蹈', '舞蹈 dance'),
  ]),
  ExploreTopic('影视动漫', Icons.movie_rounded, '电影 动画', subs: [
    ExploreSub('电影', '电影 解说'),
    ExploreSub('电视剧', '电视剧'),
    ExploreSub('动画', '动画 动漫'),
    ExploreSub('影评', '影评'),
    ExploreSub('预告片', '预告片 trailer'),
  ]),
  ExploreTopic('新闻时事', Icons.newspaper_rounded, '新闻', subs: [
    ExploreSub('国际新闻', '国际新闻'),
    ExploreSub('社会热点', '社会热点'),
    ExploreSub('时事评论', '时事评论'),
  ]),
  ExploreTopic('播客访谈', Icons.podcasts_rounded, '播客 访谈', subs: [
    ExploreSub('深度对谈', '深度对谈 podcast'),
    ExploreSub('人物采访', '人物专访 interview'),
    ExploreSub('脱口秀', '脱口秀 talk show'),
  ]),
  ExploreTopic('宗教信仰', Icons.church_rounded, '宗教 信仰', subs: [
    ExploreSub('天主教', '天主教'),
    ExploreSub('弥撒', '弥撒 Holy Mass'),
    ExploreSub('圣经', '圣经 讲解'),
    ExploreSub('圣歌', '天主教 圣歌'),
    ExploreSub('教宗', '教宗 Pope'),
    ExploreSub('基督教', '基督教 讲道'),
    ExploreSub('佛教', '佛教 佛法'),
  ]),
  ExploreTopic('科学探索', Icons.science_rounded, '科学', subs: [
    ExploreSub('物理', '物理'),
    ExploreSub('宇宙', '宇宙 天文'),
    ExploreSub('生物', '生物'),
    ExploreSub('化学', '化学 实验'),
    ExploreSub('工程', '工程 engineering'),
  ]),
  ExploreTopic('财经商业', Icons.show_chart_rounded, '财经', subs: [
    ExploreSub('经济', '经济 分析'),
    ExploreSub('投资', '投资 理财'),
    ExploreSub('商业分析', '商业分析 案例'),
    ExploreSub('创业', '创业'),
  ]),
  ExploreTopic('体育健身', Icons.sports_soccer_rounded, '体育', subs: [
    ExploreSub('足球', '足球'),
    ExploreSub('篮球', '篮球 NBA'),
    ExploreSub('赛车', '赛车 F1'),
    ExploreSub('运动训练', '健身 训练'),
  ]),
  ExploreTopic('汽车交通', Icons.directions_car_rounded, '汽车', subs: [
    ExploreSub('电动车', '电动车 EV'),
    ExploreSub('汽车评测', '汽车评测'),
    ExploreSub('航空', '航空 飞机'),
    ExploreSub('铁路', '铁路 火车'),
  ]),
  ExploreTopic('美食旅行', Icons.restaurant_rounded, '美食 旅行', subs: [
    ExploreSub('烹饪', '烹饪 做菜'),
    ExploreSub('探店', '探店 美食'),
    ExploreSub('旅行', '旅行 vlog'),
    ExploreSub('城市探索', '城市漫步 walking tour'),
  ]),
  ExploreTopic('娱乐生活', Icons.sentiment_very_satisfied_rounded, '生活 vlog', subs: [
    ExploreSub('Vlog', 'vlog 日常'),
    ExploreSub('搞笑', '搞笑'),
    ExploreSub('挑战', '挑战 challenge'),
    ExploreSub('宠物', '宠物 猫 狗'),
  ]),
  ExploreTopic('艺术创作', Icons.brush_rounded, '艺术 创作', subs: [
    ExploreSub('摄影', '摄影 教程'),
    ExploreSub('设计', '设计 design'),
    ExploreSub('绘画', '绘画'),
    ExploreSub('手工', '手工 DIY'),
    ExploreSub('建筑', '建筑 architecture'),
  ]),
  ExploreTopic('健康生活', Icons.favorite_rounded, '健康', subs: [
    ExploreSub('医学科普', '医学科普'),
    ExploreSub('心理学', '心理学'),
    ExploreSub('营养', '营养 饮食'),
    ExploreSub('生活方式', '生活方式 lifestyle'),
  ]),
  ExploreTopic('自然户外', Icons.park_rounded, '自然 纪录片', subs: [
    ExploreSub('动物', '动物 纪录片'),
    ExploreSub('生态', '生态 环境'),
    ExploreSub('露营', '露营 camping'),
    ExploreSub('徒步', '徒步 hiking'),
  ]),
];

/// Live zones, streams that are on now.
const liveTopics = <ExploreTopic>[
  ExploreTopic('全部', Icons.sensors_rounded, '直播 live'),
  ExploreTopic('游戏直播', Icons.sports_esports_rounded, '游戏 直播', subs: [
    ExploreSub('单机游戏', '单机游戏 直播'),
    ExploreSub('网络游戏', '网游 直播'),
    ExploreSub('手游', '手游 直播'),
    ExploreSub('游戏实况', 'gameplay live'),
  ]),
  ExploreTopic('电竞赛事', Icons.emoji_events_rounded, 'esports live', subs: [
    ExploreSub('职业电竞', '电竞 比赛 直播'),
    ExploreSub('赛事转播', 'esports tournament live'),
    ExploreSub('比赛解说', '电竞 解说 直播'),
  ]),
  ExploreTopic('音乐现场', Icons.music_note_rounded, '音乐 直播', subs: [
    ExploreSub('演唱会', 'concert live'),
    ExploreSub('乐器演奏', '乐器 直播'),
    ExploreSub('DJ', 'DJ set live'),
    ExploreSub('点歌', '点歌 直播'),
  ]),
  ExploreTopic('聊天互动', Icons.forum_rounded, '聊天 直播', subs: [
    ExploreSub('聊天', '聊天 直播'),
    ExploreSub('问答', 'Q&A live'),
    ExploreSub('谈话节目', 'talk show live'),
  ]),
  ExploreTopic('虚拟主播', Icons.face_retouching_natural_rounded, 'vtuber', subs: [
    ExploreSub('VTuber', 'vtuber live'),
    ExploreSub('虚拟演出', 'virtual concert live'),
    ExploreSub('虚拟电台', 'vtuber radio'),
  ]),
  ExploreTopic('体育赛事', Icons.sports_soccer_rounded, '体育 直播', subs: [
    ExploreSub('体育直播', 'sports live'),
    ExploreSub('赛事评论', '赛事 评论 直播'),
    ExploreSub('赛前节目', 'pre-game show live'),
  ]),
  ExploreTopic('新闻现场', Icons.newspaper_rounded, 'news live', subs: [
    ExploreSub('新闻直播', '新闻 直播'),
    ExploreSub('发布会', '新闻发布会 直播'),
    ExploreSub('重大事件', 'breaking news live'),
  ]),
  ExploreTopic('宗教礼仪', Icons.church_rounded, '弥撒 直播 Holy Mass', subs: [
    ExploreSub('弥撒', 'Holy Mass live 弥撒'),
    ExploreSub('玫瑰经', 'rosary live 玫瑰经'),
    ExploreSub('梵蒂冈', 'Vatican live'),
    ExploreSub('朝拜圣体', 'Eucharistic adoration live'),
    ExploreSub('祈祷', 'prayer live 祈祷'),
  ]),
  ExploreTopic('科技活动', Icons.memory_rounded, '科技 发布会 直播', subs: [
    ExploreSub('新品发布会', 'launch event live'),
    ExploreSub('开发者大会', 'developer conference keynote live'),
    ExploreSub('技术讲座', 'tech talk live'),
  ]),
  ExploreTopic('学习工作', Icons.menu_book_rounded, 'study with me live', subs: [
    ExploreSub('Study with Me', 'study with me live'),
    ExploreSub('编程直播', 'live coding'),
    ExploreSub('线上课堂', '线上课堂 直播'),
  ]),
  ExploreTopic('户外实况', Icons.landscape_rounded, '户外 直播', subs: [
    ExploreSub('旅行直播', 'travel live stream'),
    ExploreSub('街头漫步', 'walking live'),
    ExploreSub('IRL 直播', 'IRL stream'),
  ]),
  ExploreTopic('电台助眠', Icons.radio_rounded, 'lofi radio 24/7', subs: [
    ExploreSub('Lo-Fi', 'lofi hip hop radio'),
    ExploreSub('ASMR', 'ASMR live'),
    ExploreSub('白噪音', 'white noise live'),
    ExploreSub('24 小时音乐', '24/7 music live'),
  ]),
  ExploreTopic('自然实况', Icons.videocam_rounded, 'live cam 24/7', subs: [
    ExploreSub('动物观察', 'animal live cam'),
    ExploreSub('城市摄像头', 'city live cam'),
    ExploreSub('太空直播', 'space live ISS'),
  ]),
];

/// The built-in zones of [section], then the user's own.
List<ExploreTopic> exploreTopicsOf(ExploreSection section, [List<CustomTopic> custom = const []]) => [
      ...switch (section) {
        ExploreSection.popular => popularTopics,
        ExploreSection.live => liveTopics,
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
  forYou('为你推荐', live: false),
  popular('热门', live: false),
  latest('最新', live: false),
  gems('冷门宝藏', live: false),
  long('长视频', live: false),
  liveViewers('观看最多', live: true),
  liveLatest('最新开播', live: true);

  const ExploreMode(this.label, {required this.live});
  final String label;
  final bool live;

  static List<ExploreMode> of(ExploreSection section) => values.where((m) => m.live == (section == ExploreSection.live)).toList();
  static ExploreMode defaultOf(ExploreSection section) => section == ExploreSection.live ? liveViewers : popular;

  /// Whether the period chips apply.
  bool get hasPeriod => this == popular;
}

/// 冷门宝藏: videos of at least four minutes with at most this many views.
const gemMaxViews = 50000;

/// The periods popular videos can be counted over.
const explorePeriods = [SearchUploadDate.today, SearchUploadDate.week, SearchUploadDate.month, SearchUploadDate.year];

/// YouTube's `sp` for a zone shown by [mode]: the most viewed of [period],
/// the newest, the most relevant of the year (ranked or filtered here
/// afterwards), long videos, or live streams.
String exploreParams(
  ExploreMode mode, {
  SearchUploadDate period = SearchUploadDate.month,
  SearchDuration duration = SearchDuration.any,
  SearchQuality quality = SearchQuality.any,
}) =>
    switch (mode) {
      ExploreMode.popular => searchParams(type: SearchFilter.videos, sort: SearchSort.views, date: period, duration: duration, quality: quality)!,
      ExploreMode.latest => searchParams(type: SearchFilter.videos, sort: SearchSort.date, duration: duration, quality: quality)!,
      ExploreMode.forYou => searchParams(type: SearchFilter.videos, date: SearchUploadDate.month, duration: duration, quality: quality)!,
      ExploreMode.gems => searchParams(type: SearchFilter.videos, date: SearchUploadDate.year, duration: duration, quality: quality)!,
      ExploreMode.long => searchParams(type: SearchFilter.videos, sort: SearchSort.views, date: SearchUploadDate.year, duration: SearchDuration.long, quality: quality)!,
      ExploreMode.liveViewers => searchParams(type: SearchFilter.live, sort: SearchSort.views, quality: quality)!,
      ExploreMode.liveLatest => searchParams(type: SearchFilter.live, sort: SearchSort.date, quality: quality)!,
    };
