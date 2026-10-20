import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../piped_streams.dart';
import '../theme.dart';
import 'settings_sections.dart';

/// 设置 › Piped 服务器: choose automatic selection or one server, measure
/// them all, and download the public list again.
Future<void> openPipedServers(BuildContext context, AppController controller) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (context) => _PipedServersPage(controller: controller)));

class _PipedServersPage extends StatefulWidget {
  const _PipedServersPage({required this.controller});
  final AppController controller;

  @override
  State<_PipedServersPage> createState() => _PipedServersPageState();
}

class _PipedServersPageState extends State<_PipedServersPage> {
  PipedStreams get _piped => widget.controller.piped;
  String? _busy;

  @override
  void initState() {
    super.initState();
    if (!_piped.catalog.any(_piped.wasTried)) unawaited(_run('正在测速…', _piped.servers));
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

  Future<void> _update() => _run('正在更新列表并测速…', () async {
        await _piped.updateCatalog();
        await _piped.remeasure();
      });

  Future<void> _choose(String? server) {
    final settings = widget.controller.settings;
    return widget.controller.saveSettings(server == null
        ? settings.copyWith(playbackSource: PlaybackSource.pipedAuto)
        : settings.copyWith(playbackSource: PlaybackSource.pipedCustom, pipedServer: server));
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
      appBar: AppBar(title: const Text('Piped 服务器'), actions: [
        IconButton(tooltip: '测速', icon: const Icon(Icons.speed_rounded), onPressed: _busy == null ? () => _run('正在测速…', _piped.remeasure) : null),
        IconButton(tooltip: '更新列表', icon: const Icon(Icons.refresh_rounded), onPressed: _busy == null ? _update : null),
      ]),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final settings = widget.controller.settings;
          final custom = settings.playbackSource == PlaybackSource.pipedCustom ? settings.pipedServer : null;
          final auto = settings.playbackSource == PlaybackSource.pipedAuto;
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
            option(selected: auto, title: '自动选择最快的服务器', subtitle: '每 3 小时重新测速，失败时换下一个', onTap: () => _choose(null)),
            if (custom != null && !servers.contains(custom))
              option(selected: true, title: Uri.parse(custom).host, subtitle: '手动填写的地址', onTap: () {}),
            option(
              selected: false,
              title: '手动填写地址…',
              onTap: () => editPipedServer(context, widget.controller),
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
                '列表每天从 Piped 官方文档（public-instances）和 piped-instances.kavin.rocks 自动更新。测速只访问各服务器的 /healthcheck；'
                '能连接不代表能播放，YouTube 经常拦截公共服务器，这时会自动改为直接连接 YouTube。',
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
      null when tried => ('无法连接', colors.error),
      null => ('未测速', colors.outline),
    };
    return Text(text, style: TextStyle(color: color, fontSize: 13, fontFeatures: const [FontFeature.tabularFigures()]));
  }
}
