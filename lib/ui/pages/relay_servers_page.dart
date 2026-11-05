import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../piped_streams.dart';
import '../../relay_servers.dart';
import '../theme.dart';
import 'settings_sections.dart';
import '../../l10n/l10n.dart';
import '../app_icons.dart';

/// 设置 › Piped 服务器 / Invidious 实例: choose automatic selection or one
/// server, measure them all, and download the public list again.
Future<void> openRelayServers(BuildContext context, AppController controller, RelayKind kind) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (context) => _RelayServersPage(controller: controller, kind: kind)));

class _RelayServersPage extends StatefulWidget {
  const _RelayServersPage({required this.controller, required this.kind});
  final AppController controller;
  final RelayKind kind;

  @override
  State<_RelayServersPage> createState() => _RelayServersPageState();
}

class _RelayServersPageState extends State<_RelayServersPage> {
  bool get _isPiped => widget.kind == RelayKind.piped;
  RelayServers get _piped => _isPiped ? widget.controller.piped : widget.controller.invidious;
  String? _busy;

  @override
  void initState() {
    super.initState();
    if (!_piped.catalog.any(_piped.wasTried)) unawaited(_run(tr('Testing speed…'), _piped.servers));
  }

  Future<void> _run(String label, Future<void> Function() task) async {
    if (_busy != null) return;
    setState(() => _busy = label);
    try {
      await task();
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _update() => _run(tr('Updating list and testing speed…'), () async {
        await _piped.updateCatalog();
        await _piped.remeasure();
      });

  Future<void> _choose(String? server) {
    final settings = widget.controller.settings;
    return widget.controller.saveSettings(switch ((_isPiped, server)) {
      (true, null) => settings.copyWith(playbackSource: PlaybackSource.pipedAuto),
      (true, final server?) => settings.copyWith(playbackSource: PlaybackSource.pipedCustom, pipedServer: server),
      (false, null) => settings.copyWith(playbackSource: PlaybackSource.invidiousAuto),
      (false, final server?) => settings.copyWith(playbackSource: PlaybackSource.invidiousCustom, invidiousServer: server),
    });
  }

  /// Answering servers fastest first, then unmeasured, then unreachable.
  List<String> _sorted() {
    int rank(String s) => _piped.timingOf(s) ?? (_piped.wasTried(s) ? 1 << 30 : 1 << 29);
    return _piped.catalog..sort((a, b) => rank(a).compareTo(rank(b)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final updated = _piped.catalogUpdatedAt;
    return Scaffold(
      appBar: AppBar(title: Text(_isPiped ? tr('Piped servers') : tr('Invidious instance')), actions: [
        IconButton(tooltip: tr('Speed test'), icon: const Icon(AppIcons.gauge), onPressed: _busy == null ? () => _run(tr('Testing speed…'), _piped.remeasure) : null),
        IconButton(tooltip: tr('Update list'), icon: const Icon(AppIcons.arrowsClockwise), onPressed: _busy == null ? _update : null),
      ]),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final settings = widget.controller.settings;
          final source = settings.playbackSource;
          final custom = source == (_isPiped ? PlaybackSource.pipedCustom : PlaybackSource.invidiousCustom) ? (_isPiped ? settings.pipedServer : settings.invidiousServer) : null;
          final auto = source == (_isPiped ? PlaybackSource.pipedAuto : PlaybackSource.invidiousAuto);
          final servers = _sorted();
          Widget option({required bool selected, required String title, String? subtitle, Widget? trailing, required VoidCallback onTap}) => ListTile(
                leading: Icon(selected ? AppIcons.radioButton : AppIcons.circle, color: selected ? colors.primary : colors.outline),
                title: Text(title),
                subtitle: subtitle == null ? null : Text(subtitle, style: TextStyle(color: colors.outline, fontSize: 12)),
                trailing: trailing,
                onTap: onTap,
              );
          return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
            if (_busy != null) const LinearProgressIndicator() else const SizedBox(height: 4),
            option(selected: auto, title: tr('Pick the fastest server automatically'), subtitle: tr('Retest speed every 3 hours and switch to the next server on failure'), onTap: () => _choose(null)),
            if (custom != null && !servers.contains(custom))
              option(selected: true, title: Uri.parse(custom).host, subtitle: tr('Manually entered address'), onTap: () {}),
            option(
              selected: false,
              title: tr('Enter address manually…'),
              onTap: () => editRelayServer(context, widget.controller, widget.kind),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                '${_busy ?? tr('{0} in all, {1} reachable', [servers.length, servers.where((s) => _piped.timingOf(s) != null).length])}'
                '${updated == null ? '' : tr(' · list updated {0}/{1} at {2}', [updated.month, updated.day, '${updated.hour.toString().padLeft(2, '0')}:${updated.minute.toString().padLeft(2, '0')}'])}',
                style: Theme.of(context).textTheme.titleSmall!.copyWith(color: colors.primary),
              ),
            ),
            for (final server in servers)
              option(
                selected: server == custom,
                title: Uri.parse(server).host,
                subtitle: server,
                trailing: _Timing(ms: _piped.timingOf(server), tried: _piped.wasTried(server)),
                onTap: () => _choose(server),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Text(
                _isPiped
                    ? tr("The list updates daily from the official Piped docs (public-instances) and piped-instances.kavin.rocks. Speed tests only hit each server's /healthcheck; connecting doesn't guarantee playback. YouTube often blocks public servers, in which case Lumtub falls back to connecting to YouTube directly.")
                    : tr('The list is updated daily from api.invidious.io and keeps only https instances with the API enabled. Speed tests have the instance resolve a public short video; an instance counts as connectable only if it resolves. YouTube often blocks public instances, so on failure it automatically switches to direct YouTube connection.'),
                style: TextStyle(color: colors.outline, fontSize: 12, height: 1.5),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _Timing extends StatelessWidget {
  const _Timing({required this.ms, required this.tried});
  final int? ms;
  final bool tried;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (text, color) = switch (ms) {
      final ms? => ('$ms ms', ms < 300 ? Colors.green : (ms < 1000 ? Colors.orange : colors.error)),
      null when tried => (tr("Couldn't connect"), colors.error),
      null => (tr('Not tested'), colors.outline),
    };
    return Text(text, style: TextStyle(color: color, fontSize: 12, fontFeatures: const [FontFeature.tabularFigures()]));
  }
}
