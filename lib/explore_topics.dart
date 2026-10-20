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
  const ExploreTopic(this.label, this.icon, this.query);
  final String label;
  final IconData icon;
  final String query;
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
  ExploreTopic('新闻', Icons.newspaper_rounded, '新闻'),
  ExploreTopic('体育', Icons.sports_soccer_rounded, '体育'),
  ExploreTopic('汽车', Icons.directions_car_rounded, '汽车 评测'),
  ExploreTopic('美食', Icons.restaurant_rounded, '美食'),
  ExploreTopic('旅行', Icons.flight_rounded, '旅行 vlog'),
  ExploreTopic('时尚美妆', Icons.checkroom_rounded, '美妆 穿搭'),
  ExploreTopic('健身', Icons.fitness_center_rounded, '健身'),
  ExploreTopic('宠物', Icons.pets_rounded, '宠物 猫 狗'),
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

List<ExploreTopic> exploreTopicsOf(ExploreSection section) => switch (section) {
      ExploreSection.popular => popularTopics,
      ExploreSection.live => liveTopics,
    };

/// The periods popular videos can be counted over.
const explorePeriods = [SearchUploadDate.today, SearchUploadDate.week, SearchUploadDate.month, SearchUploadDate.year];

/// YouTube's `sp` for a topic: the most viewed of [period], or live
/// streams with the most viewers.
String exploreParams(ExploreSection section, SearchUploadDate period) => switch (section) {
      ExploreSection.popular => searchParams(type: SearchFilter.videos, sort: SearchSort.views, date: period)!,
      ExploreSection.live => searchParams(type: SearchFilter.live, sort: SearchSort.views)!,
    };
