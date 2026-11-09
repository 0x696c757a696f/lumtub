// Settings sub-pages adapted from PiliNara (lib/pages/setting/pages/
// play_speed_set.dart, color_select.dart, font_setting.dart, logs.dart,
// lib/pages/setting/widgets/ and lib/pages/about/view.dart).
//
// PiliNara: https://github.com/Starfallan/PiliNara
// Copyright (C) PiliNara contributors.
// Adapted for Lumtub under the GNU General Public License, version 3 or
// later. Changes: the pages read and save Lumtub's settings through
// AppController instead of PiliNara's storage, GetX and SmartDialog are
// removed, and the Bilibili-only options (danmaku, long-press speed,
// dynamic colour on Android) are dropped or replaced by Windows ones.

import 'dart:io';

import 'package:flutter/material.dart';

import '../../app_updater.dart';
import '../../tool_manager.dart';
import '../../app/app_controller.dart';
import '../../app_log.dart';
import '../../app_preferences.dart';
import '../../blocked_groups.dart';
import '../../encrypted_dns.dart';
import '../../piped_streams.dart';
import '../../appearance_settings.dart';
import '../../player_settings.dart';
import '../../translation.dart';
import '../../windows_shell.dart';
import '../../widgets/pilinara_settings_tiles.dart';
import '../common.dart';
import '../subtitle_style.dart';
import '../theme.dart';
import '../palettes.dart';
import '../theme_preset_card.dart';
import 'settings_sections.dart';
import 'support_page.dart';
import 'translation_settings_page.dart';
import '../../l10n/l10n.dart';
import '../motion.dart';
import '../app_icons.dart';

const _repository = 'https://github.com/0x696c757a696f/lumtub';

/// Pushes a sub-page that rebuilds whenever [controller] changes.
Future<void> _push(BuildContext context, AppController controller, String title, List<Widget> Function(BuildContext context) children, {List<Widget>? actions}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(title), actions: actions),
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => ListView(padding: const EdgeInsets.only(bottom: 40), children: children(context)),
        ),
      ),
    ));

Widget _header(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall!.copyWith(color: context.colors.primary)),
    );

Widget _tip(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(AppIcons.info, size: 16, color: context.colors.outline),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: context.colors.outline, fontSize: 12, height: 1.5))),
      ]),
    );

// 隐私设置 › 屏蔽频道

/// Blocked channels, by id or typed name, and channels not to recommend.
Future<void> openBlockedChannels(BuildContext context, AppController controller) => _push(
      context,
      controller,
      tr('Blocked channels'),
      (context) {
        final prefs = controller.preferences;
        final outline = TextStyle(color: context.colors.outline, fontSize: 12);
        return [
          _header(context, tr('Blocked channels')),
          if (prefs.blockedChannels.isEmpty && prefs.blockedChannelNames.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(tr('No channels blocked yet. Use “Add” at the top right, or choose “Block this channel” on a video card, channel page or the watch page.'), style: TextStyle(color: context.colors.outline, height: 1.6)),
            ),
          for (final channel in prefs.blockedChannels)
            ListTile(
              leading: Icon(AppIcons.userMinus),
              title: Text(channel.name.isEmpty ? channel.id : channel.name),
              subtitle: Text(channel.id, style: outline),
              trailing: TextButton(onPressed: () => controller.unblockChannel(channel.id), child: Text(tr('Remove'))),
            ),
          for (final name in prefs.blockedChannelNames)
            ListTile(
              leading: Icon(AppIcons.userMinus),
              title: Text(name),
              subtitle: Text(tr('Blocked by name'), style: outline),
              trailing: TextButton(onPressed: () => controller.unblockChannelName(name), child: Text(tr('Remove'))),
            ),
          _tip(context, tr('Blocked channels never show in the home feed, Explore, search, related videos or the subscription feed. The list stays on this computer.')),
          _header(context, tr('Channels not recommended')),
          if (prefs.unrecommendedChannels.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(tr("None yet. Choose “Don't recommend this channel” on a video card, channel page or the watch page."), style: TextStyle(color: context.colors.outline, height: 1.6)),
            ),
          for (final channel in prefs.unrecommendedChannels)
            ListTile(
              leading: Icon(AppIcons.thumbsDown),
              title: Text(channel.name.isEmpty ? channel.id : channel.name),
              subtitle: Text(channel.id, style: outline),
              trailing: TextButton(onPressed: () => controller.setRecommendChannel(channel, true), child: Text(tr('Recommend again'))),
            ),
          _tip(context, tr('Channels not recommended stay out of the home feed, Explore and related videos, but still show in searches and follows.')),
        ];
      },
      actions: [
        Builder(builder: (context) => TextButton.icon(
              onPressed: () => _addBlockedChannel(context, controller),
              icon: Icon(AppIcons.plus),
              label: Text(tr('Add')),
            )),
        const SizedBox(width: 8),
      ],
    );

Future<void> _addBlockedChannel(BuildContext context, AppController controller) async {
  final text = TextEditingController();
  final typed = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('Blocked channels')),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: text,
          autofocus: true,
          decoration: InputDecoration(
            labelText: tr('Channel link or full name'),
            helperText: tr('A link with a channel ID starting with UC blocks by ID; anything else blocks the channel with exactly that name'),
            helperMaxLines: 2,
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, text.text), child: Text(tr('Block'))),
      ],
    ),
  );
  text.dispose();
  if (typed == null) return;
  final blocked = controller.blockChannelTyped(typed);
  if (blocked != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Blocked “{0}”', [blocked]))));
}

// 首页与搜索设置 › 屏蔽争议宗教团体

/// The groups of blocked_groups.dart, all on or off and one by one.
Future<void> openBlockedGroups(BuildContext context, AppController controller) => _push(context, controller, tr('Block controversial religious groups'), (context) {
      final prefs = controller.preferences;
      void save(AppPreferences next) => controller.savePreferences(next);
      return [
        SwitchListTile(
          secondary: const Icon(AppIcons.prohibitFill),
          title: Text(tr('Block controversial religious groups')),
          subtitle: Text(tr("Channels and videos of the groups below are left out of recommendations, Explore, related videos and search; other channels' reports about them, and searches for their names, are not affected")),
          value: prefs.blockGroups,
          onChanged: (v) => save(prefs.copyWith(blockGroups: v)),
        ),
        _tip(context, tr("Searching for a channel's exact name (letter case included; not one character more or less) still finds that channel and its videos. Followed channels still show in subscriptions.")),
        _header(context, tr('Groups to block')),
        ..._groupTiles(context, controller, blockedGroups, media: false),
        _tip(context, tr('Tap a group to see its whole list and untick entries one by one. Only channel names, @handles and channel IDs are matched, never titles or descriptions, and the list stays on this computer. To block more, use Home & search › Title keyword filter, or Privacy › Blocked channels.')),
      ];
    });

