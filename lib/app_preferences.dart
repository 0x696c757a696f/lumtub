import 'dart:convert';
import 'dart:io';
import 'ai_filter.dart';
import 'block_list_renames.dart';
import 'app_log.dart';

import 'app_directories.dart';
import 'blocked_groups.dart';
import 'danmaku.dart' show DanmakuSettings;
import 'explore_filters.dart';
import 'feed_quality.dart';
import 'explore_topics.dart';
import 'models.dart';
import 'player_settings.dart' show interfaceTranslationLanguage;
import 'progress_line.dart';
import 'right_click.dart';
import 'title_translation.dart';
import 'translation.dart';
import 'wheel_gesture.dart';
import 'translation_services.dart';
import 'l10n/l10n.dart';
import 'list_order.dart';
import 'live_chat.dart' show ChatView;

/// Pages the app can open on start, in navigation order.
///
/// This must be evaluated after the selected language is loaded, instead of
/// once during library initialization.
/// [AppPreferences.gpuPreference]'s values, as the Windows runner reads them.
const gpuPreferences = {'system', 'low-power', 'high-performance'};

List<(String, String)> get startPages => [
      ('home', tr('Home')),
      ('explore', tr('Explore')),
      ('subscriptions', tr('Subscriptions')),
      ('history', tr('History')),
      ('playlists', tr('Playlist')),
    ];

/// Behaviour and content preferences that are neither player options nor
/// looks: privacy, filters, start page and how the watch page behaves.
/// What 字幕列表 lists while a first and a second subtitle are on.
enum SubtitleListMode {
  firstOver('Both, first subtitle on top'),
  secondOver('Both, second subtitle on top'),
  first('First subtitle only'),
  second('Second subtitle only');

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
    this.aiFilter = AiFilterMode.off,
    this.logLevel = LogLevel.info,
    this.minDurationMinutes = 0,
    this.hideWatched = false,
    this.hideMembersOnly = false,
    this.updateBlockLists = true,
    this.blockGroups = false,
    this.allowedGroups = const [],
    this.blockStateMedia = false,
    this.blockOtherLists = true,
    this.allowedMedia = const [],
    this.reversedPlaylists = const [],
    this.groupOrder = GroupOrder.manual,
    this.channelOrder = ChannelOrder.recent,
    this.playlistOrder = PlaylistOrder.manual,
    this.videoOrders = const {},
    this.castMaxHeight = 1080,
    this.castFormats = const {},
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
    this.syncHistoryToYoutube = false,
    this.startPage = 'home',
    this.feedAutoRefresh = true,
    this.feedRefreshMinutes = 10,
    this.autoPlay = true,
    this.resumePlayback = true,
    this.watchLaterAutoRemove = true,
    this.autoFullscreen = false,
    this.autoLightsOff = false,
    this.rememberChannelPlayback = true,
    this.focusHideHome = false,
    this.focusHideComments = false,
    this.lightsOffDim = 85,
    this.miniPlayer = true,
    this.exitFullscreenOnEnd = false,
    this.pauseOnMinimize = false,
    this.audioOnlyInBackground = false,
    this.pipOnLeave = false,
    this.closeToTray = false,
    this.minimizeToTray = false,
    this.speakSubtitles = false,
    this.audioDescription = false,
    this.systemCaptionsSeen = false,
    this.learningMode = true,
    this.softwareQualityTold = false,
    this.batteryAsked = false,
    this.gpuPreference = 'system',
    this.matchFrameRate = true,
    this.keyboardShortcuts = true,
    this.seekSeconds = 5,
    this.longSeekSeconds = 10,
    this.volumeStep = 5,
    this.shortcutKeys = const {},
    this.rightClick = RightClick.fillWindow,
    this.wheelGesture = WheelGesture.off,
    this.controlsHideSeconds = 3,
    this.showHeatmap = true,
    this.progressLine = ProgressLine.always,
    this.showRelated = true,
    this.expandDescription = false,
    this.autoCheckUpdates = true,
    this.autoUpdateApp = true,
    this.translateLanguage = '',
    this.translation = const TranslationConfig(),
    this.subtitlesByService = false,
    this.bilingualTranslation = true,
    this.immersiveTranslation = false,
    this.titleTranslation = TitleTranslation.replace,
    this.superChatHighlights = true,
    this.chatView = ChatView.top,
    this.danmaku = const DanmakuSettings(),
    this.immersiveLanguage = '',
    this.translationStyle = TranslationStyle.quote,
    this.translationFirst = false,
    this.subtitleListMode = SubtitleListMode.firstOver,
    this.exploreRailWidth = 220,
    this.skipSameLanguage = true,
    this.chineseAsOne = true,
    this.neverTranslate = const [],
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
  /// Hides videos labeled as made with AI, and the listed AI channels'.
  final AiFilterMode aiFilter;

  /// How much goes into the log.
  final LogLevel logLevel;

