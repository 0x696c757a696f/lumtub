import 'package:flutter/widgets.dart' show IconData;

import 'faith_topics.dart';
import 'l10n/l10n.dart';
import 'search_options.dart';
import 'video_repository.dart';
import 'ui/app_icons.dart';

/// The parts of the explore page: videos, live streams, and the four tabs
/// of 宗教与信仰.
enum ExploreSection {
  popular('Videos'),
  live('Live', isLive: true),
  faith('Traditions', isFaith: true),
  faithStudy('Study', isFaith: true),
  faithArts('Culture & art', isFaith: true),
  faithLive('Faith live', isLive: true, isFaith: true);

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
  const ExploreTopic(this._label, this.icon, this.query, {this.subs = const [], this.custom = false, this.opens, this.mix = false});
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
  /// 全部: a mix of the other zones, with one of the history's interests
  /// when there is a history, rather than a search of its own.
  final bool mix;

  /// Names the zone in the saved order and hidden lists; custom zones as
  /// `custom:<label>`.
  String get key => custom ? 'custom:$_label' : _label;
}

/// The zone keys saved before the interface was written in English, which
/// named zones by their simplified Chinese name, and the keys of the same
/// zones now, so a saved order and hidden list keep working.
const legacyTopicKeys = {
  '全部': 'All',
  '知识教育': 'Education',
  '科技数码': 'Tech & gadgets',
  '人工智能': 'Artificial intelligence',
  '编程开发': 'Programming',
  '游戏': 'Gaming',
  '音乐舞蹈': 'Music & dance',
  '影视动漫': 'Film, TV & anime',
  '新闻时事': 'News & current affairs',
  '播客访谈': 'Podcast interviews',
  '宗教信仰': 'Religion & faith',
  '科学探索': 'Science',
  '财经商业': 'Finance & business',
  '体育健身': 'Sports & fitness',
  '汽车交通': 'Cars & transport',
  '美食旅行': 'Food & travel',
  '娱乐生活': 'Entertainment & lifestyle',
  '艺术创作': 'Art & creativity',
  '健康生活': 'Healthy living',
  '自然户外': 'Nature & outdoors',
  '游戏直播': 'Gaming live streams',
  '电竞赛事': 'Esports',
  '音乐现场': 'Live music',
  '聊天互动': 'Chat & interaction',
  '虚拟主播': 'VTubers',
  '体育赛事': 'Sports events',
  '新闻现场': 'On the scene',
  '科技活动': 'Tech & development',
  'Tech events': 'Tech & development',
  '学习工作': 'Study & work',
  '户外实况': 'Outdoor live',
  '电台助眠': '24/7 live',
  '自然实况': '24/7 live',
  'Radio for sleep': '24/7 live',
  'Nature footage': '24/7 live',
  '基督宗教': 'Christianity',
  '伊斯兰教': 'Islam',
  '佛教': 'Buddhism',
  '道教与中国传统信仰': 'Taoism & Chinese religion',
  '印度教': 'Hinduism',
  '犹太教': 'Judaism',
  '其他宗教': 'Other religions',
  '精选专题': 'Featured',
  '宗教历史': 'Religious history',
  '宗教哲学': 'Philosophy of religion',
  '比较宗教学': 'Comparative religion',
  '经典研究': 'Scripture study',
  '宗教与社会': 'Religion and society',
  '无神论与宗教批评': 'Atheism and critique',
  '宗教对话': 'Dialogue',
  '宗教艺术': 'Sacred art',
  '宗教建筑': 'Religious architecture',
  '宗教纪录片': 'Documentaries',
  '宗教音乐': 'Sacred music',
  '节日与习俗': 'Festivals & customs',
  '世界宗教文化': 'Faith around the world',
  '宗教礼仪': 'Liturgy',
  '祈祷与冥想': 'Prayer & meditation',
  '宗教讲道': 'Sermons',
  '宗教教育': 'Religious education',
  '宗教新闻': 'Religion news',
  '宗教节庆': 'Religious festivals',
  '圣地实况': 'Holy places live',
  '宗教电台': 'Religious radio',
};

