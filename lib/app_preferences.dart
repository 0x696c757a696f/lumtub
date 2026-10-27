import 'dart:convert';
import 'dart:io';

import 'app_directories.dart';
import 'blocked_groups.dart';
import 'state_media.dart';
import 'explore_filters.dart';
import 'feed_quality.dart';
import 'explore_topics.dart';
import 'models.dart';
import 'player_settings.dart' show SubtitleLanguage;
import 'progress_line.dart';
import 'translation.dart';
import 'translation_services.dart';
import 'l10n/l10n.dart';

/// Pages the app can open on start, in navigation order.
///
/// This must be evaluated after the selected language is loaded, instead of
/// once during library initialization.
List<(String, String)> get startPages => [
      ('home', tr('首页')),
      ('explore', tr('探索')),
      ('subscriptions', tr('订阅')),
      ('history', tr('历史')),
      ('playlists', tr('播放列表')),
    ];

/// Behaviour and content preferences that are neither player options nor
/// looks: privacy, filters, start page and how the watch page behaves.
/// What 字幕列表 lists while a first and a second subtitle are on.
enum SubtitleListMode {
  firstOver('双语，第一字幕在上'),
  secondOver('双语，第二字幕在上'),
  first('只看第一字幕'),
  second('只看第二字幕');

