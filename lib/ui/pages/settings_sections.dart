import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../ai_filter.dart';
import '../../app/app_controller.dart';
import '../../blocked_groups.dart';
import '../../feed_quality.dart';
import '../../format_policy.dart';
import '../../sun_times.dart';
import '../../app_log.dart';
import '../../app_window.dart';
import '../../app_preferences.dart';
import '../../appearance_settings.dart';
import '../../decoder_status.dart';
import '../../encrypted_dns.dart';
import '../../native_core.dart';
import '../../network_proxy.dart';
import '../../piped_streams.dart';
import '../../player_settings.dart';
import '../../progress_line.dart';
import '../../shortcut_bindings.dart';
import '../../video_codec.dart';
import '../../widgets/pilinara_settings_tiles.dart';
import '../../windows_video_info.dart';
import '../../friendly_error.dart';
import '../common.dart';
import '../diagnostics_dialog.dart';
import 'downloads_page.dart' show openInExplorer;
import '../format_policy_dialogs.dart';
import '../player_shortcuts.dart';
import '../shortcut_settings.dart';
import '../motion.dart';
import '../palettes.dart';
import '../../skins/skin_library.dart';
import 'skins_page.dart';
import '../theme.dart';
import 'account_settings.dart';
import 'relay_servers_page.dart';
import 'settings_subpages.dart';
import 'subscription_import_dialog.dart';
import 'translation_settings_page.dart';
import 'watch_stats_page.dart';
import '../../l10n/l10n.dart';
import '../app_icons.dart';

/// The groups in the settings list, in display order, named and ordered
/// like PiliNara's settings page. [account] and [about] are drawn at the
/// bottom of the list without a subtitle, as PiliNara draws them.
enum SettingsCategory {
  privacy('Privacy settings', 'Blocked channels, watch history, playback progress'),
  recommend('Home & search settings', 'Home content, keyword filters, hiding Shorts and watched videos'),
  subscriptions('Subscription settings', 'Subscription feed refresh and filtering'),
  video('Video settings', 'Quality, audio quality, decoding, buffering, audio output and more'),
  play('Playback settings', 'Speed, autoplay, play order, subtitles, volume, fullscreen, shortcuts and more'),
  style('Appearance', 'Theme, fonts, page transitions, navigation bar, card width, thumbnail quality and more'),
  extra('Other settings', 'SponsorBlock, related videos, descriptions, component updates, download and cache locations and more'),
  backup('Backup & restore', 'Import, export and reset settings'),
  account('YouTube account', 'Google sign-in, TV-code sign-in, syncing subscriptions and playlists'),
  about('About', 'Version, logs, diagnostics, open-source licenses');

  const SettingsCategory(this._title, this._subtitle);

  IconData get icon => switch (this) {
        privacy => AppIcons.shieldWarning,
        recommend => AppIcons.compass,
        subscriptions => AppIcons.stackSimple,
        video => AppIcons.gearSix,
        play => AppIcons.handTap,
        style => AppIcons.cards,
        extra => AppIcons.puzzlePiece,
        backup => AppIcons.gearFine,
        account => AppIcons.userCircle,
        about => AppIcons.info,
      };
  final String _title;
  String get title => tr(_title);
  final String _subtitle;
  String get subtitle => tr(_subtitle);
}

/// One searchable row of a settings group.
class SettingEntry {
  const SettingEntry(this.title, this.builder, {this.subtitle});
  final String title;
  /// Extra words the search matches, such as the mpv option name.
  final String? subtitle;
  final WidgetBuilder builder;

  bool matches(String query) => title.toLowerCase().contains(query) || (subtitle?.toLowerCase().contains(query) ?? false);
}

String qualityLabel(int height, [int? fps]) => height == 0 ? tr('Auto (up to screen resolution)') : heightLabel(height, fps);

List<(String, String)> get _scaleModes => [
      ('spline36', tr('Spline36 (default)')),
      ('bilinear', tr('Bilinear (lightest)')),
      ('lanczos', tr('Lanczos (sharper)')),
      ('ewa_lanczossharp', tr('EWA Lanczos Sharp (sharpest, heavy GPU load)')),
    ];
List<(String, String)> get _cacheModes => [('auto', tr('Auto (recommended)')), ('yes', tr('Enable')), ('no', tr('Disable'))];
List<(ThemeMode, String)> get themeModes => [(ThemeMode.system, tr('Follow system')), (ThemeMode.light, tr('Light')), (ThemeMode.dark, tr('Dark'))];
List<(int, String)> get _durations => [(0, tr('Any')), (1, tr('1 minute')), (3, tr('3 minutes')), (5, tr('5 minutes')), (10, tr('10 minutes')), (20, tr('20 minutes'))];
List<(AiFilterMode, String)> get _aiFilterModes => [
      (AiFilterMode.off, tr('Close')),
      (AiFilterMode.labeled, tr('Hide videos YouTube labels as made with AI')),
      (AiFilterMode.labeledAndList, tr('Also hide known AI content-farm channels')),
    ];
List<(FeedLevel, String)> get _feedLevels => [(FeedLevel.off, tr('Any')), (FeedLevel.reduce, tr('Fewer')), (FeedLevel.drop, tr("Don't recommend"))];
List<(int, String)> get _feedIntervals => [(5, tr('5 minutes')), (10, tr('10 minutes')), (30, tr('30 minutes')), (60, tr('1 hour')), (180, tr('3 hours'))];
List<(int, String)> get _hideTimes => [(2, tr('2 seconds')), (3, tr('3 seconds (default)')), (5, tr('5 seconds')), (10, tr('10 seconds')), (30, tr('30 seconds (for screen readers)'))];
List<(int, String)> get _volumeMaxes => [(100, tr('100% (no boost)')), (130, '130%'), (150, '150%'), (200, '200%')];

String labelOf<T>(List<(T, String)> values, T value) {
  for (final (key, label) in values) {
    if (key == value) return label;
  }
  return '$value';
}

List<(T, String)> _enumValues<T extends Enum>(List<T> values, String Function(T) label) => [for (final v in values) (v, label(v))];

Widget _icon(IconData icon) => Icon(icon);

String _hoursLabel(int start, int end) => tr('{0}:00 to {1}:00', [start, end]);

/// Today's sunrise and sunset for 日落到日出, as the settings show them.
String _sunLabel() {
  final sun = SunTimes.here;
  final times = sun.on(DateTime.now());
  String clock(DateTime t) => '${t.hour}:${t.minute.toString().padLeft(2, '0')}';
  if (times == null) return sun.polarNight(DateTime.now()) ? tr('The sun does not rise today') : tr('The sun does not set today');
  return tr('sunrise {0}, sunset {1} today', [clock(times.$1), clock(times.$2)]);
}

String _darkLabel(AppearanceSettings a) => switch (a.darkSchedule) {
      DarkSchedule.off => themeModes.firstWhere((m) => m.$1 == a.themeMode).$2,
      DarkSchedule.sun => tr('Dark from sunset to sunrise ({0})', [_sunLabel()]),
      DarkSchedule.hours => tr('Dark from {0}', [_hoursLabel(a.darkStart, a.darkEnd)]),
    };

String _eyeCareLabel(AppearanceSettings a) => switch (a.eyeCare) {
      EyeCare.sun => tr('Sunset to sunrise ({0})', [_sunLabel()]),
      EyeCare.hours => _hoursLabel(a.eyeCareStart, a.eyeCareEnd),
      _ => a.eyeCare.label,
    };

/// Asks for a span of hours, which may run through midnight.
Future<(int, int)?> _pickHours(BuildContext context, String title, int start, int end) => showDialog<(int, int)>(
      context: context,
      builder: (context) {
        var from = start;
        var to = end;
        Widget hour(int value, ValueChanged<int> changed) => DropdownButton<int>(
              value: value,
              items: [for (var h = 0; h < 24; h++) DropdownMenuItem(value: h, child: Text('$h:00'))],
              onChanged: (v) => v == null ? null : changed(v),
            );
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(title),
            content: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(tr('From')),
              const SizedBox(width: Space.s),
              hour(from, (v) => setState(() => from = v)),
              const SizedBox(width: Space.m),
              Text(tr('to')),
              const SizedBox(width: Space.s),
              hour(to, (v) => setState(() => to = v)),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
              FilledButton(onPressed: () => Navigator.pop(context, (from, to)), child: Text(tr('OK'))),
            ],
          ),
        );
      },
    );

