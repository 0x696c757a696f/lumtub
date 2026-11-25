import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../app/app_controller.dart';
import '../../app_log.dart';
import '../../app_updater.dart';
import '../../appearance_settings.dart';
import '../../blocked_groups.dart';
import '../../encrypted_dns.dart';
import '../../friendly_error.dart';
import '../../l10n/l10n.dart';
import '../../packs.dart';
import '../../piped_streams.dart';
import '../../player_settings.dart';
import '../../save_file.dart';
import '../../translation.dart';
import '../../widgets/settings_tiles.dart';
import '../../windows_shell.dart';
import '../app_icons.dart';
import '../common.dart';
import '../motion.dart';
import '../skin_paint.dart';
import '../subtitle_style.dart';
import '../theme.dart';
import 'downloads_page.dart' show openInExplorer;
import 'settings_sections.dart' show SettingEntry, themeModes, trimSpeed, labelOf;
import 'support_page.dart';
import 'translation_settings_page.dart';

const _repository = 'https://github.com/0x696c757a696f/lumtub';

Widget _header(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: context.colors.primary)),
    );

Widget _tip(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.all(12).copyWith(left: 16, right: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(AppIcons.info, size: 16, color: context.colors.outline)),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12, height: 1.5, color: context.colors.outline))),
      ]),
    );

TextStyle _faint(BuildContext context) => TextStyle(fontSize: 12, color: context.colors.outline);

Widget _plainNote(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(text, style: TextStyle(color: context.colors.outline, height: 1.6)),
    );

Widget _cancel(BuildContext context) => TextButton(
      onPressed: () => Navigator.pop(context),
      child: Text(tr('Cancel'), style: TextStyle(color: context.colors.outline)),
    );

Future<void> _openList(
  BuildContext context,
  AppController controller,
  String title,
  List<Widget> Function(BuildContext context) rows, {
  List<Widget> Function(BuildContext context)? actions,
}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Scaffold(
          appBar: SkinAppBar(AppBar(title: Text(title), actions: actions?.call(context))),
          body: ListView(padding: const EdgeInsets.only(bottom: 40), children: rows(context)),
        ),
      ),
    ));

Future<void> _openPage(BuildContext context, String title, Widget body, {List<Widget>? actions}) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(appBar: SkinAppBar(AppBar(title: Text(title), actions: actions)), body: body),
    ));

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.label,
    required this.confirm,
    this.helper,
    this.helperLines,
    this.numeric = false,
    this.filled = false,
  });
  final String title;
  final String label;
  final String confirm;
  final String? helper;
  final int? helperLines;
  final bool numeric;
  final bool filled;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _text.text);

  @override
  Widget build(BuildContext context) {
    final confirm = Text(widget.confirm);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: dialogWidth(context, 420),
        child: TextField(
          controller: _text,
          autofocus: true,
          keyboardType: widget.numeric ? const TextInputType.numberWithOptions(decimal: true) : null,
          decoration: InputDecoration(labelText: widget.label, helperText: widget.helper, helperMaxLines: widget.helperLines),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        _cancel(context),
        widget.filled ? FilledButton(onPressed: _submit, child: confirm) : TextButton(onPressed: _submit, child: confirm),
      ],
    );
  }
}

// Blocked channels

Future<void> openBlockedChannels(BuildContext context, AppController controller) => _openList(
      context,
      controller,
      tr('Blocked channels'),
      (context) {
        final prefs = controller.preferences;
        final none = prefs.blockedChannels.isEmpty && prefs.blockedChannelNames.isEmpty;
        return [
          _header(context, tr('Blocked channels')),
          if (none) _plainNote(context, tr('No channels blocked yet. Use “Add” at the top right, or choose “Block this channel” on a video card, channel page or the watch page.')),
          for (final channel in prefs.blockedChannels)
            ListTile(
              leading: Icon(AppIcons.userMinus),
              title: Text(channel.name.isEmpty ? channel.id : channel.name),
              subtitle: Text(channel.id, style: _faint(context)),
              trailing: TextButton(onPressed: () => controller.unblockChannel(channel.id), child: Text(tr('Remove'))),
            ),
          for (final name in prefs.blockedChannelNames)
            ListTile(
              leading: Icon(AppIcons.userMinus),
              title: Text(name),
              subtitle: Text(tr('Blocked by name'), style: _faint(context)),
              trailing: TextButton(onPressed: () => controller.unblockChannelName(name), child: Text(tr('Remove'))),
            ),
          _tip(context, tr('Blocked channels never show in the home feed, Explore, search, related videos or the subscription feed. The list stays on this computer.')),
          _header(context, tr('Channels not recommended')),
          if (prefs.unrecommendedChannels.isEmpty) _plainNote(context, tr("None yet. Choose “Don't recommend this channel” on a video card, channel page or the watch page.")),
          for (final channel in prefs.unrecommendedChannels)
            ListTile(
              leading: Icon(AppIcons.thumbsDown),
              title: Text(channel.name.isEmpty ? channel.id : channel.name),
              subtitle: Text(channel.id, style: _faint(context)),
              trailing: TextButton(onPressed: () => controller.setRecommendChannel(channel, true), child: Text(tr('Recommend again'))),
            ),
          _tip(context, tr('Channels not recommended stay out of the home feed, Explore and related videos, but still show in searches and follows.')),
        ];
      },
      actions: (context) => [
        TextButton.icon(
          icon: Icon(AppIcons.plus),
          label: Text(tr('Add')),
          onPressed: () async {
            final typed = await showDialog<String>(
              context: context,
              builder: (_) => _PromptDialog(
                title: tr('Blocked channels'),
                label: tr('Channel link or full name'),
                helper: tr('A link with a channel ID starting with UC blocks by ID; anything else blocks the channel with exactly that name'),
                helperLines: 2,
                confirm: tr('Block'),
                filled: true,
              ),
            );
            if (typed == null) return;
            final blocked = controller.blockChannelTyped(typed);
            if (blocked != null && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Blocked “{0}”', [blocked]))));
            }
          },
        ),
        const SizedBox(width: 8),
      ],
    );

// Block lists

Widget _suggestTile() => ListTile(
      leading: Icon(AppIcons.arrowSquareOut),
      title: Text(tr('Suggest a channel or report a mistake')),
      subtitle: Text(tr('The lists are public on GitHub, and anyone can add to them. Every entry needs a public source')),
      onTap: () => openExternal('$_repository/issues/new?template=block_list.yml'),
    );

Future<void> openBlockedGroups(BuildContext context, AppController controller) => _openBlockList(context, controller, media: false);

Future<void> openStateMedia(BuildContext context, AppController controller) => _openBlockList(context, controller, media: true);

Future<void> _openBlockList(BuildContext context, AppController controller, {required bool media}) {
  final title = media ? tr('Block state propaganda media') : tr('Block controversial religious groups');
  return _openList(context, controller, title, (context) {
    final prefs = controller.preferences;
    final master = media ? prefs.blockStateMedia : prefs.blockGroups;
    final groups = media ? stateMedia : blockedGroups;
    return [
      SwitchListTile(
        secondary: Icon(media ? AppIcons.megaphone : AppIcons.prohibitFill),
        title: Text(title),
        subtitle: Text(media
            ? '${tr('Channels and videos of the government propaganda outlets below are hidden from recommendations, Explore, related videos and search')}. ${tr('Only the channel name counts, so videos from other channels that repost or report on them still show. Editorially independent public broadcasters such as the BBC, NHK and PBS are not included. Searching for the exact channel name (case-sensitive) still finds them.')}'
            : '${tr("Channels and videos of the groups below are left out of recommendations, Explore, related videos and search; other channels' reports about them, and searches for their names, are not affected")}. ${tr("Searching for a channel's exact name (letter case included; not one character more or less) still finds that channel and its videos. Followed channels still show in subscriptions.")}'),
        value: master,
        onChanged: (v) => controller.savePreferences(media ? prefs.copyWith(blockStateMedia: v) : prefs.copyWith(blockGroups: v)),
      ),
      _tip(context, media
          ? tr('The list stays on this computer. Add any channel it misses under Privacy › Blocked channels.')
          : tr('Tap a group to see its whole list and untick entries one by one. Only channel names, @handles and channel IDs are matched, never titles or descriptions, and the list stays on this computer. To block more, use Home & search › Title keyword filter, or Privacy › Blocked channels.')),
      _header(context, tr('Groups to block')),
      for (final group in groups) _groupTile(context, controller, group, media, master),
      _tip(context, tr('A channel is blocked when its name is one of these or starts with one, followed by a space or sign.')),
      _suggestTile(),
    ];
  });
}

