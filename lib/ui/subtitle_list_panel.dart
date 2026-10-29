import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../app/app_controller.dart';
import '../app_preferences.dart' show SubtitleListMode;
import '../l10n/l10n.dart';
import '../models.dart' show SubtitleOption;
import '../subtitle_cues.dart';
import 'motion.dart';
import 'player_panel.dart';

/// 字幕列表: every line of the main subtitle beside the video, with the
/// second subtitle's words under it, the one being spoken marked and kept
/// in view. A tap jumps there; the copy button
/// or a right click copies the line.
Future<void> showSubtitleList(BuildContext context, AppController controller, Player player) => showPlayerPanel(
      context,
      title: tr('字幕列表'),
      width: 420,
      builder: (context) => SubtitleList(controller: controller, player: player),
    );

class SubtitleList extends StatefulWidget {
  const SubtitleList({super.key, required this.controller, required this.player});
  final AppController controller;
  final Player player;

  @override
  State<SubtitleList> createState() => _SubtitleListState();
}

class _SubtitleListState extends State<SubtitleList> {
  late Future<List<PairedCue>> _cues = widget.controller.listedSubtitleCues();
  final _scroll = ScrollController();
  StreamSubscription<Object?>? _trackChanges;
  StreamSubscription<Duration>? _positions;
  int _current = -1;
  /// Following the playing line stops while the person scrolls.
  bool _follow = true;
  String _query = '';
  final _currentKey = GlobalKey();

  late SubtitleOption? _second = widget.controller.secondarySubtitle;
  late SubtitleListMode _mode = widget.controller.preferences.subtitleListMode;

  @override
  void initState() {
    super.initState();
    _trackChanges = widget.player.stream.track.listen((_) => _reload());
    widget.controller.addListener(_secondChanged);
  }

  void _reload() => setState(() {
        _cues = widget.controller.listedSubtitleCues();
        _current = -1;
        unawaited(_positions?.cancel());
        _positions = null;
      });

  void _secondChanged() {
    final mode = widget.controller.preferences.subtitleListMode;
    if (identical(widget.controller.secondarySubtitle, _second) && mode == _mode) return;
    _second = widget.controller.secondarySubtitle;
    _mode = mode;
    _reload();
  }

  /// Both subtitles are on, so there is a choice of what to list.
  bool get _bothOn {
    final main = widget.player.state.track.subtitle;
    if (const {'no', 'auto'}.contains(main.id)) return false;
    // A translation is listed with its original lines too.
    return _second != null || widget.controller.listedOriginalOf(main) != null;
  }

  Widget _modeMenu(ColorScheme colors) => PopupMenuButton<SubtitleListMode>(
        tooltip: tr('列表显示'),
        initialValue: _mode,
        onSelected: (mode) => unawaited(widget.controller.savePreferences(widget.controller.preferences.copyWith(subtitleListMode: mode))),
        itemBuilder: (context) => [
          for (final mode in SubtitleListMode.values) CheckedPopupMenuItem(value: mode, checked: mode == _mode, child: Text(mode.label)),
        ],
        icon: Icon(Icons.view_agenda_outlined, color: colors.onSurfaceVariant),
      );

  @override
  void dispose() {
    widget.controller.removeListener(_secondChanged);
    _trackChanges?.cancel();
    _positions?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _listen(List<PairedCue> cues) {
    final starts = [for (final c in cues) c.cue];
    _positions?.cancel();
    void at(Duration position) {
      final index = cueIndexAt(starts, position);
      if (index == _current || !mounted) return;
      setState(() => _current = index);
      if (_follow && _query.isEmpty && index >= 0) WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(index, cues.length));
    }

    _positions = widget.player.stream.position.listen(at);
    WidgetsBinding.instance.addPostFrameCallback((_) => at(widget.player.state.position));
  }

