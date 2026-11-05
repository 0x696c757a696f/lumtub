import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../l10n/l10n.dart';
import '../../models.dart' show ChannelRef;
import '../../watch_time.dart';
import '../../widgets/pilinara_settings_tiles.dart' show confirmDialog;
import '../theme.dart';
import '../app_icons.dart';

/// [seconds] as 1 小时 5 分 or 12 分钟.
String watchDuration(int seconds) {
  final minutes = seconds ~/ 60;
  if (minutes < 1) return seconds > 0 ? tr('Under 1 min') : tr('0 min');
  if (minutes < 60) return tr('{0} min', [minutes]);
  final rest = minutes % 60;
  return rest == 0 ? tr('{0} h', [minutes ~/ 60]) : tr('{0} h {1} min', [minutes ~/ 60, rest]);
}

/// 观看统计: how long videos played, from [WatchTime].
Future<void> openWatchStats(BuildContext context, AppController controller) {
  controller.flushWatchTime();
  return Navigator.of(context).push(MaterialPageRoute<void>(builder: (context) => _WatchStatsPage(controller: controller)));
}

class _WatchStatsPage extends StatefulWidget {
  const _WatchStatsPage({required this.controller});
  final AppController controller;

  @override
  State<_WatchStatsPage> createState() => _WatchStatsPageState();
}

class _WatchStatsPageState extends State<_WatchStatsPage> {
  late Future<WatchStats?> _stats = _load();

  Future<WatchStats?> _load() async => await widget.controller.watchTime?.stats();

  Future<void> _clear() async {
    if (!await confirmDialog(context, title: tr('Clear watch statistics?'), content: tr('The daily watch time kept on this computer will be deleted.'), confirm: tr('Clear'))) return;
    widget.controller.watchTime?.clear();
    setState(() => _stats = _load());
  }

  @override
  Widget build(BuildContext context) {
    final recording = widget.controller.preferences.recordHistory;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Watch statistics')), actions: [
        IconButton(tooltip: tr('Clear watch statistics'), icon: const Icon(AppIcons.trash), onPressed: _clear),
      ]),
      body: FutureBuilder<WatchStats?>(
        future: _stats,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          final stats = snapshot.data;
          if (stats == null) return Center(child: Text(tr('The native core is missing')));
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
            if (!recording)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(tr('Record watch history is off, so new watch time is not counted.'), style: TextStyle(color: context.colors.outline)),
              ),
            Wrap(spacing: 12, runSpacing: 12, children: [
              _Tile(label: tr('Today'), value: watchDuration(stats.today)),
              _Tile(label: tr('Last 7 days'), value: watchDuration(stats.week)),
              _Tile(label: tr('Last 30 days'), value: watchDuration(stats.month)),
              _Tile(label: tr('Daily average'), value: watchDuration(stats.average)),
            ]),
            const SizedBox(height: 24),
            Text(tr('Each day, last 30 days'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SizedBox(height: 140, child: _DailyBars(days: stats.days)),
            const SizedBox(height: 24),
            Text(tr('Most watched channels, last 30 days'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            if (stats.top.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(tr('Nothing recorded yet'), style: TextStyle(color: context.colors.outline)))
            else
              for (final (key, name, seconds) in stats.top)
                _ChannelRow(
                  name: name,
                  seconds: seconds,
                  most: stats.top.first.$3,
                  onTap: key.startsWith('name:')
                      ? null
                      : () {
                          Navigator.of(context).popUntil((route) => route.isFirst);
                          widget.controller.openChannel(ChannelRef(key, name));
                        },
                ),
          ]);
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        width: 160,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: context.colors.surfaceContainerHighest, borderRadius: AppStyle.cardRadius),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: context.colors.outline, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ]),
      );
}

/// One bar a day; the day's date and time show on hover.
class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.days});
  final List<(String, int)> days;

  @override
  Widget build(BuildContext context) {
    final most = days.fold(0, (m, d) => max(m, d.$2));
    final colors = context.colors;
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (final (day, seconds) in days)
        Expanded(
          child: Tooltip(
            message: '${day.substring(5)} · ${watchDuration(seconds)}',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: most == 0 ? 0.02 : max(0.02, seconds / most),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: seconds == 0 ? colors.surfaceContainerHighest : colors.primary,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({required this.name, required this.seconds, required this.most, this.onTap});
  final String name;
  final int seconds;
  final int most;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: AppStyle.cardRadius,
        child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(name.isEmpty ? tr('Unknown channel') : name, maxLines: 1, overflow: TextOverflow.ellipsis)),
            Text(watchDuration(seconds), style: TextStyle(color: context.colors.outline, fontSize: 12)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(value: most == 0 ? 0 : seconds / most, minHeight: 4, backgroundColor: context.colors.surfaceContainerHighest),
          ),
        ]),
      ),
      );
}
