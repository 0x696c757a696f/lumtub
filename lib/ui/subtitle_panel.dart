import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../app/app_controller.dart';
import '../l10n/l10n.dart';
import '../models.dart' show SubtitleKind, SubtitleOption;
import '../subtitle_translation.dart';
import '../player_settings.dart' show SubtitleLanguage, interfaceTranslationLanguage;
import '../translation.dart' show TranslationException;
import 'pages/translation_settings_page.dart' show openTranslationSettings;
import 'player_panel.dart';
import 'common.dart' show ErrorBanner;
import 'subtitle_list_panel.dart';
import 'app_icons.dart';

/// The player's 字幕 panel: the main subtitle on the left, the one shown
/// above it (双语字幕) on the right, as PiliNara's `_SubtitleSelectPanel`
/// has them. A choice applies at once and the panel stays open; a track
/// chosen on one side is greyed out on the other, and tapping it there
/// swaps the two sides.
Future<void> showSubtitlePanel(BuildContext context, AppController controller, Player player, {required VoidCallback onSettings, VoidCallback? onList}) => showPlayerPanel(
      context,
      title: tr('Subtitles'),
      width: 560,
      actions: [
        Builder(
          builder: (inner) => TextButton.icon(
            onPressed: () {
              Navigator.of(inner).pop();
              onList != null ? onList() : unawaited(showSubtitleList(context, controller, player));
            },
            icon: Icon(AppIcons.textAlignLeft, size: 18),
            label: Text(tr('Subtitle list')),
          ),
        ),
        Builder(
          builder: (context) => TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              onSettings();
            },
            icon: Icon(AppIcons.slidersHorizontal, size: 18),
            label: Text(tr('Subtitle settings')),
          ),
        ),
      ],
      builder: (context) => _SubtitlePanel(controller: controller, player: player),
    );

class _SubtitlePanel extends StatefulWidget {
  const _SubtitlePanel({required this.controller, required this.player});
  final AppController controller;
  final Player player;

  @override
  State<_SubtitlePanel> createState() => _SubtitlePanelState();
}

/// One row: an option the video offers, or a track already in the player.
typedef _Choice = ({String key, String label, String? detail, SubtitleOption? option, SubtitleTrack? track});

class _SubtitlePanelState extends State<_SubtitlePanel> {
  String _query = '';
  bool _allLanguages = false;
  /// The row being applied, per side.
  String? _busyMain;
  String? _busySecondary;
  /// The options shown, by row key, for swapping the two sides.
  var _options = <String, SubtitleOption>{};
  final _subscriptions = <StreamSubscription<Object?>>[];

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _subscriptions.addAll([
      widget.player.stream.track.listen((_) => _changed()),
      widget.player.stream.tracks.listen((_) => _changed()),
    ]);
    widget.controller.addListener(_changed);
    // The subtitle mpv chose by itself shows as chosen here too.
    unawaited(widget.controller.syncMainSubtitle());
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  static bool _real(SubtitleTrack t) => t.id != 'auto' && t.id != 'no';

  _Choice _ofOption(SubtitleOption o) => (key: 'o:${o.label}', label: o.label, detail: o.language, option: o, track: null);

  bool _matches(String text) => _query.isEmpty || text.toLowerCase().contains(_query);

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final player = widget.player;
    final offered = controller.details?.subtitles ?? const <SubtitleOption>[];
    // The video's own language, at the top so it need not be looked for,
    // then the interface's and Windows', each once.
    final spoken = originalSubtitle(offered, language: controller.details?.language);
    final chosen = controller.settings.subtitleLanguage;
    final near = languageRows(offered, spoken, [
      (tr('Interface language'), interfaceTranslationLanguage),
      (tr('System language'), SubtitleLanguage.systemTranslation),
      if (chosen != SubtitleLanguage.auto) (tr('Subtitle language'), chosen.translation),
    ]);
    final nearOptions = [for (final r in near) r.option];
    final labels = {for (final o in offered) o.label};
    final nearLabels = {for (final o in nearOptions) o.label};
    // Tracks mpv has that the list above does not name, such as those
    // libmpv's ytdl_hook added or a downloaded video's files.
    // libmpv's ytdl_hook names YouTube's automatic captions "xx-orig":
    // the same lines as the automatic subtitle listed in that language.
    SubtitleOption? listedAs(SubtitleTrack t) {
      final language = t.language ?? '';
      if (!language.endsWith('-orig')) return null;
      final code = language.substring(0, language.length - 5);
      return offered.where((o) => o.kind == SubtitleKind.automatic && o.language == code).firstOrNull;
    }

