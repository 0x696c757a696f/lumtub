import 'dart:convert';
import 'dart:io';

import 'app_directories.dart';
import 'models.dart';

/// Pages the app can open on start, in navigation order.
const startPages = [('home', '首页'), ('explore', '探索'), ('subscriptions', '订阅'), ('history', '历史'), ('playlists', '播放列表')];

/// Behaviour and content preferences that are neither player options nor
/// looks: privacy, filters, start page and how the watch page behaves.
class AppPreferences {
  const AppPreferences({
    this.recordHistory = true,
    this.recordProgress = true,
    this.blockedChannels = const [],
    this.blockedKeywords = const [],
    this.hideShorts = false,
    this.minDurationMinutes = 0,
    this.hideWatched = false,
    this.filterSubscriptions = true,
    this.homeShowContinue = true,
    this.homeShowRecent = true,
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
  /// Hides videos of a minute or less, which YouTube lists as Shorts.
  final bool hideShorts;
  final int minDurationMinutes;
  final bool hideWatched;
  /// Whether the filters also apply to the subscriptions feed.
  final bool filterSubscriptions;
  final bool homeShowContinue;
  final bool homeShowRecent;
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

  /// Whether [item] passes the privacy and content filters. [watched] says
  /// whether it was watched to the end.
  bool shows(VideoItem item, {bool watched = false}) {
    if (isBlocked(item.channelId)) return false;
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
    bool? hideShorts,
    int? minDurationMinutes,
    bool? hideWatched,
    bool? filterSubscriptions,
    bool? homeShowContinue,
    bool? homeShowRecent,
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
        hideShorts: hideShorts ?? this.hideShorts,
        minDurationMinutes: minDurationMinutes ?? this.minDurationMinutes,
        hideWatched: hideWatched ?? this.hideWatched,
        filterSubscriptions: filterSubscriptions ?? this.filterSubscriptions,
        homeShowContinue: homeShowContinue ?? this.homeShowContinue,
        homeShowRecent: homeShowRecent ?? this.homeShowRecent,
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
        'hideShorts': hideShorts,
        'minDurationMinutes': minDurationMinutes,
        'hideWatched': hideWatched,
        'filterSubscriptions': filterSubscriptions,
        'homeShowContinue': homeShowContinue,
        'homeShowRecent': homeShowRecent,
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
    final channels = <ChannelRef>[];
    if (raw['blockedChannels'] is List) {
      for (final entry in raw['blockedChannels'] as List) {
        if (entry is! Map) continue;
        final id = entry['id']?.toString() ?? '';
        if (ChannelRef.isValidId(id) && !channels.any((c) => c.id == id)) channels.add(ChannelRef(id, entry['name']?.toString() ?? ''));
      }
    }
    final keywords = raw['blockedKeywords'] is List
        ? (raw['blockedKeywords'] as List).map((k) => k.toString().trim()).where((k) => k.isNotEmpty).toSet().toList()
        : const <String>[];
    final start = raw['startPage']?.toString();
    return AppPreferences(
      recordHistory: flag('recordHistory', d.recordHistory),
      recordProgress: flag('recordProgress', d.recordProgress),
      blockedChannels: channels,
      blockedKeywords: keywords,
      hideShorts: flag('hideShorts', d.hideShorts),
      minDurationMinutes: number('minDurationMinutes', 0, 0, 120),
      hideWatched: flag('hideWatched', d.hideWatched),
      filterSubscriptions: flag('filterSubscriptions', d.filterSubscriptions),
      homeShowContinue: flag('homeShowContinue', d.homeShowContinue),
      homeShowRecent: flag('homeShowRecent', d.homeShowRecent),
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