  final int minDurationMinutes;
  final bool hideWatched;
  final bool hideMembersOnly;
  /// Fetches the signed block lists once a day (lib/block_list_updates.dart).
  final bool updateBlockLists;
  /// Hides the lists of lists/religion from recommendations, explore and
  /// search, unless a search names the channel exactly. Off for a new
  /// install; turned on in settings.
  final bool blockGroups;
  /// [BlockedGroup.name]s the user unticked, so they show.
  final List<String> allowedGroups;
  /// Hides the propaganda channels in state_media.dart the same way, off by
  /// default.
  final bool blockStateMedia;
  /// state_media.dart group names the user unticked.
  final List<String> allowedMedia;
  /// Hides the lists of every other category of lists/ (scams, malware,
  /// fake cures and the rest), of which only safety lists start ticked.
  final bool blockOtherLists;
  /// Playlists shown and played last to first (倒序), by id.
  final List<String> reversedPlaylists;
  /// The order of the 订阅分组.
  final GroupOrder groupOrder;
  /// The order of the followed channels on the subscriptions page.
  final ChannelOrder channelOrder;
  /// The order of the playlists on the playlists page.
  final PlaylistOrder playlistOrder;
  /// The order chosen for a playlist's videos, by playlist id; one not here
  /// keeps the order videos were added in.
  final Map<String, VideoOrder> videoOrders;
  /// 投屏画质: the tallest picture sent to a TV, 1080, 2160 or 4320. Above
  /// 1080 the picture is VP9 or AV1 at up to 60 fps, which only newer TVs
  /// decode.
  final int castMaxHeight;
  /// The stream format chosen for a DLNA renderer, by its id: `ts`, `hls`
  /// or `mp4`; a renderer not here gets the one Lumtub picks.
  final Map<String, String> castFormats;
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
  /// Videos watched here are added to the YouTube account's history, with
  /// the browser sign-in. Off unless turned on.
  final bool syncHistoryToYoutube;
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
  /// Each channel plays at the speed and volume last chosen on it.
  final bool rememberChannelPlayback;
  /// 专注模式: the home page shows no videos at all, only a way to search.
  final bool focusHideHome;
  /// 专注模式: no comments on the watch page.
  final bool focusHideComments;
  /// How dark 关灯 makes the rest of the window, in percent.
  final int lightsOffDim;
  /// Leaving the watch page keeps the video in the in-app mini player
  /// (ui/mini_player.dart) instead of stopping it.
  final bool miniPlayer;
  final bool exitFullscreenOnEnd;
  final bool pauseOnMinimize;
  /// Minimised or hidden to the tray, mpv decodes no picture.
  final bool audioOnlyInBackground;
  /// Phones and tablets: leaving the app while a video plays on its page
  /// keeps it in picture in picture. Off, the sound plays on alone.
  final bool pipOnLeave;
  /// Closing the window hides it to the tray icon instead of exiting.
  final bool closeToTray;
  /// Minimising the window hides it to the tray icon.
  final bool minimizeToTray;

  /// A running screen reader says each new subtitle line, for those who
  /// cannot see the ones drawn on the video.
  final bool speakSubtitles;

  /// Plays a video's described sound (audio description) when it has
  /// one; Android's own setting for it turns it on too.
  final bool audioDescription;

  /// The system's captions setting has turned subtitles on once already: a
  /// later choice in Lumtub is left alone.
  final bool systemCaptionsSeen;

  /// The language-learning features: off, none of them shows and nothing
  /// of them loads or runs. Playback's own learning aids stay.
  final bool learningMode;
  /// Lumtub has said once why automatic quality stays at 1080p on a device
  /// that decodes neither VP9 nor AV1 in hardware.
  final bool softwareQualityTold;
  /// Android: Lumtub has asked once, after playing in the background, to
  /// run free of battery optimisation.
  final bool batteryAsked;
  /// Windows: the graphics card Lumtub draws and decodes on, read by the
  /// runner from `config\gpu.txt` before the engine starts: `system` (as
  /// Windows decides), `low-power` (integrated) or `high-performance`.
  final String gpuPreference;
  /// Android: the screen switches to a refresh rate that fits the video's
  /// frame rate while it plays, as TVs do for films.
  final bool matchFrameRate;
  final bool keyboardShortcuts;
  final int seekSeconds;
  final int longSeekSeconds;
  final int volumeStep;
  /// Keys chosen for player actions, by [PlayerAction] name; actions not
  /// here keep their default keys.
  final Map<String, List<String>> shortcutKeys;
  /// What a right click on the video does.
  final RightClick rightClick;
  /// What the mouse wheel does over the video; off lets the page scroll.
  final WheelGesture wheelGesture;
  /// 0 keeps them shown while playing, for screen readers and switch
  /// access that cannot hover the player.
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
  /// The language 翻译 turns text into (a TranslationLanguage code); empty
  /// follows the interface's language.
  final String translateLanguage;

  /// [translateLanguage], with the interface's language for empty.
  String get translateTarget => translateLanguage.isEmpty ? interfaceTranslationLanguage.code : translateLanguage;

  /// Which service 翻译 uses, and its settings; the keys are kept apart.
  final TranslationConfig translation;