List<SettingEntry> settingEntries(SettingsCategory category, AppController controller) {
  final settings = controller.settings;
  final prefs = controller.preferences;
  final appearance = controller.appearance;
  void save(PlayerSettings next) => controller.saveSettings(next);
  void savePrefs(AppPreferences next) => controller.savePreferences(next);
  void saveLooks(AppearanceSettings next) => controller.saveAppearance(next);

  /// Saves the language and offers to restart, since text on screen keeps
  /// the language Lumtub started in.
  Future<void> changeLanguage(BuildContext context, AppearanceSettings next) async {
    if (next.language == appearance.language) return;
    await controller.saveAppearance(next);
    if (!context.mounted || next.language.resolved == currentLanguage) return;
    final restart = await confirmDialog(context, title: tr('Restart to change the language'), content: tr('Lumtub shows the new language after a restart. Restart now?'), confirm: tr('Restart now'));
    if (restart) await controller.restart();
  }

  final hardware = settings.hwdec != 'no';
  return switch (category) {
    SettingsCategory.privacy => [
        SettingEntry(tr('Blocked channels'), (context) => NormalItem(
              title: tr('Blocked channels'),
              subtitle: prefs.blockedChannels.isEmpty && prefs.blockedChannelNames.isEmpty && prefs.unrecommendedChannels.isEmpty
                  ? tr('Add one here, or choose “Block this channel” on a video card, channel page or the watch page')
                  : tr('{0} blocked, {1} not recommended', [prefs.blockedChannels.length + prefs.blockedChannelNames.length, prefs.unrecommendedChannels.length]),
              leading: _icon(AppIcons.prohibitFill),
              onTap: () => openBlockedChannels(context, controller),
            ), subtitle: tr('blocklist not recommended')),
        SettingEntry(tr('Save watch history'), (context) => SwitchItem(
              title: tr('Save watch history'),
              subtitle: tr("When off, newly watched videos won't appear in History or Home, and search terms aren't saved"),
              leading: _icon(AppIcons.clockCounterClockwiseFill),
              value: prefs.recordHistory,
              onChanged: (v) => savePrefs(prefs.copyWith(recordHistory: v)),
            )),
        SettingEntry(tr('Watch statistics'), (context) => NormalItem(
              title: tr('Watch statistics'),
              subtitle: tr('How long you watched each day and your most watched channels, kept on this computer only'),
              leading: _icon(AppIcons.chartLineUp),
              onTap: () => openWatchStats(context, controller),
            ), subtitle: tr('Watch time')),
        SettingEntry(tr('Save playback position'), (context) => SwitchItem(
              title: tr('Save playback position'),
              subtitle: tr('Used for resuming playback and progress bars on cards'),
              leading: _icon(AppIcons.hourglassMedium),
              value: prefs.recordProgress,
              onChanged: (v) => savePrefs(prefs.copyWith(recordProgress: v)),
            )),
        SettingEntry(tr('Clear watch history'), (context) => NormalItem(
              title: tr('Clear watch history'),
              subtitle: tr('{0} entries', [controller.history.length]),
              leading: _icon(AppIcons.trashSimple),
              onTap: () async {
                if (await confirmDialog(context, title: tr('Clear watch history?'), content: tr('Only deletes records on this device. Your YouTube account is not affected.'))) await controller.clearHistory();
              },
            )),
        SettingEntry(tr('Clear search history'), (context) => NormalItem(
              title: tr('Clear search history'),
              subtitle: tr('Recent searches shown below the search box'),
              leading: _icon(AppIcons.listMagnifyingGlass),
              onTap: () async {
                if (await confirmDialog(context, title: tr('Clear search history?'), content: tr('Only deletes search terms saved on this device.'))) await controller.clearSearchHistory();
              },
            )),
        SettingEntry(tr('Clear playback progress'), (context) => NormalItem(
              title: tr('Clear playback progress'),
              subtitle: tr('Start all videos from the beginning'),
              leading: _icon(AppIcons.arrowCounterClockwise),
              onTap: () async {
                if (await confirmDialog(context, title: tr('Clear playback progress?'), content: tr('"Continue watching" and the progress bars on cards will also be cleared.'))) controller.clearProgress();
              },
            )),
        SettingEntry(tr('Connected servers'), (context) => NormalItem(
              title: tr('Connected servers'),
              subtitle: tr('Which servers Lumtub connects to and what each learns; whatever can be turned off can be turned off here'),
              leading: _icon(AppIcons.network),
              onTap: () => openPrivacyConnections(context, controller),
            ), subtitle: tr('privacy servers network connections telemetry third party')),
        SettingEntry(tr('Incognito mode'), (context) => SwitchItem(
              title: tr('Incognito mode'),
              subtitle: keyNames(tr("Watch history, searches and progress aren't recorded and For you doesn't learn; it ends when Lumtub closes. Shortcut Ctrl+Shift+N")),
              leading: _icon(AppIcons.eyeSlash),
              value: controller.incognito,
              onChanged: controller.setIncognito,
            ), subtitle: tr('incognito private no history')),
        SettingEntry(tr('Clear local data'), (context) => NormalItem(
              title: tr('Clear local data'),
              subtitle: tr('Choose what to remove from this computer; favorites, playlists and followed channels are kept'),
              leading: _icon(AppIcons.broom),
              onTap: () => _clearLocalData(context, controller),
            ), subtitle: tr('clear delete data privacy reset uninstall')),
      ],
    SettingsCategory.recommend => [
        SettingEntry(tr('Focus mode: hide the home page'), (context) => SwitchItem(
              title: tr('Focus mode: hide the home page'),
              subtitle: tr('The home page shows no videos, only search'),
              leading: _icon(AppIcons.personSimpleTaiChi),
              value: prefs.focusHideHome,
              onChanged: (v) => savePrefs(prefs.copyWith(focusHideHome: v)),
            ), subtitle: tr('Focus mode')),
        SettingEntry(tr('Focus mode: hide related videos'), (context) => SwitchItem(
              title: tr('Focus mode: hide related videos'),
              subtitle: tr('The watch page neither shows nor loads related videos; the queue plays as usual. The same switch as “Show related videos” under Other settings'),
              leading: _icon(AppIcons.filmReel),
              value: !prefs.showRelated,
              onChanged: (v) => savePrefs(prefs.copyWith(showRelated: !v)),
            ), subtitle: tr('Focus mode')),
        SettingEntry(tr('Focus mode: hide comments'), (context) => SwitchItem(
              title: tr('Focus mode: hide comments'),
              subtitle: tr('The watch page neither shows nor loads comments'),
              leading: _icon(AppIcons.chatCircleSlash),
              value: prefs.focusHideComments,
              onChanged: (v) => savePrefs(prefs.copyWith(focusHideComments: v)),
            ), subtitle: tr('Focus mode')),
        SettingEntry(tr('Show For you on Home'), (context) => SwitchItem(
              title: tr('Show "For you" on Home'),
              subtitle: tr('Calculated on this device from your watch history, favorites and follows. Nothing is uploaded'),
              leading: _icon(AppIcons.sparkle),
              value: prefs.homeShowRecommended,
              onChanged: (v) => savePrefs(prefs.copyWith(homeShowRecommended: v)),
            )),
        SettingEntry(tr('Auto-refresh For you'), (context) => SwitchItem(
              title: tr('Auto-refresh "For you"'),
              subtitle: tr('Gathers it again at launch and once the list is over 30 minutes old; when off, the last list stays until you press Refresh'),
              leading: _icon(AppIcons.arrowClockwise),
              value: prefs.homeAutoRefresh,
              enabled: prefs.homeShowRecommended,
              onChanged: (v) => savePrefs(prefs.copyWith(homeAutoRefresh: v)),
            ), subtitle: tr('startup refresh')),
        SettingEntry(tr('Hide Shorts'), (context) => SwitchItem(
              title: tr('Hide all Shorts'),
              subtitle: tr('No Shorts in search, channels, Home or Explore'),
              leading: _icon(AppIcons.deviceMobile),
              value: prefs.hideShorts,
              onChanged: (v) => savePrefs(prefs.copyWith(hideShorts: v)),
            ), subtitle: tr('shorts hide')),
        SettingEntry(tr('Hide AI-generated videos'), (context) => NormalItem(
              title: tr('Hide AI-generated videos'),
              subtitle: tr('Now: {0}. Applies to Home, search, Explore, related videos and channels; subscribed channels are not affected. Each video is checked once with YouTube for its AI label. The AI channel lists come from KillSlop (killslop.app, CC BY-SA 4.0) and AiSList (CC BY-NC 4.0) and are downloaded daily', [labelOf(_aiFilterModes, prefs.aiFilter)]),
              leading: _icon(AppIcons.robot),
              onTap: () => pickFromDialog<AiFilterMode>(context, title: tr('Hide AI-generated videos'), value: prefs.aiFilter, values: _aiFilterModes, onSelected: (v) => savePrefs(prefs.copyWith(aiFilter: v))),
            ), subtitle: tr('AI artificial intelligence generated synthetic hide')),
        SettingEntry(tr('Shorts in For You'), (context) => NormalItem(
              title: tr('Shorts in For You'),
              subtitle: prefs.hideShorts
                  ? tr('All Shorts are hidden')
                  : tr('Now: {0}. Shorts use YouTube Shorts metadata or short duration. They are separate from ordinary vertical videos and affect For You on Home and Explore only', [labelOf(_feedLevels, prefs.feedShorts)]),
              leading: _icon(AppIcons.deviceMobile),
              enabled: !prefs.hideShorts,
              onTap: () => pickFromDialog<FeedLevel>(context, title: tr('Shorts in For You'), value: prefs.feedShorts, values: _feedLevels, onSelected: (v) => savePrefs(prefs.copyWith(feedShorts: v))),
            ), subtitle: tr("shorts fewer don't recommend")),
        SettingEntry(tr('Vertical videos in For You'), (context) => NormalItem(
              title: tr('Vertical videos in For You'),
              subtitle: tr('Now: {0}. A vertical video has known dimensions with height greater than width. It is separate from Shorts and affects For You on Home and Explore only', [labelOf(_feedLevels, prefs.feedVertical)]),
              leading: _icon(AppIcons.deviceMobileSpeaker),
              onTap: () => pickFromDialog<FeedLevel>(context, title: tr('Vertical videos in For You'), value: prefs.feedVertical, values: _feedLevels, onSelected: (v) => savePrefs(prefs.copyWith(feedVertical: v))),
            ), subtitle: tr("vertical fewer don't recommend")),
        SettingEntry(tr('Block controversial religious groups'), (context) => NormalItem(
              title: tr('Block controversial religious groups'),
              subtitle: prefs.blockGroups
                  ? tr("On, {0} groups blocked; a search for a channel's exact name still finds it", [blockedGroups.where(prefs.groupOn).length])
                  : tr('Off'),
              leading: _icon(AppIcons.prohibitFill),
              onTap: () => openBlockedGroups(context, controller),
            ), subtitle: tr('Falun Gong Almighty God Shincheonji Unification cult heresy 法轮功 全能神 新天地 统一教')),
        SettingEntry(tr('Block state propaganda media'), (context) => NormalItem(
              title: tr('Block state propaganda media'),
              subtitle: prefs.blockStateMedia
                  ? tr('On, blocking {0} kinds of media', [stateMedia.where((g) => prefs.groupOn(g, media: true)).length])
                  : tr('Off'),
              leading: _icon(AppIcons.megaphone),
              onTap: () => openStateMedia(context, controller),
            ), subtitle: tr('CGTN CCTV RT government propaganda state media')),
        SettingEntry(tr('Update block lists automatically'), (context) => SwitchItem(
              title: tr('Update block lists automatically'),
              subtitle: _blockListsVersion(controller),
              leading: _icon(AppIcons.arrowsClockwise),
              value: prefs.updateBlockLists,
              onChanged: (v) => savePrefs(prefs.copyWith(updateBlockLists: v)),
            )),
        SettingEntry(tr('Clear Not interested'), (context) => NormalItem(
              title: tr('Clear "Not interested" list'),
              subtitle: tr('{0} videos', [controller.homeFeed?.notInterested.videos.length ?? 0]),
              leading: _icon(AppIcons.thumbsDown),
              onTap: () async {
                if (await confirmDialog(context, title: tr('Clear "Not interested" list?'), content: tr('Marked videos and channels will show up in recommendations again.'))) await controller.clearNotInterested();
              },
            )),
        SettingEntry(tr('Show Continue watching on Home'), (context) => SwitchItem(
              title: tr('Show "Continue watching" on Home'),
              subtitle: tr('Unfinished videos'),
              leading: _icon(AppIcons.playCircle),
              value: prefs.homeShowContinue,
              onChanged: (v) => savePrefs(prefs.copyWith(homeShowContinue: v)),
            )),
        SettingEntry(tr('Show Recently watched on Home'), (context) => SwitchItem(
              title: tr('Show "Recently watched" on Home'),
              leading: _icon(AppIcons.clockCountdown),
              value: prefs.homeShowRecent,
              onChanged: (v) => savePrefs(prefs.copyWith(homeShowRecent: v)),
            )),
        SettingEntry(tr('Title keyword filter'), (context) => NormalItem(
              title: tr('Title keyword filter'),
              subtitle: prefs.blockedKeywords.isEmpty ? tr('Tap to add') : tr('{0} keywords', [prefs.blockedKeywords.length]),
              leading: _icon(AppIcons.funnelSimple),
              onTap: () async {
                final result = await showDialog<List<String>>(
                  context: context,
                  builder: (context) => ListEditorDialog(title: tr('Title keyword filter'), initialItems: prefs.blockedKeywords, hintText: tr('Enter keywords (case-insensitive)'), itemLabel: tr('Keywords')),
                );
                if (result != null) savePrefs(controller.preferences.copyWith(blockedKeywords: result));
              },
            ), subtitle: tr('Block keywords')),
        SettingEntry(tr('Minimum video length'), (context) => NormalItem(
              title: tr('Minimum video length'),
              subtitle: tr('Current: {0}. Shorter videos are hidden', [labelOf(_durations, prefs.minDurationMinutes)]),
              leading: _icon(AppIcons.timer),
              onTap: () => pickFromDialog<int>(context, title: tr('Minimum video length'), value: prefs.minDurationMinutes, values: _durations, onSelected: (v) => savePrefs(prefs.copyWith(minDurationMinutes: v))),
            ), subtitle: tr('Duration filter')),
        SettingEntry(tr('Hide watched videos'), (context) => SwitchItem(
              title: tr('Hide watched videos'),
              subtitle: tr('Based on playback progress on this device'),
              leading: _icon(AppIcons.eyeSlash),
              value: prefs.hideWatched,
              onChanged: (v) => savePrefs(prefs.copyWith(hideWatched: v)),
            )),
        SettingEntry(tr('Hide members-only videos'), (context) => SwitchItem(
              title: tr('Hide members-only videos'),
              subtitle: tr('Videos only channel members can watch are left out of lists'),
              leading: _icon(AppIcons.eyeSlash),
              value: prefs.hideMembersOnly,
              onChanged: (v) => savePrefs(prefs.copyWith(hideMembersOnly: v)),
            ), subtitle: tr('members only membership')),
      ],
    SettingsCategory.subscriptions => [
        SettingEntry(tr('Refresh automatically when opening Subscriptions'), (context) => SwitchItem(
              title: tr('Refresh automatically when opening Subscriptions'),
              subtitle: tr('When off, updates only when you tap refresh'),
              leading: _icon(AppIcons.arrowsCounterClockwise),
              value: prefs.feedAutoRefresh,
              onChanged: (v) => savePrefs(prefs.copyWith(feedAutoRefresh: v)),
            )),
        SettingEntry(tr('Auto-refresh interval'), (context) => NormalItem(
              title: tr('Auto-refresh interval'),
              subtitle: tr("Current: {0}. Revisiting within this interval won't reload", [labelOf(_feedIntervals, prefs.feedRefreshMinutes)]),
              leading: _icon(AppIcons.clockClockwise),
              enabled: prefs.feedAutoRefresh,
              onTap: () => pickFromDialog<int>(context, title: tr('Auto-refresh interval'), value: prefs.feedRefreshMinutes, values: _feedIntervals, onSelected: (v) => savePrefs(prefs.copyWith(feedRefreshMinutes: v))),
            )),
        SettingEntry(tr('Apply filters to subscription feed too'), (context) => SwitchItem(
              title: tr('Apply filters to subscription feed too'),
              subtitle: tr('Keywords, Shorts, duration and watched videos; blocked channels are always hidden'),
              leading: _icon(AppIcons.funnel),
              value: prefs.filterSubscriptions,
              onChanged: (v) => savePrefs(prefs.copyWith(filterSubscriptions: v)),
            )),
        SettingEntry(tr('Refresh subscription feed now'), (context) => NormalItem(
              title: tr('Refresh subscription feed now'),
              subtitle: tr('Following {0} channels', [controller.library?.channels.length ?? 0]),
              leading: _icon(AppIcons.arrowsClockwise),
              onTap: () => controller.library?.refreshFeed(force: true),
            )),
        SettingEntry(tr('Import from file'), (context) => NormalItem(
              title: tr('Import from file'),
              subtitle: tr('Import subscriptions from a NewPipe, FreeTube or Google Takeout file; nothing is uploaded'),
              leading: _icon(AppIcons.downloadSimple),
              onTap: () {
                final library = controller.library;
                if (library != null) importSubscriptionsFromFile(context, library);
              },
            )),
      ],
    SettingsCategory.video => [
        SettingEntry(tr('Enable hardware decoding'), (context) => SwitchItem(
              title: tr('Enable hardware decoding'),
              subtitle: tr('Plays video with lower power use. Turn off if playback freezes.'),
              leading: _icon(AppIcons.cpu),
              value: hardware,
              onChanged: (value) => save(settings.copyWith(hwdec: value ? 'auto-safe' : 'no')),
            ), subtitle: tr('Hardware decoding hwdec')),
        SettingEntry(tr('Hardware decoding mode'), (context) => NormalItem(
              title: tr('Hardware decoding mode'),
              subtitle: hardware ? tr("Current: {0} (this is mpv's --hwdec, tried in order)", [settings.hwdec]) : tr('Hardware decoding off'),
              leading: _icon(AppIcons.circuitry),
              enabled: hardware,
              onTap: () async {
                final result = await showDialog<List<String>>(
                  context: context,
                  builder: (context) => OrderedMultiSelectDialog<String>(
                    title: tr('Hardware decoding mode'),
                    initValues: settings.hwdec.split(','),
                    values: [for (final (name, label) in hwdecChoices) (name, name, label)],
                  ),
                );
                if (result != null && result.isNotEmpty) save(controller.settings.copyWith(hwdec: result.join(',')));
              },
            ), subtitle: 'hwdec D3D11VA D3D12VA DXVA2 NVDEC Vulkan AMF QSV'),
        SettingEntry(tr('Playback test'), (context) => NormalItem(
              title: tr('Playback test'),
              subtitle: tr('Plays a test video as H.264, VP9 and AV1 and measures processor use, memory, dropped frames and the decoder used'),
              leading: _icon(AppIcons.speedometer),
              onTap: () => showDiagnostics(context, controller, playback: true),
            ), subtitle: tr('benchmark performance CPU hardware decoding diagnostics')),
        if (Platform.isWindows) SettingEntry(tr('D3D11VA zero-copy'), (context) => SwitchItem(
              title: tr('D3D11VA zero-copy'),
              subtitle: tr("This is mpv's --d3d11va-zero-copy and only works with d3d11va. For other decoders, pick a mode without -copy for zero-copy"),
              leading: _icon(AppIcons.lightning),
              enabled: hardware,
              value: settings.d3d11vaZeroCopy,
              onChanged: (v) => save(settings.copyWith(d3d11vaZeroCopy: v)),
            ), subtitle: 'd3d11va-zero-copy'),
        SettingEntry(tr('Decode directly to video memory'), (context) => PopupItem<String>(
              title: tr('Decode directly to video memory (vd-lavc-dr)'),
              leading: _icon(AppIcons.cpuFill),
              value: settings.directRendering,
              values: [('auto', tr('auto (default)')), ('yes', 'yes'), ('no', 'no')],
              onSelected: (v) => save(settings.copyWith(directRendering: v)),
            ), subtitle: 'vd-lavc-dr direct rendering'),
        SettingEntry(tr('Default quality'), (context) => NormalItem(
              title: tr('Default quality'),
              subtitle: tr('Current: {0}', [qualityLabel(settings.maxHeight)]),
              leading: _icon(AppIcons.sealCheck),
              onTap: () => pickFromDialog<int>(context, title: tr('Default quality'), value: settings.maxHeight, values: [for (final h in qualityHeights) (h, qualityLabel(h))], onSelected: (h) => controller.setMaxHeight(h, asDefault: true)),
            ), subtitle: tr('Quality resolution')),
        SettingEntry(tr('Playback strategy'), (context) => NormalItem(
              title: tr('Playback strategy'),
              subtitle: tr('{0}: {1}', [settings.strategy.label, settings.strategy.description]),
              leading: _icon(AppIcons.filmStrip),
              onTap: () => pickPlaybackStrategy(context, settings.strategy, (v) => save(settings.copyWith(strategy: v))),
            ), subtitle: tr('video format codec H.264 VP9 AV1 smart auto quality first low resource')),
        for (final codec in VideoCodec.values)
          SettingEntry(tr('Disable {0}', [codec.label]), (context) => SwitchItem(
                title: tr('Disable {0}', [codec.label]),
                subtitle: codec == VideoCodec.h264 && !FormatPolicy.canDisableH264(settings)
                    ? h264NeededNote
                    : codec == VideoCodec.values.first ? disabledCodecsNote : null,
                leading: _icon(AppIcons.prohibit),
                value: settings.disabledCodecs.contains(codec),
                enabled: codec != VideoCodec.h264 || FormatPolicy.canDisableH264(settings) || settings.disabledCodecs.contains(codec),
                onChanged: (v) => toggleCodec(context, settings, codec, v, save),
              ), subtitle: tr('video format disable video codecs')),
        SettingEntry(tr('Current rule'), (context) => ListTile(
              dense: true,
              leading: _icon(AppIcons.checkSquare),
              title: Text(FormatPolicy.summary(settings), style: _note(context)),
            ), subtitle: tr('Video format')),
        SettingEntry(tr('Default audio quality'), (context) => NormalItem(
              title: tr('Default audio quality'),
              subtitle: tr('Current: {0}', [settings.audioQuality.label]),
              leading: _icon(AppIcons.musicNote),
              onTap: () => pickFromDialog<AudioQuality>(
                context,
                title: tr('Default audio quality'),
                value: settings.audioQuality,
                values: _enumValues(AudioQuality.values, (q) => q.label),
                onSelected: (v) => save(settings.copyWith(audioQuality: v)),
              ),
            )),
        SettingEntry(tr('Audio output device'), (context) {
          final devices = controller.audioDevices;
          String describe(String name) => name == 'auto'
              ? tr('Auto (system default)')
              : devices.where((d) => d.name == name).map((d) => d.description.isEmpty ? d.name : d.description).firstOrNull ?? name;
          return NormalItem(
            title: tr('Audio output device'),
            subtitle: tr('Current: {0}', [describe(settings.audioDevice)]),
            leading: _icon(AppIcons.speakerHifi),
            onTap: () => pickFromDialog<String>(
              context,
              title: tr('Audio output device'),
              value: settings.audioDevice,
              values: [('auto', tr('Auto (system default)')), for (final d in devices) if (d.name != 'auto') (d.name, describe(d.name))],
              onSelected: (v) => save(settings.copyWith(audioDevice: v)),
            ),
          );
        }, subtitle: tr('Sound card headphones speakers')),
        SettingEntry(tr('Volume normalization'), (context) => NormalItem(
              title: tr('Volume normalization'),
              subtitle: tr('Current: {0}', [audioFilterPresets.where((p) => p.$1 == settings.audioFilter).map((p) => p.$2).firstOrNull ?? tr('Custom {0}', [settings.audioFilter])]),
              leading: _icon(AppIcons.equalizer),
              onTap: () => _pickAudioFilter(context, controller),
            ), subtitle: tr('loudnorm dynaudnorm af loudness')),
        SettingEntry(tr('Video and A/V sync adjustments'), (context) => NormalItem(
              title: tr('Video and A/V sync adjustments'),
              subtitle: settings.picture.isEmpty && settings.audioDelayMs == 0 ? tr('Brightness, contrast, saturation, gamma, hue, audio delay') : tr('Adjusted'),
              leading: _icon(AppIcons.slidersHorizontal),
              onTap: () => openPictureSettings(context, controller),
            ), subtitle: tr('brightness contrast saturation gamma hue audio delay audio-delay')),
        SettingEntry(tr('Playback source'), (context) => NormalItem(
              title: tr('Playback source'),
              subtitle: tr('Current: {0}{1}. Piped and Invidious servers fetch videos from YouTube for you, which avoids rate limits, but they will know which videos you watch. On failure, for livestreams, or when subtitles are on, connect directly to YouTube. When YouTube returns 429, they are tried automatically.', [settings.playbackSource.label, switch (settings.playbackSource) { PlaybackSource.pipedCustom => ' ${settings.pipedServer}', PlaybackSource.invidiousCustom => ' ${settings.invidiousServer}', _ => '' }]),
              leading: _icon(AppIcons.hardDrives),
              onTap: () => pickFromDialog<PlaybackSource>(
                context,
                title: tr('Playback source'),
                value: settings.playbackSource,
                values: _enumValues(PlaybackSource.values, (s) => s.label),
                onSelected: (source) async {
                  if (!source.isCustom) return save(settings.copyWith(playbackSource: source));
                  if (context.mounted) await openRelayServers(context, controller, source.relay!);
                },
              ),
            ), subtitle: tr('Piped Invidious server rate limit instance instance 429')),
        SettingEntry(tr('Piped servers'), (context) => NormalItem(
              title: tr('Piped servers'),
              subtitle: settings.playbackSource == PlaybackSource.pipedCustom ? tr('Current: {0}', [settings.pipedServer]) : tr('Current: automatically picks the fastest server. You can run a speed test or choose manually; the list updates daily'),
              leading: _icon(AppIcons.gauge),
              onTap: () => openRelayServers(context, controller, RelayKind.piped),
            ), subtitle: tr('Piped server speed test list update instance')),
        SettingEntry(tr('Invidious instance'), (context) => NormalItem(
              title: tr('Invidious instance'),
              subtitle: settings.playbackSource == PlaybackSource.invidiousCustom ? tr('Current: {0}', [settings.invidiousServer]) : tr('Current: automatically selects the fastest instance. You can run speed tests or choose manually; the list updates daily.'),
              leading: _icon(AppIcons.gauge),
              onTap: () => openRelayServers(context, controller, RelayKind.invidious),
            ), subtitle: tr('Invidious instance speed test list update instance')),
        SettingEntry(tr('Network proxy'), (context) {
          final proxy = controller.proxy;
          final now = proxy.url == null ? tr('Currently connecting directly') : tr('Currently using {0}{1}', [proxy.url, '']);
          return NormalItem(
            title: tr('Network proxy'),
            subtitle: tr('{0}. {1}', [settings.proxyMode.label, now]),
            leading: _icon(AppIcons.lockKey),
            onTap: () => pickFromDialog<ProxyMode>(
              context,
              title: tr('Network proxy'),
              value: settings.proxyMode,
              values: _enumValues(ProxyMode.values, (m) => m.label),
              onSelected: (mode) async {
                if (mode != ProxyMode.custom) return save(settings.copyWith(proxyMode: mode));
                await _editProxy(context, controller);
              },
            ),
          );
        }, subtitle: tr('proxy Clash v2rayN system proxy http-proxy')),
        SettingEntry(tr('Encrypted DNS'), (context) => NormalItem(
              title: tr('Encrypted DNS'),
              subtitle: tr("Current: {0}. On a direct connection, host names are looked up over DNS-over-HTTPS so DNS can't be tampered with; if the server can't be reached, the system DNS is used. Through a proxy the proxy looks names up and this has no effect. Keep it off with Clash's TUN/fake-ip mode", [DnsServer.label(settings.dnsServer, settings.dnsCustomUrl)]),
              leading: _icon(AppIcons.hardDrives),
              onTap: () => pickFromDialog<String>(
                context,
                title: tr('Encrypted DNS'),
                value: settings.dnsServer,
                values: [
                  ('', DnsServer.label('', '')),
                  for (final server in DnsServer.presets) (server.id, server.name),
                  (DnsServer.custom, tr('Custom…')),
                ],
                onSelected: (id) async {
                  var custom = settings.dnsCustomUrl;
                  if (id == DnsServer.custom) {
                    final url = await _editDnsUrl(context, custom);
                    if (url == null) return;
                    custom = url;
                  }
                  await controller.saveSettings(settings.copyWith(dnsServer: id, dnsCustomUrl: custom));
                  final server = DnsServer.of(id, custom);
                  if (server != null && context.mounted) await _testDns(context, server);
                },
              ),
            ), subtitle: tr('DNS DoH DNS-over-HTTPS Cloudflare Google Quad9 encrypted poisoning')),
        SettingEntry(tr('Network check'), (context) => NormalItem(
              title: tr('Network check'),
              subtitle: tr('Tries the YouTube API, stream extraction, video servers, subtitles and thumbnails one by one, and shows whether each went through the proxy and where it came out'),
              leading: _icon(AppIcons.globe),
              onTap: () => showDiagnostics(context, controller),
            ), subtitle: tr('diagnostics network test proxy exit address connection')),
        SettingEntry(tr('Certificate authorities'), (context) {
          final roots = [
            ('system', tr('System (default)')),
            ('mozilla', tr('Mozilla (the list Firefox uses)')),
            ('google', tr('Google (the list Chrome uses)')),
          ];
          return NormalItem(
            title: tr('Certificate authorities'),
            subtitle: tr("Now: {0}. With Mozilla or Google, only the certificate authorities on that list are trusted, not root certificates added to the system; where a company network, antivirus or proxy tool inspects HTTPS, connections fail, so keep System. Live streams and yt-dlp's own requests are not affected", [labelOf(roots, settings.certificateRoots)]),
            leading: _icon(AppIcons.sealCheck),
            onTap: () => pickFromDialog<String>(context, title: tr('Certificate authorities'), value: settings.certificateRoots, values: roots, onSelected: (value) => save(settings.copyWith(certificateRoots: value))),
          );
        }, subtitle: tr('certificate CA root TLS HTTPS Mozilla Google Chrome Firefox')),
        SettingEntry(tr('Post-quantum encryption'), (context) {
          final modes = [
            ('prefer', tr('Prefer (default)')),
            ('off', tr('Off')),
            ('require', tr('Require')),
          ];
          return NormalItem(
            title: tr('Post-quantum encryption'),
            subtitle: tr("Now: {0}. HTTPS connections Lumtub makes itself (YouTube's pages and data, the stream relay, encrypted DNS, updates) offer the X25519MLKEM768 key exchange first, which a future quantum computer can't break; servers without it use a classic exchange. Require refuses servers without it and TLS 1.2. Video players' and yt-dlp's own connections are not covered", [labelOf(modes, settings.postQuantum)]),
            leading: _icon(AppIcons.lockSimple),
            onTap: () => pickFromDialog<String>(context, title: tr('Post-quantum encryption'), value: settings.postQuantum, values: modes, onSelected: (value) => save(settings.copyWith(postQuantum: value))),
          );
        }, subtitle: tr('post-quantum quantum ML-KEM Kyber X25519MLKEM768 TLS 1.3 key exchange')),
        SettingEntry(tr('Key exchange by site'), (context) => NormalItem(
              title: tr('Key exchange by site'),
              subtitle: tr('What each site agreed on the last time Lumtub connected to it'),
              leading: _icon(AppIcons.key),
              onTap: () => _showTlsSeen(context),
            ), subtitle: tr('post-quantum TLS key exchange X25519MLKEM768 sites hosts')),
        SettingEntry(tr('Buffering mode'), (context) => NormalItem(
              title: tr('Buffering mode'),
              subtitle: tr('Current: {0}. Memory only, nothing written to disk', [labelOf(_cacheModes, settings.cacheMode)]),
              leading: _icon(AppIcons.database),
              onTap: () => pickFromDialog<String>(context, title: tr('Buffering mode'), value: settings.cacheMode, values: _cacheModes, onSelected: (value) => save(settings.copyWith(cacheMode: value))),
            ), subtitle: tr('Network cache')),
        SettingEntry(tr('Buffer size'), (context) => NormalItem(
              title: tr('Buffer size'),
              subtitle: tr('Current: {0} MB, memory limit for read-ahead', [settings.cacheMemoryMb]),
              leading: _icon(AppIcons.hardDrive),
              onTap: () => pickWithSlider(context, title: tr('Buffer size'), value: settings.cacheMemoryMb.toDouble(), min: 16, max: 512, divisions: 31, suffix: ' MB', onSelected: (v) => save(settings.copyWith(cacheMemoryMb: v.round()))),
            ), subtitle: tr('Memory limit')),
        SettingEntry(tr('Buffer duration'), (context) => NormalItem(
              title: tr('Buffer duration'),
              subtitle: tr('Current: {0} seconds, the maximum video to read ahead', [settings.cacheSeconds]),
              leading: _icon(AppIcons.timer),
              onTap: () => pickWithSlider(context, title: tr('Buffer duration'), value: settings.cacheSeconds.toDouble(), min: 1, max: 300, divisions: 299, suffix: tr(' s'), onSelected: (v) => save(settings.copyWith(cacheSeconds: v.round()))),
            ), subtitle: tr('Read-ahead time')),
        SettingEntry(tr('Video sync'), (context) => NormalItem(
              title: tr('Video sync'),
              subtitle: tr("Current: {0}, {1} (this is mpv's --video-sync)", [settings.videoSync.mpvValue, settings.videoSync.label]),
              leading: _icon(AppIcons.arrowsLeftRight),
              onTap: () => pickFromDialog<VideoSync>(
                context,
                title: tr('Video sync'),
                value: settings.videoSync,
                values: _enumValues(VideoSync.values, (v) => v.label),
                onSelected: (v) => save(settings.copyWith(videoSync: v)),
              ),
            ), subtitle: 'video-sync display-resample'),
        SettingEntry(tr('Auto sync'), (context) => NormalItem(
              title: tr('Auto sync'),
              subtitle: tr("Current: {0} (this is mpv's --autosync; 0 is off)", [settings.autosync == 0 ? tr('Close') : settings.autosync]),
              leading: _icon(AppIcons.arrowsCounterClockwise),
              onTap: () => pickWithSlider(context, title: tr('Auto sync'), value: settings.autosync.toDouble(), min: 0, max: 30, divisions: 30, suffix: '', onSelected: (v) => save(controller.settings.copyWith(autosync: v.round()))),
            ), subtitle: 'autosync'),
        SettingEntry(tr('Video scaling algorithm'), (context) => NormalItem(
              title: tr('Video scaling algorithm'),
              subtitle: tr('Current: {0}', [labelOf(_scaleModes, settings.scale)]),
              leading: _icon(AppIcons.imagesSquare),
              onTap: () => pickFromDialog<String>(context, title: tr('Video scaling algorithm'), value: settings.scale, values: _scaleModes, onSelected: (value) => save(settings.copyWith(scale: value))),
            ), subtitle: tr('scale upscaling')),
        SettingEntry(tr('Debanding'), (context) => SwitchItem(
              title: tr('Debanding'),
              subtitle: tr('Reduces banding in gradients; slightly increases GPU load'),
              leading: _icon(AppIcons.gradient),
              value: settings.deband,
              onChanged: (value) => save(settings.copyWith(deband: value)),
            ), subtitle: 'deband'),
        SettingEntry(tr('Frame interpolation'), (context) => SwitchItem(
              title: tr('Frame interpolation'),
              subtitle: tr('Makes motion smoother but increases GPU load. Takes effect on the next video. It needs video sync to the display, so with video sync set to audio it uses display-resample.'),
              leading: _icon(AppIcons.spiralFill),
              value: settings.interpolation,
              onChanged: (value) => save(settings.copyWith(interpolation: value)),
            ), subtitle: 'interpolation'),
        SettingEntry(tr('Decoding status'), (context) => _DecoderStatus(controller: controller), subtitle: tr('GPU current decoding mode VP9 AV1 video extensions')),
        SettingEntry(tr('Custom mpv options'), (context) {
          final (options, rejected) = parseMpvConf(settings.mpvConf);
          return NormalItem(
            title: tr('Custom mpv options'),
            subtitle: options.isEmpty ? tr('Use mpv.conf format, e.g. d3d11va-zero-copy=yes') : tr('{0} options set{1}', [options.length, rejected.isEmpty ? '' : tr(", {0} lines couldn't be used", [rejected.length])]),
            leading: _icon(AppIcons.code),
            onTap: () => _editMpvConf(context, controller),
          );
        }, subtitle: tr('Custom mpv.conf options')),
        SettingEntry(tr('Advanced libmpv options'), (context) => _AdvancedOptions(settings: settings, onReset: () => save(PlayerSettings(cachePath: settings.cachePath, decoderResults: settings.decoderResults))), subtitle: tr('Restore default settings')),
      ],
    SettingsCategory.play => [
        SettingEntry(tr('Speed settings'), (context) => NormalItem(
              title: tr('Speed settings'),
              subtitle: tr('Default {0}x, {1} presets available', [trimSpeed(settings.defaultSpeed), settings.speeds.length]),
              leading: _icon(AppIcons.gauge),
              onTap: () => openPlaySpeed(context, controller),
            ), subtitle: tr('Playback speed')),
        SettingEntry(tr('Remember speed and volume per channel'), (context) => SwitchItem(
              title: tr('Remember speed and volume per channel'),
              subtitle: tr("The speed and volume you set on a channel's videos are used again the next time that channel plays"),
              leading: _icon(AppIcons.slidersHorizontal),
              value: prefs.rememberChannelPlayback,
              onChanged: (v) {
                // Off forgets what was kept, so it does not come back later.
                if (!v) controller.channelPlayback?.clear();
                savePrefs(prefs.copyWith(rememberChannelPlayback: v));
              },
            ), subtitle: tr('channel speed volume')),
        SettingEntry(tr('Autoplay'), (context) => SwitchItem(
              title: tr('Autoplay'),
              subtitle: tr('Start playing as soon as a video opens'),
              leading: _icon(AppIcons.playFill),
              value: prefs.autoPlay,
              onChanged: (v) => savePrefs(prefs.copyWith(autoPlay: v)),
            )),
        SettingEntry(tr('Playback order'), (context) => PopupItem<PlayOrder>(
              title: tr('Playback order'),
              leading: _icon(AppIcons.repeat),
              value: settings.playOrder,
              values: _enumValues(PlayOrder.values, (o) => o.label),
              onSelected: controller.setPlayOrder,
            ), subtitle: tr('Autoplay next, loop')),
        SettingEntry(tr('Resume from last position'), (context) => SwitchItem(
              title: tr('Resume from last position'),
              subtitle: prefs.recordProgress ? tr('Jump to where you left off when reopening an unfinished video') : tr('Needs Save playback position in Privacy settings'),
              leading: _icon(AppIcons.clockCounterClockwiseFill),
              value: prefs.resumePlayback,
              enabled: prefs.recordProgress,
              onChanged: (v) => savePrefs(prefs.copyWith(resumePlayback: v)),
            ), subtitle: tr('Resume progress')),
        SettingEntry(tr('In-app mini player'), (context) => SwitchItem(
              title: tr('In-app mini player'),
              subtitle: tr('Keep the video playing in the mini player when leaving the watch page; off stops playback'),
              leading: _icon(AppIcons.pictureInpicture),
              value: prefs.miniPlayer,
              onChanged: (v) => savePrefs(prefs.copyWith(miniPlayer: v)),
            ), subtitle: tr('mini player leave watch page floating')),
        SettingEntry(tr('Remove from Watch later when finished'), (context) => SwitchItem(
              title: tr('Remove from Watch later when finished'),
              subtitle: tr('Videos in Watch later leave the list once played to the end'),
              leading: _icon(AppIcons.clock),
              value: prefs.watchLaterAutoRemove,
              onChanged: (v) => savePrefs(prefs.copyWith(watchLaterAutoRemove: v)),
            ), subtitle: tr('watch later auto remove')),
        SettingEntry(tr('Subtitle settings'), (context) => NormalItem(
              title: tr('Subtitle settings'),
              subtitle: '${settings.subtitleMode.label} · ${settings.subtitleOriginal ? tr("Video's own language") : settings.subtitleLanguage.label} · ${settings.subtitleScale.toStringAsFixed(1)}×',
              leading: _icon(AppIcons.subtitles),
              onTap: () => openSubtitleSettings(context, controller),
            ), subtitle: tr('Turn on subtitles automatically, subtitle language, subtitle size')),
        SettingEntry(tr('Player volume'), (context) => NormalItem(
              title: tr('Player volume'),
              subtitle: tr('Startup volume: {0}%', [settings.defaultVolume]),
              leading: _icon(AppIcons.speakerHigh),
              onTap: () => pickWithSlider(context, title: tr('Player volume'), value: settings.defaultVolume.toDouble(), min: 0, max: 100, divisions: 20, suffix: '%', onSelected: (v) => save(settings.copyWith(defaultVolume: v.round()))),
            )),
        SettingEntry(tr('Max volume'), (context) => NormalItem(
              title: tr('Max volume'),
              subtitle: tr('Current: {0}. Above 100% boosts quiet videos', [labelOf(_volumeMaxes, settings.volumeMax)]),
              leading: _icon(AppIcons.megaphone),
              onTap: () => pickFromDialog<int>(context, title: tr('Max volume'), value: settings.volumeMax, values: _volumeMaxes, onSelected: (v) => save(settings.copyWith(volumeMax: v))),
            ), subtitle: tr('Volume boost')),
        SettingEntry(tr('Auto fullscreen'), (context) => SwitchItem(
              title: tr('Auto fullscreen'),
              subtitle: tr('Go fullscreen when a video starts playing'),
              leading: _icon(AppIcons.cornersOut),
              value: prefs.autoFullscreen,
              onChanged: (v) => savePrefs(prefs.copyWith(autoFullscreen: v)),
            )),
        SettingEntry(tr('Lights off while playing'), (context) => SwitchItem(
              title: tr('Lights off while playing'),
              subtitle: tr('Dims everything but the video while it plays, back when paused'),
              leading: _icon(AppIcons.lightbulb),
              value: prefs.autoLightsOff,
              onChanged: (v) => savePrefs(prefs.copyWith(autoLightsOff: v)),
            ), subtitle: tr('Cinema mode')),
        SettingEntry(tr('Lights-off darkness'), (context) => NormalItem(
              title: tr('Lights-off darkness'),
              subtitle: tr('Everything but the video goes {0}% dark', [prefs.lightsOffDim]),
              leading: _icon(AppIcons.moon),
              onTap: () => pickWithSlider(context, title: tr('Lights-off darkness'), value: prefs.lightsOffDim.toDouble(), min: 50, max: 98, divisions: 48, suffix: '%', onSelected: (v) => savePrefs(prefs.copyWith(lightsOffDim: v.round()))),
            ), subtitle: tr('Cinema mode')),
        SettingEntry(tr('Exit fullscreen automatically'), (context) => SwitchItem(
              title: tr('Exit fullscreen automatically'),
              subtitle: tr('Exit fullscreen when a video ends and nothing is next'),
              leading: _icon(AppIcons.cornersIn),
              value: prefs.exitFullscreenOnEnd,
              onChanged: (v) => savePrefs(prefs.copyWith(exitFullscreenOnEnd: v)),
            )),
        SettingEntry(tr('Pause when minimized'), (context) => SwitchItem(
              title: tr('Pause when minimized / play when restored'),
              leading: _icon(AppIcons.minus),
              value: prefs.pauseOnMinimize,
              onChanged: (v) => savePrefs(prefs.copyWith(pauseOnMinimize: v)),
            ), subtitle: tr('Background playback')),
        SettingEntry(tr('Audio only when minimized'), (context) => SwitchItem(
              title: tr('Audio only when minimized'),
              subtitle: prefs.pauseOnMinimize
                  ? tr('Not needed while Pause when minimized is on')
                  : tr('Decode no picture while the window is minimized or in the tray; restored with the window'),
              leading: _icon(AppIcons.headphones),
              value: prefs.audioOnlyInBackground,
              enabled: !prefs.pauseOnMinimize,
              onChanged: (v) => savePrefs(prefs.copyWith(audioOnlyInBackground: v)),
            ), subtitle: tr('Background playback')),
        if (Platform.isAndroid)
          SettingEntry(tr('Match the frame rate'), (context) => SwitchItem(
                title: tr('Match the frame rate'),
                subtitle: tr('While a video plays, the screen switches to a refresh rate that fits it, so motion is even; TVs may go dark for a moment'),
                leading: _icon(AppIcons.monitorPlay),
                value: prefs.matchFrameRate,
                onChanged: (v) => savePrefs(prefs.copyWith(matchFrameRate: v)),
              ), subtitle: tr('refresh rate fps TV')),
        if (!Platform.isAndroid) SettingEntry(tr('Minimize to tray on close'), (context) => SwitchItem(
              title: tr('Minimize to tray on close'),
              subtitle: tr('The close button hides the window to the tray icon and playback continues; exit from the tray menu'),
              leading: _icon(AppIcons.layout),
              value: prefs.closeToTray,
              onChanged: (v) => savePrefs(prefs.copyWith(closeToTray: v)),
            ), subtitle: tr('tray background playback')),
        if (!Platform.isAndroid) SettingEntry(tr('Minimize to tray'), (context) => SwitchItem(
              title: tr('Minimize to tray'),
              subtitle: tr('Minimizing hides the window to the tray icon and takes it off the taskbar; click the icon to bring it back'),
              leading: _icon(AppIcons.minus),
              value: prefs.minimizeToTray,
              onChanged: (v) => savePrefs(prefs.copyWith(minimizeToTray: v)),
            ), subtitle: tr('tray background playback')),
        if (AppWindow.waylandDesktop && controller.directories != null)
          SettingEntry(tr('X11 compatibility mode'), (context) => _X11ModeSwitch(controller: controller, data: controller.directories!.data), subtitle: tr('Wayland on top picture in picture')),
        SettingEntry(tr('Show playback controls longer'), (context) => NormalItem(
              title: tr('Playback controls display time'),
              subtitle: tr('Hide after {0} without mouse movement', [labelOf(_hideTimes, prefs.controlsHideSeconds)]),
              leading: _icon(AppIcons.handTap),
              onTap: () => pickFromDialog<int>(context, title: tr('Playback controls display time'), value: prefs.controlsHideSeconds, values: _hideTimes, onSelected: (v) => savePrefs(prefs.copyWith(controlsHideSeconds: v))),
            ), subtitle: tr('Controls hide')),
        SettingEntry(tr('Most replayed curve'), (context) => SwitchItem(
              title: tr('Show the "Most replayed" curve above the progress bar'),
              subtitle: tr('Only popular videos have it; shows which parts are replayed most'),
              leading: _icon(AppIcons.chartBar),
              value: prefs.showHeatmap,
              onChanged: (v) => savePrefs(prefs.copyWith(showHeatmap: v)),
            ), subtitle: tr('heatmap progress bar most replayed')),
        SettingEntry(tr('Thin progress line'), (context) => NormalItem(
              title: tr('Thin progress line'),
              subtitle: tr('Now: {0}; a thin line at the bottom of the picture while the controls are hidden', [prefs.progressLine.label]),
              leading: _icon(AppIcons.lineSegment),
              onTap: () => pickFromDialog<ProgressLine>(context, title: tr('Thin progress line'), value: prefs.progressLine, values: [for (final v in ProgressLine.values) (v, v.label)], onSelected: (v) => savePrefs(prefs.copyWith(progressLine: v))),
            ), subtitle: tr('progress bar mini hidden')),
        SettingEntry(tr('Enable keyboard controls'), (context) => SwitchItem(
              title: tr('Enable keyboard controls'),
              subtitle: tr('Space to pause, arrow keys to seek and change volume, F for full screen and more'),
              leading: _icon(AppIcons.keyboard),
              value: prefs.keyboardShortcuts,
              onChanged: (v) => savePrefs(prefs.copyWith(keyboardShortcuts: v)),
            ), subtitle: tr('Keyboard shortcuts')),
        SettingEntry(tr('Seek duration'), (context) => NormalItem(
              title: tr('Seek duration'),
              subtitle: tr('{0}: {1} s', [_keysOf(prefs, PlayerAction.seekBack, PlayerAction.seekForward), prefs.seekSeconds]),
              leading: _icon(AppIcons.fastForward),
              enabled: prefs.keyboardShortcuts,
              onTap: () => pickWithSlider(context, title: tr('Seek duration'), value: prefs.seekSeconds.toDouble(), min: 1, max: 30, divisions: 29, suffix: tr(' s'), onSelected: (v) => savePrefs(prefs.copyWith(seekSeconds: v.round()))),
            ), subtitle: tr('Arrow keys')),
        SettingEntry(tr('Long seek duration'), (context) => NormalItem(
              title: tr('Long seek duration'),
              subtitle: tr('{0}: {1} s', [_keysOf(prefs, PlayerAction.longSeekBack, PlayerAction.longSeekForward), prefs.longSeekSeconds]),
              leading: _icon(AppIcons.caretDoubleRight),
              enabled: prefs.keyboardShortcuts,
              onTap: () => pickWithSlider(context, title: tr('Long seek duration'), value: prefs.longSeekSeconds.toDouble(), min: 5, max: 120, divisions: 23, suffix: tr(' s'), onSelected: (v) => savePrefs(prefs.copyWith(longSeekSeconds: v.round()))),
            )),
        SettingEntry(tr('Volume step'), (context) => NormalItem(
              title: tr('Volume step'),
              subtitle: tr('{0} and scroll wheel: {1}% per step', [_keysOf(prefs, PlayerAction.volumeUp, PlayerAction.volumeDown), prefs.volumeStep]),
              leading: _icon(AppIcons.speakerLow),
              onTap: () => pickWithSlider(context, title: tr('Volume step'), value: prefs.volumeStep.toDouble(), min: 1, max: 20, divisions: 19, suffix: '%', onSelected: (v) => savePrefs(prefs.copyWith(volumeStep: v.round()))),
            )),
        SettingEntry(tr('Customize shortcuts'), (context) => NormalItem(
              title: tr('Customize shortcuts'),
              subtitle: tr('Choose the keys for seeking, volume, fullscreen and more'),
              leading: _icon(AppIcons.keyboard),
              enabled: prefs.keyboardShortcuts,
              onTap: () => showShortcutSettings(context, controller),
            ), subtitle: tr('Keyboard shortcuts')),
        SettingEntry(tr('Right click on the video'), (context) => SwitchItem(
              title: tr('Right click on the video'),
              subtitle: tr('Exit fullscreen, or else go back'),
              leading: _icon(AppIcons.handTap),
              value: prefs.rightClickBack,
              onChanged: (v) => savePrefs(prefs.copyWith(rightClickBack: v)),
            ), subtitle: tr('mouse back')),
        SettingEntry(tr('Keyboard shortcuts help'), (context) => NormalItem(
              title: tr('Keyboard shortcuts help'),
              subtitle: tr('View all player shortcuts'),
              leading: _icon(AppIcons.question),
              onTap: () => showShortcutHelp(context, controller.preferences),
            )),
      ],
    SettingsCategory.style => [
        SettingEntry(tr('Language'), (context) => PopupItem<AppLanguage>(
              title: tr('Language'),
              leading: _icon(AppIcons.translate),
              value: appearance.language,
              values: [for (final l in AppLanguage.selectable) (l, l.label)],
              onSelected: (language) => changeLanguage(context, appearance.copyWith(language: language)),
            ), subtitle: 'Language 语言 English 简体中文'),
        SettingEntry(tr('Theme mode'), (context) => NormalItem(
              title: tr('Theme mode'),
              subtitle: _darkLabel(appearance),
              leading: _icon(AppIcons.sunHorizon),
              onTap: () => pickFromDialog<String>(
                context,
                title: tr('Theme mode'),
                value: appearance.darkSchedule == DarkSchedule.off ? appearance.themeMode.name : appearance.darkSchedule.name,
                values: [
                  for (final (mode, label) in themeModes) (mode.name, label),
                  (DarkSchedule.sun.name, tr('Dark from sunset to sunrise')),
                  (DarkSchedule.hours.name, tr('Dark during set hours')),
                ],
                onSelected: (choice) async {
                  if (choice == DarkSchedule.sun.name) return saveLooks(appearance.copyWith(darkSchedule: DarkSchedule.sun));
                  if (choice == DarkSchedule.hours.name) {
                    final hours = await _pickHours(context, tr('Dark hours'), appearance.darkStart, appearance.darkEnd);
                    if (hours != null) saveLooks(controller.appearance.copyWith(darkSchedule: DarkSchedule.hours, darkStart: hours.$1, darkEnd: hours.$2));
                    return;
                  }
                  saveLooks(appearance.copyWith(darkSchedule: DarkSchedule.off, themeMode: ThemeMode.values.byName(choice)));
                },
              ),
            ), subtitle: tr('dark light sunrise sunset schedule night')),
        if (appearance.darkSchedule == DarkSchedule.hours)
          SettingEntry(tr('Dark hours'), (context) => NormalItem(
                title: tr('Dark hours'),
                subtitle: _hoursLabel(appearance.darkStart, appearance.darkEnd),
                leading: _icon(AppIcons.clock),
                onTap: () async {
                  final hours = await _pickHours(context, tr('Dark hours'), appearance.darkStart, appearance.darkEnd);
                  if (hours != null) saveLooks(controller.appearance.copyWith(darkStart: hours.$1, darkEnd: hours.$2));
                },
              )),
        SettingEntry(tr('Skins'), (context) => NormalItem(
              title: tr('Skins'),
              subtitle: tr('Current: {0}', [SkinLibrary.instance.byId(appearance.skin)?.nameIn(currentLanguage.tag) ?? tr('Standard')]),
              leading: _icon(AppIcons.paintBrush),
              onTap: () => openSkins(context, controller),
            ), subtitle: '${tr('skin theme y2k retro aero chrome pixel classic window frame title bar menu bar')} ${tr('color scheme theme rice paper candlelight ink bamboo rime pine soot night voyage dusk hills falling petals sandstone high contrast')}'),
        SettingEntry(tr('Warm light'), (context) => NormalItem(
              title: tr('Warm light'),
              subtitle: tr('Now: {0}. Lays a warm light over the whole window, video included, with less blue; black stays black and white turns warm like paper', [_eyeCareLabel(appearance)]),
              leading: _icon(AppIcons.eye),
              onTap: () => pickFromDialog<EyeCare>(
                context,
                title: tr('Warm light'),
                value: appearance.eyeCare,
                values: _enumValues(EyeCare.values, (e) => e.label),
                onSelected: (care) async {
                  if (care != EyeCare.hours) return saveLooks(appearance.copyWith(eyeCare: care));
                  final hours = await _pickHours(context, tr('Warm light hours'), appearance.eyeCareStart, appearance.eyeCareEnd);
                  if (hours != null) saveLooks(controller.appearance.copyWith(eyeCare: care, eyeCareStart: hours.$1, eyeCareEnd: hours.$2));
                },
              ),
            ), subtitle: tr('eye care warm blue light night mode night light color temperature')),
        if (appearance.eyeCare == EyeCare.hours)
          SettingEntry(tr('Warm light hours'), (context) => NormalItem(
                title: tr('Warm light hours'),
                subtitle: _hoursLabel(appearance.eyeCareStart, appearance.eyeCareEnd),
                leading: _icon(AppIcons.clock),
                onTap: () async {
                  final hours = await _pickHours(context, tr('Warm light hours'), appearance.eyeCareStart, appearance.eyeCareEnd);
                  if (hours != null) saveLooks(controller.appearance.copyWith(eyeCareStart: hours.$1, eyeCareEnd: hours.$2));
                },
              )),
        if (appearance.eyeCare != EyeCare.off)
          SettingEntry(tr('Color temperature'), (context) => NormalItem(
                title: tr('Color temperature'),
                subtitle: tr('{0} K, lower is warmer; on a schedule it changes over an hour', [AppearanceSettings.kelvinOf(appearance.warmth)]),
                leading: _icon(AppIcons.sun),
                onTap: () => pickWithSlider(
                  context,
                  title: tr('Color temperature'),
                  value: (AppearanceSettings.kelvinOf(appearance.warmth) / 100).roundToDouble() * 100,
                  min: 1900,
                  max: 6000,
                  divisions: 41,
                  suffix: ' K',
                  onSelected: (v) => saveLooks(appearance.copyWith(warmth: AppearanceSettings.warmthOf(v.round()))),
                ),
              ), subtitle: tr('eye care warm blue light night mode night light color temperature')),
        SettingEntry(tr('Low resource mode'), (context) => SwitchItem(
              title: tr('Low resource mode'),
              subtitle: tr('No animations, the smallest thumbnails, nothing loaded while the pointer rests on a video, and a smaller image cache. For older computers or to save laptop battery'),
              leading: _icon(AppIcons.gauge),
              value: appearance.lowResource,
              onChanged: (v) => saveLooks(appearance.copyWith(lowResource: v)),
            ), subtitle: tr('battery performance low end memory smooth')),
        SettingEntry(tr('Video list style'), (context) => PopupItem<VideoLayout>(
              title: tr('Video list style'),
              leading: _icon(AppIcons.listDashes),
              value: appearance.layout,
              values: _enumValues(VideoLayout.values, (l) => l.label),
              onSelected: (v) => saveLooks(appearance.copyWith(layout: v)),
            ), subtitle: tr('list grid text only layout')),
        SettingEntry(tr('Pure black theme'), (context) => SwitchItem(
              title: tr('Pure black theme'),
              subtitle: tr('Pure black background in dark mode'),
              leading: _icon(AppIcons.moon),
              value: appearance.pureBlack,
              onChanged: (v) => saveLooks(appearance.copyWith(pureBlack: v)),
            ), subtitle: 'AMOLED'),
        SettingEntry(tr('Compact mode'), (context) => SwitchItem(
              title: tr('Compact mode'),
              subtitle: tr('Tighter lists, menus and settings rows, so more fits on screen'),
              leading: _icon(AppIcons.rows),
              value: appearance.compact,
              onChanged: (v) => saveLooks(appearance.copyWith(compact: v)),
            ), subtitle: tr('spacing density')),
        SettingEntry(tr('App theme'), (context) => NormalItem(
              title: tr('App theme'),
              subtitle: switch (paletteForSkin(appearance.skin)) {
                final palette? => tr('Set by the {0} color scheme', [palette.name]),
                null => tr('Current: {0} · {1}', [appearance.accentLabel, schemeVariantNames[appearance.schemeVariant]]),
              },
              leading: _icon(AppIcons.eyedropper),
              trailing: CircleAvatar(radius: 12, backgroundColor: controller.accentColor),
              onTap: () => openColorSelect(context, controller),
            ), subtitle: tr('theme color palette dynamic color')),
        SettingEntry(tr('App font'), (context) => NormalItem(
              title: tr('App font'),
              subtitle: tr('{0} · font size {1}%', [fontChoices.where((f) => f.$1 == appearance.fontFamily).map((f) => f.$2).firstOrNull ?? tr('System default'), (appearance.textScale * 100).round()]),
              leading: _icon(AppIcons.textbox),
              onTap: () => openFontSettings(context, controller),
            ), subtitle: tr('Font size text size')),
        SettingEntry(tr('Page transitions'), (context) => NormalItem(
              title: tr('Page transitions'),
              subtitle: tr('Current: {0}', [appearance.transition.label]),
              leading: _icon(AppIcons.spiral),
              onTap: () => pickFromDialog<PageTransition>(
                context,
                title: tr('Page transitions'),
                value: appearance.transition,
                values: _enumValues(PageTransition.values, (t) => t.label),
                onSelected: (v) => saveLooks(appearance.copyWith(transition: v)),
              ),
            )),
        SettingEntry(tr('Reduce animations'), (context) => NormalItem(
              title: tr('Reduce animations'),
              subtitle: appearance.lowResource
                  ? tr('Set by Low resource mode')
                  : tr('Current: {0}{1}. With fewer animations, page changes, expanding sections and hover effects finish at once', [
                      appearance.motion.label,
                      appearance.motion == MotionPreference.system ? (Motion.reduced ? tr(' (animations are off in the system)') : tr(' (animations are on in the system)')) : '',
                    ]),
              enabled: !appearance.lowResource,
              leading: _icon(AppIcons.videoCameraSlash),
              onTap: () => pickFromDialog<MotionPreference>(
                context,
                title: tr('Reduce animations'),
                value: appearance.motion,
                values: _enumValues(MotionPreference.values, (m) => m.label),
                onSelected: (v) => saveLooks(appearance.copyWith(motion: v)),
              ),
            ), subtitle: tr('animation motion reduce motion accessibility')),
        SettingEntry(tr('Navigation bar style'), (context) => PopupItem<NavigationStyle>(
              title: tr('Navigation bar style'),
              leading: _icon(AppIcons.sidebar),
              value: appearance.navigation,
              values: _enumValues(NavigationStyle.values, (n) => n.label),
              onSelected: (v) => saveLooks(appearance.copyWith(navigation: v)),
            ), subtitle: tr('sidebar bottom bar')),
        SettingEntry(tr('Default start page'), (context) => PopupItem<String>(
              title: tr('Default start page'),
              leading: _icon(AppIcons.house),
              value: prefs.startPage,
              values: startPages,
              onSelected: (v) => savePrefs(prefs.copyWith(startPage: v)),
            )),
        SettingEntry(tr('Video card width'), (context) => NormalItem(
              title: tr('Minimum video card width'),
              subtitle: tr('Current: {0} px. Smaller fits more videos per row', [appearance.cardWidth.round()]),
              leading: _icon(AppIcons.gridFour),
              onTap: () => pickWithSlider(context, title: tr('Minimum video card width'), value: appearance.cardWidth, min: 180, max: 420, divisions: 24, suffix: tr(' px'), onSelected: (v) => saveLooks(appearance.copyWith(cardWidth: v))),
            ), subtitle: tr('column width columns')),
        SettingEntry(tr('Thumbnail quality'), (context) => NormalItem(
              title: tr('Thumbnail quality'),
              subtitle: appearance.lowResource ? tr('Set by Low resource mode') : tr('Current: {0}', [appearance.thumbnailQuality.label]),
              enabled: !appearance.lowResource,
              leading: _icon(AppIcons.image),
              onTap: () => pickFromDialog<ThumbnailQuality>(
                context,
                title: tr('Thumbnail quality'),
                value: appearance.thumbnailQuality,
                values: _enumValues(ThumbnailQuality.values, (q) => q.label),
                onSelected: (v) => saveLooks(appearance.copyWith(thumbnailQuality: v)),
              ),
            ), subtitle: tr('Thumbnail')),
        SettingEntry(tr('Use dark theme on the video page'), (context) => SwitchItem(
              title: tr('Use dark theme on the video page'),
              leading: _icon(AppIcons.circleHalf),
              value: appearance.darkWatchPage,
              onChanged: (v) => saveLooks(appearance.copyWith(darkWatchPage: v)),
            )),
        if (!touchFirst) SettingEntry(tr('Show bottom status bar'), (context) => SwitchItem(
              title: tr('Show bottom status bar'),
              subtitle: tr('libmpv version and status at the bottom of the window'),
              leading: _icon(AppIcons.lineSegment),
              value: appearance.showStatusBar,
              onChanged: (v) => saveLooks(appearance.copyWith(showStatusBar: v)),
            )),
      ],
    SettingsCategory.extra => [
        SettingEntry(tr('SponsorBlock'), (context) => SwitchItem(
              title: tr('SponsorBlock'),
              subtitle: settings.sponsorBlock ? tr('On · Skipping {0} segment types, click to configure', [settings.sponsorCategories.length]) : tr('Tap to configure'),
              leading: _icon(AppIcons.airplaneTakeoff),
              value: settings.sponsorBlock,
              onChanged: (v) => save(settings.copyWith(sponsorBlock: v)),
              onTap: () => openSponsorBlock(context, controller),
            ), subtitle: tr('SponsorBlock skip sponsor ads')),
        SettingEntry(tr('Show dislikes'), (context) => SwitchItem(
              title: tr('Show dislikes'),
              subtitle: tr("Return YouTube Dislike's estimated dislikes, shown on the watch page; when on, the id of the video you watch is sent to its server"),
              leading: _icon(AppIcons.thumbsDown),
              value: settings.returnDislike,
              onChanged: (v) => save(settings.copyWith(returnDislike: v)),
            ), subtitle: tr('Return YouTube Dislike dislikes')),
        SettingEntry(tr('DeArrow titles'), (context) => SwitchItem(
              title: tr('DeArrow titles'),
              subtitle: tr("Replace clickbait titles with ones DeArrow's users submitted. Like SponsorBlock, only the first digits of a hash of the video id are sent, so the server cannot tell what you watch"),
              leading: _icon(AppIcons.textT),
              value: settings.deArrowTitles,
              onChanged: (v) => save(settings.copyWith(deArrowTitles: v)),
            ), subtitle: tr('DeArrow clickbait titles thumbnails')),
        SettingEntry(tr('DeArrow thumbnails'), (context) => SwitchItem(
              title: tr('DeArrow thumbnails'),
              subtitle: tr("Replace exaggerated thumbnails with a frame DeArrow's users picked. Its server renders the frame, so when on, the ids of videos with a replacement are sent to it"),
              leading: _icon(AppIcons.image),
              value: settings.deArrowThumbnails,
              onChanged: (v) => save(settings.copyWith(deArrowThumbnails: v)),
            ), subtitle: tr('DeArrow cover thumbnail')),
        SettingEntry(tr('Show related videos on the video page'), (context) => SwitchItem(
              title: tr('Show related videos on the video page'),
              subtitle: tr('Found by title search; when off, autoplay plays only the queue'),
              leading: _icon(AppIcons.filmReel),
              value: prefs.showRelated,
              onChanged: (v) => savePrefs(prefs.copyWith(showRelated: v)),
            )),
        SettingEntry(tr('Expand video description by default'), (context) => SwitchItem(
              title: tr('Expand video description by default'),
              leading: _icon(AppIcons.notepad),
              value: prefs.expandDescription,
              onChanged: (v) => savePrefs(prefs.copyWith(expandDescription: v)),
            )),
        SettingEntry(tr('Translation & AI'), (context) => NormalItem(
              title: tr('Translation & AI'),
              subtitle: tr('Translation: {0} · AI: {1}', [prefs.translation.service.label, controller.canSummarize ? prefs.translation.effectiveAiModel : tr('Not set')]),
              leading: _icon(AppIcons.translate),
              onTap: () => openTranslationSettings(context, controller),
            ), subtitle: '翻译目标语言 沉浸式翻译 双语对照 译文 翻译服务 AI 总结 接口 模型 语音识别 Whisper Groq 没有字幕 DeepL 微软 LibreTranslate AI OpenAI DeepSeek Claude Gemini 通义千问 Ollama prompt 提示词 API 密钥'),
        SettingEntry(tr('Check for component updates automatically'), (context) => SwitchItem(
              title: tr('Check for component updates automatically'),
              subtitle: tr('Check libmpv, yt-dlp and Deno once a day'),
              leading: _icon(AppIcons.arrowLineDown),
              value: prefs.autoCheckUpdates,
              onChanged: (v) => savePrefs(prefs.copyWith(autoCheckUpdates: v)),
            )),
        SettingEntry(tr('Update Lumtub automatically'), (context) => SwitchItem(
              title: tr('Update Lumtub automatically'),
              subtitle: tr('Downloads new versions in the background and installs them when Lumtub closes'),
              leading: _icon(AppIcons.monitorArrowUp),
              value: prefs.autoUpdateApp,
              onChanged: (v) => savePrefs(prefs.copyWith(autoUpdateApp: v)),
            )),
        SettingEntry(tr('Components'), (context) => NormalItem(
              title: tr('Components'),
              subtitle: '${controller.tools?.libmpvLabel ?? 'libmpv'} · yt-dlp ${controller.tools?.ytDlpVersion ?? tr('Not installed')}',
              leading: _icon(AppIcons.puzzlePiece),
              onTap: () => openComponents(context, controller),
            ), subtitle: tr('libmpv yt-dlp Deno check for updates roll back')),
        SettingEntry(tr('Cache location'), (context) => NormalItem(
              title: tr('Cache location'),
              subtitle: settings.cachePath ?? controller.cacheRoot?.path ?? tr('Preparing…'),
              leading: _icon(AppIcons.folder),
              onTap: () => _changeCacheLocation(context, controller),
            ), subtitle: tr('Cache folder')),
        SettingEntry(tr('Clear cache'), (context) => NormalItem(
              title: tr('Clear cache'),
              subtitle: tr('Using {0}. Only thumbnails and temporary files created by Lumtub are cleared', [formatBytes(controller.cacheBytes)]),
              leading: _icon(AppIcons.broom),
              onTap: controller.clearCache,
            ), subtitle: tr('Cache usage')),
        SettingEntry(tr('Download location'), (context) => NormalItem(
              title: tr('Download location'),
              subtitle: controller.downloads == null ? tr('Preparing…') : tr('{0}\nNew downloads are saved here; click to change', [controller.downloads!.directory]),
              leading: _icon(AppIcons.arrowCircleDown),
              onTap: controller.downloads == null ? null : () => _changeDownloadLocation(context, controller),
            ), subtitle: tr('downloads save location folder')),
        SettingEntry(tr('Data location'), (context) => NormalItem(
              title: tr('Data location'),
              subtitle: tr('{0}\nSettings, watch history, favorites and downloaded components are stored here and kept when you uninstall.', [controller.directories?.root.path ?? tr('Preparing…')]),
              leading: _icon(AppIcons.archive),
              // Android has no file manager to hand the folder to.
              onTap: controller.directories == null || Platform.isAndroid ? null : () => unawaited(openInExplorer(controller.directories!.root.path)),
            )),
      ],
    SettingsCategory.backup => [
        SettingEntry(tr('Export settings'), (context) => NormalItem(
              title: tr('Export settings'),
              subtitle: tr('Saves to a JSON file, without accounts, watch history or local paths'),
              leading: _icon(AppIcons.fileArrowUp),
              onTap: () => _exportSettings(context, controller),
            ), subtitle: tr('Backup')),
        SettingEntry(tr('Import settings'), (context) => NormalItem(
              title: tr('Import settings'),
              subtitle: tr('Restore from exported file'),
              leading: _icon(AppIcons.downloadSimple),
              onTap: () => _importSettings(context, controller),
            ), subtitle: tr('Restore')),
        SettingEntry(tr('Reset all settings'), (context) => NormalItem(
              title: tr('Reset all settings'),
              subtitle: tr('Restores defaults; watch history, favorites, playlists and account are not affected'),
              leading: _icon(AppIcons.clockCounterClockwise),
              onTap: () async {
                if (await confirmDialog(context, title: tr('Reset all settings?'), content: tr('Playback, appearance and privacy settings will all be reset to defaults.'), confirm: tr('Reset'))) await controller.resetSettings();
              },
            ), subtitle: tr('Restore default')),
      ],
    SettingsCategory.account => [
        SettingEntry(tr('YouTube account'), (context) => AccountSettings(account: controller.account, tvSignIn: controller.tvSignIn, webSignIn: controller.webSignIn, saveTvSamples: controller.saveTvSamples, note: _note(context)), subtitle: tr('Google sign-in, TV code sign-in, browser sign-in, sync, sign out, custom client')),
        SettingEntry(tr('Subscribe when following'), (context) => SwitchItem(
              title: tr('Also subscribe on YouTube when you follow a channel'),
              subtitle: tr('When signed in, following and unfollowing also subscribes or unsubscribes on your YouTube account'),
              leading: _icon(AppIcons.stack),
              value: prefs.syncFollowToYoutube,
              onChanged: (v) => savePrefs(prefs.copyWith(syncFollowToYoutube: v)),
            )),
        SettingEntry(tr('Sync watch history to YouTube'), (context) => SwitchItem(
              title: tr('Sync watch history to YouTube'),
              subtitle: tr('With the TV-code sign-in, videos watched in Lumtub are also added to your YouTube watch history, which YouTube uses for recommendations. Off by default; nothing is synced in incognito mode or when local history is off'),
              leading: _icon(AppIcons.clockCounterClockwiseFill),
              value: prefs.syncHistoryToYoutube,
              onChanged: (v) => savePrefs(prefs.copyWith(syncHistoryToYoutube: v)),
            )),
      ],
    SettingsCategory.about => aboutEntries(controller),
  };
}

