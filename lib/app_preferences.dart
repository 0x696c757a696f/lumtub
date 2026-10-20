import 'dart:convert';
import 'dart:io';

import 'app_directories.dart';
import 'blocked_groups.dart';
import 'state_media.dart';
import 'explore_filters.dart';
import 'explore_topics.dart';
import 'models.dart';
import 'l10n/l10n.dart';

/// Pages the app can open on start, in navigation order.
final startPages = [('home', tr('首页')), ('explore', tr('探索')), ('subscriptions', tr('订阅')), ('history', tr('历史')), ('playlists', tr('播放列表'))];

/// Behaviour and content preferences that are neither player options nor
/// looks: privacy, filters, start page and how the watch page behaves.
class AppPreferences {
  const AppPreferences({
    this.recordHistory = true,
    this.recordProgress = true,
    this.blockedChannels = const [],
    this.blockedKeywords = const [],
    this.unrecommendedChannels = const [],
    this.exploreCustomTopics = const [],
    this.exploreOrder = const {},
    this.exploreHidden = const {},
    this.exploreRegion = ExploreRegion.any,
    this.exploreLanguage = ExploreLanguage.any,
    this.hideShorts = false,
    this.minDurationMinutes = 0,
    this.hideWatched = false,
    this.blockGroups = true,
    this.allowedGroups = const [],
    this.blockStateMedia = false,
    this.allowedMedia = const [],
    this.enabledGroups = const [],
    this.allowedEntries = const [],
    this.blockedChannelNames = const [],
    this.filterSubscriptions = true,
    this.homeShowContinue = true,
    this.homeShowRecent = true,
    this.homeShowRecommended = true,
    this.syncFollowToYoutube = true,
    this.startPage = 'home',
    this.feedAutoRefresh = true,
    this.feedRefreshMinutes = 10,
    this.autoPlay = true,
    this.resumePlayback = true,
    this.autoFullscreen = false,
    this.exitFullscreenOnEnd = false,
    this.pauseOnMinimize = false,
    this.keyboardShortcuts = true,
    this.seekSeconds = 5,
    this.longSeekSeconds = 10,
    this.volumeStep = 5,
    this.controlsHideSeconds = 3,
    this.showRelated = true,
    this.expandDescription = false,
    this.autoCheckUpdates = true,
  });

  final bool recordHistory;
  final bool recordProgress;
  final List<ChannelRef> blockedChannels;
  /// Case-insensitive words; a video whose title contains one is hidden.
  final List<String> blockedKeywords;
  /// Channels left out of recommendations, explore and related videos, but
  /// still found by a search and shown when followed.
  final List<ChannelRef> unrecommendedChannels;
  /// Explore categories the user added.
  final List<CustomTopic> exploreCustomTopics;
  /// Per explore half ([ExploreSection.name]), zone keys in the user's
  /// order, the pinned ones first.
  final Map<String, List<String>> exploreOrder;
  /// Explore's 地区 and 语言, kept between runs.
  final ExploreRegion exploreRegion;
  final ExploreLanguage exploreLanguage;
  /// Per explore half, the zone keys the user hid.
  final Map<String, List<String>> exploreHidden;
  /// Hides videos of a minute or less, which YouTube lists as Shorts.
  final bool hideShorts;
  final int minDurationMinutes;
  final bool hideWatched;
  /// Hides the groups in blocked_groups.dart from recommendations, explore
  /// and search, unless a search names the channel exactly.
  final bool blockGroups;
  /// [BlockedGroup.name]s the user unticked, so they show.
  final List<String> allowedGroups;
  /// Hides the propaganda channels in state_media.dart the same way, off by
  /// default.
  final bool blockStateMedia;
  /// state_media.dart group names the user unticked.
  final List<String> allowedMedia;
  /// Groups of either list that start unticked and the user ticked.
  final List<String> enabledGroups;
  /// [BlockEntry.key]s the user unticked inside a ticked group.
  final List<String> allowedEntries;
  /// Channels the user typed in by name; a video whose channel is called
  /// exactly this, apart from letter case, is hidden like a blocked one.
  final List<String> blockedChannelNames;
  /// Whether the filters also apply to the subscriptions feed.
  final bool filterSubscriptions;
  final bool homeShowContinue;
  final bool homeShowRecent;
  /// 为你推荐, worked out on this computer from the history.
  final bool homeShowRecommended;
  /// 关注 also subscribes on YouTube when signed in.
  final bool syncFollowToYoutube;
  final String startPage;
  final bool feedAutoRefresh;
  final int feedRefreshMinutes;
  /// Start playing as soon as a video opens.
  final bool autoPlay;
  final bool resumePlayback;
  final bool autoFullscreen;
  final bool exitFullscreenOnEnd;
  final bool pauseOnMinimize;
  final bool keyboardShortcuts;
  final int seekSeconds;
  final int longSeekSeconds;
  final int volumeStep;
  final int controlsHideSeconds;
  final bool showRelated;
  final bool expandDescription;
  final bool autoCheckUpdates;