  /// Translated subtitles come from [translation] instead of YouTube.
  final bool subtitlesByService;
  /// 翻译 shows the translation under the original, not in its place.
  final bool bilingualTranslation;
  /// 沉浸式翻译: comments, posts and live chat in another language show
  /// their translation under them without asking.
  final bool immersiveTranslation;
  /// Whether titles in video and playlist lists show their translation,
  /// and how.
  final TitleTranslation titleTranslation;
  /// Super Chats in their amount's colour, and the strip of recent ones
  /// over the live chat.
  final bool superChatHighlights;
  /// Which messages a live chat and its replay show: YouTube's Top chat
  /// or every message.
  final ChatView chatView;
  /// 弹幕: the live chat or its replay flying across the picture.
  final DanmakuSettings danmaku;
  /// The language 沉浸式翻译 turns text into; empty follows
  /// [translateTarget], the language set for every translation.
  final String immersiveLanguage;

  /// [immersiveLanguage], with [translateTarget] for empty.
  String get immersiveTarget => immersiveLanguage.isEmpty ? translateTarget : immersiveLanguage;
  /// How the translation under the original looks.
  final TranslationStyle translationStyle;
  /// The translation goes above the original instead of under it.
  final bool translationFirst;
  /// Which subtitles 字幕列表 shows while two are on.
  final SubtitleListMode subtitleListMode;

  /// How wide the zone column down the left of 探索 was dragged.
  final double exploreRailWidth;
  /// 翻译 does nothing for text already in the target language.
  final bool skipSameLanguage;
  /// 沉浸式翻译 takes Simplified and Traditional Chinese as one language,
  /// leaving either alone when the other is the target; a tap on 翻译
  /// always turns one into the other.
  final bool chineseAsOne;
  /// Translation codes of languages the user reads, left untranslated like
  /// the target.
  final List<String> neverTranslate;

  bool isBlocked(String? channelId) => channelId != null && _lists.blockedIds.contains(channelId);

  bool isUnrecommended(String? channelId) => channelId != null && _lists.unrecommendedIds.contains(channelId);

  /// Whether a channel called [name] was blocked by name.
  bool isBlockedName(String name) => _lists.names.isNotEmpty && _lists.names.contains(name.trim().toLowerCase());

  /// The block lists as sets and lowercased once per preferences: [shows]
  /// runs for every item of every list on every rebuild.
  ({Set<String> blockedIds, Set<String> unrecommendedIds, Set<String> names, Set<String> refNames, List<String> keywords}) get _lists => _listCache[this] ??= (
        blockedIds: {for (final c in blockedChannels) c.id},
        // As saved, not lowercased: matched exactly, unlike [names].
        refNames: {for (final c in blockedChannels) if (c.name.isNotEmpty) c.name},
        unrecommendedIds: {for (final c in unrecommendedChannels) c.id},
        names: {for (final n in blockedChannelNames) n.trim().toLowerCase()},
        keywords: [for (final w in blockedKeywords) w.toLowerCase()],
      );
  static final _listCache = Expando<({Set<String> blockedIds, Set<String> unrecommendedIds, Set<String> names, Set<String> refNames, List<String> keywords})>();

  /// Whether a channel called [name], with [id] or [handle] if known, is
  /// one the user blocks by group or as state media.
  /// Remembered per channel for these preferences, as each test goes
  /// through the native core.
  bool blocksChannel(String name, {String? id, String? handle}) {
    if (!blockGroups && !blockStateMedia && !blockOtherLists) return false;
    final memo = _block.memo;
    if (memo.length > 20000) memo.clear();
    return memo['channel\n$id\n$handle\n$name'] ??= (blockGroups && _matchers.groups.channel(name, id: id, handle: handle)) ||
        blocksMediaChannel(name) ||
        (blockOtherLists && _matchers.others.channel(name, id: id, handle: handle));
  }

  /// Whether [group] is ticked. A list of [otherLists] starts ticked only
  /// when its file says `default: on`.
  bool groupOn(BlockedGroup group, {bool media = false}) {
    // A choice the user made stands whatever a later version of the lists
    // makes the default: ticked groups are kept in [enabledGroups], unticked
    // ones in [allowedGroups] (or [allowedMedia]), and a tick moves a group
    // from one to the other.
    final ticked = enabledGroups.contains(group.name);
    final unticked = (media ? allowedMedia : allowedGroups).contains(group.name);
    if (ticked != unticked) return ticked;
    if (otherLists.contains(group)) return group.defaultOn ? !unticked : ticked;
    return group.onByDefault ? !unticked : ticked;
  }

  /// These preferences with [group] ticked or not, remembered as the
  /// user's own choice.
  AppPreferences withGroup(BlockedGroup group, bool on, {bool media = false}) {
    List<String> toggled(List<String> list, bool add) => add ? {...list, group.name}.toList() : [...list.where((n) => n != group.name)];
    final unticked = toggled(media ? allowedMedia : allowedGroups, !on);
    return copyWith(enabledGroups: toggled(enabledGroups, on), allowedGroups: media ? null : unticked, allowedMedia: media ? unticked : null);
  }