Widget _groupTile(BuildContext context, AppController controller, BlockedGroup group, bool media, bool master) {
  final prefs = controller.preferences;
  final keys = {for (final e in group.entries) e.key};
  final unticked = prefs.allowedEntries.where(keys.contains).length;
  final parts = [
    tr('{0} entries', [group.entries.length]),
    if (unticked > 0) tr('{0} unticked', [unticked]),
    if (!group.onByDefault) tr('Not blocked by default'),
    group.entries.take(4).map((e) => e.label).join(tr(', ')),
  ];
  final note = group.note;
  final lines = [if (note != null) tr(note), parts.join(' · ')];
  return ListTile(
    dense: true,
    enabled: master,
    leading: Checkbox(
      value: prefs.groupOn(group, media: media),
      onChanged: master ? (on) => controller.savePreferences(prefs.withGroup(group, on == true, media: media)) : null,
    ),
    title: Text(group.label),
    subtitle: Text(lines.join('\n'), maxLines: note != null ? 3 : 1, overflow: TextOverflow.ellipsis, style: _faint(context)),
    trailing: Icon(AppIcons.caretRight),
    onTap: () => _openGroupEntries(context, controller, group, media),
  );
}

Future<void> _openGroupEntries(BuildContext context, AppController controller, BlockedGroup group, bool media) {
  final keys = [for (final e in group.entries) e.key];
  return _openList(
    context,
    controller,
    group.label,
    (context) {
      final prefs = controller.preferences;
      final master = media ? prefs.blockStateMedia : prefs.blockGroups;
      final on = prefs.groupOn(group, media: media);
      return [
        SwitchListTile(
          title: Text(tr('Block this group')),
          subtitle: Text(media ? tr('Needs "Block state propaganda media" on') : tr('Needs "Block controversial religious groups" on')),
          value: on,
          onChanged: (v) => controller.savePreferences(prefs.withGroup(group, v, media: media)),
        ),
        for (final kind in BlockKind.values)
          if (group.entries.any((e) => e.kind == kind)) ...[
            _header(context, '${kind.label} · ${group.entries.where((e) => e.kind == kind).length}'),
            for (final entry in group.entries.where((e) => e.kind == kind))
              CheckboxListTile(
                dense: true,
                enabled: on && master,
                value: !prefs.allowedEntries.contains(entry.key),
                title: Text(entry.label),
                subtitle: entry.forms.length > 1 ? Text(entry.forms.skip(1).join(tr(', ')), style: _faint(context)) : null,
                onChanged: (checked) {
                  final latest = controller.preferences;
                  final rest = latest.allowedEntries.where((k) => k != entry.key).toList();
                  controller.savePreferences(latest.copyWith(allowedEntries: checked == true ? rest : [...rest, entry.key]));
                },
              ),
          ],
        _tip(context, tr('"Words in titles and channel names" block wherever they appear in a title or channel name; "Channel names" only count the channel name, which must be the name or start with it; @handles and channel ids must match exactly.')),
      ];
    },
    actions: (context) => [
      TextButton(
        onPressed: () {
          final latest = controller.preferences;
          controller.savePreferences(latest.copyWith(allowedEntries: latest.allowedEntries.where((k) => !keys.contains(k)).toList()));
        },
        child: Text(tr('Tick all')),
      ),
      TextButton(
        onPressed: () {
          final latest = controller.preferences;
          controller.savePreferences(latest.copyWith(allowedEntries: [...latest.allowedEntries.where((k) => !keys.contains(k)), ...keys]));
        },
        child: Text(tr('Untick all')),
      ),
    ],
  );
}

// Speeds

Future<void> openPlaySpeed(BuildContext context, AppController controller) => _openList(
      context,
      controller,
      tr('Speed settings'),
      (context) {
        final settings = controller.settings;
        return [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(tr('Tap the buttons below to set the default (preferred) speed or delete it'), style: TextStyle(color: context.colors.outline)),
          ),
          ListTile(title: Text(tr('Default speed')), subtitle: Text('${trimSpeed(settings.defaultSpeed)}x')),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
            child: Row(children: [
              Text(tr('Speed list'), style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton(onPressed: () => _addSpeed(context, controller), child: Text(tr('Add'))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final speed in settings.speeds)
                speed == settings.defaultSpeed
                    ? FilledButton(onPressed: () => _speedSheet(context, controller, speed), child: Text('${trimSpeed(speed)}x'))
                    : FilledButton.tonal(onPressed: () => _speedSheet(context, controller, speed), child: Text('${trimSpeed(speed)}x')),
            ]),
          ),
          _tip(context, tr("The speed menu in the player's bottom bar uses this list.")),
        ];
      },
      actions: (context) => [
        TextButton(
          onPressed: () async {
            final yes = await confirmDialog(
              context,
              title: tr('Reset speed?'),
              content: tr('Restores the default speed list and sets the default speed back to 1x.'),
              confirm: 'Reset',
            );
            if (yes) await controller.saveSettings(controller.settings.copyWith(speeds: defaultSpeeds, defaultSpeed: 1));
          },
          child: Text(tr('Reset')),
        ),
        const SizedBox(width: 8),
      ],
    );

Future<void> _addSpeed(BuildContext context, AppController controller) async {
  final text = await showDialog<String>(
    context: context,
    builder: (_) => _PromptDialog(
      title: tr('Add speed'),
      label: tr('Custom speed'),
      helper: tr('Between 0.1 and 5'),
      confirm: tr('Confirm'),
      numeric: true,
    ),
  );
  final value = text == null ? null : double.tryParse(text.trim());
  if (value == null) return;
  if (value < 0.1 || value > 5) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Speed must be between 0.1 and 5'))));
    return;
  }
  final speed = double.parse(value.toStringAsFixed(2));
  final settings = controller.settings;
  if (settings.speeds.contains(speed)) return;
  await controller.saveSettings(settings.copyWith(speeds: [...settings.speeds, speed]..sort()));
}

Future<void> _speedSheet(BuildContext context, AppController controller, double speed) => showModalBottomSheet<void>(
      context: context,
      builder: (sheet) {
        final settings = controller.settings;
        final removable = settings.speeds.length > 1 && speed != settings.defaultSpeed;
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.all(12), child: Text('${trimSpeed(speed)}x', style: Theme.of(sheet).textTheme.titleMedium)),
            ListTile(
              leading: Icon(AppIcons.checkCircle),
              title: Text(tr('Set as default speed')),
              onTap: () {
                Navigator.pop(sheet);
                controller.saveSettings(controller.settings.copyWith(defaultSpeed: speed));
              },
            ),
            ListTile(
              enabled: removable,
              leading: Icon(AppIcons.trash),
              title: Text(tr('Delete this item')),
              onTap: () {
                Navigator.pop(sheet);
                final latest = controller.settings;
                controller.saveSettings(latest.copyWith(speeds: latest.speeds.where((s) => s != speed).toList()));
              },
            ),
          ]),
        );
      },
    );