/// A category the user added: its name, the words searched for, and which
/// half of the explore page it belongs to.
class CustomTopic {
  const CustomTopic(this.label, this.query, this.section);
  final String label;
  final String query;
  final ExploreSection section;

  ExploreTopic get topic => ExploreTopic(label, AppIcons.bookmarkSimple, query, custom: true);

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
  ExploreTopic('All', AppIcons.squaresFour, '', mix: true),
  ExploreTopic('Education', AppIcons.graduationCap, '知识 科普', subs: [
    ExploreSub('Popular science', '科普'),
    ExploreSub('History', '历史 纪录片'),
    ExploreSub('University courses', '大学 公开课 lecture'),
    ExploreSub('Language learning', '语言学习 英语 日语'),
    ExploreSub('Math', '数学 讲解'),
    ExploreSub('Philosophy', '哲学 philosophy'),
    ExploreSub('Geography', '地理 geography explained'),
    ExploreSub('Study methods', '学习方法 study tips'),
    ExploreSub('Workplace skills', '职场技能 career skills'),
    ExploreSub("Children's education", '儿童教育 kids learning'),
  ]),
  ExploreTopic('Tech & gadgets', AppIcons.cpuFill, '科技 数码 评测', subs: [
    ExploreSub('Tech reviews', '数码 开箱 评测'),
    ExploreSub('Phones', '手机 评测'),
    ExploreSub('PC hardware', '电脑硬件 显卡 CPU'),
    ExploreSub('Laptops & tablets', '笔记本 平板 laptop tablet review'),
    ExploreSub('Headphones & speakers', '耳机 音响 headphones review'),
    ExploreSub('Smart home', '智能家居 smart home'),
    ExploreSub('Tech news', '科技新闻 tech news'),
    ExploreSub('Product launches', '新品发布会 keynote'),
    ExploreSub('Operating system', 'Windows Linux macOS 操作系统'),
    ExploreSub('Cybersecurity', '网络安全 cybersecurity'),
  ]),
  ExploreTopic('Artificial intelligence', AppIcons.sparkleFill, 'AI 人工智能', subs: [
    ExploreSub('AI news', 'AI 新闻 AI news'),
    ExploreSub('AI models', 'AI 大模型 LLM'),
    ExploreSub('AI tools', 'AI 工具 教程'),
    ExploreSub('AI programming', 'AI 编程 AI coding Cursor'),
    ExploreSub('AI art videos', 'AI 绘画 AI video generation'),
    ExploreSub('Machine learning', '机器学习 深度学习 machine learning'),
    ExploreSub('Paper explanations', 'AI 论文解读 paper explained'),
    ExploreSub('Robotics', '机器人 robotics'),
    ExploreSub('Self-driving', '自动驾驶 autonomous driving'),
  ]),
  ExploreTopic('Programming', AppIcons.code, '编程 教程', subs: [
    ExploreSub('Programming basics', '编程入门 教程 beginner'),
    ExploreSub('Python', 'Python 教程'),
    ExploreSub('Front-end development', 'JavaScript 前端 frontend'),
    ExploreSub('Back-end development', '后端 backend Java Go'),
    ExploreSub('Rust', 'Rust 编程'),
    ExploreSub('C / C++', 'C++ 编程 教程'),
    ExploreSub('Mobile development', 'Android iOS Flutter 开发'),
    ExploreSub('Algorithms', '算法 数据结构 LeetCode'),
    ExploreSub('Cloud & DevOps', '云计算 DevOps Docker'),
    ExploreSub('Open source projects', '开源项目 GitHub'),
    ExploreSub('Software development', '软件开发 software engineering'),
  ]),
  ExploreTopic('Gaming', AppIcons.gameController, '游戏', subs: [
    ExploreSub("Let's plays", '游戏实况'),
    ExploreSub('Gaming news', '游戏新闻 game news'),
    ExploreSub('Reviews', '游戏评测'),
    ExploreSub('Guides', '游戏攻略'),
    ExploreSub('Indie games', '独立游戏 indie game'),
    ExploreSub('Mobile games', '手游 mobile game'),
    ExploreSub('Console gaming', '主机游戏 PS5 Switch'),
    ExploreSub('Minecraft', '我的世界 Minecraft'),
    ExploreSub('Esports', '电竞 esports'),
    ExploreSub('Speedruns', '速通 speedrun'),
  ]),
  ExploreTopic('Music & dance', AppIcons.musicNoteFill, '音乐', subs: [
    ExploreSub('MV', 'MV 官方'),
    ExploreSub('Live performances', '现场 live concert'),
    ExploreSub('Chinese pop', '华语流行 C-pop'),
    ExploreSub('Western pop', '欧美流行 pop music'),
    ExploreSub('Japanese & Korean music', 'J-pop K-pop 日韩'),
    ExploreSub('Rock & metal', '摇滚 rock metal'),
    ExploreSub('Rap', '说唱 hip hop rap'),
    ExploreSub('Jazz', 'jazz 爵士乐'),
    ExploreSub('Electronic music', '电子音乐 EDM'),
    ExploreSub('Classical music', '古典音乐 classical music'),
    ExploreSub('Instruments', '乐器 演奏'),
    ExploreSub('Covers', '翻唱 cover'),
    ExploreSub('Dance', '舞蹈 dance'),
  ]),
  ExploreTopic('Film, TV & anime', AppIcons.filmSlateFill, '电影 动画', subs: [
    ExploreSub('Movies', '电影 movie'),
    ExploreSub('Film commentary', '电影解说 movie recap'),
    ExploreSub('TV series', '电视剧'),
    ExploreSub('US TV shows', '美剧 TV series'),
    ExploreSub('Korean & Japanese dramas', '韩剧 日剧'),
    ExploreSub('Animation', '动画 动漫 anime'),
    ExploreSub('Chinese animation', '国漫 国产动画'),
    ExploreSub('Comics', '漫画 manga'),
    ExploreSub('Film reviews', '影评'),
    ExploreSub('Trailers', '预告片 trailer'),
    ExploreSub('Behind the scenes', '幕后花絮 behind the scenes'),
  ]),
  ExploreTopic('News & current affairs', AppIcons.newspaper, '新闻', subs: [
    ExploreSub('World news', '国际新闻'),
    ExploreSub('Trending topics', '社会热点'),
    ExploreSub('Commentary', '时事评论'),
    ExploreSub('China news', '中国新闻'),
    ExploreSub('HK & Taiwan news', '香港 台湾 新闻'),
    ExploreSub('Politics', '政治 politics'),
    ExploreSub('War & conflict', '战争 冲突 conflict news'),
    ExploreSub('Investigative reporting', '调查报道 investigative journalism'),
    ExploreSub('News documentaries', '新闻纪录 news documentary'),
  ]),
  ExploreTopic('Podcast interviews', AppIcons.microphoneStage, '播客 访谈', subs: [
    ExploreSub('In-depth conversations', '深度对谈 podcast'),
    ExploreSub('Interviews', '人物专访 interview'),
    ExploreSub('Stand-up comedy', '脱口秀 talk show'),
    ExploreSub('Roundtable talk', '圆桌 讨论 roundtable'),
    ExploreSub('Book reviews', '读书 书评 book review'),
    ExploreSub('Business podcasts', '商业 播客 business podcast'),
    ExploreSub('Tech podcasts', '科技 播客 tech podcast'),
    ExploreSub('History & humanities', '历史 人文 播客 history podcast'),
    ExploreSub('Debate', '辩论 debate'),
  ]),
  ExploreTopic('Religion & faith', AppIcons.church, '宗教 信仰', opens: ExploreSection.faith),
  ExploreTopic('Science', AppIcons.flask, '科学', subs: [
    ExploreSub('Universe', '宇宙 天文'),
    ExploreSub('Physics', '物理'),
    ExploreSub('Biology', '生物'),
    ExploreSub('Chemistry', '化学 实验'),
    ExploreSub('Earth science', '地球科学 地质 气候'),
    ExploreSub('Engineering', '工程 engineering'),
    ExploreSub('Science experiments', '科学实验 experiment'),
    ExploreSub('Cutting-edge tech', '前沿科技 量子 quantum'),
    ExploreSub('Energy', '能源 核聚变 energy'),
    ExploreSub('Paleontology', '古生物 恐龙 paleontology'),
  ]),
  ExploreTopic('Finance & business', AppIcons.chartLine, '财经', subs: [
    ExploreSub('Financial news', '财经新闻 markets'),
    ExploreSub('Economics', '经济 分析'),
    ExploreSub('Stocks', '股票 美股 stock'),
    ExploreSub('Investing', '投资 理财'),
    ExploreSub('Personal finance', '个人理财 personal finance'),
    ExploreSub('Cryptocurrency', '加密货币 比特币 crypto'),
    ExploreSub('Real estate', '房地产 楼市'),
    ExploreSub('Business analysis', '商业分析 案例'),
    ExploreSub('Entrepreneurship', '创业'),
    ExploreSub('Marketing', '营销 品牌 marketing'),
  ]),
  ExploreTopic('Sports & fitness', AppIcons.soccerBall, '体育', subs: [
    ExploreSub('Football', '足球'),
    ExploreSub('Basketball', '篮球 NBA'),
    ExploreSub('Match highlights', '赛事集锦 highlights'),
    ExploreSub('Tennis', '网球 tennis'),
    ExploreSub('Table tennis badminton', '乒乓球 羽毛球'),
    ExploreSub('Baseball & football', '棒球 橄榄球 MLB NFL'),
    ExploreSub('Combat sports', '格斗 UFC 拳击'),
    ExploreSub('Motorsport', '赛车 F1'),
    ExploreSub('Fitness', '健身 训练 workout'),
    ExploreSub('Running', '跑步 马拉松 running'),
    ExploreSub('Extreme sports', '极限运动 滑雪 冲浪'),
  ]),
  ExploreTopic('Cars & transport', AppIcons.car, '汽车', subs: [
    ExploreSub('Car reviews', '汽车评测'),
    ExploreSub('Electric vehicles', '电动车 EV'),
    ExploreSub('Car buying guide', '购车 选车 buying guide'),
    ExploreSub('Supercars & luxury cars', '超跑 豪车 supercar'),
    ExploreSub('Modifications', '改装 tuning'),
    ExploreSub('Car repair', '汽车维修 保养 DIY'),
    ExploreSub('Motorcycles', '摩托车 motorcycle'),
    ExploreSub('Aviation', '航空 飞机'),
    ExploreSub('Railways', '铁路 火车'),
    ExploreSub('Urban transport', '地铁 公交 subway'),
    ExploreSub('Ships', '船舶 轮船 ship'),
  ]),
  ExploreTopic('Food & travel', AppIcons.forkKnife, '美食 旅行', subs: [
    ExploreSub('Cooking', '烹饪 做菜'),
    ExploreSub('Baking', '烘焙 baking'),
    ExploreSub('Shop visits', '探店 美食'),
    ExploreSub('Street food', '街头小吃 street food'),
    ExploreSub('World cuisine', '各国美食 food around the world'),
    ExploreSub('Coffee & tea', '咖啡 茶 coffee tea'),
    ExploreSub('Travel', '旅行 vlog'),
    ExploreSub('Travel guides', '旅行攻略 travel guide'),
    ExploreSub('Urban exploration', '城市漫步 walking tour'),
    ExploreSub('Road trips', '自驾游 road trip'),
    ExploreSub('Hotel reviews', '酒店 体验 hotel review'),
  ]),
  ExploreTopic('Entertainment & lifestyle', AppIcons.smiley, '生活 vlog', subs: [
    ExploreSub('Vlog', 'vlog 日常'),
    ExploreSub('Comedy', '搞笑'),
    ExploreSub('Variety shows', '综艺 variety show'),
    ExploreSub('Challenges', '挑战 challenge'),
    ExploreSub('Pets', '宠物 猫 狗'),
    ExploreSub('Celebrity entertainment', '明星 娱乐 celebrity'),
    ExploreSub('Fashion & beauty', '穿搭 美妆 fashion beauty'),
    ExploreSub('Home renovation', '家居 装修 home'),
    ExploreSub('Parenting', '育儿 亲子 parenting'),
    ExploreSub('Product recommendations', '好物分享 haul'),
    ExploreSub('Relationships & emotions', '情感 恋爱'),
  ]),
  ExploreTopic('Art & creativity', AppIcons.paintBrush, '艺术 创作', subs: [
    ExploreSub('Photography', '摄影 教程'),
    ExploreSub('Painting', '绘画 插画 drawing'),
    ExploreSub('Design', '设计 design'),
    ExploreSub('Video editing', '视频剪辑 Premiere'),
    ExploreSub('3D modeling', '3D 建模 Blender'),
    ExploreSub('Crafts', '手工 DIY'),
    ExploreSub('Woodworking', '木工 woodworking'),
    ExploreSub('Calligraphy', '书法 calligraphy'),
    ExploreSub('Architecture', '建筑 architecture'),
    ExploreSub('Art history', '艺术史 美术馆 museum'),
    ExploreSub('Writing', '写作 writing'),
  ]),
  ExploreTopic('Healthy living', AppIcons.heartFill, '健康', subs: [
    ExploreSub('Medical science', '医学科普'),
    ExploreSub('Psychology', '心理学 心理健康'),
    ExploreSub('Nutrition', '营养 饮食'),
    ExploreSub('Weight loss', '减肥 weight loss'),
    ExploreSub('Sleep', '睡眠 sleep'),
    ExploreSub('Traditional Chinese medicine', '中医 养生'),
    ExploreSub('Meditation', '冥想 正念 meditation'),
    ExploreSub('Disease prevention', '疾病 症状 预防'),
    ExploreSub('Rehab & physiotherapy', '康复 理疗 rehab'),
    ExploreSub('Lifestyle', '生活方式 lifestyle'),
  ]),
  ExploreTopic('Nature & outdoors', AppIcons.tree, '自然 纪录片', subs: [
    ExploreSub('Animals', '动物 纪录片'),
    ExploreSub('Ocean', '海洋 ocean'),
    ExploreSub('Ecology', '生态 环境'),
    ExploreSub('Scenery', '风光 4K nature scenery'),
    ExploreSub('Camping', '露营 camping'),
    ExploreSub('Hiking', '徒步 hiking'),
    ExploreSub('Mountaineering', '登山 mountaineering'),
    ExploreSub('Survival', '荒野求生 survival'),
    ExploreSub('Fishing', '钓鱼 fishing'),
    ExploreSub('Cycling', '骑行 cycling'),
    ExploreSub('Gardening', '园艺 gardening'),
    ExploreSub('Rural life', '田园 乡村 farm'),
  ]),
];

