import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../app/app_controller.dart';
import '../l10n/l10n.dart';
import '../models.dart' show SubtitleKind, SubtitleOption;
import '../subtitle_translation.dart';
import '../speech_subtitles.dart' show SpeechNeedsFfmpeg;
import '../player_settings.dart' show SubtitleLanguage;
import '../translation.dart' show TranslationException, TranslationLanguage;
import 'pages/translation_settings_page.dart' show openTranslationSettings;
import 'player_panel.dart';
import 'common.dart' show ErrorBanner;
import 'subtitle_list_panel.dart';

/// The player's 字幕 panel: the main subtitle on the left, the one shown
/// above it (双语字幕) on the right, as PiliNara's `_SubtitleSelectPanel`
/// has them. A choice applies at once and the panel stays open; a track
/// chosen on one side is greyed out on the other, and tapping it there
/// swaps the two sides.
Future<void> showSubtitlePanel(BuildContext context, AppController controller, Player player, {required VoidCallback onSettings, VoidCallback? onList}) => showPlayerPanel(
      context,
      title: tr('字幕'),
      width: 560,
      actions: [
        Builder(
          builder: (inner) => TextButton.icon(
            onPressed: () {
              Navigator.of(inner).pop();
              onList != null ? onList() : unawaited(showSubtitleList(context, controller, player));
            },
            icon: const Icon(Icons.subject_rounded, size: 18),
            label: Text(tr('字幕列表')),
          ),
        ),
        Builder(
          builder: (context) => TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              onSettings();
            },
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: Text(tr('字幕设置')),
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
    final interface = TranslationLanguage.maybeByCode(youtubeHl);
    final near = languageRows(offered, spoken, [
      if (interface != null) (tr('界面语言'), interface),
      (tr('系统语言'), SubtitleLanguage.auto.translation),
      if (chosen != SubtitleLanguage.auto) (tr('字幕语言'), chosen.translation),
    ]);
    final nearOptions = [for (final r in near) r.option];
    final labels = {for (final o in offered) o.label};
    final nearLabels = {for (final o in nearOptions) o.label};
    // Tracks mpv has that the list above does not name, such as those
    // libmpv's ytdl_hook added or a downloaded video's files.
    final others = [
      for (final t in player.state.tracks.subtitle)
        if (_real(t) && !labels.contains(t.title) && !nearLabels.contains(t.title))
          (key: 't:${t.id}', label: _trackLabel(t), detail: null, option: null, track: t) as _Choice,
    ];
    final main = player.state.track.subtitle;
    final mainKey = !_real(main) ? 'off' : labels.contains(main.title) || nearLabels.contains(main.title) ? 'o:${main.title}' : 't:${main.id}';
    final secondary = controller.secondarySubtitle;
    // Being fetched or translated still: shown as on its way, not 关闭.
    final loading = controller.secondaryLoading;
    final secondaryKey = secondary == null ? (loading == null ? 'off' : 'o:${loading.label}') : 'o:${secondary.label}';
    _options = {for (final o in [...nearOptions, ...offered]) 'o:${o.label}': o};
    bool listedAbove(SubtitleOption o) => identical(o, spoken) || nearOptions.any((n) => identical(n, o));

    final searching = _query.isNotEmpty;
    final groups = <(String, List<_Choice>)>[
      if (others.isNotEmpty) (tr('已加载'), others),
      (tr('视频自带'), [for (final o in offered) if (o.kind == SubtitleKind.uploaded && (searching || !listedAbove(o))) _ofOption(o)]),
      (tr('自动生成'), [for (final o in offered) if (o.kind == SubtitleKind.automatic && (searching || !listedAbove(o))) _ofOption(o)]),
      (tr('语音识别'), [for (final o in offered) if (o.kind == SubtitleKind.speech && (searching || !listedAbove(o))) _ofOption(o)]),
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
                  style: TextStyle(fontSize: 13, color: swap ? colors.outline : isSelected ? colors.primary : colors.onSurface, fontWeight: isSelected ? FontWeight.w600 : null),
                ),
              ),
              if (busy == choice.key)
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              else if (isSelected)
                Icon(Icons.check_rounded, size: 18, color: colors.primary),
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
          child: Text(primary ? tr('第一字幕') : tr('第二字幕（上方）'), style: theme.textTheme.titleSmall),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.only(bottom: 12), children: [
            row((key: 'off', label: tr('关闭'), detail: null, option: null, track: null), icon: Icons.block_rounded),
            if (spoken != null && !searching) row((key: 'o:${spoken.label}', label: tr('原语言：{0}', [spoken.label]), detail: null, option: spoken, track: null), icon: Icons.record_voice_over_outlined),
            if (!searching)
              for (final r in near)
                row(
                  (
                    key: 'o:${r.option.label}',
                    label: r.option.kind == SubtitleKind.translated ? tr('{0}：{1}（YouTube 翻译）', [r.name, r.language.label]) : tr('{0}：{1}', [r.name, r.option.label]),
                    detail: null,
                    option: r.option,
                    track: null,
                  ),
                  icon: r.option.kind == SubtitleKind.translated ? Icons.translate_rounded : Icons.subtitles_outlined,
                ),
            for (final (title, rows) in visible) ...[heading(title), for (final c in rows) row(c)],
            if (shownTranslated.isNotEmpty) ...[
              if (searching || _allLanguages) ...[heading(tr('YouTube 自动翻译')), for (final c in shownTranslated) row(c)]
              else
                TextButton.icon(
                  onPressed: () => setState(() => _allLanguages = true),
                  icon: const Icon(Icons.expand_more_rounded, size: 18),
                  label: Text(tr('更多语言（{0} 种）', [shownTranslated.length])),
                ),
            ],
            if (searching && visible.isEmpty && shownTranslated.isEmpty)
              Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(tr('没有匹配的语言'), style: TextStyle(color: colors.outline)))),
          ]),
        ),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (offered.length > 6)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search_rounded, size: 20), hintText: tr('搜索语言，如 中文、ja')),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
        ),
      if (offered.isEmpty && others.isEmpty)
        Expanded(
          child: Center(
            child: controller.loadingDetails
                ? Text(tr('正在读取字幕列表…'), style: TextStyle(color: colors.outline))
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
    return parts.isEmpty ? tr('轨道 {0}', [t.id]) : parts.join(' · ');
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
  bool _needsFfmpeg = false;

  Future<void> _run({bool withFfmpeg = false}) async {
    setState(() {
      _error = null;
      _needsFfmpeg = false;
    });
    try {
      await widget.controller.recognizeSpeech(withFfmpeg: withFfmpeg);
      widget.onDone?.call();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is TranslationException ? e.message : '$e';
          _needsFfmpeg = e is SpeechNeedsFfmpeg;
        });
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
            Text(widget.message ?? tr('这个视频没有字幕'), textAlign: TextAlign.center, style: TextStyle(color: colors.outline)),
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
                icon: const Icon(Icons.graphic_eq_rounded, size: 18),
                label: Text(tr('用语音识别生成字幕')),
              )
            else ...[
              Text(tr('语音识别会把这个视频的音频发给你在“翻译与 AI”里设置的服务（如 Groq、OpenAI），生成带时间轴的字幕。'),
                  textAlign: TextAlign.center, style: TextStyle(color: colors.outline, fontSize: 12, height: 1.5)),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  await openTranslationSettings(context, controller);
                  if (mounted) setState(() {});
                },
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: Text(tr('设置语音识别')),
              ),
            ],
            if (_error case final error? when !mine) ...[
              const SizedBox(height: 12),
              _needsFfmpeg
                  ? ErrorBanner(error, onRetry: () => _run(withFfmpeg: true), retryLabel: tr('安装 ffmpeg 并继续'))
                  : ErrorBanner(error, onRetry: controller.canRecognizeSpeech ? _run : null),
            ],
          ]);
        },
      ),
    );
  }
}