// Subtitles

Future<void> openSubtitleSettings(BuildContext context, AppController controller) => _openList(context, controller, tr('Subtitle settings'), (context) {
      final settings = controller.settings;
      Future<void> change(PlayerSettings Function(PlayerSettings latest) edit) => controller.saveSettings(edit(controller.settings));
      final off = settings.subtitleMode == SubtitleMode.off;
      final secondary = settings.secondarySubtitleLanguage;
      return [
        PopupItem<SubtitleMode>(
          title: tr('Turn on subtitles automatically'),
          leading: Icon(AppIcons.subtitles),
          value: settings.subtitleMode,
          values: [for (final m in SubtitleMode.values) (m, m.label)],
          onSelected: (m) => change((s) => s.copyWith(subtitleMode: m)),
        ),
        if (settings.subtitleMode == SubtitleMode.foreign)
          NormalItem(
            title: tr('Languages I understand'),
            leading: Icon(AppIcons.globe),
            subtitle: settings.understood.map((code) => TranslationLanguage.maybeByCode(code)?.label ?? code).join(', '),
            onTap: () async {
              final picked = await showDialog<List<String>>(context: context, builder: (_) => _KnownLanguagesDialog(initial: settings.understood));
              if (picked != null) await change((s) => s.copyWith(knownLanguages: picked));
            },
          ),
        PopupItem<Object>(
          title: tr('First subtitle language'),
          leading: Icon(AppIcons.translate),
          value: settings.subtitleOriginal ? PlayerSettings.originalSubtitle : settings.subtitleLanguage,
          values: <(Object, String)>[
            (PlayerSettings.originalSubtitle, tr("Video's own language")),
            for (final l in SubtitleLanguage.values) (l, l.label),
          ],
          onSelected: (v) => change((s) => v is SubtitleLanguage ? s.copyWith(subtitleLanguage: v, subtitleOriginal: false) : s.copyWith(subtitleOriginal: true)),
        ),
        PopupItem<String>(
          title: tr('Second subtitle language'),
          leading: Icon(AppIcons.closedCaptioning),
          enabled: !off,
          value: secondary == PlayerSettings.originalSubtitle || secondary == PlayerSettings.interfaceSubtitle ? secondary : TranslationLanguage.maybeByCode(secondary)?.code ?? '',
          values: [
            ('', tr('Never')),
            (PlayerSettings.interfaceSubtitle, tr('Interface language ({0})', [interfaceTranslationLanguage.label])),
            (PlayerSettings.originalSubtitle, tr("Video's own language (uploaded or auto-generated)")),
            for (final l in TranslationLanguage.all) (l.code, l.label),
          ],
          onSelected: (v) => change((s) => s.copyWith(secondarySubtitleLanguage: v)),
        ),
        _tip(
          context,
          off
              ? tr('Turn on “Turn on subtitles automatically” first, so the second subtitle can show by itself.')
              : tr('The first subtitle is shown in the first subtitle language, translated by YouTube when the video has none in it. The second subtitle appears above it; "Video\'s own language" is the subtitle in the language spoken in the video. It is hidden when it matches the first.'),
        ),
        SubtitlePreview(settings: settings),
        _header(context, tr('First subtitle style')),
        ..._subtitleStyleRows(
          context,
          font: settings.subtitleFont,
          scale: settings.subtitleScale,
          color: settings.subtitleColor,
          opacity: settings.subtitleOpacity,
          setFont: (v) => change((s) => s.copyWith(subtitleFont: v)),
          setScale: (v) => change((s) => s.copyWith(subtitleScale: v)),
          setColor: (v) => change((s) => s.copyWith(subtitleColor: v)),
          setOpacity: (v) => change((s) => s.copyWith(subtitleOpacity: v)),
        ),
        _header(context, tr('Second subtitle style')),
        ..._subtitleStyleRows(
          context,
          font: settings.secondaryFont,
          scale: settings.secondaryScale,
          color: settings.secondaryColor,
          opacity: settings.secondaryOpacity,
          setFont: (v) => change((s) => s.copyWith(secondaryFont: v)),
          setScale: (v) => change((s) => s.copyWith(secondaryScale: v)),
          setColor: (v) => change((s) => s.copyWith(secondaryColor: v)),
          setOpacity: (v) => change((s) => s.copyWith(secondaryOpacity: v)),
        ),
        _header(context, tr('General')),
        SwitchItem(
          title: tr('Subtitles rendered by mpv (libass)'),
          subtitle: tr('Supports styled subtitles; when off, the UI draws them, using fewer resources'),
          leading: Icon(AppIcons.stack),
          value: settings.libassSubtitles,
          onChanged: (v) => change((s) => s.copyWith(libassSubtitles: v)),
        ),
        SwitchItem(
          title: tr('Subtitles in picture in picture'),
          leading: Icon(AppIcons.pictureInpicture),
          value: settings.pipSubtitles,
          onChanged: (v) => change((s) => s.copyWith(pipSubtitles: v)),
        ),
        SwitchItem(
          title: tr('Subtitles in the mini player'),
          leading: Icon(AppIcons.closedCaptioning),
          value: settings.miniPlayerSubtitles,
          onChanged: (v) => change((s) => s.copyWith(miniPlayerSubtitles: v)),
        ),
        NormalItem(
          title: tr('Subtitle position'),
          subtitle: tr('Current: {0}% (100 is the bottom of the frame)', [settings.subtitlePosition]),
          leading: Icon(AppIcons.alignBottom),
          onTap: () => pickWithSlider(
            context,
            title: tr('Subtitle position'),
            value: settings.subtitlePosition.toDouble(),
            min: 0,
            max: 100,
            divisions: 100,
            suffix: '%',
            precise: 0,
            onSelected: (v) => change((s) => s.copyWith(subtitlePosition: v.round())),
          ),
        ),
        NormalItem(
          title: tr('Outline thickness'),
          subtitle: tr('Current: {0}', [settings.subtitleBorder.toStringAsFixed(1)]),
          leading: Icon(AppIcons.rectangleDashed),
          onTap: () => pickWithSlider(
            context,
            title: tr('Outline thickness'),
            value: settings.subtitleBorder,
            min: 0,
            max: 8,
            divisions: 16,
            precise: 1,
            onSelected: (v) => change((s) => s.copyWith(subtitleBorder: v)),
          ),
        ),
        SwitchItem(
          title: tr('Background box'),
          subtitle: tr('Add a semi-transparent black background behind subtitles instead of an outline'),
          leading: Icon(AppIcons.rectangle),
          value: settings.subtitleBackground,
          onChanged: (v) => change((s) => s.copyWith(subtitleBackground: v)),
        ),
        SwitchItem(
          title: tr('Bold'),
          leading: Icon(AppIcons.textB),
          value: settings.subtitleBold,
          onChanged: (v) => change((s) => s.copyWith(subtitleBold: v)),
        ),
        NormalItem(
          title: tr('Restore default style'),
          subtitle: tr('Microsoft YaHei, a white first subtitle and a smaller light gold second one'),
          leading: Icon(AppIcons.arrowCounterClockwise),
          onTap: () => change((s) => s.withDefaultSubtitleStyle()),
        ),
        _tip(context, tr('Subtitles are fetched by yt-dlp; auto-generated subtitles are used when no manual ones exist. Language and enable settings take effect from the next video; styles apply immediately.')),
      ];
    });