  ({BlockMatcher groups, BlockMatcher media, BlockMatcher others}) get _matchers => _block.matchers ??= (
        groups: BlockMatcher([for (final g in blockedGroups) if (groupOn(g)) g], allowedEntries: allowedEntries.toSet()),
        media: BlockMatcher([for (final g in stateMedia) if (groupOn(g, media: true)) g], allowedEntries: allowedEntries.toSet()),
        // Lists that only label or demote are not left out.
        others: BlockMatcher([for (final g in otherLists) if (groupOn(g) && (g.action == 'hide' || g.action == 'quiet')) g], allowedEntries: allowedEntries.toSet()),
      );

  /// The block matchers and what they answered, shared by every copy of
  /// the preferences with the same block settings: a change to anything
  /// else (danmaku, subtitles, layout) keeps them; a change to any of
  /// these builds them and their answers afresh. The lists themselves are
  /// read once a run.
  _BlockState get _block => _blockStates[this] ??= () {
        final key = jsonEncode([blockGroups, blockStateMedia, blockOtherLists, enabledGroups, allowedGroups, allowedMedia, allowedEntries]);
        final last = _lastBlock;
        return last != null && last.key == key ? last : _lastBlock = _BlockState(key);
      }();
  static final _blockStates = Expando<_BlockState>();
  static _BlockState? _lastBlock;

  /// Whether a channel called [name] is state media the user blocks.
  bool blocksMediaChannel(String name) => blockStateMedia && _matchers.media.channel(name);

  /// Whether [item] comes from a channel the user blocks as a group or state
  /// media. Its title and description are never looked at. Remembered per
  /// channel for these preferences: lists are filtered again on every
  /// rebuild, and the block lists run to hundreds of names.
  bool blocksGroup(VideoItem item) {
    final memo = _block.memo;
    if (memo.length > 20000) memo.clear();
    return memo['${item.channelId}\n${item.channel}'] ??= blocksChannel(item.channel, id: item.channelId);
  }

  /// Whether a comment by [author] (a name or @handle) with channel [id] is
  /// by a channel the user blocks. Its text is never looked at.
  bool blocksCommenter(String author, String? id) =>
      isBlocked(id) || isBlockedName(author) || blocksChannel(author, id: id, handle: author.startsWith('@') ? author : null);

