import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../app/app_controller.dart';
import '../l10n/l10n.dart';
import '../models.dart' show SubtitleKind, SubtitleOption;
import '../subtitle_translation.dart';
import '../translation.dart';

/// The player's 字幕 panel: the main subtitle on the left, the one shown
/// above it (双语字幕) on the right, as PiliNara's `_SubtitleSelectPanel`
/// has them. A choice applies at once and the panel stays open; a track
/// chosen on one side is greyed out on the other.
Future<void> showSubtitlePanel(BuildContext context, AppController controller, Player player, {required VoidCallback onSettings}) => showGeneralDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: tr('关闭'),
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondary) => _SubtitlePanel(controller: controller, player: player, onSettings: onSettings),
      transitionBuilder: (context, animation, secondary, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );

class _SubtitlePanel extends StatefulWidget {
  const _SubtitlePanel({required this.controller, required this.player, required this.onSettings});
  final AppController controller;
  final Player player;
  final VoidCallback onSettings;

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
    final target = TranslationLanguage.byCode(controller.preferences.translateLanguage);
    final translation = translationOf(offered, target);
    final labels = {for (final o in offered) o.label};
    // Tracks mpv has that the list above does not name, such as those
    // libmpv's ytdl_hook added or a downloaded video's files.
    final others = [
      for (final t in player.state.tracks.subtitle)
        if (_real(t) && !labels.contains(t.title) && (translation == null || t.title != translation.label))
          (key: 't:${t.id}', label: _trackLabel(t), detail: null, option: null, track: t) as _Choice,
    ];
    final main = player.state.track.subtitle;
    final mainKey = !_real(main) ? 'off' : labels.contains(main.title) || main.title == translation?.label ? 'o:${main.title}' : 't:${main.id}';
    final secondary = controller.secondarySubtitle;
    final secondaryKey = secondary == null ? 'off' : 'o:${secondary.label}';

    final groups = <(String, List<_Choice>)>[
      if (others.isNotEmpty) (tr('已加载'), others),
      (tr('视频自带'), [for (final o in offered) if (o.kind == SubtitleKind.uploaded) _ofOption(o)]),
      (tr('自动生成'), [for (final o in offered) if (o.kind == SubtitleKind.automatic) _ofOption(o)]),
    ];
    final translated = [for (final o in offered) if (o.kind == SubtitleKind.translated) _ofOption(o)];
    final searching = _query.isNotEmpty;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    Widget column({required bool primary}) {
      final selected = primary ? mainKey : secondaryKey;
      final other = primary ? secondaryKey : mainKey;
      final busy = primary ? _busyMain : _busySecondary;
      Widget row(_Choice choice, {IconData? icon}) {
        final isSelected = choice.key == selected;
        final disabled = choice.key != 'off' && choice.key == other;
        return InkWell(
          onTap: disabled || isSelected ? null : () => _choose(choice, primary: primary),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              if (icon != null) ...[Icon(icon, size: 16, color: disabled ? colors.outline : colors.primary), const SizedBox(width: 8)],
              Expanded(
                child: Text(
                  choice.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: disabled ? colors.outline : isSelected ? colors.primary : colors.onSurface, fontWeight: isSelected ? FontWeight.w600 : null),
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
            if (translation != null) row((key: 'o:${translation.label}', label: tr('翻译为{0}', [target.label]), detail: null, option: translation, track: null), icon: Icons.translate_rounded),
            for (final (title, rows) in visible) ...[heading(title), for (final c in rows) row(c)],
            if (shownTranslated.isNotEmpty) ...[
              if (searching || _allLanguages) ...[heading(tr('YouTube 自动翻译')), for (final c in shownTranslated) row(c)]
              else
                TextButton.icon(
                  onPressed: () => setState(() => _allLanguages = true),
                  icon: const Icon(Icons.expand_more_rounded, size: 18),
                  label: Text(tr('更多语言（YouTube 自动翻译，{0} 种）', [shownTranslated.length])),
                ),
            ],
            if (searching && visible.isEmpty && shownTranslated.isEmpty)
              Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(tr('没有匹配的语言'), style: TextStyle(color: colors.outline)))),
          ]),
        ),
      ]);
    }

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        elevation: 8,
        color: colors.surfaceContainerHigh,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 560,
          height: double.infinity,
          child: SafeArea(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(children: [
                  Text(tr('字幕'), style: theme.textTheme.titleMedium),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onSettings();
                    },
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: Text(tr('字幕设置')),
                  ),
                  IconButton(tooltip: tr('关闭'), onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
                ]),
              ),
              if (offered.length > 6)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search_rounded, size: 20), hintText: tr('搜索语言，如 中文、ja')),
                    onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  ),
                ),
              if (offered.isEmpty && others.isEmpty)
                Expanded(child: Center(child: Text(controller.loadingDetails ? tr('正在读取字幕列表…') : tr('这个视频没有字幕'), style: TextStyle(color: colors.outline))))
              else
                Expanded(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: column(primary: true)),
                    VerticalDivider(width: 1, color: colors.outlineVariant),
                    Expanded(child: column(primary: false)),
                  ]),
                ),
            ]),
          ),
        ),
      ),
    );
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
    } finally {
      if (mounted) setState(() => primary ? _busyMain = null : _busySecondary = null);
    }
  }

  static String _trackLabel(SubtitleTrack t) {
    final parts = [if (t.title != null && t.title!.isNotEmpty) t.title!, if (t.language != null && t.language!.isNotEmpty) t.language!];
    return parts.isEmpty ? tr('轨道 {0}', [t.id]) : parts.join(' · ');
  }
}