List<Widget> _subtitleStyleRows(
  BuildContext context, {
  required String font,
  required double scale,
  required int color,
  required double opacity,
  required ValueChanged<String> setFont,
  required ValueChanged<double> setScale,
  required ValueChanged<int> setColor,
  required ValueChanged<double> setOpacity,
}) =>
    [
      NormalItem(
        title: tr('Font'),
        leading: Icon(AppIcons.textAUnderline),
        subtitle: subtitleFontLabel(font),
        onTap: () => pickSubtitleFont(context, font, setFont),
      ),
      NormalItem(
        title: tr('Size'),
        leading: Icon(AppIcons.textAa),
        subtitle: '${scale.toStringAsFixed(1)}×',
        onTap: () => pickWithSlider(
          context,
          title: tr('Size'),
          value: scale,
          min: 0.5,
          max: 3,
          divisions: 25,
          suffix: '×',
          precise: 1,
          onSelected: (v) => setScale(double.parse(v.toStringAsFixed(1))),
        ),
      ),
      NormalItem(
        title: tr('Color'),
        leading: Icon(AppIcons.palette),
        subtitle: subtitleColorLabel(color),
        trailing: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF000000 | color),
            border: Border.all(color: context.colors.outlineVariant),
          ),
        ),
        onTap: () => pickSubtitleColor(context, color, setColor),
      ),
      NormalItem(
        title: tr('Opacity'),
        leading: Icon(AppIcons.drop),
        subtitle: '${(opacity * 100).round()}%',
        onTap: () => pickSubtitleOpacity(context, opacity, setOpacity),
      ),
    ];

class _KnownLanguagesDialog extends StatefulWidget {
  const _KnownLanguagesDialog({required this.initial});
  final List<String> initial;

  @override
  State<_KnownLanguagesDialog> createState() => _KnownLanguagesDialogState();
}

class _KnownLanguagesDialogState extends State<_KnownLanguagesDialog> {
  late final Set<String> _ticked = widget.initial.toSet();

  @override
  Widget build(BuildContext context) {
    final all = TranslationLanguage.all;
    final ordered = [...all.where((l) => _ticked.contains(l.code)), ...all.where((l) => !_ticked.contains(l.code))];
    return AlertDialog(
      title: Text(tr('Languages I understand')),
      content: SizedBox(
        width: dialogWidth(context, 380),
        height: 440,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr("Subtitles don't turn on by themselves for videos in these languages"), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(children: [
              for (final l in ordered)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _ticked.contains(l.code),
                  title: Text(l.label),
                  onChanged: (on) => setState(() => on == true ? _ticked.add(l.code) : _ticked.remove(l.code)),
                ),
            ]),
          ),
        ]),
      ),
      actions: [
        _cancel(context),
        TextButton(onPressed: () => Navigator.pop(context, [for (final l in all) if (_ticked.contains(l.code)) l.code]), child: Text(tr('Done'))),
      ],
    );
  }
}

// SponsorBlock

Future<void> openSponsorBlock(BuildContext context, AppController controller) => _openList(context, controller, tr('SponsorBlock'), (context) {
      final settings = controller.settings;
      final on = settings.sponsorBlock;
      return [
        SwitchItem(
          title: tr('Enable SponsorBlock'),
          subtitle: tr('Automatically skip sponsors, self-promotion and other segments'),
          leading: Icon(AppIcons.airplaneTakeoff),
          value: on,
          onChanged: (v) => controller.saveSettings(controller.settings.copyWith(sponsorBlock: v)),
        ),
        SwitchItem(
          title: tr('Show a notice when skipping'),
          leading: Icon(AppIcons.bell),
          enabled: on,
          value: settings.sponsorNotice,
          onChanged: (v) => controller.saveSettings(controller.settings.copyWith(sponsorNotice: v)),
        ),
        SwitchItem(
          title: tr('Cut them out of downloads'),
          subtitle: tr('Downloaded videos leave these segments out, cut at keyframes without encoding again'),
          leading: Icon(AppIcons.scissors),
          enabled: on,
          value: settings.sponsorCut,
          onChanged: (v) => controller.saveSettings(controller.settings.copyWith(sponsorCut: v)),
        ),
        _header(context, tr('Segment types to skip')),
        for (final MapEntry(key: category, value: (name, description)) in sponsorCategoryNames.entries)
          CheckboxListTile(
            title: Text(name),
            subtitle: Text(description, style: _faint(context)),
            value: settings.sponsorCategories.contains(category),
            onChanged: on
                ? (checked) {
                    final latest = controller.settings;
                    final next = {...latest.sponsorCategories};
                    checked == true ? next.add(category) : next.remove(category);
                    controller.saveSettings(latest.copyWith(sponsorCategories: next));
                  }
                : null,
          ),
        _tip(context, tr('Segment data comes from the SponsorBlock community (sponsor.ajay.app). Lookups send only the first 4 characters of the video ID hash, never your account or watch history.')),
      ];
    });

// Colors

