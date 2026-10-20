import 'package:flutter/widgets.dart' show IconData;
import 'package:flutter/material.dart' show Icons;

import 'search_options.dart';
import 'video_repository.dart';

/// The two halves of the explore page.
enum ExploreSection {
  popular('热门'),
  live('直播');

  const ExploreSection(this.label);
  final String label;
}

/// One explore category: what it is called and the search behind it.
class ExploreTopic {
  const ExploreTopic(this.label, this.icon, this.query, {this.custom = false});
  final String label;
  final IconData icon;
  final String query;
  /// Added by the user; it can be removed.
  final bool custom;
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

/// Categories of popular videos, each searched for the most viewed in the
/// chosen period.
const popularTopics = <ExploreTopic>[
  ExploreTopic('音乐', Icons.music_note_rounded, '音乐'),
  ExploreTopic('游戏', Icons.sports_esports_rounded, '游戏'),
  ExploreTopic('动画', Icons.animation_rounded, '动画'),
  ExploreTopic('影视', Icons.movie_rounded, '电影 预告片'),
  ExploreTopic('电视剧', Icons.live_tv_rounded, '电视剧'),
  ExploreTopic('综艺', Icons.celebration_rounded, '综艺'),
  ExploreTopic('科技', Icons.memory_rounded, '科技 数码'),
  ExploreTopic('知识', Icons.lightbulb_outline_rounded, '科普'),
  ExploreTopic('教育', Icons.school_rounded, '教程 学习'),
  ExploreTopic('编程', Icons.code_rounded, '编程'),
  ExploreTopic('历史', Icons.history_edu_rounded, '历史'),
  ExploreTopic('人文', Icons.public_rounded, '人文 纪录片'),
  ExploreTopic('心理', Icons.psychology_rounded, '心理学'),
  ExploreTopic('财经', Icons.show_chart_rounded, '财经'),
  ExploreTopic('军事', Icons.military_tech_rounded, '军事'),
  ExploreTopic('天文', Icons.nights_stay_rounded, '天文 宇宙'),
  ExploreTopic('自然', Icons.park_rounded, '自然 纪录片'),
  ExploreTopic('语言', Icons.translate_rounded, '英语 学习'),
  ExploreTopic('读书', Icons.menu_book_rounded, '读书 书评'),
  ExploreTopic('宗教', Icons.self_improvement_rounded, '宗教 信仰'),
  ExploreTopic('天主教', Icons.church_rounded, '天主教'),
  ExploreTopic('圣经', Icons.auto_stories_rounded, '圣经 讲解'),
  ExploreTopic('圣歌', Icons.queue_music_rounded, '天主教 圣歌'),
  ExploreTopic('佛教', Icons.temple_buddhist_rounded, '佛教 佛法'),
  ExploreTopic('新闻', Icons.newspaper_rounded, '新闻'),
  ExploreTopic('体育', Icons.sports_soccer_rounded, '体育'),
  ExploreTopic('汽车', Icons.directions_car_rounded, '汽车 评测'),
  ExploreTopic('美食', Icons.restaurant_rounded, '美食'),
  ExploreTopic('旅行', Icons.flight_rounded, '旅行 vlog'),
  ExploreTopic('时尚美妆', Icons.checkroom_rounded, '美妆 穿搭'),
  ExploreTopic('健身', Icons.fitness_center_rounded, '健身'),
  ExploreTopic('宠物', Icons.pets_rounded, '宠物 猫 狗'),
  ExploreTopic('摄影', Icons.photo_camera_rounded, '摄影 教程'),
  ExploreTopic('绘画', Icons.brush_rounded, '绘画'),
  ExploreTopic('手工', Icons.handyman_rounded, '手工 DIY'),
  ExploreTopic('家居', Icons.chair_rounded, '家居 装修'),
  ExploreTopic('育儿', Icons.child_care_rounded, '育儿'),
  ExploreTopic('舞蹈', Icons.nightlife_rounded, '舞蹈'),
  ExploreTopic('乐器', Icons.piano_rounded, '乐器 演奏'),
  ExploreTopic('搞笑', Icons.sentiment_very_satisfied_rounded, '搞笑'),
  ExploreTopic('播客', Icons.podcasts_rounded, '播客 podcast'),
  ExploreTopic('ASMR', Icons.headphones_rounded, 'ASMR'),
];

/// Categories of streams that are live now, most watched first.
const liveTopics = <ExploreTopic>[
  ExploreTopic('全部', Icons.sensors_rounded, '直播 live'),
  ExploreTopic('游戏', Icons.sports_esports_rounded, '游戏 直播'),
  ExploreTopic('电竞', Icons.emoji_events_rounded, 'esports live'),
  ExploreTopic('音乐', Icons.music_note_rounded, '音乐 直播'),
  ExploreTopic('电台', Icons.radio_rounded, 'lofi radio 24/7'),
  ExploreTopic('聊天', Icons.forum_rounded, '聊天 直播'),
  ExploreTopic('虚拟主播', Icons.face_retouching_natural_rounded, 'vtuber'),
  ExploreTopic('新闻', Icons.newspaper_rounded, 'news live'),
  ExploreTopic('弥撒', Icons.church_rounded, 'Holy Mass live 弥撒'),
  ExploreTopic('玫瑰经', Icons.brightness_7_rounded, 'rosary live 玫瑰经'),
  ExploreTopic('梵蒂冈', Icons.account_balance_rounded, 'Vatican live'),
  ExploreTopic('祈祷', Icons.self_improvement_rounded, 'prayer live 祈祷'),
  ExploreTopic('体育', Icons.sports_soccer_rounded, '体育 直播'),
  ExploreTopic('科技', Icons.memory_rounded, '科技 发布会 直播'),
  ExploreTopic('学习', Icons.menu_book_rounded, 'study with me live'),
  ExploreTopic('户外', Icons.landscape_rounded, '户外 直播'),
  ExploreTopic('风景', Icons.videocam_rounded, 'live cam 24/7'),
  ExploreTopic('太空', Icons.rocket_launch_rounded, 'space live'),
  ExploreTopic('动物', Icons.pets_rounded, 'animal live cam'),
  ExploreTopic('美食', Icons.restaurant_rounded, '美食 直播'),
  ExploreTopic('购物', Icons.shopping_bag_rounded, '带货 直播'),
];

/// The built-in categories of [section], then the user's own.
List<ExploreTopic> exploreTopicsOf(ExploreSection section, [List<CustomTopic> custom = const []]) => [
      ...switch (section) {
        ExploreSection.popular => popularTopics,
        ExploreSection.live => liveTopics,
      },
      for (final topic in custom)
        if (topic.section == section) topic.topic,
    ];

/// The periods popular videos can be counted over.
const explorePeriods = [SearchUploadDate.today, SearchUploadDate.week, SearchUploadDate.month, SearchUploadDate.year];

/// YouTube's `sp` for a topic: the most viewed of [period], or live
/// streams with the most viewers.
String exploreParams(ExploreSection section, SearchUploadDate period) => switch (section) {
      ExploreSection.popular => searchParams(type: SearchFilter.videos, sort: SearchSort.views, date: period)!,
      ExploreSection.live => searchParams(type: SearchFilter.live, sort: SearchSort.views)!,
    };