String trimSpeed(double speed) => speed.toString().replaceFirst(RegExp(r'\.0$'), '');

TextStyle _note(BuildContext context) => TextStyle(color: context.colors.outline, fontSize: 12, height: 1.5);

Future<void> _exportSettings(BuildContext context, AppController controller) async {
  final now = DateTime.now();
  final name = tr('Lumtub_settings_{0}{1}{2}.json', [now.year, now.month.toString().padLeft(2, '0'), now.day.toString().padLeft(2, '0')]);
  final location = await getSaveLocation(suggestedName: name, acceptedTypeGroups: const [XTypeGroup(label: 'JSON', extensions: ['json'])]);
  if (location == null) return;
  try {
    await XFile.fromData(Uint8List.fromList(utf8.encode(controller.exportSettings())), mimeType: 'application/json', name: name).saveTo(location.path);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Settings exported'))));
  } catch (e) {
    logError('Could not export settings', e);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Export failed: {0}', [friendlyFileError(e)]))));
  }
}

Future<void> _importSettings(BuildContext context, AppController controller) async {
  final file = await openFile(acceptedTypeGroups: const [XTypeGroup(label: 'JSON', extensions: ['json'])]);
  if (file == null) return;
  final String text;
  try {
    text = await file.readAsString();
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr("Couldn't read file: {0}", [friendlyFileError(e)]))));
    return;
  }
  final ok = await controller.importSettings(text);
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? tr('Settings imported') : tr("This isn't a settings file exported by Lumtub"))));
}