Future<void> openStateMedia(BuildContext context, AppController controller) => _push(context, controller, tr('Block state propaganda media'), (context) {
      final prefs = controller.preferences;
      void save(AppPreferences next) => controller.savePreferences(next);
      return [
        SwitchListTile(
          secondary: Icon(AppIcons.megaphone),
          title: Text(tr('Block state propaganda media')),
          subtitle: Text(tr('Channels and videos of the government propaganda outlets below are hidden from recommendations, Explore, related videos and search')),
          value: prefs.blockStateMedia,
          onChanged: (v) => save(prefs.copyWith(blockStateMedia: v)),
        ),
        _tip(context, tr('Only the channel name counts, so videos from other channels that repost or report on them still show. Editorially independent public broadcasters such as the BBC, NHK and PBS are not included. Searching for the exact channel name (case-sensitive) still finds them.')),
        _header(context, tr('Groups to block')),
        ..._groupTiles(context, controller, stateMedia, media: true),
        _tip(context, tr('The list stays on this computer. Add any channel it misses under Privacy › Blocked channels.')),
      ];
    });

/// [prefs] with [group] ticked or not.
AppPreferences _withGroup(AppPreferences prefs, BlockedGroup group, bool on, {required bool media}) {
  List<String> toggled(List<String> list, bool add) => add ? {...list, group.name}.toList() : [...list.where((n) => n != group.name)];
  if (!group.onByDefault) return prefs.copyWith(enabledGroups: toggled(prefs.enabledGroups, on));
  return media ? prefs.copyWith(allowedMedia: toggled(prefs.allowedMedia, !on)) : prefs.copyWith(allowedGroups: toggled(prefs.allowedGroups, !on));
}

/// One row per group: a tick for the whole group, and a tap for its list.
List<Widget> _groupTiles(BuildContext context, AppController controller, List<BlockedGroup> groups, {required bool media}) {
  final prefs = controller.preferences;
  final enabled = media ? prefs.blockStateMedia : prefs.blockGroups;
  final allowed = prefs.allowedEntries.toSet();
  return [
    for (final group in groups)
      Builder(builder: (context) {
        final entries = group.entries;
        final off = entries.where((e) => allowed.contains(e.key)).length;
        return ListTile(
          dense: true,
          enabled: enabled,
          leading: Checkbox(
            value: prefs.groupOn(group, media: media),
            onChanged: enabled ? (on) => controller.savePreferences(_withGroup(prefs, group, on == true, media: media)) : null,
          ),
          title: Text(group.label),
          subtitle: Text(
            [
              if (group.note case final note?) tr(note),
              [
                tr('{0} entries', [entries.length]),
                if (off > 0) tr('{0} unticked', [off]),
                if (!group.onByDefault) tr('Not blocked by default'),
                entries.take(4).map((e) => e.label).join(tr(', ')),
              ].join(' · '),
            ].join('\n'),
            maxLines: group.note == null ? 1 : 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.colors.outline, fontSize: 12),
          ),
          trailing: Icon(AppIcons.caretRight),
          onTap: () => _openGroupEntries(context, controller, group, media: media),
        );
      }),
  ];
}

/// Everything [group] blocks, each tickable on its own.
Future<void> _openGroupEntries(BuildContext context, AppController controller, BlockedGroup group, {required bool media}) {
  final entries = group.entries;
  void setAll(bool on) {
    final keys = {for (final e in entries) e.key};
    final rest = controller.preferences.allowedEntries.where((k) => !keys.contains(k));
    controller.savePreferences(controller.preferences.copyWith(allowedEntries: [...rest, if (!on) ...keys]));
  }

  return _push(context, controller, group.label, (context) {
    final prefs = controller.preferences;
    final allowed = prefs.allowedEntries.toSet();
    final groupOn = prefs.groupOn(group, media: media) && (media ? prefs.blockStateMedia : prefs.blockGroups);
    return [
      SwitchListTile(
        title: Text(tr('Block this group')),
        subtitle: Text(media ? tr('Needs "Block state propaganda media" on') : tr('Needs "Block controversial religious groups" on')),
        value: prefs.groupOn(group, media: media),
        onChanged: (on) => controller.savePreferences(_withGroup(prefs, group, on, media: media)),
      ),
      for (final kind in BlockKind.values)
        if (entries.where((e) => e.kind == kind).toList() case final list when list.isNotEmpty) ...[
          _header(context, '${kind.label} · ${list.length}'),
          for (final entry in list)
            CheckboxListTile(
              dense: true,
              enabled: groupOn,
              title: Text(entry.label),
              subtitle: entry.forms.length > 1 ? Text(entry.forms.skip(1).join(tr(', ')), style: TextStyle(color: context.colors.outline, fontSize: 12)) : null,
              value: !allowed.contains(entry.key),
              onChanged: (on) => controller.savePreferences(prefs.copyWith(
                allowedEntries: on == true ? [...prefs.allowedEntries.where((k) => k != entry.key)] : [...prefs.allowedEntries, entry.key],
              )),
            ),
        ],
      _tip(context, switch (media) {
        true => tr('A channel is blocked when its name is one of these or starts with one, followed by a space or sign.'),
        false => tr('"Words in titles and channel names" block wherever they appear in a title or channel name; "Channel names" only count the channel name, which must be the name or start with it; @handles and channel ids must match exactly.'),
      }),
    ];
  }, actions: [
    TextButton(onPressed: () => setAll(true), child: Text(tr('Tick all'))),
    TextButton(onPressed: () => setAll(false), child: Text(tr('Untick all'))),
  ]);
}

// 播放设置 › 倍速设置 (PiliNara's play_speed_set.dart)