  const SubtitleListMode(this._label);
  final String _label;
  String get label => tr(_label);
}

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
    this.homeAutoRefresh = true,
    this.feedShorts = FeedLevel.reduce,
    this.feedVertical = FeedLevel.reduce,
    this.syncFollowToYoutube = true,
    this.startPage = 'home',
    this.feedAutoRefresh = true,
    this.feedRefreshMinutes = 10,
    this.autoPlay = true,
    this.resumePlayback = true,
    this.watchLaterAutoRemove = true,
    this.autoFullscreen = false,
    this.autoLightsOff = false,
    this.lightsOffDim = 85,
    this.miniPlayer = true,
    this.exitFullscreenOnEnd = false,
    this.pauseOnMinimize = false,
    this.audioOnlyInBackground = false,
    this.closeToTray = false,
    this.keyboardShortcuts = true,
    this.seekSeconds = 5,
    this.longSeekSeconds = 10,
    this.volumeStep = 5,
    this.controlsHideSeconds = 3,
    this.showHeatmap = true,
    this.progressLine = ProgressLine.always,
    this.showRelated = true,
    this.expandDescription = false,
    this.autoCheckUpdates = true,
    this.autoUpdateApp = true,
    this.skipFfmpegPrompt = false,
    this.translateLanguage = '',
    this.translation = const TranslationConfig(),
    this.subtitlesByService = false,
    this.bilingualTranslation = true,
    this.translationStyle = TranslationStyle.quote,
    this.translationFirst = false,
    this.subtitleListMode = SubtitleListMode.firstOver,
    this.skipSameLanguage = true,
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
  /// Whether 为你推荐 is gathered again at launch and once it is half an
  /// hour old; off, the last list stays until refreshed by hand.
  final bool homeAutoRefresh;
  /// How much For You shows Shorts and vertical videos.
  final FeedLevel feedShorts;
  final FeedLevel feedVertical;
  FeedMix get feedMix => FeedMix(shorts: feedShorts, vertical: feedVertical);
  /// 关注 also subscribes on YouTube when signed in.
  final bool syncFollowToYoutube;
  final String startPage;
  final bool feedAutoRefresh;
  final int feedRefreshMinutes;
  /// Start playing as soon as a video opens.
  final bool autoPlay;
  final bool resumePlayback;
  /// Take a video off 稍后观看 once it was played to the end.
  final bool watchLaterAutoRemove;
  final bool autoFullscreen;
  /// 关灯 while the video plays, lights on when it pauses.
  final bool autoLightsOff;
  /// How dark 关灯 makes the rest of the window, in percent.
  final int lightsOffDim;
  /// Leaving the watch page keeps the video in the in-app mini player
  /// (ui/mini_player.dart) instead of stopping it.
  final bool miniPlayer;
  final bool exitFullscreenOnEnd;
  final bool pauseOnMinimize;
  /// Minimised or hidden to the tray, mpv decodes no picture.
  final bool audioOnlyInBackground;
  /// Closing the window hides it to the tray icon instead of exiting.
  final bool closeToTray;
  final bool keyboardShortcuts;
  final int seekSeconds;
  final int longSeekSeconds;
  final int volumeStep;
  final int controlsHideSeconds;
  /// The 最多重放 curve above the progress bar.
  final bool showHeatmap;
  /// The thin line along the bottom of the video while the controls hide.
  final ProgressLine progressLine;
  final bool showRelated;
  final bool expandDescription;
  final bool autoCheckUpdates;
  /// Download new Lumtub versions in the background and install them when
  /// Lumtub closes.
  final bool autoUpdateApp;
  /// The user chose single-file downloads and not to be asked to install ffmpeg.
  final bool skipFfmpegPrompt;
  /// The language 翻译 turns text into (a TranslationLanguage code); empty
  /// follows Windows' language.
  final String translateLanguage;

  /// [translateLanguage], with Windows' language for empty.
  String get translateTarget => translateLanguage.isEmpty ? SubtitleLanguage.auto.translation.code : translateLanguage;

  /// Which service 翻译 uses, and its settings; the keys are kept apart.
  final TranslationConfig translation;

  /// Translated subtitles come from [translation] instead of YouTube.
  final bool subtitlesByService;
  /// 翻译 shows the translation under the original, not in its place.
  final bool bilingualTranslation;
  /// How the translation under the original looks.
  final TranslationStyle translationStyle;
  /// The translation goes above the original instead of under it.
  final bool translationFirst;
  /// Which subtitles 字幕列表 shows while two are on.
  final SubtitleListMode subtitleListMode;
  /// 翻译 does nothing for text already in the target language.
  final bool skipSameLanguage;

  bool isBlocked(String? channelId) => channelId != null && _lists.blockedIds.contains(channelId);

  bool isUnrecommended(String? channelId) => channelId != null && _lists.unrecommendedIds.contains(channelId);

  /// Whether a channel called [name] was blocked by name.
  bool isBlockedName(String name) => _lists.names.isNotEmpty && _lists.names.contains(name.trim().toLowerCase());

  /// The block lists as sets and lowercased once per preferences: [shows]
  /// runs for every item of every list on every rebuild.
  ({Set<String> blockedIds, Set<String> unrecommendedIds, Set<String> names, List<String> keywords}) get _lists => _listCache[this] ??= (
        blockedIds: {for (final c in blockedChannels) c.id},
        unrecommendedIds: {for (final c in unrecommendedChannels) c.id},
        names: {for (final n in blockedChannelNames) n.trim().toLowerCase()},
        keywords: [for (final w in blockedKeywords) w.toLowerCase()],
      );
  static final _listCache = Expando<({Set<String> blockedIds, Set<String> unrecommendedIds, Set<String> names, List<String> keywords})>();

  /// Whether a channel called [name], with [id] or [handle] if known, is
  /// one the user blocks by group or as state media.
  /// Remembered per channel for these preferences, as each test goes
  /// through the native core.
  bool blocksChannel(String name, {String? id, String? handle}) {
    if (!blockGroups && !blockStateMedia) return false;
    final memo = _blockMemo[this] ??= <String, bool>{};
    if (memo.length > 20000) memo.clear();
    return memo['channel\n$id\n$handle\n$name'] ??= (blockGroups && _matchers.groups.channel(name, id: id, handle: handle)) || blocksMediaChannel(name);
  }

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
    return memo['${item.channelId}\n${item.channel}'] ??= blocksChannel(item.channel, id: item.channelId);
  }

  static final _blockMemo = Expando<Map<String, bool>>();

  /// Whether a comment by [author] (a name or @handle) with channel [id] is
  /// by a channel the user blocks. Its text is never looked at.
  bool blocksCommenter(String author, String? id) {
    final memo = _blockMemo[this] ??= <String, bool>{};
    if (memo.length > 20000) memo.clear();
    return memo['comment\n$id\n$author'] ??= isBlocked(id) || isBlockedName(author) || blocksChannel(author, id: id, handle: author.startsWith('@') ? author : null);
  }

  /// Whether [item] passes the privacy and content filters. [watched] says
  /// whether it was watched to the end.
  bool shows(VideoItem item, {bool watched = false}) {
    if (isBlocked(item.channelId) || isBlockedName(item.channel)) return false;
    if (blockedChannels.isNotEmpty && item.channelId == null && blockedChannels.any((c) => c.name.isNotEmpty && c.name == item.channel)) return false;
    final keywords = _lists.keywords;
    if (keywords.isNotEmpty) {
      final title = item.title.toLowerCase();
      if (keywords.any(title.contains)) return false;
    }
    final duration = item.duration;
    if (hideShorts && _isShort(item)) return false;
    if (minDurationMinutes > 0 && duration != null && duration > 0 && duration < minDurationMinutes * 60) return false;
    if (hideWatched && watched) return false;
    return true;
  }

  /// The same test as 为你推荐's Shorts setting, which also works without the
  /// native core.
  static bool _isShort(VideoItem item) =>
      item.isShortListing || item.url.contains('/shorts/') || ((item.duration ?? 0) > 0 && item.duration! <= 60) || isShort(item);

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
    bool? homeAutoRefresh,
    FeedLevel? feedShorts,
    FeedLevel? feedVertical,
    bool? syncFollowToYoutube,
    String? startPage,
    bool? feedAutoRefresh,
    int? feedRefreshMinutes,
    bool? autoPlay,
    bool? resumePlayback,
    bool? watchLaterAutoRemove,
    bool? autoFullscreen,
    bool? autoLightsOff,
    int? lightsOffDim,
    bool? miniPlayer,
    bool? exitFullscreenOnEnd,
    bool? pauseOnMinimize,
    bool? audioOnlyInBackground,
    bool? closeToTray,
    bool? keyboardShortcuts,
    int? seekSeconds,
    int? longSeekSeconds,
    int? volumeStep,
    int? controlsHideSeconds,
    bool? showHeatmap,
    ProgressLine? progressLine,
    bool? showRelated,
    bool? expandDescription,
    bool? autoCheckUpdates,
    bool? autoUpdateApp,
    bool? skipFfmpegPrompt,
    String? translateLanguage,
    TranslationConfig? translation,
    bool? subtitlesByService,
    bool? bilingualTranslation,
    TranslationStyle? translationStyle,
    bool? translationFirst,
    SubtitleListMode? subtitleListMode,
    bool? skipSameLanguage,
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
        homeAutoRefresh: homeAutoRefresh ?? this.homeAutoRefresh,
        feedShorts: feedShorts ?? this.feedShorts,
        feedVertical: feedVertical ?? this.feedVertical,
        syncFollowToYoutube: syncFollowToYoutube ?? this.syncFollowToYoutube,
        startPage: startPage ?? this.startPage,
        feedAutoRefresh: feedAutoRefresh ?? this.feedAutoRefresh,
        feedRefreshMinutes: feedRefreshMinutes ?? this.feedRefreshMinutes,
        autoPlay: autoPlay ?? this.autoPlay,
        resumePlayback: resumePlayback ?? this.resumePlayback,
        watchLaterAutoRemove: watchLaterAutoRemove ?? this.watchLaterAutoRemove,
        autoFullscreen: autoFullscreen ?? this.autoFullscreen,
        autoLightsOff: autoLightsOff ?? this.autoLightsOff,
        lightsOffDim: lightsOffDim ?? this.lightsOffDim,
        miniPlayer: miniPlayer ?? this.miniPlayer,
        exitFullscreenOnEnd: exitFullscreenOnEnd ?? this.exitFullscreenOnEnd,
        pauseOnMinimize: pauseOnMinimize ?? this.pauseOnMinimize,
        audioOnlyInBackground: audioOnlyInBackground ?? this.audioOnlyInBackground,
        closeToTray: closeToTray ?? this.closeToTray,
        keyboardShortcuts: keyboardShortcuts ?? this.keyboardShortcuts,
        seekSeconds: seekSeconds ?? this.seekSeconds,
        longSeekSeconds: longSeekSeconds ?? this.longSeekSeconds,
        volumeStep: volumeStep ?? this.volumeStep,
        controlsHideSeconds: controlsHideSeconds ?? this.controlsHideSeconds,
        showHeatmap: showHeatmap ?? this.showHeatmap,
        progressLine: progressLine ?? this.progressLine,
        showRelated: showRelated ?? this.showRelated,
        expandDescription: expandDescription ?? this.expandDescription,
        autoCheckUpdates: autoCheckUpdates ?? this.autoCheckUpdates,
        autoUpdateApp: autoUpdateApp ?? this.autoUpdateApp,
        skipFfmpegPrompt: skipFfmpegPrompt ?? this.skipFfmpegPrompt,
        translateLanguage: translateLanguage ?? this.translateLanguage,
        translation: translation ?? this.translation,
        subtitlesByService: subtitlesByService ?? this.subtitlesByService,
        bilingualTranslation: bilingualTranslation ?? this.bilingualTranslation,
        translationStyle: translationStyle ?? this.translationStyle,
        translationFirst: translationFirst ?? this.translationFirst,
        subtitleListMode: subtitleListMode ?? this.subtitleListMode,
        skipSameLanguage: skipSameLanguage ?? this.skipSameLanguage,
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
        'homeAutoRefresh': homeAutoRefresh,
        'feedShorts': feedShorts.name,
        'feedVertical': feedVertical.name,
        'syncFollowToYoutube': syncFollowToYoutube,
        'startPage': startPage,
        'feedAutoRefresh': feedAutoRefresh,
        'feedRefreshMinutes': feedRefreshMinutes,
        'autoPlay': autoPlay,
        'resumePlayback': resumePlayback,
        'watchLaterAutoRemove': watchLaterAutoRemove,
        'autoFullscreen': autoFullscreen,
        'autoLightsOff': autoLightsOff,
        'lightsOffDim': lightsOffDim,
        'miniPlayer': miniPlayer,
        'exitFullscreenOnEnd': exitFullscreenOnEnd,
        'pauseOnMinimize': pauseOnMinimize,
        'audioOnlyInBackground': audioOnlyInBackground,
        'closeToTray': closeToTray,
        'keyboardShortcuts': keyboardShortcuts,
        'seekSeconds': seekSeconds,
        'longSeekSeconds': longSeekSeconds,
        'volumeStep': volumeStep,
        'controlsHideSeconds': controlsHideSeconds,
        'showHeatmap': showHeatmap,
        'progressLine': progressLine.name,
        'showRelated': showRelated,
        'expandDescription': expandDescription,
        'autoCheckUpdates': autoCheckUpdates,
        'autoUpdateApp': autoUpdateApp,
        'skipFfmpegPrompt': skipFfmpegPrompt,
        'translateLanguageV2': translateLanguage,
        'translation': translation.toJson(),
        'subtitlesByService': subtitlesByService,
        'bilingualTranslation': bilingualTranslation,
        'translationStyle': translationStyle.name,
        'translationFirst': translationFirst,
        'subtitleListMode': subtitleListMode.name,
        'skipSameLanguage': skipSameLanguage,
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
      homeAutoRefresh: flag('homeAutoRefresh', d.homeAutoRefresh),
      feedShorts: FeedLevel.parse(raw['feedShorts'], d.feedShorts),
      feedVertical: FeedLevel.parse(raw['feedVertical'], d.feedVertical),
      syncFollowToYoutube: flag('syncFollowToYoutube', d.syncFollowToYoutube),
      startPage: startPages.any((p) => p.$1 == start) ? start! : 'home',
      feedAutoRefresh: flag('feedAutoRefresh', d.feedAutoRefresh),
      feedRefreshMinutes: number('feedRefreshMinutes', 10, 1, 1440),
      autoPlay: flag('autoPlay', d.autoPlay),
      resumePlayback: flag('resumePlayback', d.resumePlayback),
      watchLaterAutoRemove: flag('watchLaterAutoRemove', d.watchLaterAutoRemove),
      autoFullscreen: flag('autoFullscreen', d.autoFullscreen),
      autoLightsOff: flag('autoLightsOff', d.autoLightsOff),
      lightsOffDim: number('lightsOffDim', 85, 50, 98),
      miniPlayer: flag('miniPlayer', d.miniPlayer),
      exitFullscreenOnEnd: flag('exitFullscreenOnEnd', d.exitFullscreenOnEnd),
      pauseOnMinimize: flag('pauseOnMinimize', d.pauseOnMinimize),
      audioOnlyInBackground: flag('audioOnlyInBackground', d.audioOnlyInBackground),
      closeToTray: flag('closeToTray', d.closeToTray),
      keyboardShortcuts: flag('keyboardShortcuts', d.keyboardShortcuts),
      seekSeconds: number('seekSeconds', 5, 1, 60),
      longSeekSeconds: number('longSeekSeconds', 10, 1, 120),
      volumeStep: number('volumeStep', 5, 1, 25),
      controlsHideSeconds: number('controlsHideSeconds', 3, 1, 30),
      showHeatmap: flag('showHeatmap', d.showHeatmap),
      progressLine: ProgressLine.parse(raw['progressLine'], d.progressLine),
      showRelated: flag('showRelated', d.showRelated),
      expandDescription: flag('expandDescription', d.expandDescription),
      autoCheckUpdates: flag('autoCheckUpdates', d.autoCheckUpdates),
      autoUpdateApp: flag('autoUpdateApp', d.autoUpdateApp),
      skipFfmpegPrompt: flag('skipFfmpegPrompt', d.skipFfmpegPrompt),
      // Simplified Chinese was the default before Windows' language was
      // followed, so a value saved then follows Windows too.
      translateLanguage: raw.containsKey('translateLanguageV2')
          ? TranslationLanguage.maybeByCode(raw['translateLanguageV2'])?.code ?? ''
          : raw['translateLanguage'] == TranslationLanguage.defaultCode
              ? ''
              : TranslationLanguage.maybeByCode(raw['translateLanguage'])?.code ?? '',
      translation: TranslationConfig.fromJson(raw['translation']),
      subtitlesByService: flag('subtitlesByService', d.subtitlesByService),
      bilingualTranslation: flag('bilingualTranslation', d.bilingualTranslation),
      translationStyle: TranslationStyle.values.where((v) => v.name == raw['translationStyle']).firstOrNull ?? d.translationStyle,
      translationFirst: flag('translationFirst', d.translationFirst),
      subtitleListMode: SubtitleListMode.values.where((v) => v.name == raw['subtitleListMode']).firstOrNull ?? d.subtitleListMode,
      skipSameLanguage: flag('skipSameLanguage', d.skipSameLanguage),
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