Future<void> _changeDownloadLocation(BuildContext context, AppController controller) async {
  final manager = controller.downloads!;
  final selected = await getDirectoryPath(initialDirectory: manager.directory);
  if (selected != null) await manager.setDirectory(selected);
}

Future<void> _changeCacheLocation(BuildContext context, AppController controller) async {
  if (controller.cacheRoot == null) return;
  if (!controller.ensureNotPlaying(tr('Go back to the list and stop the current video before moving the cache.'))) return;
  final selected = await getDirectoryPath(initialDirectory: controller.cacheRoot!.path);
  if (selected == null || !context.mounted) return;
  await controller.changeCacheLocation(selected, (targetPath) => showDialog<bool>(context: context, builder: (context) => AlertDialog(
    title: Text(tr('Move existing cache?')),
    content: Text(tr('New location: {0}\n\nOnly the thumbnail, temp file, yt-dlp and mpv cache folders created by Lumtub are moved.', [targetPath])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr("Don't migrate"))),
      FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Move'))),
    ],
  )));
}

/// GPU, the decoder in use, which codecs were verified to decode in
/// hardware, and the optional Windows video extensions.
class _DecoderStatus extends StatefulWidget {
  const _DecoderStatus({required this.controller});
  final AppController controller;

  @override
  State<_DecoderStatus> createState() => _DecoderStatusState();
}