  /// Scrolls the playing row to a third of the way down. Rows differ in
  /// height, so one not built yet is first jumped near by the average.
  void _reveal(int index, int count) {
    if (!mounted) return;
    final built = _currentKey.currentContext;
    if (built != null) {
      unawaited(Scrollable.ensureVisible(built, alignment: 0.3, duration: Motion.of(const Duration(milliseconds: 250)), curve: Curves.easeOut));
      return;
    }
    if (!_scroll.hasClients || count == 0) return;
    final position = _scroll.position;
    final average = (position.maxScrollExtent + position.viewportDimension) / count;
    _scroll.jumpTo((index * average - position.viewportDimension / 3).clamp(0.0, position.maxScrollExtent));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _currentKey.currentContext;
      if (row != null && mounted) unawaited(Scrollable.ensureVisible(row, alignment: 0.3));
    });
  }

  void _copy(PairedCue line) {
    unawaited(Clipboard.setData(ClipboardData(text: [line.cue.text, if (line.second != null) line.second!].join('\n'))));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr('已复制字幕')), duration: const Duration(seconds: 1)));
  }

  static String _clock(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FutureBuilder<List<PairedCue>>(
      future: _cues,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        final cues = snapshot.data ?? const <PairedCue>[];
        if (cues.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                const {'no', 'auto'}.contains(widget.player.state.track.subtitle.id) && widget.controller.secondarySubtitle == null ? tr('先打开一条字幕') : tr('这条字幕无法列出'),
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.outline),
              ),
            ),
          );
        }
        if (_positions == null) _listen(cues);
        final shown = [
          for (final (i, cue) in cues.indexed)
            if (_query.isEmpty || cue.cue.text.toLowerCase().contains(_query) || (cue.second?.toLowerCase().contains(_query) ?? false)) i,
        ];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, _bothOn ? 4 : 16, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search_rounded, size: 20), hintText: tr('搜索字幕')),
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                ),
              ),
              if (_bothOn) _modeMenu(colors),
            ]),
          ),
          Expanded(
            child: NotificationListener<UserScrollNotification>(
              onNotification: (_) {
                _follow = false;
                return false;
              },
              child: ListView.builder(
                controller: _scroll,
                itemCount: shown.length,
                itemBuilder: (context, k) {
                  final i = shown[k];
                  final line = cues[i];
                  final cue = line.cue;
                  final swap = _mode == SubtitleListMode.secondOver && line.second != null;
                  final top = swap ? line.second! : cue.text;
                  final under = swap ? cue.text : line.second;
                  final playing = i == _current;
                  return GestureDetector(
                    key: playing ? _currentKey : null,
                    onSecondaryTap: () => _copy(line),
                    child: Material(
                      color: playing ? colors.secondaryContainer : Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          _follow = true;
                          unawaited(widget.player.seek(cue.start));
                        },
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            SizedBox(
                              width: 52,
                              child: Text(_clock(cue.start), style: TextStyle(fontSize: 12, color: playing ? colors.primary : colors.outline, fontFeatures: const [FontFeature.tabularFigures()])),
                            ),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                Text(
                                  top,
                                  style: TextStyle(fontSize: 13, height: 1.4, color: playing ? colors.onSecondaryContainer : colors.onSurface, fontWeight: playing ? FontWeight.w600 : null),
                                ),
                                if (under != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    under,
                                    style: TextStyle(fontSize: 12, height: 1.4, color: playing ? colors.onSecondaryContainer.withValues(alpha: 0.8) : colors.onSurfaceVariant),
                                  ),
                                ],
                              ]),
                            ),
                            IconButton(
                              tooltip: tr('复制'),
                              visualDensity: VisualDensity.compact,
                              iconSize: 16,
                              icon: Icon(Icons.content_copy_rounded, color: colors.outline),
                              onPressed: () => _copy(line),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (!_follow)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Center(
                child: FilledButton.tonalIcon(
                  onPressed: () => setState(() {
                    _follow = true;
                    _current = -1;
                  }),
                  icon: const Icon(Icons.my_location_rounded, size: 18),
                  label: Text(tr('回到当前这句')),
                ),
              ),
            ),
        ]);
      },
    );
  }
}