Future<void> openColorSelect(BuildContext context, AppController controller) => _openList(context, controller, tr('Custom color'), (context) {
      final appearance = controller.appearance;
      final brightness = Theme.of(context).brightness;
      final hasWindowsAccent = controller.windowsAccent != null;
      final collapsed = appearance.systemAccent && hasWindowsAccent;
      ColorScheme schemeOf(Color seed) => ColorScheme.fromSeed(seedColor: seed, brightness: brightness, dynamicSchemeVariant: appearance.schemeVariant);

      Future<void> toggleSystemAccent() => controller.saveAppearance(appearance.copyWith(systemAccent: !appearance.systemAccent, skin: '', palette: ''));

      Widget swatch(String label, Color seed, bool selected, VoidCallback onTap) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ColorPalette(colorScheme: schemeOf(seed), selected: selected),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 12, color: selected ? context.colors.onSurface : context.colors.outline)),
            ]),
          );

      return [
        _header(context, tr('Custom')),
        PopupItem<ThemeMode>(
          title: tr('Theme mode'),
          leading: Icon(AppIcons.flashlight),
          value: appearance.themeMode,
          values: themeModes,
          onSelected: (m) => controller.saveAppearance(controller.appearance.copyWith(themeMode: m)),
        ),
        PopupItem<DynamicSchemeVariant>(
          title: tr('Palette style'),
          leading: Icon(AppIcons.palette),
          value: appearance.schemeVariant,
          values: [for (final e in schemeVariantNames.entries) (e.key, e.value)],
          onSelected: (v) => controller.saveAppearance(controller.appearance.copyWith(schemeVariant: v)),
        ),
        ListTile(
          enabled: hasWindowsAccent,
          leading: Checkbox(
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            value: appearance.systemAccent,
            onChanged: hasWindowsAccent ? (_) => toggleSystemAccent() : null,
          ),
          title: Text(tr('Follow Windows accent color')),
          subtitle: Text(
            hasWindowsAccent ? tr('Change it in Windows Settings › Personalization › Colors') : tr("Couldn't read the system accent color"),
            style: _faint(context),
          ),
          onTap: hasWindowsAccent ? toggleSystemAccent : null,
        ),
        AnimatedSize(
          duration: Motion.of(const Duration(milliseconds: 200)),
          curve: Ease.out,
          child: collapsed
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(spacing: 22, runSpacing: 18, alignment: WrapAlignment.center, children: [
                    swatch(tr('Custom'), Color(appearance.customAccent), appearance.accentIndex < 0, () async {
                      final picked = await showDialog<Color>(
                        context: context,
                        builder: (_) => AlertDialog(
                          clipBehavior: Clip.hardEdge,
                          contentPadding: const EdgeInsets.symmetric(vertical: 16),
                          title: Text(tr('Custom color')),
                          content: SlideColorPicker(color: Color(appearance.customAccent)),
                        ),
                      );
                      if (picked == null) return;
                      await controller.saveAppearance(controller.appearance.copyWith(skin: '', palette: '', accentIndex: -1, customAccent: picked.toARGB32()));
                    }),
                    for (var i = 0; i < accentChoices.length; i++)
                      swatch(accentChoices[i].$1, accentChoices[i].$2, appearance.accentIndex == i, () {
                        controller.saveAppearance(controller.appearance.copyWith(accentIndex: i, skin: '', palette: ''));
                      }),
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
                  Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
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

// Fonts

Future<void> openFontSettings(BuildContext context, AppController controller) => _openPage(context, tr('App font'), _FontPage(controller: controller));

class _FontPage extends StatefulWidget {
  const _FontPage({required this.controller});
  final AppController controller;

  @override
  State<_FontPage> createState() => _FontPageState();
}

class _FontPageState extends State<_FontPage> {
  final _search = TextEditingController();
  List<String> _system = const [];
  late bool _loading = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  String _query = '';

  @override
  void initState() {
    super.initState();
    if (_loading) unawaited(_load());
  }

  Future<void> _load() async {
    final names = await WindowsShell.systemFontFamilies();
    if (!mounted) return;
    setState(() {
      _system = names;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pick(String? family) {
    final appearance = widget.controller.appearance;
    return widget.controller.saveAppearance(family == null ? appearance.copyWith(clearFontFamily: true) : appearance.copyWith(fontFamily: family));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final appearance = widget.controller.appearance;
          final theme = Theme.of(context);
          final offered = {for (final (family, _) in fontChoices) family};
          final needle = _query.trim().toLowerCase();
          final installed = [for (final name in _system) if (!offered.contains(name) && name.toLowerCase().contains(needle)) name];
          final percent = (appearance.textScale * 100).round();
          return RadioGroup<String?>(
            groupValue: appearance.fontFamily,
            onChanged: _pick,
            child: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
              _header(context, tr('Font')),
              for (final (family, label) in fontChoices)
                RadioListTile<String?>(
                  value: family,
                  title: Text(label, style: TextStyle(fontFamily: family == autoFont ? appearance.font : family)),
                  subtitle: family == null || family == autoFont ? null : Text(family, style: _faint(context)),
                ),
              _header(context, tr('Installed system fonts')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LeavesByKeys(
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(prefixIcon: Icon(AppIcons.magnifyingGlass), hintText: tr('Search installed fonts')),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
              ),
              if (_loading)
                const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
              else if (installed.isEmpty)
                Padding(padding: const EdgeInsets.all(16), child: Text(tr('No installed fonts match'), style: TextStyle(color: context.colors.outline)))
              else
                for (final name in installed) RadioListTile<String?>(value: name, title: Text(name, style: TextStyle(fontFamily: name))),
              _header(context, tr('Font size')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(children: [
                  Expanded(
                    child: Slider(
                      value: appearance.textScale.clamp(0.8, 1.4),
                      min: 0.8,
                      max: 1.4,
                      divisions: 12,
                      label: '$percent%',
                      onChanged: (v) => widget.controller.saveAppearance(widget.controller.appearance.copyWith(textScale: double.parse(v.toStringAsFixed(2)))),
                    ),
                  ),
                  SizedBox(width: 48, child: Text('$percent%')),
                  TextButton(
                    onPressed: () => widget.controller.saveAppearance(widget.controller.appearance.copyWith(textScale: 1, fontFamily: autoFont)),
                    child: Text(tr('Reset')),
                  ),
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
                  Text(tr('Channel name · 120K views · 3 days ago'), style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline)),
                ]),
              ),
              _tip(context, tr("Noto Sans CJK SC is bundled with Lumtub. System fonts are read from the current Windows user's font collection.")),
            ]),
          );
        },
      );
}

// Picture

Future<void> openPictureSettings(BuildContext context, AppController controller) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _PicturePage(controller: controller)));

class _PicturePage extends StatefulWidget {
  const _PicturePage({required this.controller});
  final AppController controller;

  @override
  State<_PicturePage> createState() => _PicturePageState();
}

class _PicturePageState extends State<_PicturePage> {
  late final Map<String, int> _values = {...widget.controller.settings.picture};
  late int _delay = widget.controller.settings.audioDelayMs;

  AppController get _c => widget.controller;

  Future<void> _persist() => _c.saveSettings(_c.settings.copyWith(
        picture: {for (final e in _values.entries) if (e.value != 0) e.key: e.value},
        audioDelayMs: _delay,
      ));

  void _previewDelay() => _c.previewProperty('audio-delay', (_delay / 1000).toString());

  Future<void> _resetAll() async {
    setState(() {
      _values.clear();
      _delay = 0;
    });
    for (final (key, _) in pictureProperties) {
      unawaited(_c.previewProperty(key, '0'));
    }
    unawaited(_c.previewProperty('audio-delay', '0'));
    await _persist();
  }

  Widget _row({
    required String label,
    required int value,
    required int min,
    required int max,
    required int step,
    String suffix = '',
    required ValueChanged<int> onChanged,
    required VoidCallback onReset,
  }) =>
      Padding(
        padding: const EdgeInsetsDirectional.only(start: 16, top: 4, bottom: 4, end: 8),
        child: Row(children: [
          SizedBox(width: 72, child: Text(label)),
          Expanded(
            child: Slider(
              value: value.toDouble().clamp(min, max).toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: (max - min) ~/ step,
              label: '$value$suffix',
              onChanged: (v) => onChanged((v / step).round() * step),
              onChangeEnd: (_) => _persist(),
            ),
          ),
          SizedBox(width: 64, child: Text('$value$suffix', textAlign: TextAlign.end)),
          IconButton(
            tooltip: tr('Reset'),
            icon: Icon(AppIcons.arrowCounterClockwise, size: 20),
            onPressed: value == 0 ? null : onReset,
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SkinAppBar(AppBar(
        title: Text(tr('Video and A/V sync adjustments')),
        actions: [TextButton(onPressed: _resetAll, child: Text(tr('Reset all'))), const SizedBox(width: 8)],
      )),
      body: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        _header(context, tr('Video')),
        for (final (key, label) in pictureProperties)
          _row(
            label: label,
            value: _values[key] ?? 0,
            min: -pictureLimit(key),
            max: pictureLimit(key),
            step: 1,
            onChanged: (v) {
              setState(() => _values[key] = v);
              _c.previewProperty(key, '$v');
            },
            onReset: () {
              setState(() => _values.remove(key));
              _c.previewProperty(key, '0');
              _persist();
            },
          ),
        _header(context, tr('A/V sync')),
        _row(
          label: tr('Audio delay'),
          value: _delay,
          min: -2000,
          max: 2000,
          step: 10,
          suffix: ' ms',
          onChanged: (v) {
            setState(() => _delay = v);
            _previewDelay();
          },
          onReset: () {
            setState(() => _delay = 0);
            _previewDelay();
            _persist();
          },
        ),
        _tip(context, tr('Previews live on the playing video while dragging. Positive audio delay plays sound later; negative plays it earlier. These values apply to all subsequent videos.')),
      ]),
    );
  }
}

// Components

Future<void> openComponents(BuildContext context, AppController controller) => _openList(context, controller, tr('Components & data packs'), (context) {
      final tools = controller.tools;
      if (tools == null || !controller.ready) return [NormalItem(title: tr('Preparing components…'))];
      final libmpv = tools.libmpv;
      final selected = libmpv.selected;
      final restartPending = selected != null && selected.label != libmpv.current?.label;
      final libmpvLines = [
        if (!Platform.isWindows)
          tools.libmpvLabel
        else
          tr('{0}: {1}', [libmpv.usesDownload ? tr('Updated') : tr('Built-in'), libmpv.current?.label ?? tr('Unknown version')]),
        if (restartPending) tr('Uses {0} after restart', [selected.label]),
      ];
      return [
        NormalItem(
          title: 'libmpv',
          leading: Icon(AppIcons.filmSlate),
          subtitle: libmpvLines.join('\n'),
          trailing: libmpv.usesDownload || restartPending ? TextButton(onPressed: controller.rollBackLibmpv, child: Text(tr('Revert to built-in'))) : null,
        ),
        NormalItem(
          title: 'yt-dlp',
          leading: Icon(AppIcons.terminal),
          subtitle: tools.ytDlpVersion ?? tr('Not installed'),
          trailing: tools.canRollBackYtDlp ? TextButton(onPressed: controller.rollBackYtDlp, child: Text(tr('Roll back to previous version'))) : null,
        ),
        NormalItem(title: 'Deno', leading: Icon(AppIcons.code), subtitle: tools.denoVersion ?? tr('Not installed')),
        NormalItem(
          title: controller.checking ? tr('Checking for updates…') : tr('Check for updates now'),
          subtitle: tr('Downloads only from the official GitHub Release and verifies SHA-256. Takes effect after restart'),
          leading: Icon(AppIcons.arrowLineDown),
          enabled: !controller.checking,
          onTap: controller.checkUpdates,
        ),
        _tip(context, tr("New libmpv falls back to the built-in version automatically if it fails. If videos won't play after a yt-dlp update, you can roll back to the previous version.")),
        if (controller.packs case final packs?) PacksSection(packs),
      ];
    });

/// 组件与数据包 › 数据包: models, language data and shaders downloaded only
/// when wanted, with their size, license and a delete button.
class PacksSection extends StatelessWidget {
  const PacksSection(this.packs, {super.key});
  final PackManager packs;

  Future<void> _install(BuildContext context, Pack pack) async {
    final ok = await confirmDialog(
      context,
      title: tr('Download {0}?', [pack.title]),
      content: tr('{0} will be downloaded from {1} and checked against the signed list. License: {2}', [formatBytes(pack.size), Uri.tryParse(pack.files.first.url)?.host ?? '', pack.license]),
      confirm: tr('Download'),
    );
    if (!ok || !context.mounted) return;
    try {
      await packs.install(pack.id);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Could not download {0}: {1}', [pack.title, friendlyError(e)]))));
    }
  }

  Future<void> _remove(BuildContext context, InstalledPack installed) async {
    final ok = await confirmDialog(context, title: tr('Delete {0}?', [installed.pack.title]), content: tr('Frees {0}. You can download it again later.', [formatBytes(installed.pack.size)]), confirm: tr('Delete'));
    if (ok) await packs.remove(installed.pack.id);
  }

  void _details(BuildContext context, Pack pack) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(pack.title),
          content: SingleChildScrollView(
            child: SelectableText([
              if (pack.description.isNotEmpty) pack.description,
              tr('Version: {0}', [pack.version]),
              tr('Size: {0}', [formatBytes(pack.size)]),
              tr('License: {0}', [pack.license]),
              if (pack.source.isNotEmpty) tr('Source: {0}', [pack.source]),
              if (pack.notice.isNotEmpty) pack.notice,
            ].join('\n\n')),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Close')))],
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: packs,
        builder: (context, _) {
          final offered = packs.offered;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _header(context, tr('Data packs')),
            for (final installed in packs.installed)
              NormalItem(
                title: installed.pack.title,
                subtitle: '${installed.pack.kind.label} · ${installed.pack.version} · ${formatBytes(installed.pack.size)} · ${installed.pack.license}',
                leading: Icon(AppIcons.archive),
                onTap: () => _details(context, installed.pack),
                trailing: IconButton(tooltip: tr('Delete'), icon: Icon(AppIcons.trash), onPressed: packs.progress.isEmpty ? () => _remove(context, installed) : null),
              ),
            for (final pack in offered)
              NormalItem(
                title: pack.title,
                subtitle: [
                  '${pack.kind.label} · ${pack.version} · ${formatBytes(pack.size)} · ${pack.license}',
                  if (packs.progress[pack.id] case final done?) tr('Downloading… {0}%', [(done * 100).floor()]),
                  if (packs.installedOf(pack.id) != null) tr('Update available'),
                ].join('\n'),
                leading: Icon(AppIcons.archive),
                onTap: () => _details(context, pack),
                trailing: packs.progress.containsKey(pack.id)
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : TextButton(onPressed: packs.progress.isEmpty ? () => _install(context, pack) : null, child: Text(tr('Download'))),
              ),
            if (packs.installed.isEmpty && offered.isEmpty)
              NormalItem(title: tr('No data packs yet'), subtitle: tr('Offline subtitles, summaries and upscaling will download their models here when you turn them on.'), leading: Icon(AppIcons.archive)),
            NormalItem(
              title: packs.refreshing ? tr('Checking the data pack list…') : tr('Check the data pack list'),
              subtitle: packs.error ?? tr('Nothing is downloaded until you choose. Every file is checked against a list signed like Lumtub\'s updates'),
              leading: Icon(AppIcons.arrowsClockwise),
              enabled: !packs.refreshing,
              onTap: packs.refresh,
            ),
          ]);
        },
      );
}