class _DecoderStatusState extends State<_DecoderStatus> {
  @override
  void initState() {
    super.initState();
    widget.controller.refreshWindowsVideoInfo();
  }

  AppController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final info = controller.windowsVideoInfo;
    final colors = context.colors;
    return ExpansionTile(
      // Its own key: an unkeyed tile shares the page's PageStorage slot with
      // the list's scroll offset, and reads that double as its open state.
      key: const PageStorageKey('expand:decoder'),
      leading: Icon(AppIcons.gauge),
      title: Text(tr('Decoding status'), style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(tr('Current: {0} · {1}', [controller.currentCodec, controller.currentHwdec]), style: _subtitle(context)),
      children: [
        if (Platform.isWindows) ListTile(dense: true, title: const Text('GPU'), subtitle: Text(info.gpuNames.isEmpty ? tr('Not detected or unreadable') : info.gpuNames.join('\n'))),
        ListTile(
          dense: true,
          title: Text(tr('Current decoding method')),
          subtitle: Text(tr('Video: {0}\nMethod: {1}', [controller.currentCodec, controller.currentHwdec])),
          trailing: OutlinedButton(onPressed: controller.playing == null ? null : controller.inspectCurrentDecoder, child: Text(tr('Detect'))),
        ),
        for (final (key, label) in const [('h264', 'H.264'), ('vp9', 'VP9'), ('av1', 'AV1')])
          ListTile(
            dense: true,
            title: Text(tr('{0} hardware decoding', [label])),
            trailing: Builder(builder: (context) {
              final status = controller.decodeStates[key] ?? const DecoderStatus.unverified();
              return Text(status.label, style: TextStyle(color: status.isVerified ? colors.primary : colors.onSurfaceVariant));
            }),
          ),
        if (Platform.isWindows) ...[
          _extension(context, 'VP9 Video Extensions', info.vp9Extension, 'https://apps.microsoft.com/detail/9n4d0msmp0pt'),
          _extension(context, 'AV1 Video Extension', info.av1Extension, 'https://apps.microsoft.com/detail/9mvzqvxjbq9v'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(tr("Status updates only after a matching codec actually plays. Store extensions are Windows Media Foundation components. Lumtub doesn't need them, and they can't give hardware decoding to unsupported graphics cards."), style: _note(context)),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(tr('The status updates only after a video in that format has played.'), style: _note(context)),
          ),
      ],
    );
  }

  Widget _extension(BuildContext context, String title, ExtensionStatus status, String storeUrl) {
    final colors = context.colors;
    return ListTile(
      dense: true,
      title: Text(title),
      trailing: switch (status) {
        ExtensionStatus.missing => TextButton(onPressed: () => controller.openStore(storeUrl), child: Text(tr('View in Store'))),
        ExtensionStatus.present => Text(tr('Installed'), style: TextStyle(color: colors.primary)),
        ExtensionStatus.unknown => Text(tr('Not verified yet'), style: TextStyle(color: colors.onSurfaceVariant)),
      },
    );
  }
}

class _AdvancedOptions extends StatelessWidget {
  const _AdvancedOptions({required this.settings, required this.onReset});
  final PlayerSettings settings;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    Widget option(String name, String value, String description, String applies) => ListTile(
          dense: true,
          title: Text(name, style: const TextStyle(fontFamily: 'monospace')),
          subtitle: Text(tr('{0} · takes effect {1}', [description, applies])),
          trailing: Text(value, style: TextStyle(color: context.colors.primary, fontFamily: 'monospace')),
        );
    return ExpansionTile(
      key: const PageStorageKey('expand:mpv'),
      leading: Icon(AppIcons.slidersHorizontal),
      title: Text(tr('Advanced libmpv options'), style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(tr('See the options passed to libmpv, or restore defaults'), style: _subtitle(context)),
      children: [
        option('hwdec', settings.hwdec, tr('Hardware decoding method'), tr('Next segment')),
        option('scale', settings.scale, tr('Video scaling algorithm'), tr('Immediately')),
        option('deband', settings.deband ? 'yes' : 'no', tr('Debanding'), tr('Immediately')),
        option('interpolation', settings.interpolation ? 'yes' : 'no', tr('Frame interpolation'), tr('Next segment')),
        option('hwdec-codecs', defaultHwdecCodecs, tr('Hardware-decoded codecs'), tr('Next segment')),
        if (Platform.isWindows) option('d3d11va-zero-copy', settings.d3d11vaZeroCopy ? 'yes' : 'no', tr('D3D11VA zero-copy'), tr('Next segment')),
        option('vd-lavc-dr', settings.directRendering, tr('Decode directly to video memory'), tr('Next segment')),
        option('video-sync', settings.videoSync.mpvValue, tr('Video sync'), tr('Immediately')),
        option('autosync', settings.autosync == 0 ? 'no' : '${settings.autosync}', tr('Auto sync'), tr('Immediately')),
        option('af', settings.audioFilter.isEmpty ? tr('(None)') : settings.audioFilter, tr('Audio filter'), tr('Immediately')),
        for (final (key, value) in settings.customOptions.entries.map((e) => (e.key, e.value))) option(key, value, tr('Custom options'), tr('Immediately or next video')),
        option('cache', settings.cacheMode, tr('Network cache mode'), tr('Immediately')),
        option('cache-secs', '${settings.cacheSeconds}', tr('Cache read-ahead time'), tr('Immediately')),
        option('demuxer-max-bytes', '${settings.cacheMemoryMb}MiB', tr('Cache memory limit'), tr('Immediately')),
        option('volume-max', '${settings.volumeMax}', tr('Max volume'), tr('Immediately')),
        option('audio-device', settings.audioDevice, tr('Audio output device'), tr('Immediately')),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: OutlinedButton.icon(onPressed: onReset, icon: Icon(AppIcons.arrowCounterClockwise), label: Text(tr('Restore all player defaults'))),
          ),
        ),
      ],
    );
  }
}