  /// Whether [item] passes the privacy and content filters. [watched] says
  /// whether it was watched to the end.
  bool shows(VideoItem item, {bool watched = false}) {
    if (isBlocked(item.channelId) || isBlockedName(item.channel)) return false;
    if (blockedChannels.isNotEmpty && item.channelId == null && _lists.refNames.contains(item.channel)) return false;
    final keywords = _lists.keywords;
    if (keywords.isNotEmpty) {
      final title = item.title.toLowerCase();
      if (keywords.any(title.contains)) return false;
    }
    final duration = item.duration;
    if (hideShorts && _isShort(item)) return false;
    if (minDurationMinutes > 0 && duration != null && duration > 0 && duration < minDurationMinutes * 60) return false;
    if (hideWatched && watched) return false;
    if (hideMembersOnly && item.membersOnly) return false;
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
    AiFilterMode? aiFilter,
    LogLevel? logLevel,
    int? minDurationMinutes,
    bool? hideWatched,
    bool? hideMembersOnly,
    bool? updateBlockLists,
    bool? blockGroups,
    List<String>? allowedGroups,
    bool? blockStateMedia,
    List<String>? allowedMedia,
    bool? blockOtherLists,
    List<String>? reversedPlaylists,
    GroupOrder? groupOrder,
    ChannelOrder? channelOrder,
    PlaylistOrder? playlistOrder,
    Map<String, VideoOrder>? videoOrders,
    int? castMaxHeight,
    Map<String, String>? castFormats,
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
    bool? syncHistoryToYoutube,
    String? startPage,
    bool? feedAutoRefresh,
    int? feedRefreshMinutes,
    bool? autoPlay,
    bool? resumePlayback,
    bool? watchLaterAutoRemove,
    bool? autoFullscreen,
    bool? autoLightsOff,
    bool? rememberChannelPlayback,
    bool? focusHideHome,
    bool? focusHideComments,
    int? lightsOffDim,
    bool? miniPlayer,
    bool? exitFullscreenOnEnd,
    bool? pauseOnMinimize,
    bool? audioOnlyInBackground,
    bool? pipOnLeave,
    bool? closeToTray,
    bool? minimizeToTray,
    bool? speakSubtitles,
    bool? audioDescription,
    bool? systemCaptionsSeen,
    bool? learningMode,
    bool? softwareQualityTold,
    bool? batteryAsked,
    String? gpuPreference,
    bool? matchFrameRate,
    bool? keyboardShortcuts,
    int? seekSeconds,
    int? longSeekSeconds,
    int? volumeStep,
    Map<String, List<String>>? shortcutKeys,
    RightClick? rightClick,
    WheelGesture? wheelGesture,
    int? controlsHideSeconds,
    bool? showHeatmap,
    ProgressLine? progressLine,
    bool? showRelated,
    bool? expandDescription,
    bool? autoCheckUpdates,
    bool? autoUpdateApp,
    String? translateLanguage,
    TranslationConfig? translation,
    bool? subtitlesByService,
    bool? bilingualTranslation,
    bool? immersiveTranslation,
    TitleTranslation? titleTranslation,
    bool? superChatHighlights,
    ChatView? chatView,
    DanmakuSettings? danmaku,
    String? immersiveLanguage,
    TranslationStyle? translationStyle,
    bool? translationFirst,
    SubtitleListMode? subtitleListMode,
    double? exploreRailWidth,
    bool? skipSameLanguage,
    bool? chineseAsOne,
    List<String>? neverTranslate,
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
        aiFilter: aiFilter ?? this.aiFilter,
        logLevel: logLevel ?? this.logLevel,
        minDurationMinutes: minDurationMinutes ?? this.minDurationMinutes,
        hideWatched: hideWatched ?? this.hideWatched,
        hideMembersOnly: hideMembersOnly ?? this.hideMembersOnly,
        updateBlockLists: updateBlockLists ?? this.updateBlockLists,
        blockGroups: blockGroups ?? this.blockGroups,
        allowedGroups: allowedGroups ?? this.allowedGroups,
        blockStateMedia: blockStateMedia ?? this.blockStateMedia,
        allowedMedia: allowedMedia ?? this.allowedMedia,
        blockOtherLists: blockOtherLists ?? this.blockOtherLists,
        reversedPlaylists: reversedPlaylists ?? this.reversedPlaylists,
        groupOrder: groupOrder ?? this.groupOrder,
        channelOrder: channelOrder ?? this.channelOrder,
        playlistOrder: playlistOrder ?? this.playlistOrder,
        videoOrders: videoOrders ?? this.videoOrders,
        castMaxHeight: castMaxHeight ?? this.castMaxHeight,
        castFormats: castFormats ?? this.castFormats,
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
        syncHistoryToYoutube: syncHistoryToYoutube ?? this.syncHistoryToYoutube,
        startPage: startPage ?? this.startPage,
        feedAutoRefresh: feedAutoRefresh ?? this.feedAutoRefresh,
        feedRefreshMinutes: feedRefreshMinutes ?? this.feedRefreshMinutes,
        autoPlay: autoPlay ?? this.autoPlay,
        resumePlayback: resumePlayback ?? this.resumePlayback,
        watchLaterAutoRemove: watchLaterAutoRemove ?? this.watchLaterAutoRemove,
        autoFullscreen: autoFullscreen ?? this.autoFullscreen,
        autoLightsOff: autoLightsOff ?? this.autoLightsOff,
        rememberChannelPlayback: rememberChannelPlayback ?? this.rememberChannelPlayback,
        focusHideHome: focusHideHome ?? this.focusHideHome,
        focusHideComments: focusHideComments ?? this.focusHideComments,
        lightsOffDim: lightsOffDim ?? this.lightsOffDim,
        miniPlayer: miniPlayer ?? this.miniPlayer,
        exitFullscreenOnEnd: exitFullscreenOnEnd ?? this.exitFullscreenOnEnd,
        pauseOnMinimize: pauseOnMinimize ?? this.pauseOnMinimize,
        audioOnlyInBackground: audioOnlyInBackground ?? this.audioOnlyInBackground,
        pipOnLeave: pipOnLeave ?? this.pipOnLeave,
        closeToTray: closeToTray ?? this.closeToTray,
        minimizeToTray: minimizeToTray ?? this.minimizeToTray,
        speakSubtitles: speakSubtitles ?? this.speakSubtitles,
        audioDescription: audioDescription ?? this.audioDescription,
        systemCaptionsSeen: systemCaptionsSeen ?? this.systemCaptionsSeen,
        learningMode: learningMode ?? this.learningMode,
        softwareQualityTold: softwareQualityTold ?? this.softwareQualityTold,
        batteryAsked: batteryAsked ?? this.batteryAsked,
        gpuPreference: gpuPreference ?? this.gpuPreference,
        matchFrameRate: matchFrameRate ?? this.matchFrameRate,
        keyboardShortcuts: keyboardShortcuts ?? this.keyboardShortcuts,
        seekSeconds: seekSeconds ?? this.seekSeconds,
        longSeekSeconds: longSeekSeconds ?? this.longSeekSeconds,
        volumeStep: volumeStep ?? this.volumeStep,
        shortcutKeys: shortcutKeys ?? this.shortcutKeys,
        rightClick: rightClick ?? this.rightClick,
        wheelGesture: wheelGesture ?? this.wheelGesture,
        controlsHideSeconds: controlsHideSeconds ?? this.controlsHideSeconds,
        showHeatmap: showHeatmap ?? this.showHeatmap,
        progressLine: progressLine ?? this.progressLine,
        showRelated: showRelated ?? this.showRelated,
        expandDescription: expandDescription ?? this.expandDescription,
        autoCheckUpdates: autoCheckUpdates ?? this.autoCheckUpdates,
        autoUpdateApp: autoUpdateApp ?? this.autoUpdateApp,
        translateLanguage: translateLanguage ?? this.translateLanguage,
        translation: translation ?? this.translation,
        subtitlesByService: subtitlesByService ?? this.subtitlesByService,
        bilingualTranslation: bilingualTranslation ?? this.bilingualTranslation,
        immersiveTranslation: immersiveTranslation ?? this.immersiveTranslation,
        titleTranslation: titleTranslation ?? this.titleTranslation,
        superChatHighlights: superChatHighlights ?? this.superChatHighlights,
        chatView: chatView ?? this.chatView,
        danmaku: danmaku ?? this.danmaku,
        immersiveLanguage: immersiveLanguage ?? this.immersiveLanguage,
        translationStyle: translationStyle ?? this.translationStyle,
        translationFirst: translationFirst ?? this.translationFirst,
        subtitleListMode: subtitleListMode ?? this.subtitleListMode,
        exploreRailWidth: exploreRailWidth ?? this.exploreRailWidth,
        skipSameLanguage: skipSameLanguage ?? this.skipSameLanguage,
        chineseAsOne: chineseAsOne ?? this.chineseAsOne,
        neverTranslate: neverTranslate ?? this.neverTranslate,
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
        'aiFilter': aiFilter.name,
        'logLevel': logLevel.name,
        'minDurationMinutes': minDurationMinutes,
        'hideWatched': hideWatched,
        'hideMembersOnly': hideMembersOnly,
        'updateBlockLists': updateBlockLists,
        'blockGroups': blockGroups,
        'allowedGroups': allowedGroups,
        'blockStateMedia': blockStateMedia,
        'allowedMedia': allowedMedia,
        'blockOtherLists': blockOtherLists,
        'reversedPlaylists': reversedPlaylists,
        'groupOrder': groupOrder.name,
        'channelOrder': channelOrder.name,
        'playlistOrder': playlistOrder.name,
        'videoOrders': {for (final MapEntry(:key, :value) in videoOrders.entries) key: value.name},
        'castMaxHeight': castMaxHeight,
        'castFormats': castFormats,
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
        'syncHistoryToYoutube': syncHistoryToYoutube,
        'startPage': startPage,
        'feedAutoRefresh': feedAutoRefresh,
        'feedRefreshMinutes': feedRefreshMinutes,
        'autoPlay': autoPlay,
        'resumePlayback': resumePlayback,
        'watchLaterAutoRemove': watchLaterAutoRemove,
        'autoFullscreen': autoFullscreen,
        'autoLightsOff': autoLightsOff,
        'rememberChannelPlayback': rememberChannelPlayback,
        'focusHideHome': focusHideHome,
        'focusHideComments': focusHideComments,
        'lightsOffDim': lightsOffDim,
        'miniPlayer': miniPlayer,
        'exitFullscreenOnEnd': exitFullscreenOnEnd,
        'pauseOnMinimize': pauseOnMinimize,
        'audioOnlyInBackground': audioOnlyInBackground,
        'pipOnLeave': pipOnLeave,
        'closeToTray': closeToTray,
        'minimizeToTray': minimizeToTray,
        'speakSubtitles': speakSubtitles,
        'audioDescription': audioDescription,
        'systemCaptionsSeen': systemCaptionsSeen,
        'learningMode': learningMode,
        'softwareQualityTold': softwareQualityTold,
        'batteryAsked': batteryAsked,
        'gpuPreference': gpuPreference,
        'matchFrameRate': matchFrameRate,
        'keyboardShortcuts': keyboardShortcuts,
        'seekSeconds': seekSeconds,
        'longSeekSeconds': longSeekSeconds,
        'volumeStep': volumeStep,
        'shortcutKeys': shortcutKeys,
        'rightClick': rightClick.name,
        'wheelGesture': wheelGesture.name,
        'controlsHideSeconds': controlsHideSeconds,
        'showHeatmap': showHeatmap,
        'progressLine': progressLine.name,
        'showRelated': showRelated,
        'expandDescription': expandDescription,
        'autoCheckUpdates': autoCheckUpdates,
        'autoUpdateApp': autoUpdateApp,
        'translateLanguageV2': translateLanguage,
        'translation': translation.toJson(),
        'subtitlesByService': subtitlesByService,
        'bilingualTranslation': bilingualTranslation,
        'immersiveTranslation': immersiveTranslation,
        'titleTranslation': titleTranslation.name,
        'superChatHighlights': superChatHighlights,
        'chatView': chatView.name,
        'danmaku': danmaku.toJson(),
        'immersiveLanguage': immersiveLanguage,
        'translationStyle': translationStyle.name,
        'translationFirst': translationFirst,
        'subtitleListMode': subtitleListMode.name,
        'exploreRailWidth': exploreRailWidth,
        'skipSameLanguage': skipSameLanguage,
        'chineseAsOne': chineseAsOne,
        'neverTranslate': neverTranslate,
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
      final ids = <String>{};
      if (raw[key] is List) {
        for (final entry in raw[key] as List) {
          if (entry is! Map) continue;
          final id = entry['id']?.toString() ?? '';
          if (ChannelRef.isValidId(id) && ids.add(id)) channels.add(ChannelRef(id, entry['name']?.toString() ?? ''));
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
          if (entry.value is List) '${entry.key}': [for (final k in entry.value as List) legacyTopicKeys['$k'] ?? '$k'],
      };
    }
    final start = raw['startPage']?.toString();
    return AppPreferences(
      recordHistory: flag('recordHistory', d.recordHistory),
      recordProgress: flag('recordProgress', d.recordProgress),
      blockedChannels: channelList('blockedChannels'),
      blockedKeywords: strings('blockedKeywords'),
      unrecommendedChannels: channelList('unrecommendedChannels'),
      allowedGroups: renamedBlockLists(strings('allowedGroups')),
      allowedMedia: renamedBlockLists(strings('allowedMedia')),
      reversedPlaylists: strings('reversedPlaylists'),
      groupOrder: GroupOrder.parse(raw['groupOrder']),
      channelOrder: ChannelOrder.parse(raw['channelOrder']),
      playlistOrder: PlaylistOrder.parse(raw['playlistOrder']),
      videoOrders: {
        if (raw['videoOrders'] case final Map<String, dynamic> orders)
          for (final MapEntry(:key, :value) in orders.entries)
            if (VideoOrder.values.where((v) => v.name == value).firstOrNull case final order? when order != VideoOrder.added) key: order,
      },
      castMaxHeight: const {720, 1080, 1440, 2160, 4320}.contains(raw['castMaxHeight']) ? raw['castMaxHeight'] as int : d.castMaxHeight,
      castFormats: {
        if (raw['castFormats'] case final Map<String, dynamic> formats)
          for (final MapEntry(:key, :value) in formats.entries)
            if (value case 'ts' || 'hls' || 'mp4' || 'mkv') key: value as String,
      },
      enabledGroups: renamedBlockLists(strings('enabledGroups')),
      allowedEntries: renamedBlockEntries(strings('allowedEntries')),
      blockedChannelNames: strings('blockedChannelNames'),
      exploreCustomTopics: topics,
      exploreOrder: keyLists('exploreOrder'),
      exploreHidden: keyLists('exploreHidden'),
      exploreRegion: ExploreRegion.parse(raw['exploreRegion']),
      exploreLanguage: ExploreLanguage.parse(raw['exploreLanguage']),
      hideShorts: flag('hideShorts', d.hideShorts),
      aiFilter: AiFilterMode.parse(raw['aiFilter']),
      logLevel: LogLevel.parse(raw['logLevel']),
      minDurationMinutes: number('minDurationMinutes', 0, 0, 120),
      hideWatched: flag('hideWatched', d.hideWatched),
      hideMembersOnly: flag('hideMembersOnly', d.hideMembersOnly),
      updateBlockLists: flag('updateBlockLists', d.updateBlockLists),
      // Saved before new installs started with it off and asked.
      blockGroups: flag('blockGroups', true),
      blockStateMedia: flag('blockStateMedia', d.blockStateMedia),
      blockOtherLists: flag('blockOtherLists', d.blockOtherLists),
      filterSubscriptions: flag('filterSubscriptions', d.filterSubscriptions),
      homeShowContinue: flag('homeShowContinue', d.homeShowContinue),
      homeShowRecent: flag('homeShowRecent', d.homeShowRecent),
      homeShowRecommended: flag('homeShowRecommended', d.homeShowRecommended),
      homeAutoRefresh: flag('homeAutoRefresh', d.homeAutoRefresh),
      feedShorts: FeedLevel.parse(raw['feedShorts'], d.feedShorts),
      feedVertical: FeedLevel.parse(raw['feedVertical'], d.feedVertical),
      syncFollowToYoutube: flag('syncFollowToYoutube', d.syncFollowToYoutube),
      syncHistoryToYoutube: flag('syncHistoryToYoutube', d.syncHistoryToYoutube),
      startPage: startPages.any((p) => p.$1 == start) ? start! : 'home',
      feedAutoRefresh: flag('feedAutoRefresh', d.feedAutoRefresh),
      feedRefreshMinutes: number('feedRefreshMinutes', 10, 1, 1440),
      autoPlay: flag('autoPlay', d.autoPlay),
      resumePlayback: flag('resumePlayback', d.resumePlayback),
      watchLaterAutoRemove: flag('watchLaterAutoRemove', d.watchLaterAutoRemove),
      autoFullscreen: flag('autoFullscreen', d.autoFullscreen),
      autoLightsOff: flag('autoLightsOff', d.autoLightsOff),
      rememberChannelPlayback: flag('rememberChannelPlayback', d.rememberChannelPlayback),
      focusHideHome: flag('focusHideHome', d.focusHideHome),
      focusHideComments: flag('focusHideComments', d.focusHideComments),
      lightsOffDim: number('lightsOffDim', 85, 50, 98),
      miniPlayer: flag('miniPlayer', d.miniPlayer),
      exitFullscreenOnEnd: flag('exitFullscreenOnEnd', d.exitFullscreenOnEnd),
      pauseOnMinimize: flag('pauseOnMinimize', d.pauseOnMinimize),
      audioOnlyInBackground: flag('audioOnlyInBackground', d.audioOnlyInBackground),
      pipOnLeave: flag('pipOnLeave', d.pipOnLeave),
      closeToTray: flag('closeToTray', d.closeToTray),
      minimizeToTray: flag('minimizeToTray', d.minimizeToTray),
      speakSubtitles: flag('speakSubtitles', d.speakSubtitles),
      audioDescription: flag('audioDescription', d.audioDescription),
      systemCaptionsSeen: flag('systemCaptionsSeen', d.systemCaptionsSeen),
      learningMode: flag('learningMode', d.learningMode),
      softwareQualityTold: flag('softwareQualityTold', d.softwareQualityTold),
      batteryAsked: flag('batteryAsked', d.batteryAsked),
      gpuPreference: gpuPreferences.contains(raw['gpuPreference']) ? raw['gpuPreference'] as String : d.gpuPreference,
      matchFrameRate: flag('matchFrameRate', d.matchFrameRate),
      keyboardShortcuts: flag('keyboardShortcuts', d.keyboardShortcuts),
      seekSeconds: number('seekSeconds', 5, 1, 60),
      longSeekSeconds: number('longSeekSeconds', 10, 1, 120),
      volumeStep: number('volumeStep', 5, 1, 25),
      shortcutKeys: keyLists('shortcutKeys'),
      rightClick: RightClick.parse(raw['rightClick'], raw['rightClickBack']),
      wheelGesture: WheelGesture.parse(raw['wheelGesture'], d.wheelGesture),
      controlsHideSeconds: number('controlsHideSeconds', 3, 0, 30),
      showHeatmap: flag('showHeatmap', d.showHeatmap),
      progressLine: ProgressLine.parse(raw['progressLine'], d.progressLine),
      showRelated: flag('showRelated', d.showRelated),
      expandDescription: flag('expandDescription', d.expandDescription),
      autoCheckUpdates: flag('autoCheckUpdates', d.autoCheckUpdates),
      autoUpdateApp: flag('autoUpdateApp', d.autoUpdateApp),
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
      immersiveTranslation: flag('immersiveTranslation', d.immersiveTranslation),
      titleTranslation: TitleTranslation.values.where((v) => v.name == raw['titleTranslation']).firstOrNull ?? d.titleTranslation,
      superChatHighlights: flag('superChatHighlights', d.superChatHighlights),
      chatView: ChatView.values.where((v) => v.name == raw['chatView']).firstOrNull ?? d.chatView,
      danmaku: DanmakuSettings.fromJson(raw['danmaku']),
      immersiveLanguage: TranslationLanguage.maybeByCode(raw['immersiveLanguage'])?.code ?? '',
      translationStyle: TranslationStyle.values.where((v) => v.name == raw['translationStyle']).firstOrNull ?? d.translationStyle,
      translationFirst: flag('translationFirst', d.translationFirst),
      subtitleListMode: SubtitleListMode.values.where((v) => v.name == raw['subtitleListMode']).firstOrNull ?? d.subtitleListMode,
      exploreRailWidth: raw['exploreRailWidth'] is num ? (raw['exploreRailWidth'] as num).toDouble().clamp(128.0, 360.0) : d.exploreRailWidth,
      skipSameLanguage: flag('skipSameLanguage', d.skipSameLanguage),
      chineseAsOne: flag('chineseAsOne', d.chineseAsOne),
      neverTranslate: [
        if (raw['neverTranslate'] is List)
          for (final code in raw['neverTranslate'] as List)
            if (TranslationLanguage.maybeByCode(code) != null) TranslationLanguage.maybeByCode(code)!.code,
      ],
    );
  }
}

class AppPreferencesStore {
  AppPreferencesStore(AppDirectories directories) : file = File('${directories.config.path}${Platform.pathSeparator}preferences.json');
  final File file;

  Future<AppPreferences> load() async {
    if (!await file.exists()) return const AppPreferences();
    try {
      return AppPreferences.fromJson(jsonDecode(await file.readAsString()));
    } catch (e) {
      await setBrokenFileAside(file, e);
      return const AppPreferences();
    }
  }

  final _writes = WriteQueue();

  Future<void> save(AppPreferences preferences) {
    final text = jsonEncode(preferences.toJson());
    return _writes.run(() => writeFileAtomic(file, text));
  }
}

/// A playback speed as shown to people: `2`, `1.25`.
String rateText(double rate) => rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : rate.toString();

/// See [AppPreferences._block].
class _BlockState {
  _BlockState(this.key);
  final String key;
  ({BlockMatcher groups, BlockMatcher media, BlockMatcher others})? matchers;
  final memo = <String, bool>{};
}