// About

List<SettingEntry> aboutEntries(AppController controller) {
  const logLevelNames = [LogLevel.off, LogLevel.error, LogLevel.warn, LogLevel.info, LogLevel.debug];
  List<(LogLevel, String)> logLevels() => [
        (logLevelNames[0], tr('Off: nothing is recorded')),
        (logLevelNames[1], tr('Errors: only problems Lumtub could not get past')),
        (logLevelNames[2], tr('Warnings: also problems Lumtub worked around')),
        (logLevelNames[3], tr('Info: also what Lumtub did (default)')),
        (logLevelNames[4], tr('Debug: also every step and timing')),
      ];
  return [
    SettingEntry(
      tr('Version'),
      (context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(children: [
          Icon(AppIcons.monitorPlayFill, size: 72, color: context.colors.primary),
          const SizedBox(height: 4),
          Text('Lumtub', style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 2)),
          Text(tr('A third-party YouTube client built with Flutter and mpv'), style: TextStyle(color: context.colors.outline)),
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(AppIcons.gitCommit),
            title: Text(tr('Current version')),
            trailing: Text(appVersion, style: TextStyle(fontSize: 14, color: context.colors.outline)),
            onTap: () => copyText(context, appVersion, tr('Version number copied')),
          ),
        ]),
      ),
      subtitle: tr('Current version update'),
    ),
    SettingEntry(
      tr('Check for updates'),
      (context) => _UpdateCheckRow(controller: controller),
      subtitle: tr('Release page new version auto update'),
    ),
    SettingEntry(
      tr('Support development'),
      (context) => NormalItem(
        title: tr('Support development'),
        subtitle: tr('Sponsor Lumtub on GitHub Sponsors or with crypto'),
        leading: Icon(AppIcons.heartFill, color: const Color(0xFFEA4AAA)),
        onTap: () => openSupport(context),
      ),
      subtitle: tr('sponsor donate support'),
    ),
    SettingEntry(
      tr('Star it on GitHub'),
      (context) => NormalItem(
        title: tr('Star it on GitHub'),
        subtitle: tr('Helps more people find Lumtub'),
        leading: Icon(AppIcons.star, color: const Color(0xFFE3B341)),
        onTap: () => openExternal(_repository),
      ),
      subtitle: 'GitHub star',
    ),
    SettingEntry(
      tr('Support reminder'),
      (context) => StatefulBuilder(
        builder: (context, setState) {
          final reminder = controller.supportReminder;
          return SwitchItem(
            title: tr('Support reminder'),
            subtitle: tr('Now and then, at most once every two months, ask whether to support Lumtub'),
            leading: Icon(AppIcons.bell),
            enabled: reminder != null,
            value: reminder?.enabled ?? false,
            onChanged: (v) {
              reminder?.enabled = v;
              setState(() {});
            },
          );
        },
      ),
      subtitle: tr('sponsor donate support reminder'),
    ),
    SettingEntry(
      tr('Source code'),
      (context) => NormalItem(
        title: tr('GitHub repository'),
        subtitle: 'github.com/0x696c757a696f/lumtub',
        leading: Icon(AppIcons.code),
        onTap: () => openExternal(_repository),
      ),
      subtitle: tr('GitHub source code'),
    ),
    SettingEntry(
      tr('Feedback'),
      (context) => NormalItem(
        title: tr('Feedback'),
        subtitle: tr('File an issue on GitHub with the diagnostics and error log attached'),
        leading: Icon(AppIcons.chatCenteredText),
        onTap: () => openExternal('$_repository/issues/new/choose'),
      ),
      subtitle: 'issue bug',
    ),
    SettingEntry(
      tr('Error log'),
      (context) => NormalItem(
        title: tr('Error log'),
        subtitle: tr('Stored only on this device. Sign-in credentials and stream URLs are never saved'),
        leading: Icon(AppIcons.bug),
        onTap: () => openLogs(context, controller),
      ),
      subtitle: tr('Log'),
    ),
    SettingEntry(
      tr('Log level'),
      (context) => NormalItem(
        title: tr('Log level'),
        subtitle: tr('Now: {0}. Set it to Debug for a while to track a problem down; it records more detail', [labelOf(logLevels(), controller.preferences.logLevel)]),
        leading: Icon(AppIcons.slidersHorizontal),
        onTap: () => pickFromDialog<LogLevel>(
          context,
          title: tr('Log level'),
          value: controller.preferences.logLevel,
          values: logLevels(),
          onSelected: (v) => controller.savePreferences(controller.preferences.copyWith(logLevel: v)),
        ),
      ),
      subtitle: tr('log level debug verbose'),
    ),
    SettingEntry(
      tr('Copy diagnostics'),
      (context) => NormalItem(
        title: tr('Copy diagnostics'),
        subtitle: tr('Version, system, graphics card, components and playback settings'),
        leading: Icon(AppIcons.copy),
        onTap: () => copyText(context, controller.diagnostics(), tr('Diagnostics copied')),
      ),
      subtitle: tr('feedback issues'),
    ),
    SettingEntry(
      tr('Open source licenses'),
      (context) => NormalItem(
        title: tr('Open source licenses'),
        subtitle: tr('AGPLv3; playback is built on mpv, media_kit and yt-dlp'),
        leading: Icon(AppIcons.gavel),
        onTap: () => showLicensePage(context: context, applicationName: 'Lumtub', applicationVersion: appVersion),
      ),
      subtitle: 'mpv media_kit yt-dlp license',
    ),
  ];
}