Future<void> openPlaySpeed(BuildContext context, AppController controller) {
  void save(PlayerSettings next) => controller.saveSettings(next);

  Future<void> add(BuildContext context) async {
    final text = TextEditingController();
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Add speed')),
        content: TextField(
          controller: text,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: tr('Custom speed'), helperText: tr('Between 0.1 and 5')),
          onSubmitted: (v) => Navigator.pop(context, double.tryParse(v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'), style: TextStyle(color: context.colors.outline))),
          TextButton(onPressed: () => Navigator.pop(context, double.tryParse(text.text)), child: Text(tr('Confirm'))),
        ],
      ),
    );
    text.dispose();
    if (value == null) return;
    if (value < 0.1 || value > 5) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Speed must be between 0.1 and 5'))));
      return;
    }
    final speed = (value * 100).round() / 100;
    final speeds = controller.settings.speeds;
    if (speeds.contains(speed)) return;
    save(controller.settings.copyWith(speeds: [...speeds, speed]..sort()));
  }

  Future<void> edit(BuildContext context, double speed) async {
    final settings = controller.settings;
    final action = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.all(12), child: Text('${trimSpeed(speed)}x', style: Theme.of(context).textTheme.titleMedium)),
          ListTile(leading: Icon(AppIcons.checkCircle), title: Text(tr('Set as default speed')), onTap: () => Navigator.pop(context, 0)),
          ListTile(
            leading: Icon(AppIcons.trash),
            title: Text(tr('Delete this item')),
            enabled: settings.speeds.length > 1 && speed != settings.defaultSpeed,
            onTap: () => Navigator.pop(context, 1),
          ),
        ]),
      ),
    );
    if (action == 0) save(controller.settings.copyWith(defaultSpeed: speed));
    if (action == 1) save(controller.settings.copyWith(speeds: [...controller.settings.speeds]..remove(speed)));
  }

  return _push(
    context,
    controller,
    tr('Speed settings'),
    actions: [
      Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            if (await confirmDialog(context, title: tr('Reset speed?'), content: tr('Restores the default speed list and sets the default speed back to 1x.'), confirm: tr('Reset'))) {
              save(controller.settings.copyWith(speeds: defaultSpeeds, defaultSpeed: 1));
            }
          },
          child: Text(tr('Reset')),
        ),
      ),
      const SizedBox(width: 8),
    ],
    (context) {
      final settings = controller.settings;
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(tr('Tap the buttons below to set the default (preferred) speed or delete it'), style: TextStyle(color: context.colors.outline)),
        ),
        ListTile(title: Text(tr('Default speed')), subtitle: Text('${trimSpeed(settings.defaultSpeed)}x')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          child: Row(children: [
            Text(tr('Speed list'), style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton(onPressed: () => add(context), child: Text(tr('Add'))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final speed in settings.speeds)
              speed == settings.defaultSpeed
                  ? FilledButton(onPressed: () => edit(context, speed), child: Text('${trimSpeed(speed)}x'))
                  : FilledButton.tonal(onPressed: () => edit(context, speed), child: Text('${trimSpeed(speed)}x')),
          ]),
        ),
        _tip(context, tr("The speed menu in the player's bottom bar uses this list.")),
      ];
    },
  );
}

// 播放设置 › 字幕设置

Future<void> openSubtitleSettings(BuildContext context, AppController controller) => _push(context, controller, tr('Subtitle settings'), (context) {
      final settings = controller.settings;
      void save(PlayerSettings next) => controller.saveSettings(next);
      // Read when a picker closes, so two quick changes do not undo each other.
      PlayerSettings now() => controller.settings;
      String percent(double v) => '${(v * 100).round()}%';
      List<Widget> look({
        required String font,
        required double scale,
        required int color,
        required double opacity,
        required void Function(String) setFont,
        required void Function(double) setScale,
        required void Function(int) setColor,
        required void Function(double) setOpacity,
        bool enabled = true,
      }) =>
          [
            NormalItem(
              title: tr('Font'),
              subtitle: subtitleFontLabel(font),
              leading: Icon(AppIcons.textAUnderline),
              enabled: enabled,
              onTap: () => pickSubtitleFont(context, font, setFont),
            ),
            NormalItem(
              title: tr('Size'),
              subtitle: '${scale.toStringAsFixed(1)}×',
              leading: Icon(AppIcons.textAa),
              enabled: enabled,
              onTap: () => pickWithSlider(context, title: tr('Size'), value: scale, min: 0.5, max: 3, divisions: 25, suffix: '×', precise: 1, onSelected: (v) => setScale((v * 10).round() / 10)),
            ),
            NormalItem(
              title: tr('Color'),
              subtitle: subtitleColorLabel(color),
              leading: Icon(AppIcons.palette),
              trailing: Container(width: 20, height: 20, decoration: BoxDecoration(color: Color(0xFF000000 | color), shape: BoxShape.circle, border: Border.all(color: context.colors.outlineVariant))),
              enabled: enabled,
              onTap: () => pickSubtitleColor(context, color, setColor),
            ),
            NormalItem(
              title: tr('Opacity'),
              subtitle: percent(opacity),
              leading: Icon(AppIcons.drop),
              enabled: enabled,
              onTap: () => pickSubtitleOpacity(context, opacity, setOpacity),
            ),
          ];
      final secondary = TranslationLanguage.maybeByCode(settings.secondarySubtitleLanguage);
      return [
        PopupItem<SubtitleMode>(
          title: tr('Turn on subtitles automatically'),
          leading: Icon(AppIcons.subtitles),
          value: settings.subtitleMode,
          values: [for (final m in SubtitleMode.values) (m, m.label)],
          onSelected: (v) => save(settings.copyWith(subtitleMode: v)),
        ),
        PopupItem<Object>(
          title: tr('First subtitle language'),
          leading: Icon(AppIcons.translate),
          value: settings.subtitleOriginal ? PlayerSettings.originalSubtitle : settings.subtitleLanguage,
          values: [(PlayerSettings.originalSubtitle, tr("Video's own language")), for (final l in SubtitleLanguage.values) (l, l.label)],
          onSelected: (v) => save(v is SubtitleLanguage ? settings.copyWith(subtitleLanguage: v, subtitleOriginal: false) : settings.copyWith(subtitleOriginal: true)),
        ),
        PopupItem<String>(
          title: tr('Second subtitle language'),
          leading: Icon(AppIcons.closedCaptioning),
          value: const {PlayerSettings.originalSubtitle, PlayerSettings.interfaceSubtitle}.contains(settings.secondarySubtitleLanguage) ? settings.secondarySubtitleLanguage : secondary?.code ?? '',
          values: [
            ('', tr('Never')),
            (PlayerSettings.interfaceSubtitle, tr('Interface language ({0})', [interfaceTranslationLanguage.label])),
            (PlayerSettings.originalSubtitle, tr("Video's own language (uploaded or auto-generated)")),
            for (final l in TranslationLanguage.all) (l.code, l.label),
          ],
          enabled: settings.subtitleMode != SubtitleMode.off,
          onSelected: (v) => save(settings.copyWith(secondarySubtitleLanguage: v)),
        ),
        _tip(
          context,
          settings.subtitleMode == SubtitleMode.off
              ? tr('Turn on “Turn on subtitles automatically” first, so the second subtitle can show by itself.')
              : tr('The first subtitle is shown in the first subtitle language, translated by YouTube when the video has none in it. The second subtitle appears above it; "Video\'s own language" is the subtitle in the language spoken in the video. It is hidden when it matches the first.'),
        ),
        SubtitlePreview(settings: settings),
        _header(context, tr('First subtitle style')),
        ...look(
          font: settings.subtitleFont,
          scale: settings.subtitleScale,
          color: settings.subtitleColor,
          opacity: settings.subtitleOpacity,
          setFont: (v) => save(now().copyWith(subtitleFont: v)),
          setScale: (v) => save(now().copyWith(subtitleScale: v)),
          setColor: (v) => save(now().copyWith(subtitleColor: v)),
          setOpacity: (v) => save(now().copyWith(subtitleOpacity: v)),
        ),
        _header(context, tr('Second subtitle style')),
        if (settings.libassSubtitles) _tip(context, tr("While mpv draws subtitles, the second subtitle uses the first one's style.")),
        ...look(
          font: settings.secondaryFont,
          scale: settings.secondaryScale,
          color: settings.secondaryColor,
          opacity: settings.secondaryOpacity,
          enabled: !settings.libassSubtitles,
          setFont: (v) => save(now().copyWith(secondaryFont: v)),
          setScale: (v) => save(now().copyWith(secondaryScale: v)),
          setColor: (v) => save(now().copyWith(secondaryColor: v)),
          setOpacity: (v) => save(now().copyWith(secondaryOpacity: v)),
        ),
        _header(context, tr('General')),
        SwitchItem(
          title: tr('Subtitles rendered by mpv (libass)'),
          subtitle: tr('Supports styled subtitles; when off, the UI draws them, using fewer resources'),
          leading: Icon(AppIcons.stack),
          value: settings.libassSubtitles,
          onChanged: (v) => save(settings.copyWith(libassSubtitles: v)),
        ),
        NormalItem(
          title: tr('Subtitle position'),
          subtitle: tr('Current: {0}% (100 is the bottom of the frame)', [settings.subtitlePosition]),
          leading: Icon(AppIcons.alignBottom),
          onTap: () => pickWithSlider(context, title: tr('Subtitle position'), value: settings.subtitlePosition.toDouble(), min: 0, max: 100, divisions: 100, suffix: '%', onSelected: (v) => save(now().copyWith(subtitlePosition: v.round()))),
        ),
        NormalItem(
          title: tr('Outline thickness'),
          subtitle: tr('Current: {0}', [settings.subtitleBorder.toStringAsFixed(1)]),
          leading: Icon(AppIcons.rectangleDashed),
          onTap: () => pickWithSlider(context, title: tr('Outline thickness'), value: settings.subtitleBorder, min: 0, max: 8, divisions: 16, suffix: '', precise: 1, onSelected: (v) => save(now().copyWith(subtitleBorder: v))),
        ),
        SwitchItem(
          title: tr('Background box'),
          subtitle: tr('Add a semi-transparent black background behind subtitles instead of an outline'),
          leading: Icon(AppIcons.rectangle),
          value: settings.subtitleBackground,
          onChanged: (v) => save(settings.copyWith(subtitleBackground: v)),
        ),
        SwitchItem(
          title: tr('Bold'),
          leading: Icon(AppIcons.textB),
          value: settings.subtitleBold,
          onChanged: (v) => save(settings.copyWith(subtitleBold: v)),
        ),
        NormalItem(
          title: tr('Restore default style'),
          subtitle: tr('Microsoft YaHei, a white first subtitle and a smaller light gold second one'),
          leading: Icon(AppIcons.arrowCounterClockwise),
          onTap: () => save(now().withDefaultSubtitleStyle()),
        ),
        _tip(context, tr('Subtitles are fetched by yt-dlp; auto-generated subtitles are used when no manual ones exist. Language and enable settings take effect from the next video; styles apply immediately.')),
      ];
    });