  bool isBlocked(String? channelId) => channelId != null && blockedChannels.any((c) => c.id == channelId);

  bool isUnrecommended(String? channelId) => channelId != null && unrecommendedChannels.any((c) => c.id == channelId);

  /// Whether a channel called [name] was blocked by name.
  bool isBlockedName(String name) => blockedChannelNames.any((n) => n.trim().toLowerCase() == name.trim().toLowerCase());

  /// Whether a channel called [name], with [id] or [handle] if known, is
  /// one the user blocks by group or as state media.
  bool blocksChannel(String name, {String? id, String? handle}) =>
      (blockGroups && _matchers.groups.channel(name, id: id, handle: handle)) || blocksMediaChannel(name);

  /// Whether [group] of either list is ticked.
  bool groupOn(BlockedGroup group, {bool media = false}) =>
      group.onByDefault ? !(media ? allowedMedia : allowedGroups).contains(group.name) : enabledGroups.contains(group.name);

  ({BlockMatcher groups, BlockMatcher media}) get _matchers => _matcherCache[this] ??= (
        groups: BlockMatcher([for (final g in blockedGroups) if (groupOn(g)) g], allowedEntries: allowedEntries.toSet()),
        media: BlockMatcher([for (final g in stateMedia) if (groupOn(g, media: true)) g], allowedEntries: allowedEntries.toSet()),
      );
  static final _matcherCache = Expando<({BlockMatcher groups, BlockMatcher media})>();

  /// Whether a channel called [name] is state media the user blocks.
  bool blocksMediaChannel(String name) => blockStateMedia && _matchers.media.channel(name);