class _UpdateCheckRow extends StatelessWidget {
  const _UpdateCheckRow({required this.controller});
  final AppController controller;

  ({String title, String subtitle}) _text(AppUpdater? updater) {
    final available = updater?.available;
    final checkedAtStartup = tr('Checked at startup and every 6 hours; you can also check now.');
    if (updater?.ready != null) {
      final error = updater?.installError;
      return (
        title: tr('Version {0} downloaded', [updater?.readyVersion ?? available?.version ?? '']),
        subtitle: error != null
            ? tr("The installer didn't start: {0}. Click to try again", [error])
            : Platform.isAndroid
                ? tr('Tap to install it')
                : tr('Installs when Lumtub closes; click to restart and update now'),
      );
    }
    if (updater?.progress != null) {
      return (
        title: tr('Downloading version {0}…', [updater?.downloading ?? available?.version ?? '']),
        subtitle: '${((updater?.progress ?? 0) * 100).round()}%',
      );
    }
    if (updater?.checking ?? false) return (title: tr('Checking for app updates…'), subtitle: checkedAtStartup);
    if (available != null) {
      final title = tr('Update available: {0}', [available.version]);
      if (available.version == updater?.rejected) {
        return (title: title, subtitle: tr('The installer failed its signature check and was not installed. Click to download it from GitHub Releases'));
      }
      if (!AppUpdater.canInstall || available.asset == null) return (title: title, subtitle: tr('Click to open the GitHub Release download.'));
      final error = updater?.error;
      if (error != null) return (title: title, subtitle: tr('Download failed: {0}. Click to retry', [error]));
      return (title: title, subtitle: Platform.isAndroid ? tr('Tap to download and install') : tr('Click to download; it installs when Lumtub closes'));
    }
    final error = updater?.error;
    return (title: tr('Check for updates'), subtitle: error != null ? tr('Could not check for app updates: {0}', [error]) : checkedAtStartup);
  }

  Future<void> _tapped(BuildContext context) async {
    final updater = controller.appUpdater;
    if (updater?.ready != null) {
      await controller.restartToUpdate();
      return;
    }
    if (updater?.progress != null || (updater?.checking ?? false)) return;
    await controller.checkAppUpdate();
    final found = updater?.available;
    if (found != null) {
      if (!AppUpdater.canInstall || found.asset == null || found.version == updater?.rejected) {
        await openExternal(AppUpdater.releasePage(found.page));
      }
    } else if (context.mounted && updater?.error == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Lumtub is up to date'))));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([controller, controller.appUpdater]),
        builder: (context, _) {
          final text = _text(controller.appUpdater);
          return NormalItem(
            title: text.title,
            subtitle: text.subtitle,
            leading: Icon(AppIcons.clockClockwise),
            onTap: () => _tapped(context),
          );
        },
      );
}

// Logs

Future<void> openLogs(BuildContext context, AppController controller) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _LogsPage(controller: controller)));

class _LogEntry {
  _LogEntry(this.time, this.text);
  final String? time;
  String text;

  LogLevel get level {
    final body = text.trimLeft();
    for (final level in LogLevel.values) {
      if (level != LogLevel.off && body.startsWith(level.tag.trim())) return level;
    }
    return body.startsWith('错误') ? LogLevel.error : LogLevel.info;
  }
}

List<_LogEntry> _parseLog(String raw) {
  final entries = <_LogEntry>[];
  for (final line in const LineSplitter().convert(raw)) {
    if (line.isEmpty) continue;
    final space = line.indexOf(' ');
    final stamped = space > 0 && DateTime.tryParse(line.substring(0, space)) != null;
    if (stamped) {
      entries.add(_LogEntry(line.substring(0, space), line.substring(space + 1)));
    } else if (entries.isNotEmpty) {
      entries.last.text = '${entries.last.text}\n$line';
    } else {
      entries.add(_LogEntry(null, line));
    }
  }
  return entries;
}

class _LogsPage extends StatefulWidget {
  const _LogsPage({required this.controller});
  final AppController controller;