// 其它设置 › 空降助手

Future<void> openSponsorBlock(BuildContext context, AppController controller) => _push(context, controller, tr('SponsorBlock'), (context) {
      final settings = controller.settings;
      void save(PlayerSettings next) => controller.saveSettings(next);
      return [
        SwitchItem(
          title: tr('Enable SponsorBlock'),
          subtitle: tr('Automatically skip sponsors, self-promotion and other segments'),
          leading: Icon(AppIcons.airplaneTakeoff),
          value: settings.sponsorBlock,
          onChanged: (v) => save(settings.copyWith(sponsorBlock: v)),
        ),
        SwitchItem(
          title: tr('Show a notice when skipping'),
          leading: Icon(AppIcons.bell),
          value: settings.sponsorNotice,
          enabled: settings.sponsorBlock,
          onChanged: (v) => save(settings.copyWith(sponsorNotice: v)),
        ),
        _header(context, tr('Segment types to skip')),
        for (final MapEntry(key: category, value: (name, description)) in sponsorCategoryNames.entries)
          CheckboxListTile(
            title: Text(name),
            subtitle: Text(description, style: TextStyle(color: context.colors.outline, fontSize: 12)),
            value: settings.sponsorCategories.contains(category),
            enabled: settings.sponsorBlock,
            onChanged: (v) {
              final next = {...controller.settings.sponsorCategories};
              v == true ? next.add(category) : next.remove(category);
              save(controller.settings.copyWith(sponsorCategories: next));
            },
          ),
        _tip(context, tr('Segment data comes from the SponsorBlock community (sponsor.ajay.app). Lookups send only the first 4 characters of the video ID hash, never your account or watch history.')),
      ];
    });

// 外观设置 › 应用主题 (PiliNara's color_select.dart)

Future<void> openColorSelect(BuildContext context, AppController controller) => _push(context, controller, tr('Choose app theme'), (context) {
      final appearance = controller.appearance;
      final brightness = Theme.of(context).brightness;
      void save(AppearanceSettings next) => controller.saveAppearance(next);
      ColorScheme schemeOf(Color seed) => ColorScheme.fromSeed(seedColor: seed, brightness: brightness, dynamicSchemeVariant: appearance.schemeVariant);
      Widget swatch(Color seed, String label, bool selected, VoidCallback onTap) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Column(children: [
              ColorPalette(colorScheme: schemeOf(seed), selected: selected),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 12, color: selected ? null : context.colors.outline)),
            ]),
          );
      final windows = controller.windowsAccent;
      return [
        _header(context, tr('Color scheme')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(spacing: 12, runSpacing: 12, children: [
            for (final palette in palettes)
              PaletteCard(palette: palette, selected: appearance.skin == paletteSkinId(palette.id), onTap: () => save(controller.appearance.copyWith(skin: paletteSkinId(palette.id), palette: ''))),
          ]),
        ),
        _tip(context, tr('A color scheme changes the background, text and accent of the whole window, in light and dark. Choosing a theme or color below goes back to the neutral scheme.')),
        _header(context, tr('Theme presets')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(spacing: 12, runSpacing: 12, children: [
            for (final preset in themePresets)
              ThemePresetCard(preset: preset, selected: preset.isApplied(appearance), onTap: () => save(preset.applyTo(controller.appearance))),
          ]),
        ),
        _tip(context, tr('Each theme has a light and a dark version; Theme mode below picks which.')),
        _header(context, tr('Custom')),
        PopupItem<ThemeMode>(
          title: tr('Theme mode'),
          leading: Icon(AppIcons.flashlight),
          value: appearance.themeMode,
          values: themeModes,
          onSelected: (mode) => save(appearance.copyWith(themeMode: mode)),
        ),
        PopupItem<DynamicSchemeVariant>(
          title: tr('Palette style'),
          leading: Icon(AppIcons.palette),
          value: appearance.schemeVariant,
          values: [for (final e in schemeVariantNames.entries) (e.key, e.value)],
          onSelected: (v) => save(appearance.copyWith(schemeVariant: v)),
        ),
        ListTile(
          title: Text(tr('Follow Windows accent color')),
          subtitle: Text(windows == null ? tr("Couldn't read the system accent color") : tr('Change it in Windows Settings › Personalization › Colors'), style: TextStyle(color: context.colors.outline, fontSize: 12)),
          enabled: windows != null,
          leading: Checkbox(
            value: appearance.systemAccent,
            onChanged: windows == null ? null : (v) => save(appearance.copyWith(skin: '', palette: '', systemAccent: v ?? false)),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
          ),
          onTap: windows == null ? null : () => save(appearance.copyWith(skin: '', palette: '', systemAccent: !appearance.systemAccent)),
        ),
        AnimatedSize(
          duration: Motion.of(const Duration(milliseconds: 200)),
          child: appearance.systemAccent && windows != null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(spacing: 22, runSpacing: 18, alignment: WrapAlignment.center, children: [
                    swatch(Color(appearance.customAccent), tr('Custom'), appearance.accentIndex < 0, () async {
                      final color = await showDialog<Color>(
                        context: context,
                        builder: (context) => AlertDialog(
                          clipBehavior: Clip.hardEdge,
                          contentPadding: const EdgeInsets.symmetric(vertical: 16),
                          title: Text(tr('Custom color')),
                          content: SlideColorPicker(color: Color(appearance.customAccent)),
                        ),
                      );
                      if (color != null) save(controller.appearance.copyWith(skin: '', palette: '', accentIndex: -1, customAccent: color.toARGB32()));
                    }),
                    for (var i = 0; i < accentChoices.length; i++)
                      swatch(accentChoices[i].$2, accentChoices[i].$1, appearance.accentIndex == i, () => save(controller.appearance.copyWith(skin: '', palette: '', accentIndex: i))),
                  ]),
                ),
        ),
        _header(context, tr('Preview')),
        IgnorePointer(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('Title text'), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(tr('Secondary text'), style: TextStyle(color: context.colors.outline)),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    FilledButton(onPressed: () {}, child: Text(tr('Subscriptions'))),
                    FilledButton.tonal(onPressed: () {}, child: Text(tr('Favorites'))),
                    OutlinedButton(onPressed: () {}, child: Text(tr('Share'))),
                    Switch(value: true, onChanged: (_) {}),
                  ]),
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(value: 0.6),
                ]),
              ),
            ),
          ),
        ),
      ];
    });

