import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../piped_streams.dart';
import '../../relay_servers.dart';
import '../theme.dart';
import 'settings_sections.dart';
import '../../l10n/l10n.dart';

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
    if (!_piped.catalog.any(_piped.wasTried)) unawaited(_run(tr('正在测速…'), _piped.servers));
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

  Future<void> _update() => _run(tr('正在更新列表并测速…'), () async {
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
      appBar: AppBar(title: Text(_isPiped ? tr('Piped 服务器') : tr('Invidious 实例')), actions: [
        IconButton(tooltip: tr('测速'), icon: const Icon(Icons.speed_rounded), onPressed: _busy == null ? () => _run(tr('正在测速…'), _piped.remeasure) : null),
        IconButton(tooltip: tr('更新列表'), icon: const Icon(Icons.refresh_rounded), onPressed: _busy == null ? _update : null),
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
                leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: selected ? colors.primary : colors.outline),
                title: Text(title),
                subtitle: subtitle == null ? null : Text(subtitle, style: TextStyle(color: colors.outline, fontSize: 12)),
                trailing: trailing,
                onTap: onTap,
              );
          return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
            if (_busy != null) const LinearProgressIndicator() else const SizedBox(height: 4),
            option(selected: auto, title: tr('自动选择最快的服务器'), subtitle: tr('每 3 小时重新测速，失败时换下一个'), onTap: () => _choose(null)),
            if (custom != null && !servers.contains(custom))
              option(selected: true, title: Uri.parse(custom).host, subtitle: tr('手动填写的地址'), onTap: () {}),
            option(
              selected: false,
              title: tr('手动填写地址…'),
              onTap: () => editRelayServer(context, widget.controller, widget.kind),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Text(
                '${_busy ?? '共 ${servers.length} 个，${servers.where((s) => _piped.timingOf(s) != null).length} 个可连接'}'
                '${updated == null ? '' : ' · 列表更新于 ${updated.month}月${updated.day}日 ${updated.hour.toString().padLeft(2, '0')}:${updated.minute.toString().padLeft(2, '0')}'}',
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
                    ? tr('列表每天从 Piped 官方文档（public-instances）和 piped-instances.kavin.rocks 自动更新。测速只访问各服务器的 /healthcheck；能连接不代表能播放，YouTube 经常拦截公共服务器，这时会自动改为直接连接 YouTube。')
                    : tr('列表每天从 api.invidious.io 自动更新，只保留开启了 API 的 https 实例。测速会让实例解析一个公开的短视频，能解析才算可连接；YouTube 常拦截公共实例，失败时会自动改为直接连接 YouTube。'),
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
      null when tried => (tr('无法连接'), colors.error),
      null => (tr('未测速'), colors.outline),
    };
    return Text(text, style: TextStyle(color: color, fontSize: 13, fontFeatures: const [FontFeature.tabularFigures()]));
  }
}