  /// Whether [item] comes from a channel the user blocks as a group or state
  /// media. Its title and description are never looked at. Remembered per
  /// channel for these preferences: lists are filtered again on every
  /// rebuild, and the block lists run to hundreds of names.
  bool blocksGroup(VideoItem item) {
    final memo = _blockMemo[this] ??= <String, bool>{};
    if (memo.length > 20000) memo.clear();
    return memo['${item.channelId}
${item.channel}'] ??= blocksChannel(item.channel, id: item.channelId);
  }

  static final _blockMemo = Expando<Map<String, bool>>();

  /// Whether a comment by [author] (a name or @handle) with channel [id] is
  /// by a channel the user blocks. Its text is never looked at.
  bool blocksCommenter(String author, String? id) =>
      isBlocked(id) || isBlockedName(author) || blocksChannel(author, id: id, handle: author.startsWith('@') ? author : null);

  /// Whether [item] passes the privacy and content filters. [watched] says
  /// whether it was watched to the end.
  bool shows(VideoItem item, {bool watched = false}) {
    if (isBlocked(item.channelId) || isBlockedName(item.channel)) return false;
    if (blockedChannels.isNotEmpty && item.channelId == null && blockedChannels.any((c) => c.name.isNotEmpty && c.name == item.channel)) return false;
    final title = item.title.toLowerCase();
    if (blockedKeywords.any((word) => title.contains(word.toLowerCase()))) return false;
    final duration = item.duration;
    if (hideShorts && (item.url.contains('/shorts/') || (duration != null && duration > 0 && duration <= 60))) return false;
    if (minDurationMinutes > 0 && duration != null && duration > 0 && duration < minDurationMinutes * 60) return false;
    if (hideWatched && watched) return false;
    return true;
  }

  AppPreferences copyWith({
    bool? recordHistory,
    bool? recordProgress,
    List<ChannelRef>? blockedChannels,
    List<String>? blockedKeywords,
    List<ChannelRef>? unrecommendedChannels,
    List<CustomTopic>? exploreCustomTopics,
    Map<String, List<String>>? exploreOrder,
    Map<String, List<String>>? exploreHidden,
    ExploreRegion? exploreRegion,
    ExploreLanguage? exploreLanguage,
    bool? hideShorts,
    int? minDurationMinutes,
    bool? hideWatched,
    bool? blockGroups,
    List<String>? allowedGroups,
    bool? blockStateMedia,
    List<String>? allowedMedia,
    List<String>? enabledGroups,
    List<String>? allowedEntries,
    List<String>? blockedChannelNames,
    bool? filterSubscriptions,
    bool? homeShowContinue,
    bool? homeShowRecent,
    bool? homeShowRecommended,
    bool? syncFollowToYoutube,
    String? startPage,
    bool? feedAutoRefresh,
    int? feedRefreshMinutes,
    bool? autoPlay,
    bool? resumePlayback,
    bool? autoFullscreen,
    bool? exitFullscreenOnEnd,
    bool? pauseOnMinimize,
    bool? keyboardShortcuts,
    int? seekSeconds,
    int? longSeekSeconds,
    int? volumeStep,
    int? controlsHideSeconds,
    bool? showRelated,
    bool? expandDescription,
    bool? autoCheckUpdates,
  }) =>
      AppPreferences(
        recordHistory: recordHistory ?? this.recordHistory,
        recordProgress: recordProgress ?? this.recordProgress,
        blockedChannels: blockedChannels ?? this.blockedChannels,
        blockedKeywords: blockedKeywords ?? this.blockedKeywords,
        unrecommendedChannels: unrecommendedChannels ?? this.unrecommendedChannels,
        exploreCustomTopics: exploreCustomTopics ?? this.exploreCustomTopics,
        exploreOrder: exploreOrder ?? this.exploreOrder,
        exploreHidden: exploreHidden ?? this.exploreHidden,
        exploreRegion: exploreRegion ?? this.exploreRegion,
        exploreLanguage: exploreLanguage ?? this.exploreLanguage,
        hideShorts: hideShorts ?? this.hideShorts,
        minDurationMinutes: minDurationMinutes ?? this.minDurationMinutes,
        hideWatched: hideWatched ?? this.hideWatched,
        blockGroups: blockGroups ?? this.blockGroups,
        allowedGroups: allowedGroups ?? this.allowedGroups,
        blockStateMedia: blockStateMedia ?? this.blockStateMedia,
        allowedMedia: allowedMedia ?? this.allowedMedia,
        enabledGroups: enabledGroups ?? this.enabledGroups,
        allowedEntries: allowedEntries ?? this.allowedEntries,
        blockedChannelNames: blockedChannelNames ?? this.blockedChannelNames,
        filterSubscriptions: filterSubscriptions ?? this.filterSubscriptions,
        homeShowContinue: homeShowContinue ?? this.homeShowContinue,
        homeShowRecent: homeShowRecent ?? this.homeShowRecent,
        homeShowRecommended: homeShowRecommended ?? this.homeShowRecommended,
        syncFollowToYoutube: syncFollowToYoutube ?? this.syncFollowToYoutube,
        startPage: startPage ?? this.startPage,
        feedAutoRefresh: feedAutoRefresh ?? this.feedAutoRefresh,
        feedRefreshMinutes: feedRefreshMinutes ?? this.feedRefreshMinutes,
        autoPlay: autoPlay ?? this.autoPlay,
        resumePlayback: resumePlayback ?? this.resumePlayback,
        autoFullscreen: autoFullscreen ?? this.autoFullscreen,
        exitFullscreenOnEnd: exitFullscreenOnEnd ?? this.exitFullscreenOnEnd,
        pauseOnMinimize: pauseOnMinimize ?? this.pauseOnMinimize,
        keyboardShortcuts: keyboardShortcuts ?? this.keyboardShortcuts,
        seekSeconds: seekSeconds ?? this.seekSeconds,
        longSeekSeconds: longSeekSeconds ?? this.longSeekSeconds,
        volumeStep: volumeStep ?? this.volumeStep,
        controlsHideSeconds: controlsHideSeconds ?? this.controlsHideSeconds,
        showRelated: showRelated ?? this.showRelated,
        expandDescription: expandDescription ?? this.expandDescription,
        autoCheckUpdates: autoCheckUpdates ?? this.autoCheckUpdates,
      );

  Map<String, dynamic> toJson() => {
        'recordHistory': recordHistory,
        'recordProgress': recordProgress,
        'blockedChannels': [for (final c in blockedChannels) {'id': c.id, 'name': c.name}],
        'blockedKeywords': blockedKeywords,
        'unrecommendedChannels': [for (final c in unrecommendedChannels) {'id': c.id, 'name': c.name}],
        'exploreCustomTopics': [for (final t in exploreCustomTopics) t.toJson()],
        'exploreOrder': exploreOrder,
        'exploreHidden': exploreHidden,
        'exploreRegion': exploreRegion.name,
        'exploreLanguage': exploreLanguage.name,
        'hideShorts': hideShorts,
        'minDurationMinutes': minDurationMinutes,
        'hideWatched': hideWatched,
        'blockGroups': blockGroups,
        'allowedGroups': allowedGroups,
        'blockStateMedia': blockStateMedia,
        'allowedMedia': allowedMedia,
        'enabledGroups': enabledGroups,
        'allowedEntries': allowedEntries,
        'blockedChannelNames': blockedChannelNames,
        'filterSubscriptions': filterSubscriptions,
        'homeShowContinue': homeShowContinue,
        'homeShowRecent': homeShowRecent,
        'homeShowRecommended': homeShowRecommended,
        'syncFollowToYoutube': syncFollowToYoutube,
        'startPage': startPage,
        'feedAutoRefresh': feedAutoRefresh,
        'feedRefreshMinutes': feedRefreshMinutes,
        'autoPlay': autoPlay,
        'resumePlayback': resumePlayback,
        'autoFullscreen': autoFullscreen,
        'exitFullscreenOnEnd': exitFullscreenOnEnd,
        'pauseOnMinimize': pauseOnMinimize,
        'keyboardShortcuts': keyboardShortcuts,
        'seekSeconds': seekSeconds,
        'longSeekSeconds': longSeekSeconds,
        'volumeStep': volumeStep,
        'controlsHideSeconds': controlsHideSeconds,
        'showRelated': showRelated,
        'expandDescription': expandDescription,
        'autoCheckUpdates': autoCheckUpdates,
      };

  factory AppPreferences.fromJson(Object? raw) {
    if (raw is! Map) return const AppPreferences();
    const d = AppPreferences();
    bool flag(String key, bool fallback) => raw[key] is bool ? raw[key] as bool : fallback;
    int number(String key, int fallback, int min, int max) {
      final value = raw[key];
      return value is num ? value.toInt().clamp(min, max) : fallback;
    }
    List<ChannelRef> channelList(String key) {
      final channels = <ChannelRef>[];
      if (raw[key] is List) {
        for (final entry in raw[key] as List) {
          if (entry is! Map) continue;
          final id = entry['id']?.toString() ?? '';
          if (ChannelRef.isValidId(id) && !channels.any((c) => c.id == id)) channels.add(ChannelRef(id, entry['name']?.toString() ?? ''));
        }
      }
      return channels;
    }
    List<String> strings(String key, [List<String> fallback = const []]) => raw[key] is List
        ? (raw[key] as List).map((k) => k.toString().trim()).where((k) => k.isNotEmpty).toSet().toList()
        : fallback;
    final topics = raw['exploreCustomTopics'] is List
        ? (raw['exploreCustomTopics'] as List).map(CustomTopic.fromJson).whereType<CustomTopic>().toList()
        : const <CustomTopic>[];
    Map<String, List<String>> keyLists(String key) {
      final value = raw[key];
      if (value is! Map) return const {};
      return {
        for (final entry in value.entries)
          if (entry.value is List) '${entry.key}': [for (final k in entry.value as List) '$k'],
      };
    }
    final start = raw['startPage']?.toString();
    return AppPreferences(
      recordHistory: flag('recordHistory', d.recordHistory),
      recordProgress: flag('recordProgress', d.recordProgress),
      blockedChannels: channelList('blockedChannels'),
      blockedKeywords: strings('blockedKeywords'),
      unrecommendedChannels: channelList('unrecommendedChannels'),
      allowedGroups: strings('allowedGroups'),
      allowedMedia: strings('allowedMedia'),
      enabledGroups: strings('enabledGroups'),
      allowedEntries: strings('allowedEntries'),
      blockedChannelNames: strings('blockedChannelNames'),
      exploreCustomTopics: topics,
      exploreOrder: keyLists('exploreOrder'),
      exploreHidden: keyLists('exploreHidden'),
      exploreRegion: ExploreRegion.parse(raw['exploreRegion']),
      exploreLanguage: ExploreLanguage.parse(raw['exploreLanguage']),
      hideShorts: flag('hideShorts', d.hideShorts),
      minDurationMinutes: number('minDurationMinutes', 0, 0, 120),
      hideWatched: flag('hideWatched', d.hideWatched),
      blockGroups: flag('blockGroups', d.blockGroups),
      blockStateMedia: flag('blockStateMedia', d.blockStateMedia),
      filterSubscriptions: flag('filterSubscriptions', d.filterSubscriptions),
      homeShowContinue: flag('homeShowContinue', d.homeShowContinue),
      homeShowRecent: flag('homeShowRecent', d.homeShowRecent),
      homeShowRecommended: flag('homeShowRecommended', d.homeShowRecommended),
      syncFollowToYoutube: flag('syncFollowToYoutube', d.syncFollowToYoutube),
      startPage: startPages.any((p) => p.$1 == start) ? start! : 'home',
      feedAutoRefresh: flag('feedAutoRefresh', d.feedAutoRefresh),
      feedRefreshMinutes: number('feedRefreshMinutes', 10, 1, 1440),
      autoPlay: flag('autoPlay', d.autoPlay),
      resumePlayback: flag('resumePlayback', d.resumePlayback),
      autoFullscreen: flag('autoFullscreen', d.autoFullscreen),
      exitFullscreenOnEnd: flag('exitFullscreenOnEnd', d.exitFullscreenOnEnd),
      pauseOnMinimize: flag('pauseOnMinimize', d.pauseOnMinimize),
      keyboardShortcuts: flag('keyboardShortcuts', d.keyboardShortcuts),
      seekSeconds: number('seekSeconds', 5, 1, 60),
      longSeekSeconds: number('longSeekSeconds', 10, 1, 120),
      volumeStep: number('volumeStep', 5, 1, 25),
      controlsHideSeconds: number('controlsHideSeconds', 3, 1, 30),
      showRelated: flag('showRelated', d.showRelated),
      expandDescription: flag('expandDescription', d.expandDescription),
      autoCheckUpdates: flag('autoCheckUpdates', d.autoCheckUpdates),
    );
  }
}

class AppPreferencesStore {
  AppPreferencesStore(AppDirectories directories) : file = File('${directories.config.path}${Platform.pathSeparator}preferences.json');
  final File file;

  Future<AppPreferences> load() async {
    try {
      return AppPreferences.fromJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      return const AppPreferences();
    }
  }

  Future<void> save(AppPreferences preferences) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(preferences.toJson()), flush: true);
  }
}