// 外观设置 › App 字体设置 (PiliNara's font_setting.dart)

Future<void> openFontSettings(BuildContext context, AppController controller) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _FontSettingsPage(controller: controller)));

class _FontSettingsPage extends StatefulWidget {
  const _FontSettingsPage({required this.controller});
  final AppController controller;

  @override
  State<_FontSettingsPage> createState() => _FontSettingsPageState();
}

class _FontSettingsPageState extends State<_FontSettingsPage> {
  List<String>? _systemFonts;
  String _query = '';

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      WindowsShell.systemFontFamilies().then((fonts) {
        if (mounted) setState(() => _systemFonts = fonts);
      });
    } else {
      _systemFonts = const [];
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('App font'))),
        body: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final controller = widget.controller;
            final appearance = controller.appearance;
            final fixed = {for (final (family, _) in fontChoices) if (family != null) family};
            final needle = _query.trim().toLowerCase();
            final system = (_systemFonts ?? const <String>[]).where((family) => !fixed.contains(family) && (needle.isEmpty || family.toLowerCase().contains(needle))).toList();
            void save(String? family) => controller.saveAppearance(family == null ? appearance.copyWith(clearFontFamily: true) : appearance.copyWith(fontFamily: family));
            Widget option(String? family, String label) => RadioListTile<String?>(
                  value: family,
                  title: Text(label, style: TextStyle(fontFamily: family == autoFont ? appearance.font : family)),
                  subtitle: family == null || family == autoFont ? null : Text(family, style: TextStyle(color: context.colors.outline, fontSize: 12)),
                );
            final theme = Theme.of(context);
            return RadioGroup<String?>(
              groupValue: appearance.fontFamily,
              onChanged: save,
              child: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
                _header(context, tr('Font')),
                for (final (family, label) in fontChoices) option(family, label),
                _header(context, tr('Installed system fonts')),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(prefixIcon: Icon(AppIcons.magnifyingGlass), hintText: tr('Search installed fonts')),
                  ),
                ),
                if (_systemFonts == null)
                  const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                else if (system.isEmpty)
                  Padding(padding: const EdgeInsets.all(16), child: Text(tr('No installed fonts match'), style: TextStyle(color: context.colors.outline)))
                else
                  for (final family in system) option(family, family),
                _header(context, tr('Font size')),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(children: [
                    Expanded(child: Slider(min: 0.8, max: 1.4, divisions: 12, value: appearance.textScale, label: '${(appearance.textScale * 100).round()}%', onChanged: (v) => controller.saveAppearance(appearance.copyWith(textScale: (v * 100).round() / 100)))),
                    SizedBox(width: 48, child: Text('${(appearance.textScale * 100).round()}%')),
                    TextButton(onPressed: () => controller.saveAppearance(appearance.copyWith(textScale: 1, fontFamily: autoFont)), child: Text(tr('Reset'))),
                  ]),
                ),
                _header(context, tr('Preview')),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('Lumtub makes YouTube better on Windows'), style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(tr('The quick brown fox jumps over the lazy dog. 0123456789'), style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    Text(tr('Channel name · 120K views · 3 days ago'), style: theme.textTheme.labelMedium!.copyWith(color: context.colors.outline)),
                  ]),
                ),
                _tip(context, tr("Noto Sans CJK SC is bundled with Lumtub. System fonts are read from the current Windows user's font collection.")),
              ]),
            );
          },
        ),
      );
}

// 视频设置 › 画面与音画同步调节 (PiliNara's video picture panel)

Future<void> openPictureSettings(BuildContext context, AppController controller) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => _PictureSettingsPage(controller: controller)),
    );

class _PictureSettingsPage extends StatefulWidget {
  const _PictureSettingsPage({required this.controller});
  final AppController controller;

  @override
  State<_PictureSettingsPage> createState() => _PictureSettingsPageState();
}

class _PictureSettingsPageState extends State<_PictureSettingsPage> {
  late final Map<String, int> _picture = {...widget.controller.settings.picture};
  late int _audioDelay = widget.controller.settings.audioDelayMs;

  void _save() => widget.controller.saveSettings(widget.controller.settings.copyWith(picture: {
        for (final entry in _picture.entries)
          if (entry.value != 0) entry.key: entry.value,
      }, audioDelayMs: _audioDelay));