/// Live zones, streams that are on now; about 6-10 sub-categories each, as
/// fewer streams are on at a time.
const liveTopics = <ExploreTopic>[
  ExploreTopic('All', AppIcons.squaresFour, '', mix: true),
  ExploreTopic('Gaming live streams', AppIcons.gameController, '游戏 直播', subs: [
    ExploreSub("Let's plays", 'gameplay live'),
    ExploreSub('Single-player games', '单机游戏 直播'),
    ExploreSub('Online games', '网游 MMO 直播'),
    ExploreSub('Mobile games', '手游 直播'),
    ExploreSub('FPS shooter', 'FPS live Valorant CS2'),
    ExploreSub('MOBA', 'MOBA live LOL Dota'),
    ExploreSub('Minecraft', 'Minecraft live'),
    ExploreSub('Console gaming', 'console gaming live'),
    ExploreSub('Speedruns', 'speedrun live'),
  ]),
  ExploreTopic('Chat & interaction', AppIcons.chatsFill, '聊天 直播', subs: [
    ExploreSub('Chat', '聊天 直播 just chatting'),
    ExploreSub('Q&A', 'Q&A live'),
    ExploreSub('Talk shows', 'talk show live'),
    ExploreSub('Stand-up comedy', 'stand-up comedy live'),
    ExploreSub('Phone calls', 'call-in show live'),
    ExploreSub('Podcasts', 'podcast live'),
  ]),
  ExploreTopic('Live music', AppIcons.musicNoteFill, '音乐 直播', subs: [
    ExploreSub('Concerts', 'concert live'),
    ExploreSub('Music festivals', 'music festival live'),
    ExploreSub('Singing streams', '唱歌 直播 singing live'),
    ExploreSub('Instrumental performance', '乐器 直播'),
    ExploreSub('DJ', 'DJ set live'),
    ExploreSub('Classical concerts', 'classical concert live'),
    ExploreSub('Street performances', 'busking 街头艺人 live'),
    ExploreSub('Song requests', '点歌 直播'),
  ]),
  ExploreTopic('Esports', AppIcons.trophy, 'esports live', subs: [
    ExploreSub('Pro esports', '电竞 比赛 esports tournament live'),
    ExploreSub('Match commentary', '电竞 解说 直播'),
    ExploreSub('League of Legends', 'LoL Esports LCK LPL live'),
    ExploreSub('Valorant CS2', 'Valorant CS2 tournament live'),
    ExploreSub('Dota 2', 'Dota 2 tournament live'),
    ExploreSub('Fighting games', 'fighting game tournament EVO live'),
    ExploreSub('Mobile esports', '手游 电竞 比赛 live'),
  ]),
  ExploreTopic('Sports events', AppIcons.soccerBall, '体育 直播', subs: [
    ExploreSub('Live sports', 'sports live'),
    ExploreSub('Football', '足球 直播 football live'),
    ExploreSub('Basketball', '篮球 NBA live'),
    ExploreSub('Baseball', '棒球 MLB live'),
    ExploreSub('Tennis', '网球 tennis live'),
    ExploreSub('Motorsport', 'F1 racing live'),
    ExploreSub('Combat sports', 'UFC boxing live'),
    ExploreSub('Match commentary', '赛事 评论 直播'),
    ExploreSub('Pre-game shows', 'pre-game show live'),
  ]),
  ExploreTopic('On the scene', AppIcons.newspaper, 'news live', subs: [
    ExploreSub('Live news', '新闻 直播'),
    ExploreSub('World news', 'world news live'),
    ExploreSub('Major events', 'breaking news live'),
    ExploreSub('Politics & parliament', '议会 国会 parliament live'),
    ExploreSub('Financial markets', '财经 盘面 markets live'),
    ExploreSub('Launch events', '新闻发布会 直播'),
    ExploreSub('Weather disasters', 'weather severe live'),
  ]),
  ExploreTopic('VTubers', AppIcons.scanSmiley, 'vtuber', subs: [
    ExploreSub('VTuber', 'vtuber live'),
    ExploreSub('Hololive NIJISANJI', 'hololive nijisanji live'),
    ExploreSub('Chinese VTubers', '虚拟主播 直播'),
    ExploreSub('Singing streams', '歌回 vtuber singing'),
    ExploreSub('Gaming VTubers', 'vtuber gaming live'),
    ExploreSub('Virtual concerts', 'virtual concert live'),
    ExploreSub('Virtual radio', 'vtuber radio'),
  ]),
  ExploreTopic('Lifestyle & fashion', AppIcons.smiley, '生活 直播 lifestyle live', subs: [
    ExploreSub('Daily life', '日常 生活 直播 daily life live'),
    ExploreSub('Fashion & beauty', 'makeup fashion 穿搭 美妆 live'),
    ExploreSub('Home renovation', 'home decor 家居 live'),
    ExploreSub('Pets', 'pets 宠物 live'),
    ExploreSub('Vlogs', 'vlog live stream'),
    ExploreSub('Shopping', 'shopping haul live'),
  ]),
  ExploreTopic('Food & cooking', AppIcons.forkKnife, '美食 直播 cooking live', subs: [
    ExploreSub('Cooking', 'home cooking 家常菜 live'),
    ExploreSub('Baking', 'baking 烘焙 live'),
    ExploreSub('Restaurant kitchens', 'restaurant kitchen live'),
    ExploreSub('Street food', 'street food live'),
    ExploreSub('Mukbang', 'mukbang live'),
    ExploreSub('Coffee', 'coffee barista live'),
  ]),
  ExploreTopic('Art & creativity', AppIcons.paintBrush, '绘画 创作 直播 art live', subs: [
    ExploreSub('Painting', 'drawing painting 绘画 live'),
    ExploreSub('Design', 'design live'),
    ExploreSub('3D modeling', 'blender 3D modeling live'),
    ExploreSub('Crafts', 'crafts 手工 live'),
    ExploreSub('Music production', 'music production live'),
    ExploreSub('Woodworking', 'woodworking live'),
  ]),
  ExploreTopic('Study & work', AppIcons.bookOpenFill, 'study with me live', subs: [
    ExploreSub('Study with me', 'study with me live'),
    ExploreSub('Work-with-me streams', 'work with me pomodoro live'),
    ExploreSub('Coding streams', 'live coding'),
    ExploreSub('Online classes', '线上课堂 直播'),
    ExploreSub('Open courses', 'lecture 公开课 live'),
    ExploreSub('Language learning', 'language learning live'),
    ExploreSub('Creative process', 'drawing 绘画 创作 live'),
  ]),
  ExploreTopic('Tech & development', AppIcons.cpuFill, '科技 直播 tech live', subs: [
    ExploreSub('Product launches', 'launch event live'),
    ExploreSub('Developer conferences', 'developer conference keynote live'),
    ExploreSub('Trade shows', 'CES MWC expo live'),
    ExploreSub('AI conference', 'AI summit keynote live'),
    ExploreSub('Tech talks', 'tech talk live'),
    ExploreSub('Security conferences', 'security conference live'),
    ExploreSub('Unboxing & reviews', 'unboxing review live'),
    ExploreSub('Coding streams', 'live coding programming'),
    ExploreSub('Open source projects', 'open source development live'),
    ExploreSub('PC hardware', 'hardware build electronics live'),
  ]),
  ExploreTopic('Outdoor live', AppIcons.mountains, '户外 直播', subs: [
    ExploreSub('IRL streams', 'IRL stream'),
    ExploreSub('Travel live streams', 'travel live stream'),
    ExploreSub('Street walks', 'walking live'),
    ExploreSub('Hiking & mountaineering', 'hiking live'),
    ExploreSub('Camping', 'camping live'),
    ExploreSub('Fishing', 'fishing live'),
    ExploreSub('Cycling', 'cycling live'),
    ExploreSub('Festivals', 'festival parade live'),
  ]),
  ExploreTopic('Finance & business', AppIcons.chartLine, '财经 直播 finance live', subs: [
    ExploreSub('Financial markets', 'stock market 股市 live'),
    ExploreSub('Economics', 'economy analysis live'),
    ExploreSub('Interviews', 'business interview live'),
    ExploreSub('Live trading', 'day trading live'),
    ExploreSub('Investing', 'investing 投资 live'),
    ExploreSub('Entrepreneurship', 'startup entrepreneur live'),
  ]),
  ExploreTopic('Health & fitness', AppIcons.heartFill, '健身 直播 fitness live', subs: [
    ExploreSub('Fitness', 'workout 健身 live'),
    ExploreSub('Yoga & meditation', 'yoga live'),
    ExploreSub('Sports coaching', 'sports training coaching live'),
    ExploreSub('Health talks', 'health talk live'),
    ExploreSub('Running', 'running marathon live'),
    ExploreSub('Dance workouts', 'dance workout live'),
  ]),
  ExploreTopic('Religion & faith', AppIcons.church, '宗教 直播', opens: ExploreSection.faithLive),
  ExploreTopic('24/7 live', AppIcons.radio, '24/7 live', subs: [
    ExploreSub('Radio for sleep', 'lofi radio 24/7', subs: [
      ExploreSub('Lo-Fi', 'lofi hip hop radio'),
      ExploreSub('24/7 music', '24/7 music live'),
      ExploreSub('ASMR', 'ASMR live'),
      ExploreSub('White noise', 'white noise live'),
      ExploreSub('Rain sounds', 'rain sounds live'),
      ExploreSub('Sleep music', 'sleep music live'),
      ExploreSub('Jazz radio', 'jazz radio 24/7'),
      ExploreSub('Classical radio', 'classical music radio 24/7'),
      ExploreSub('Meditation music', 'meditation music live'),
    ]),
    ExploreSub('Nature footage', 'live cam 24/7', subs: [
      ExploreSub('Animal watching', 'animal live cam'),
      ExploreSub('Space live streams', 'space live ISS'),
      ExploreSub('City cams', 'city live cam'),
      ExploreSub('Birds', 'bird feeder live cam'),
      ExploreSub('Marine aquariums', 'aquarium ocean live cam'),
      ExploreSub('Railways', 'train cam railway live'),
      ExploreSub('Ports & ships', 'harbor ship cam live'),
      ExploreSub('Landscapes', 'scenic live cam 4K'),
      ExploreSub('Volcanoes & weather', 'volcano weather live cam'),
    ]),
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
  curated('Selected', live: false),
  forYou('For you', live: false),
  popular('Popular', live: false),
  latest('Latest', live: false),
  gems('Hidden gems', live: false),
  fresh('New creators', live: false),
  long('Long videos', live: false),
  liveViewers('Most watched', live: true),
  liveLatest('Just started', live: true),
  liveUpcoming('Upcoming', live: true),
  liveReplay('Replays', live: true);

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

  /// Whether the list shows the most watched first: by views, or by
  /// people watching now for streams.
  bool get byViews => this == popular || this == long || this == liveViewers;
}

/// 冷门宝藏: videos of at least four minutes with at most this many views.
const gemMaxViews = 50000;

/// 新人新作: this week's videos of at least a minute with at most this many
/// views, from channels not followed or watched.
const freshMaxViews = 5000;

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
      ExploreMode.fresh => searchParams(type: SearchFilter.videos, date: SearchUploadDate.week, duration: duration, quality: quality)!,
      ExploreMode.long => searchParams(type: SearchFilter.videos, sort: SearchSort.views, date: SearchUploadDate.year, duration: SearchDuration.long, quality: quality)!,
      ExploreMode.liveViewers => searchParams(type: SearchFilter.live, sort: SearchSort.views, quality: quality)!,
      ExploreMode.liveLatest => searchParams(type: SearchFilter.live, sort: SearchSort.date, quality: quality)!,
      ExploreMode.liveUpcoming || ExploreMode.liveReplay => searchParams(type: SearchFilter.videos, sort: SearchSort.date, quality: quality)!,
    };
