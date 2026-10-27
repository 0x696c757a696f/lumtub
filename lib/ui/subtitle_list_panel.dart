import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../app/app_controller.dart';
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

  late SubtitleOption? _second = widget.controller.secondarySubtitle;

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
    if (identical(widget.controller.secondarySubtitle, _second)) return;
    _second = widget.controller.secondarySubtitle;
    _reload();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_secondChanged);
    _trackChanges?.cancel();
    _positions?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _listen(List<PairedCue> cues, double rowHeight) {
    final starts = [for (final c in cues) c.cue];
    _positions?.cancel();
    void at(Duration position) {
      final index = cueIndexAt(starts, position);
      if (index == _current || !mounted) return;
      setState(() => _current = index);
      if (_follow && _query.isEmpty && index >= 0 && _scroll.hasClients) {
        final target = (index * rowHeight - _scroll.position.viewportDimension / 3).clamp(0.0, _scroll.position.maxScrollExtent);
        unawaited(Motion.scrollTo(_scroll, target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut));
      }
    }

    _positions = widget.player.stream.position.listen(at);
    WidgetsBinding.instance.addPostFrameCallback((_) => at(widget.player.state.position));
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
        final bilingual = cues.any((c) => c.second != null);
        final rowHeight = bilingual ? 92.0 : 64.0;
        if (_positions == null) _listen(cues, rowHeight);
        final shown = [
          for (final (i, cue) in cues.indexed)
            if (_query.isEmpty || cue.cue.text.toLowerCase().contains(_query) || (cue.second?.toLowerCase().contains(_query) ?? false)) i,
        ];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search_rounded, size: 20), hintText: tr('搜索字幕')),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: NotificationListener<UserScrollNotification>(
              onNotification: (_) {
                _follow = false;
                return false;
              },
              child: ListView.builder(
                controller: _scroll,
                itemExtent: _query.isEmpty ? rowHeight : null,
                itemCount: shown.length,
                itemBuilder: (context, k) {
                  final i = shown[k];
                  final line = cues[i];
                  final cue = line.cue;
                  final playing = i == _current;
                  return GestureDetector(
                    onSecondaryTap: () => _copy(line),
                    child: Material(
                      color: playing ? colors.secondaryContainer : Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          _follow = true;
                          unawaited(widget.player.seek(cue.start));
                        },
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            SizedBox(
                              width: 52,
                              child: Text(_clock(cue.start), style: TextStyle(fontSize: 12, color: playing ? colors.primary : colors.outline, fontFeatures: const [FontFeature.tabularFigures()])),
                            ),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                Text(
                                  cue.text,
                                  maxLines: _query.isEmpty ? 2 : null,
                                  overflow: _query.isEmpty ? TextOverflow.ellipsis : null,
                                  style: TextStyle(fontSize: 13, height: 1.4, color: playing ? colors.onSecondaryContainer : colors.onSurface, fontWeight: playing ? FontWeight.w600 : null),
                                ),
                                if (line.second case final second?)
                                  Text(
                                    second,
                                    maxLines: _query.isEmpty ? 2 : null,
                                    overflow: _query.isEmpty ? TextOverflow.ellipsis : null,
                                    style: TextStyle(fontSize: 12, height: 1.4, color: playing ? colors.onSecondaryContainer.withValues(alpha: 0.8) : colors.onSurfaceVariant),
                                  ),
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