  Widget _slider(String label, int value, int min, int max, String suffix, ValueChanged<int> onChanged, VoidCallback onReset) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(children: [
          SizedBox(width: 72, child: Text(label)),
          Expanded(
            child: Slider(
              value: value.toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              label: '$value$suffix',
              onChanged: (v) => onChanged(v.round()),
              onChangeEnd: (_) => _save(),
            ),
          ),
          SizedBox(width: 64, child: Text('$value$suffix', textAlign: TextAlign.end)),
          IconButton(tooltip: tr('Reset'), icon: Icon(AppIcons.arrowCounterClockwise, size: 20), onPressed: value == 0 ? null : onReset),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Video and A/V sync adjustments')),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _picture.clear();
                _audioDelay = 0;
              });
              for (final (key, _) in pictureProperties) {
                controller.previewProperty(key, '0');
              }
              controller.previewProperty('audio-delay', '0');
              _save();
            },
            child: Text(tr('Reset all')),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        _header(context, tr('Video')),
        for (final (key, label) in pictureProperties)
          _slider(label, _picture[key] ?? 0, -pictureLimit(key), pictureLimit(key), '', (v) {
            setState(() => _picture[key] = v);
            controller.previewProperty(key, '$v');
          }, () {
            setState(() => _picture[key] = 0);
            controller.previewProperty(key, '0');
            _save();
          }),
        _header(context, tr('A/V sync')),
        _slider(tr('Audio delay'), _audioDelay, -2000, 2000, ' ms', (v) {
          setState(() => _audioDelay = (v / 10).round() * 10);
          controller.previewProperty('audio-delay', '${_audioDelay / 1000}');
        }, () {
          setState(() => _audioDelay = 0);
          controller.previewProperty('audio-delay', '0');
          _save();
        }),
        _tip(context, tr('Previews live on the playing video while dragging. Positive audio delay plays sound later; negative plays it earlier. These values apply to all subsequent videos.')),
      ]),
    );
  }
}

// 其它设置 › 组件管理

Future<void> openComponents(BuildContext context, AppController controller) => _push(context, controller, tr('Components'), (context) {
      final tools = controller.tools;
      if (tools == null || !controller.ready) return [NormalItem(title: tr('Preparing components…'))];
      final libmpv = tools.libmpv;
      final current = libmpv.current;
      final next = libmpv.selected;
      final pendingRestart = next != null && next != current;
      return [
        NormalItem(
          title: 'libmpv',
          subtitle: [
            if (!Platform.isWindows) tools.libmpvLabel else tr('{0}: {1}', [libmpv.usesDownload ? tr('Updated') : tr('Built-in'), current?.label ?? tr('Unknown version')]),
            if (pendingRestart) tr('Uses {0} after restart', [next.label]),
          ].join('\n'),
          leading: Icon(AppIcons.filmSlate),
          trailing: libmpv.usesDownload || pendingRestart ? TextButton(onPressed: controller.rollBackLibmpv, child: Text(tr('Revert to built-in'))) : null,
        ),
        NormalItem(
          title: 'yt-dlp',
          subtitle: tools.ytDlpVersion ?? tr('Not installed'),
          leading: Icon(AppIcons.terminal),
          trailing: tools.canRollBackYtDlp ? TextButton(onPressed: controller.rollBackYtDlp, child: Text(tr('Roll back to previous version'))) : null,
        ),
        NormalItem(title: 'Deno', subtitle: tools.denoVersion ?? tr('Not installed'), leading: Icon(AppIcons.code)),
        NormalItem(
          title: 'ffmpeg',
          subtitle: controller.installingFfmpeg
              ? tr('Installing… {0}', [controller.ffmpegProgress == null ? '' : '${(controller.ffmpegProgress! * 100).round()}%'])
              : tools.ffmpegVersion == null
                  ? tr('Not installed (installed on demand when merging high-quality downloads)')
                  : tr('{0} · {1} on disk', [tools.ffmpegVersion!, formatBytes(tools.ffmpegBytes ?? 0)]),
          leading: Icon(AppIcons.gitMerge),
          trailing: controller.installingFfmpeg || ToolManager.bundledFfmpegDirectory != null
              ? null
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  TextButton(onPressed: controller.installFfmpeg, child: Text(tools.ffmpegVersion == null ? tr('Install') : tr('Update'))),
                  if (tools.ffmpegVersion != null) TextButton(onPressed: controller.removeFfmpeg, child: Text(tr('Remove'))),
                ]),
        ),
        NormalItem(
          title: controller.checking ? tr('Checking for updates…') : tr('Check for updates now'),
          subtitle: tr('Downloads only from the official GitHub Release and verifies SHA-256. Takes effect after restart'),
          leading: Icon(AppIcons.arrowLineDown),
          enabled: !controller.checking,
          onTap: controller.checkUpdates,
        ),
        _tip(context, tr("New libmpv falls back to the built-in version automatically if it fails. If videos won't play after a yt-dlp update, you can roll back to the previous version.")),
        if (Platform.isMacOS)
          _tip(context, tr('The macOS version comes with ffmpeg, used only to join high-quality video and audio. It is built from the FFmpeg source under the LGPL with container formats only, no codecs. Source code: https://ffmpeg.org/download.html.'))
        else
          _tip(context, tr('ffmpeg is an optional component used only to merge high-quality video and audio, and is never downloaded automatically. It is the LGPL build from zhongfly/mpv-winbuild (or from BtbN/FFmpeg-Builds where that cannot be installed); source code: https://ffmpeg.org/download.html.')),
      ];
    });

// 关于 (PiliNara's about/view.dart)