    final others = [
      for (final t in player.state.tracks.subtitle)
        if (_real(t) && !widget.controller.isSubtitleCopy(t.id) && !labels.contains(t.title) && !nearLabels.contains(t.title) && listedAs(t) == null)
          (key: 't:${t.id}', label: _trackLabel(t), detail: null, option: null, track: t) as _Choice,
    ];
    final main = player.state.track.subtitle;
    final mainKey = !_real(main)
        ? 'off'
        : labels.contains(main.title) || nearLabels.contains(main.title)
            ? 'o:${main.title}'
            : listedAs(main) != null
                ? 'o:${listedAs(main)!.label}'
                : 't:${main.id}';
    final secondary = controller.secondarySubtitle;
    // Being fetched or translated still: shown as on its way, not 关闭.
    final loading = controller.secondaryLoading;
    final secondaryKey = secondary == null ? (loading == null ? 'off' : 'o:${loading.label}') : 'o:${secondary.label}';
    _options = {for (final o in [...nearOptions, ...offered]) 'o:${o.label}': o};
    bool listedAbove(SubtitleOption o) => identical(o, spoken) || nearOptions.any((n) => identical(n, o));

    final searching = _query.isNotEmpty;
    final groups = <(String, List<_Choice>)>[
      if (others.isNotEmpty) (tr('Loaded'), others),
      (tr('From the video'), [for (final o in offered) if (o.kind == SubtitleKind.uploaded && (searching || !listedAbove(o))) _ofOption(o)]),
      (tr('Auto-generated'), [for (final o in offered) if (o.kind == SubtitleKind.automatic && (searching || !listedAbove(o))) _ofOption(o)]),
      (tr('Speech recognition'), [for (final o in offered) if (o.kind == SubtitleKind.speech && (searching || !listedAbove(o))) _ofOption(o)]),
    ];
    final translated = [for (final o in offered) if (o.kind == SubtitleKind.translated) _ofOption(o)];
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    Widget column({required bool primary}) {
      final busy = primary ? _busyMain : _busySecondary ?? (loading == null ? null : 'o:${loading.label}');
      // A row shows as chosen the moment it is tapped; loading follows.
      final selected = busy ?? (primary ? mainKey : secondaryKey);
      final mine = primary ? mainKey : secondaryKey;
      final other = (primary ? _busySecondary : _busyMain) ?? (primary ? secondaryKey : mainKey);
      Widget row(_Choice choice, {IconData? icon}) {
        final isSelected = choice.key == selected;
        // The other side's subtitle: tapping it swaps the two.
        final swap = choice.key != 'off' && choice.key == other;
        return InkWell(
          onTap: isSelected || _busyMain != null || _busySecondary != null ? null : () => swap ? _swap(choice, primary: primary, mine: mine) : _choose(choice, primary: primary),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              if (icon != null) ...[Icon(icon, size: 16, color: swap ? colors.outline : colors.primary), const SizedBox(width: 8)],
              Expanded(
                child: Text(
                  choice.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: swap ? colors.outline : isSelected ? colors.primary : colors.onSurface, fontWeight: isSelected ? FontWeight.w600 : null),
                ),
              ),
              if (busy == choice.key)
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              else if (isSelected)
                Icon(AppIcons.check, size: 18, color: colors.primary),
            ]),
          ),
        );
      }

      Widget heading(String text) => Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Text(text, style: theme.textTheme.labelMedium!.copyWith(color: colors.outline)),
          );

      final visible = [
        // mpv's own tracks are not offered as the secondary subtitle.
        for (final (title, rows) in primary ? groups : groups.where((g) => !identical(g.$2, others)))
          if (rows.where((c) => _matches('${c.label} ${c.detail ?? ''}')).toList() case final shown when shown.isNotEmpty) (title, shown),
      ];
      final shownTranslated = translated.where((c) => _matches('${c.label} ${c.detail ?? ''}')).toList();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Text(primary ? tr('First subtitle') : tr('Second subtitle (above)'), style: theme.textTheme.titleSmall),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.only(bottom: 12), children: [
            row((key: 'off', label: tr('Close'), detail: null, option: null, track: null), icon: AppIcons.prohibitFill),
            if (spoken != null && !searching) row((key: 'o:${spoken.label}', label: tr('Original: {0}', [spoken.label]), detail: null, option: spoken, track: null), icon: AppIcons.userSound),
            if (!searching)
              for (final r in near)
                row(
                  (
                    key: 'o:${r.option.label}',
                    label: r.option.kind == SubtitleKind.translated ? tr('{0}: {1} (YouTube translation)', [r.name, r.language.label]) : tr('{0}: {1}', [r.name, r.option.label]),
                    detail: null,
                    option: r.option,
                    track: null,
                  ),
                  icon: r.option.kind == SubtitleKind.translated ? AppIcons.translate : AppIcons.subtitles,
                ),
            for (final (title, rows) in visible) ...[heading(title), for (final c in rows) row(c)],
            if (shownTranslated.isNotEmpty) ...[
              if (searching || _allLanguages) ...[heading(tr('YouTube auto-translate')), for (final c in shownTranslated) row(c)]
              else
                TextButton.icon(
                  onPressed: () => setState(() => _allLanguages = true),
                  icon: Icon(AppIcons.caretDown, size: 18),
                  label: Text(tr('More languages ({0})', [shownTranslated.length])),
                ),
            ],
            if (searching && visible.isEmpty && shownTranslated.isEmpty)
              Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(tr('No matching languages'), style: TextStyle(color: colors.outline)))),
          ]),
        ),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (offered.length > 6)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            decoration: InputDecoration(isDense: true, prefixIcon: Icon(AppIcons.magnifyingGlass, size: 20), hintText: tr('Search language, e.g. Chinese, ja')),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
        ),
      if (offered.isEmpty && others.isEmpty)
        Expanded(
          child: Center(
            child: controller.loadingDetails
                ? Text(tr('Reading the subtitle list…'), style: TextStyle(color: colors.outline))
                : SpeechOffer(controller: controller, onDone: () => setState(() {})),
          ),
        )
      else
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: column(primary: true)),
            VerticalDivider(width: 1, color: colors.outlineVariant),
            Expanded(child: column(primary: false)),
          ]),
        ),
    ]);
  }

  Future<void> _choose(_Choice choice, {required bool primary}) async {
    setState(() => primary ? _busyMain = choice.key : _busySecondary = choice.key);
    try {
      final controller = widget.controller;
      if (primary) {
        if (choice.key == 'off') {
          await widget.player.setSubtitleTrack(SubtitleTrack.no());
        } else if (choice.track != null) {
          await widget.player.setSubtitleTrack(choice.track!);
        } else {
          await controller.showSubtitle(choice.option!);
        }
      } else {
        await controller.setSecondarySubtitle(choice.option);
      }
      // A track mpv loaded itself has no option to remember by.
      if (choice.key == 'off' || choice.option != null) await controller.rememberSubtitleChoice(primary: primary, option: choice.option);
    } finally {
      if (mounted) setState(() => primary ? _busyMain = null : _busySecondary = null);
    }
  }

  /// Puts [choice], the other side's subtitle, on this side and this
  /// side's subtitle ([mine]) on the other. mpv shows a track on one side
  /// only, so the second subtitle is cleared first.
  Future<void> _swap(_Choice choice, {required bool primary, required String mine}) async {
    final controller = widget.controller;
    final player = widget.player;
    final current = _options[mine];
    setState(() {
      _busyMain = primary ? choice.key : mine;
      _busySecondary = primary ? mine : choice.key;
    });
    try {
      await controller.setSecondarySubtitle(null);
      final main = primary ? choice.option : current;
      if (main == null) {
        await player.setSubtitleTrack(SubtitleTrack.no());
      } else {
        await controller.showSubtitle(main);
      }
      final second = primary ? current : choice.option;
      if (second != null) await controller.setSecondarySubtitle(second);
    } finally {
      if (mounted) setState(() => _busyMain = _busySecondary = null);
    }
  }

  static String _trackLabel(SubtitleTrack t) {
    final parts = [if (t.title != null && t.title!.isNotEmpty) t.title!, if (t.language != null && t.language!.isNotEmpty) t.language!];
    return parts.isEmpty ? tr('Track {0}', [t.id]) : parts.join(' · ');
  }
}