Future<void> _pickAudioFilter(BuildContext context, AppController controller) async {
  const custom = '\u0000custom';
  final current = controller.settings.audioFilter;
  final preset = audioFilterPresets.any((p) => p.$1 == current);
  final chosen = await showDialog<String>(
    context: context,
    builder: (context) => SelectDialog<String>(
      title: tr('Volume normalization'),
      value: preset ? current : custom,
      values: [...audioFilterPresets, (custom, preset ? tr('Custom') : tr('Custom: {0}', [current]))],
    ),
  );
  if (chosen == null || !context.mounted) return;
  if (chosen != custom) {
    await controller.saveSettings(controller.settings.copyWith(audioFilter: chosen));
    return;
  }
  final text = await showDialog<String>(
    context: context,
    builder: (context) => TextEditDialog(title: tr('Custom audio filter'), initialText: preset ? '' : current, hintText: tr('e.g. loudnorm=I=-14:LRA=7:TP=-2'), monospace: true),
  );
  if (text != null) await controller.saveSettings(controller.settings.copyWith(audioFilter: text.trim().replaceAll(RegExp(r'[\r\n]'), '')));
}

Future<void> editRelayServer(BuildContext context, AppController controller, RelayKind kind) async {
  final piped = kind == RelayKind.piped;
  final text = await showDialog<String>(
    context: context,
    builder: (context) => TextEditDialog(
      title: piped ? tr('Piped servers') : tr('Invidious instance'),
      initialText: piped ? controller.settings.pipedServer : controller.settings.invidiousServer,
      hintText: piped ? tr('e.g. https://pipedapi.kavin.rocks') : tr('For example https://yewtu.be'),
      helper: (text) {
        final colors = context.colors;
        final server = normalizePipedServer(text);
        return Text(server == null ? (piped ? tr('Enter the Piped API address (https://…)') : tr('Enter the Invidious instance address (https://…)')) : tr('Will use {0}', [server]), style: TextStyle(fontSize: 12, color: server == null ? colors.error : colors.outline));
      },
    ),
  );
  final server = text == null ? null : normalizePipedServer(text);
  if (server == null) return;
  final settings = controller.settings;
  await controller.saveSettings(piped
      ? settings.copyWith(playbackSource: PlaybackSource.pipedCustom, pipedServer: server)
      : settings.copyWith(playbackSource: PlaybackSource.invidiousCustom, invidiousServer: server));
}