List<SettingEntry> aboutEntries(AppController controller) => [
      SettingEntry(tr('Version'), (context) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(children: [
              Icon(AppIcons.monitorPlayFill, size: 72, color: context.colors.primary),
              const SizedBox(height: 4),
              Text('Lumtub', style: Theme.of(context).textTheme.titleMedium!.copyWith(height: 2)),
              Text(tr('A third-party YouTube client built with Flutter and mpv'), style: TextStyle(color: context.colors.outline)),
              const SizedBox(height: 8),
              ListTile(
                title: Text(tr('Current version')),
                leading: Icon(AppIcons.gitCommit),
                trailing: Text(appVersion, style: TextStyle(fontSize: 14, color: context.colors.outline)),
                onTap: () => copyText(context, appVersion, tr('Version number copied')),
              ),
            ]),
          ), subtitle: tr('Current version update')),
      SettingEntry(tr('Check for updates'), (context) {
        final updater = controller.appUpdater;
        final release = updater?.available;
        final progress = updater?.progress;
        final String title, subtitle;
        if (updater?.ready != null) {
          title = tr('Version {0} downloaded', [release?.version ?? '']);
          subtitle = updater?.installError != null ? tr("The installer didn't start: {0}. Click to try again", [updater!.installError!]) : tr('Installs when Lumtub closes; click to restart and update now');
        } else if (progress != null) {
          title = tr('Downloading version {0}…', [release?.version ?? '']);
          subtitle = '${(progress * 100).round()}%';
        } else if (updater?.checking ?? false) {
          title = tr('Checking for app updates…');
          subtitle = tr('Checked at startup and every 6 hours; you can also check now.');
        } else if (release != null && updater?.rejected == release.version) {
          title = tr('Update available: {0}', [release.version]);
          subtitle = tr('The installer failed its signature check and was not installed. Click to download it from GitHub Releases');
        } else if (release != null) {
          title = tr('Update available: {0}', [release.version]);
          subtitle = !AppUpdater.canInstall || release.asset == null
              ? tr('Click to open the GitHub Release download.')
              : updater?.error != null
                  ? tr('Download failed: {0}. Click to retry', [updater!.error!])
                  : tr('Click to download; it installs when Lumtub closes');
        } else {
          title = tr('Check for updates');
          subtitle = updater?.error == null ? tr('Checked at startup and every 6 hours; you can also check now.') : tr('Could not check for app updates: {0}', [updater!.error!]);
        }
        return NormalItem(
          title: title,
          subtitle: subtitle,
          leading: Icon(AppIcons.clockClockwise),
          onTap: () async {
            if (updater?.ready != null) return controller.restartToUpdate();
            if (progress != null || (updater?.checking ?? false)) return;
            await controller.checkAppUpdate();
            final found = controller.appUpdater?.available;
            if (found != null && (!AppUpdater.canInstall || found.asset == null || controller.appUpdater?.rejected == found.version)) openExternal(found.page.isEmpty ? '$_repository/releases' : found.page);
            if (found == null && context.mounted && controller.appUpdater?.error == null) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Lumtub is up to date'))));
            }
          },
        );
      }, subtitle: tr('Release page new version auto update')),
      SettingEntry(tr('Support development'), (context) => NormalItem(
            title: tr('Support development'),
            subtitle: tr('Sponsor Lumtub on GitHub Sponsors or with crypto'),
            leading: const Icon(AppIcons.heartFill, color: Color(0xFFEA4AAA)),
            onTap: () => openSupport(context),
          ), subtitle: tr('sponsor donate support')),
      SettingEntry(tr('Source code'), (context) => NormalItem(
            title: tr('GitHub repository'),
            subtitle: 'github.com/0x696c757a696f/lumtub',
            leading: Icon(AppIcons.code),
            onTap: () => openExternal(_repository),
          ), subtitle: tr('GitHub source code')),
      SettingEntry(tr('Feedback'), (context) => NormalItem(
            title: tr('Feedback'),
            subtitle: tr('File an issue on GitHub with the diagnostics and error log attached'),
            leading: Icon(AppIcons.chatCenteredText),
            onTap: () => openExternal('$_repository/issues/new/choose'),
          ), subtitle: 'issue bug'),
      SettingEntry(tr('Error log'), (context) => NormalItem(
            title: tr('Error log'),
            subtitle: tr('Stored only on this device. Sign-in credentials and stream URLs are never saved'),
            leading: Icon(AppIcons.bug),
            onTap: () => openLogs(context, controller),
          ), subtitle: tr('Log')),
      SettingEntry(tr('Log level'), (context) => NormalItem(
            title: tr('Log level'),
            subtitle: tr('Now: {0}. Set it to Debug for a while to track a problem down; it records more detail', [labelOf(_logLevels, controller.preferences.logLevel)]),
            leading: Icon(AppIcons.slidersHorizontal),
            onTap: () => pickFromDialog<LogLevel>(context,
                title: tr('Log level'),
                value: controller.preferences.logLevel,
                values: _logLevels,
                onSelected: (v) => controller.savePreferences(controller.preferences.copyWith(logLevel: v))),
          ), subtitle: tr('log level debug verbose')),
      SettingEntry(tr('Copy diagnostics'), (context) => NormalItem(
            title: tr('Copy diagnostics'),
            subtitle: tr('Version, system, graphics card, components and playback settings'),
            leading: Icon(AppIcons.copy),
            onTap: () => copyText(context, controller.diagnostics(), tr('Diagnostics copied')),
          ), subtitle: tr('feedback issues')),
      SettingEntry(tr('Open source licenses'), (context) => NormalItem(
            title: tr('Open source licenses'),
            subtitle: tr('GPLv3; parts of the UI are adapted from PiliNara, playback is built on mpv, media_kit and yt-dlp'),
            leading: Icon(AppIcons.gavel),
            onTap: () => showLicensePage(context: context, applicationName: 'Lumtub', applicationVersion: appVersion),
          ), subtitle: 'PiliNara mpv media_kit yt-dlp license'),
    ];

List<(LogLevel, String)> get _logLevels => [
      (LogLevel.error, tr('Errors: only problems Lumtub could not get past')),
      (LogLevel.warn, tr('Warnings: also problems Lumtub worked around')),
      (LogLevel.info, tr('Info: also what Lumtub did (default)')),
      (LogLevel.debug, tr('Debug: also every step and timing')),
    ];

// 关于 › 错误日志 (PiliNara's logs.dart)

Future<void> openLogs(BuildContext context, AppController controller) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (context) => _LogsPage(controller: controller)));

class _LogsPage extends StatefulWidget {
  const _LogsPage({required this.controller});
  final AppController controller;

  @override
  State<_LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<_LogsPage> {
  String? _text;

  /// The least important level shown.
  LogLevel _shown = LogLevel.debug;

  static LogLevel _levelOf(String rest) {
    for (final level in LogLevel.values) {
      if (rest.startsWith(level.tag.trim())) return level;
    }
    // Lines from before levels were written, such as 错误 ones.
    return rest.startsWith('错误') ? LogLevel.error : LogLevel.info;
  }

  Directory? get _directory => widget.controller.directories?.logs;

  File? _file(String name) => _directory == null ? null : File('${_directory!.path}${Platform.pathSeparator}$name');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final parts = <String>[];
    for (final name in const ['lumtub.old.log', 'lumtub.log']) {
      try {
        final file = _file(name);
        if (file != null && await file.exists()) parts.add(await file.readAsString());
      } on FileSystemException {
        // An unreadable log is shown as empty.
      }
    }
    if (mounted) setState(() => _text = parts.join());
  }