/// 这个视频没有字幕, with 语音识别 to make some: progress while it runs, and
/// the way to its settings when it is not set up.
class SpeechOffer extends StatefulWidget {
  const SpeechOffer({super.key, required this.controller, this.onDone, this.message});
  final AppController controller;
  final VoidCallback? onDone;
  /// What is said above the button; 这个视频没有字幕 when null.
  final String? message;

  @override
  State<SpeechOffer> createState() => _SpeechOfferState();
}

class _SpeechOfferState extends State<SpeechOffer> {
  String? _error;

  Future<void> _run() async {
    setState(() => _error = null);
    try {
      await widget.controller.recognizeSpeech();
      widget.onDone?.call();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is TranslationException ? e.message : '$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: ValueListenableBuilder(
        valueListenable: controller.speechJob,
        builder: (context, job, _) {
          final mine = job != null && job.videoId == controller.playing?.id;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.message ?? tr('This video has no subtitles'), textAlign: TextAlign.center, style: TextStyle(color: colors.outline)),
            const SizedBox(height: 12),
            if (mine) ...[
              SizedBox(
                width: 220,
                child: LinearProgressIndicator(value: job.total == 0 ? null : job.done / job.total),
              ),
              const SizedBox(height: 8),
              Text(job.total > 1 ? '${job.stage} ${job.done} / ${job.total}' : job.stage, style: TextStyle(color: colors.outline, fontSize: 12)),
            ] else if (controller.canRecognizeSpeech)
              FilledButton.tonalIcon(
                onPressed: job == null ? _run : null,
                icon: Icon(AppIcons.waveform, size: 18),
                label: Text(tr('Make subtitles with speech recognition')),
              )
            else ...[
              Text(tr("Speech recognition sends this video's audio to the service you set up under Translation & AI (such as Groq or OpenAI) and makes timed subtitles."),
                  textAlign: TextAlign.center, style: TextStyle(color: colors.outline, fontSize: 12, height: 1.5)),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  await openTranslationSettings(context, controller);
                  if (mounted) setState(() {});
                },
                icon: Icon(AppIcons.gear, size: 18),
                label: Text(tr('Set up speech recognition')),
              ),
            ],
            if (_error case final error? when !mine) ...[
              const SizedBox(height: 12),
              ErrorBanner(error, onRetry: controller.canRecognizeSpeech ? _run : null),
            ],
          ]);
        },
      ),
    );
  }
}