  @override
  State<_LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<_LogsPage> {
  static const _names = ['lumtub.old.log', 'lumtub.log'];
  String? _text;
  LogLevel _shown = LogLevel.debug;

  Directory? get _dir => widget.controller.directories?.logs;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final dir = _dir;
    final buffer = StringBuffer();
    if (dir != null) {
      for (final name in _names) {
        try {
          buffer.write(await File('${dir.path}${Platform.pathSeparator}$name').readAsString());
        } catch (_) {}
      }
    }
    if (mounted) setState(() => _text = buffer.toString());
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _clear() async {
    final yes = await confirmDialog(context, title: tr('Clear logs?'), content: tr('Deletes Lumtub logs saved on this device.'), confirm: 'Clear all');
    final dir = _dir;
    if (!yes || dir == null) return;
    for (final name in _names) {
      try {
        await File('${dir.path}${Platform.pathSeparator}$name').writeAsString('');
      } catch (_) {}
    }
    await _load();
    _snack(tr('Cleared'));
  }

  Future<void> _export() async {
    String two(int n) => n.toString().padLeft(2, '0');
    final now = DateTime.now();
    final name = 'lumtub-log-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}.txt';
    try {
      final saved = await saveFileAs(name, Uint8List.fromList(utf8.encode(_text ?? '')), mime: 'text/plain', label: 'TXT', extension: 'txt');
      if (saved) _snack(tr('Log exported'));
    } catch (e) {
      logError('Could not export the log', e);
      _snack(tr('Export failed: {0}', [friendlyFileError(e)]));
    }
  }

  Widget _menu() => PopupMenuButton<VoidCallback>(
        onSelected: (action) => action(),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: () => copyText(context, _text ?? '', tr('Copied')),
            child: Text(tr('Copy log')),
          ),
          PopupMenuItem(value: _export, child: Text(tr('Export log'))),
          PopupMenuItem(value: () => openExternal('$_repository/issues/new/choose'), child: Text(tr('Bug reports'))),
          if (!Platform.isAndroid && !Platform.isIOS)
            PopupMenuItem(
              value: () {
                final dir = _dir;
                if (dir != null) openInExplorer(dir.path);
              },
              child: Text(tr('Open log folder')),
            ),
          PopupMenuItem(value: _clear, child: Text(tr('Clear logs'))),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final text = _text;
    final colors = context.colors;
    final chips = [
      (LogLevel.debug, tr('All')),
      (LogLevel.info, tr('Info and above')),
      (LogLevel.warn, tr('Warnings and above')),
      (LogLevel.error, tr('Errors only')),
    ];
    final entries = text == null ? const <_LogEntry>[] : _parseLog(text).where((e) => e.level.index <= _shown.index).toList().reversed.toList();
    Color? colorOf(LogLevel level) => switch (level) {
          LogLevel.error => colors.error,
          LogLevel.warn => colors.tertiary,
          LogLevel.debug => colors.outline,
          _ => null,
        };
    return Scaffold(
      appBar: SkinAppBar(AppBar(title: Text(tr('Logs')), actions: [_menu(), const SizedBox(width: 4)])),
      body: text == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Wrap(spacing: 8, children: [
                    for (final (level, label) in chips) ChoiceChip(label: Text(label), selected: _shown == level, onSelected: (_) => setState(() => _shown = level)),
                  ]),
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? Center(child: Text(tr('No logs yet'), style: TextStyle(color: colors.outline)))
                    : SelectionArea(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                          itemCount: entries.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final e = entries[i];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                if (e.time != null) Text(e.time!.replaceFirst('T', ' ').split('.').first, style: _faint(context)),
                                Text(e.text, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: colorOf(e.level))),
                              ]),
                            );
                          },
                        ),
                      ),
              ),
            ]),
    );
  }
}

// Connected servers

Future<void> openPrivacyConnections(BuildContext context, AppController controller) => _openList(context, controller, tr('Connected servers'), (context) {
      final prefs = controller.preferences;
      final settings = controller.settings;
      final dns = DnsServer.of(settings.dnsServer, settings.dnsCustomUrl);
      final relay = settings.playbackSource.relay;
      final notInUse = tr('Not in use');

      Widget row(
        IconData icon,
        String title,
        String hosts,
        String detail, {
        String? state,
        bool? on,
        ValueChanged<bool>? toggle,
        VoidCallback? onTap,
      }) =>
          ListTile(
            isThreeLine: true,
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text('$hosts\n$detail'),
            trailing: toggle != null
                ? Switch(value: on ?? false, onChanged: toggle)
                : Text(state ?? '', style: TextStyle(color: context.colors.outline)),
            onTap: toggle != null ? () => toggle(!(on ?? false)) : onTap,
          );

      return [
        _tip(context, tr('Lumtub has no analytics, telemetry or crash reporting, and never uploads watch history, cookies or account data. These are all the servers it connects to; with a proxy on, all go through it.')),
        _header(context, tr('Required')),
        row(
          AppIcons.monitorPlay,
          'YouTube',
          'www.youtube.com · *.googlevideo.com · i.ytimg.com',
          tr('Search, lists, playback and thumbnails. YouTube sees your IP and what you watch, as in a browser'),
          state: tr('Required'),
        ),
        row(
          AppIcons.listMagnifyingGlass,
          tr('YouTube search suggestions'),
          'suggestqueries-clients6.youtube.com',
          tr('While you type in the search box, the text so far is sent to YouTube for suggestions'),
          state: tr('While typing'),
        ),
        _header(context, tr('Can be turned off')),
        row(
          AppIcons.arrowLineDown,
          tr('Update checks'),
          'api.github.com · github.com',
          tr('Checks for and downloads new versions of Lumtub, libmpv, yt-dlp and other components; GitHub sees only your IP'),
          on: prefs.autoCheckUpdates,
          toggle: (v) => controller.savePreferences(prefs.copyWith(autoCheckUpdates: v, autoUpdateApp: v && prefs.autoUpdateApp)),
        ),
        row(
          AppIcons.fastForward,
          tr('SponsorBlock'),
          'sponsor.ajay.app',
          tr("Sponsor segments are looked up by a prefix of the video ID's hash, so the server doesn't learn which video"),
          on: settings.sponsorBlock,
          toggle: (v) => controller.saveSettings(settings.copyWith(sponsorBlock: v)),
        ),
        row(
          AppIcons.textT,
          'DeArrow',
          'sponsor.ajay.app · dearrow-thumb.ajay.app',
          tr("Replaces clickbait with community titles and thumbnails; titles are looked up by a prefix of the video ID's hash, replacement thumbnails are downloaded by video ID"),
          on: settings.deArrowTitles || settings.deArrowThumbnails,
          toggle: (v) => controller.saveSettings(settings.copyWith(deArrowTitles: v, deArrowThumbnails: v)),
        ),
        row(
          AppIcons.thumbsDown,
          'Return YouTube Dislike',
          'returnyoutubedislikeapi.com',
          tr('Shows estimated dislikes on the watch page; sends it the ID of the video you watch'),
          on: settings.returnDislike,
          toggle: (v) => controller.saveSettings(settings.copyWith(returnDislike: v)),
        ),
        row(
          AppIcons.translate,
          tr('Translation'),
          prefs.translation.service.label,
          tr('Text is sent to the chosen service only when you click Translate, turn on subtitle translation or use AI summary'),
          state: tr('When pressed'),
          onTap: () => openTranslationSettings(context, controller),
        ),
        row(
          AppIcons.graph,
          tr('Piped / Invidious'),
          settings.playbackSource != PlaybackSource.youtube ? settings.playbackSource.label : notInUse,
          tr('Fetch videos from YouTube for you; they learn which video you watch. Also tried briefly when YouTube answers 429'),
          state: relay != null ? tr('In use') : tr('Fallback only'),
        ),
        row(
          AppIcons.hardDrives,
          tr('Encrypted DNS'),
          dns?.url ?? notInUse,
          tr('Looks up host names on a direct connection; the DNS server learns which sites you visit, not what you do there'),
          state: dns == null ? tr('Close') : tr('In use'),
        ),
        row(
          AppIcons.userCircle,
          tr('Google account'),
          'accounts.google.com · oauth2.googleapis.com · www.googleapis.com',
          tr('Only after signing in, to sync subscriptions, playlists, likes and comments'),
          state: controller.account?.signedIn ?? false ? tr('Signed in') : tr('Signed out'),
        ),
        row(
          AppIcons.globe,
          tr('Browser sign-in'),
          'www.youtube.com/youtubei',
          tr('Only after signing in: your YouTube pages, likes, comments, subscriptions and playlists, requested as the YouTube website'),
          state: controller.webSignIn?.signedIn ?? false ? tr('Signed in') : tr('Signed out'),
        ),
      ];
    });