Future<void> _clearLocalData(BuildContext context, AppController controller) async {
  final chosen = await showDialog<Set<LocalData>>(context: context, builder: (context) => const _ClearDataDialog());
  if (chosen == null || chosen.isEmpty) return;
  await controller.clearLocalData(chosen);
}

class _ClearDataDialog extends StatefulWidget {
  const _ClearDataDialog();

  @override
  State<_ClearDataDialog> createState() => _ClearDataDialogState();
}

class _ClearDataDialogState extends State<_ClearDataDialog> {
  // What leaves no settings to redo is chosen to start with.
  final _chosen = {LocalData.history, LocalData.progress, LocalData.recommendations, LocalData.cache};

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr('Clear local data')),
        content: SizedBox(
          width: dialogWidth(context, 420),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final kind in LocalData.values)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _chosen.contains(kind),
                title: Text(kind.label),
                onChanged: (v) => setState(() => v == true ? _chosen.add(kind) : _chosen.remove(kind)),
              ),
            const SizedBox(height: 8),
            Text(tr("Only data on this computer is removed; your YouTube account isn't affected. Favorites, playlists and followed channels are kept."), style: TextStyle(fontSize: 12, color: context.colors.outline)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.colors.error, foregroundColor: context.colors.onError),
            onPressed: _chosen.isEmpty ? null : () => Navigator.pop(context, {..._chosen}),
            child: Text(tr('Clear')),
          ),
        ],
      );
}