  Future<void> _clear() async {
    if (!await confirmDialog(context, title: tr('Clear logs?'), content: tr('Deletes Lumtub logs saved on this device.'), confirm: tr('Clear all'))) return;
    for (final name in const ['lumtub.old.log', 'lumtub.log']) {
      try {
        final file = _file(name);
        if (file != null && await file.exists()) await file.writeAsString('');
      } on FileSystemException {
        // Keep going; the rest of the log is still cleared.
      }
    }
    await _load();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Cleared'))));
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    final all = text == null ? const <String>[] : text.split('\n').where((l) => l.isNotEmpty);
    // A line without a time stamp continues the one before it, such as a
    // stack trace, and goes with it.
    final lines = <String>[];
    final levels = <LogLevel>[];
    for (final line in all) {
      final space = line.indexOf(' ');
      final stamped = space > 0 && DateTime.tryParse(line.substring(0, space)) != null;
      if (!stamped && lines.isNotEmpty) {
        lines[lines.length - 1] = '${lines.last}\n$line';
        continue;
      }
      lines.add(line);
      levels.add(_levelOf(stamped ? line.substring(space + 1) : line));
    }
    final shown = [
      for (var i = lines.length - 1; i >= 0; i--)
        if (levels[i].index <= _shown.index) (lines[i], levels[i]),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Logs')),
        actions: [
          PopupMenuButton<int>(
            onSelected: (value) => switch (value) {
              0 => copyText(context, text ?? '', tr('Copied')),
              1 => openExternal('$_repository/issues/new/choose'),
              2 => _directory == null ? null : openExternal(_directory!.path),
              _ => _clear(),
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 0, child: Text(tr('Copy log'))),
              PopupMenuItem(value: 1, child: Text(tr('Bug reports'))),
              PopupMenuItem(value: 2, child: Text(tr('Open log folder'))),
              PopupMenuItem(value: 3, child: Text(tr('Clear logs'))),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: text == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Wrap(spacing: 8, children: [
                  for (final (level, label) in [(LogLevel.debug, tr('All')), (LogLevel.info, tr('Info and above')), (LogLevel.warn, tr('Warnings and above')), (LogLevel.error, tr('Errors only'))])
                    ChoiceChip(label: Text(label), selected: _shown == level, onSelected: (_) => setState(() => _shown = level)),
                ]),
              ),
              Expanded(child: shown.isEmpty
              ? Center(child: Text(tr('No logs yet'), style: TextStyle(color: context.colors.outline)))
              : SelectionArea(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                    itemCount: shown.length,
                    separatorBuilder: (context, i) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final (line, level) = shown[i];
                      final space = line.indexOf(' ');
                      final time = space > 0 ? line.substring(0, space).replaceFirst('T', ' ').split('.').first : '';
                      final rest = space > 0 ? line.substring(space + 1) : line;
                      final color = switch (level) {
                        LogLevel.error => context.colors.error,
                        LogLevel.warn => context.colors.tertiary,
                        LogLevel.debug => context.colors.outline,
                        LogLevel.info => null,
                      };
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (time.isNotEmpty) Text(time, style: TextStyle(fontSize: 12, color: context.colors.outline)),
                          Text(rest, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: color)),
                        ]),
                      );
                    },
                  ),
                )),
            ]),
    );
  }
}

/// 连接的服务器: every service Lumtub talks to, when, and what it learns,
/// with a switch where it can be turned off.
Future<void> openPrivacyConnections(BuildContext context, AppController controller) => _push(context, controller, tr('Connected servers'), (context) {
      final settings = controller.settings;
      final prefs = controller.preferences;
      void saveSettings(PlayerSettings next) => controller.saveSettings(next);
      void savePrefs(AppPreferences next) => controller.savePreferences(next);
      Widget row(IconData icon, String title, String hosts, String detail, {bool? value, ValueChanged<bool>? onChanged, String? state, VoidCallback? onTap}) => ListTile(
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text('$hosts\n$detail'),
            isThreeLine: true,
            onTap: onTap ?? (onChanged == null || value == null ? null : () => onChanged(!value)),
            trailing: value != null && onChanged != null
                ? Switch(value: value, onChanged: onChanged)
                : state == null
                    ? null
                    : Text(state, style: TextStyle(color: context.colors.outline)),
          );
      final dns = DnsServer.of(settings.dnsServer, settings.dnsCustomUrl);
      final relay = settings.playbackSource != PlaybackSource.youtube;
      return [
        _tip(context, tr('Lumtub has no analytics, telemetry or crash reporting, and never uploads watch history, cookies or account data. These are all the servers it connects to; with a proxy on, all go through it.')),
        _header(context, tr('Required')),
        row(AppIcons.monitorPlay, 'YouTube', 'www.youtube.com · *.googlevideo.com · i.ytimg.com', tr('Search, lists, playback and thumbnails. YouTube sees your IP and what you watch, as in a browser'), state: tr('Required')),
        row(AppIcons.listMagnifyingGlass, tr('YouTube search suggestions'), 'suggestqueries-clients6.youtube.com', tr('While you type in the search box, the text so far is sent to YouTube for suggestions'), state: tr('While typing')),
        _header(context, tr('Can be turned off')),
        row(AppIcons.arrowLineDown, tr('Update checks'), 'api.github.com · github.com', tr('Checks for and downloads new versions of Lumtub, libmpv, yt-dlp and other components; GitHub sees only your IP'),
            value: prefs.autoCheckUpdates, onChanged: (v) => savePrefs(prefs.copyWith(autoCheckUpdates: v, autoUpdateApp: v && prefs.autoUpdateApp))),
        row(AppIcons.fastForward, tr('SponsorBlock'), 'sponsor.ajay.app', tr("Sponsor segments are looked up by a prefix of the video ID's hash, so the server doesn't learn which video"),
            value: settings.sponsorBlock, onChanged: (v) => saveSettings(settings.copyWith(sponsorBlock: v))),
        row(AppIcons.textT, 'DeArrow', 'sponsor.ajay.app · dearrow-thumb.ajay.app', tr("Replaces clickbait with community titles and thumbnails; titles are looked up by a prefix of the video ID's hash, replacement thumbnails are downloaded by video ID"),
            value: settings.deArrowTitles || settings.deArrowThumbnails, onChanged: (v) => saveSettings(settings.copyWith(deArrowTitles: v, deArrowThumbnails: v))),
        row(AppIcons.thumbsDown, 'Return YouTube Dislike', 'returnyoutubedislikeapi.com', tr('Shows estimated dislikes on the watch page; sends it the ID of the video you watch'),
            value: settings.returnDislike, onChanged: (v) => saveSettings(settings.copyWith(returnDislike: v))),
        row(AppIcons.translate, tr('Translation'), controller.preferences.translation.service.label, tr('Text is sent to the chosen service only when you click Translate, turn on subtitle translation or use AI summary'),
            state: tr('When pressed'), onTap: () => openTranslationSettings(context, controller)),
        row(AppIcons.graph, tr('Piped / Invidious'), relay ? settings.playbackSource.label : tr('Not in use'), tr('Fetch videos from YouTube for you; they learn which video you watch. Also tried briefly when YouTube answers 429'),
            state: relay ? tr('In use') : tr('Fallback only')),
        row(AppIcons.hardDrives, tr('Encrypted DNS'), dns?.url ?? tr('Not in use'), tr('Looks up host names on a direct connection; the DNS server learns which sites you visit, not what you do there'), state: dns == null ? tr('Close') : tr('In use')),
        row(AppIcons.userCircle, tr('Google account'), 'accounts.google.com · oauth2.googleapis.com · www.googleapis.com', tr('Only after signing in, to sync subscriptions, playlists, likes and comments'),
            state: controller.account?.signedIn ?? false ? tr('Signed in') : tr('Signed out')),
        row(AppIcons.television, tr('TV-code sign-in'), 'www.youtube.com/o/oauth2 · www.youtube.com/youtubei', tr("Only after signing in: likes and dislikes on comments and posts, requested as YouTube's TV app"),
            state: controller.tvSignIn?.signedIn ?? false ? tr('Signed in') : tr('Signed out')),
      ];
    });