Future<String?> _editDnsUrl(BuildContext context, String current) async {
  final text = await showDialog<String>(
    context: context,
    builder: (context) => TextEditDialog(
      title: tr('Custom DoH address'),
      initialText: current,
      hintText: tr('e.g. https://dns.example.com/dns-query'),
      helper: (text) {
        final colors = context.colors;
        final url = DnsServer.normalize(text);
        return Text(url == null ? tr('Enter a DoH address starting with https://') : tr('Will use {0}', [url]), style: TextStyle(fontSize: 12, color: url == null ? colors.error : colors.outline));
      },
    ),
  );
  return text == null ? null : DnsServer.normalize(text);
}

/// Looks www.youtube.com up over [server] and says how it went.
Future<void> _showTlsSeen(BuildContext context) => showDialog<void>(
      context: context,
      builder: (context) {
        final seen = NativeCore.tlsSeen();
        final colors = context.colors;
        return AlertDialog(
          title: Text(tr('Key exchange by site')),
          content: SizedBox(
            width: dialogWidth(context, 480),
            child: seen.isEmpty
                ? Text(tr('No HTTPS connection yet since Lumtub started'))
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final site in seen)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(site.postQuantum ? AppIcons.lockSimple : AppIcons.lockOpen, size: 18, color: site.postQuantum ? colors.primary : colors.outline),
                          title: Text(site.host),
                          subtitle: Text(site.postQuantum ? tr('{0}, post-quantum', [site.group]) : tr('{0}, not post-quantum', [site.group])),
                        ),
                    ],
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Close')))],
        );
      },
    );

Future<void> _testDns(BuildContext context, DnsServer server) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(SnackBar(content: Text(tr('Testing {0}…', [server.name])), duration: const Duration(seconds: 10)));
  final result = await testDnsServer(server);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(result.ok
        ? tr('{0} works: www.youtube.com → {1} in {2} ms', [server.name, result.addresses.take(2).join(tr(', ')), result.milliseconds])
        : tr("Can't reach {0} right now ({1}); the system DNS is used meanwhile", [server.name, result.error])),
    duration: const Duration(seconds: 6),
  ));
}

Future<void> _editProxy(BuildContext context, AppController controller) async {
  final text = await showDialog<String>(
    context: context,
    builder: (context) => TextEditDialog(
      title: tr('Proxy address'),
      initialText: controller.settings.proxyAddress,
      hintText: tr('e.g. 127.0.0.1:7890 or socks5://127.0.0.1:7891'),
      helper: (text) {
        final colors = context.colors;
        final address = NetworkProxy.normalize(text);
        return Text(
          address == null ? tr('Enter host:port, optionally prefixed with http:// or socks5://') : tr('Will use {0}{1}', [address, address.startsWith('http://') ? '' : tr(". Video streams only support HTTP proxies, so they'll connect directly")]),
          style: TextStyle(fontSize: 12, color: address == null ? colors.error : colors.outline),
        );
      },
    ),
  );
  final address = text == null ? null : NetworkProxy.normalize(text);
  if (address != null) await controller.saveSettings(controller.settings.copyWith(proxyMode: ProxyMode.custom, proxyAddress: address));
}

Future<void> _editMpvConf(BuildContext context, AppController controller) async {
  final text = await showDialog<String>(
    context: context,
    builder: (context) => TextEditDialog(
      title: tr('Custom mpv options'),
      initialText: controller.settings.mpvConf,
      hintText: tr('# One per line, same as mpv.conf\nd3d11va-zero-copy=yes\nhwdec-codecs = h264,vc1,hevc,vp8,vp9,av1,prores,ffv1\nvd-lavc-dr = auto'),
      monospace: true,
      maxLines: 14,
      helper: (text) {
        final (options, rejected) = parseMpvConf(text);
        final colors = context.colors;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('{0} options available, applied after other settings. Some take effect on the next video or after restart.', [options.length]), style: TextStyle(fontSize: 12, color: colors.outline)),
          for (final (line, reason) in rejected) Text(tr("Won't apply: {0} ({1})", [line, reason]), style: TextStyle(fontSize: 12, color: colors.error)),
        ]);
      },
    ),
  );
  if (text != null) await controller.saveSettings(controller.settings.copyWith(mpvConf: text));
}

TextStyle _subtitle(BuildContext context) => Theme.of(context).textTheme.labelMedium!.copyWith(color: context.colors.outline);

/// Linux on Wayland: draw the window through XWayland from the next start,
/// so it can stay on top and picture in picture can be placed.
class _X11ModeSwitch extends StatefulWidget {
  const _X11ModeSwitch({required this.controller, required this.data});

  final AppController controller;
  final Directory data;

  @override
  State<_X11ModeSwitch> createState() => _X11ModeSwitchState();
}

class _X11ModeSwitchState extends State<_X11ModeSwitch> {
  late bool _on = AppWindow.x11Marker(widget.data).existsSync();

  Future<void> _set(bool on) async {
    final marker = AppWindow.x11Marker(widget.data);
    try {
      if (on) {
        await marker.writeAsString('');
      } else if (await marker.exists()) {
        await marker.delete();
      }
    } catch (_) {
      return;
    }
    setState(() => _on = on);
    if (!mounted) return;
    final restart = await confirmDialog(context, title: tr('Takes effect after a restart'), content: tr('Lumtub uses the new display mode after it restarts. Restart now?'), confirm: tr('Restart now'));
    if (restart) await widget.controller.restart();
  }

  @override
  Widget build(BuildContext context) => SwitchItem(
        title: tr('X11 compatibility mode'),
        subtitle: tr('Draws the window through XWayland so pinning and picture in picture stay on top; may look slightly blurry with display scaling'),
        leading: Icon(AppIcons.layout),
        value: _on,
        onChanged: (v) => unawaited(_set(v)),
      );
}

/// The keys of two opposite actions, as `← / →`.
String _keysOf(AppPreferences prefs, PlayerAction a, PlayerAction b) {
  final keys = shortcutKeys(prefs.shortcutKeys);
  return [for (final action in [a, b]) keys[action]!.map((k) => k.label).join(', ')].where((k) => k.isNotEmpty).join(' / ');
}

/// When the block lists in use were changed, and the downloaded ones a
/// restart brings in.
String _blockListsVersion(AppController controller) {
  String day(int seconds) {
    final t = DateTime.fromMillisecondsSinceEpoch(seconds * 1000).toLocal();
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  final now = BlockLists.instance.version;
  final waiting = controller.blockListUpdates?.waiting;
  final current = now > 0 ? day(now) : '?';
  return waiting != null ? tr('Lists of {0}; those of {1} are used after a restart', [current, day(waiting)]) : tr('Lists of {0}', [current]);
}
