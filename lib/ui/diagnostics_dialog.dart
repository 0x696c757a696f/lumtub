import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../app_log.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';
import 'theme.dart';

/// 网络诊断 and the playback test: how each kind of request reaches
/// YouTube, what the playing video is decoded with, and how H.264, VP9 and
/// AV1 play on this computer.
Future<void> showDiagnostics(BuildContext context, AppController controller, {bool playback = false}) =>
    showDialog<void>(context: context, builder: (_) => _DiagnosticsDialog(controller: controller, playback: playback));

class _DiagnosticsDialog extends StatefulWidget {
  const _DiagnosticsDialog({required this.controller, required this.playback});
  final AppController controller;
  final bool playback;

  @override
  State<_DiagnosticsDialog> createState() => _DiagnosticsDialogState();
}

class _DiagnosticsDialogState extends State<_DiagnosticsDialog> {
  List<NetworkCheck> _checks = const [];
  var _checking = false;
  Map<String, String> _now = const {};
  List<PlaybackSample> _samples = const [];
  String? _testing;

  @override
  void initState() {
    super.initState();
    unawaited(_readNow());
    if (!widget.playback) unawaited(_check());
  }

  Future<void> _readNow() async {
    final now = await widget.controller.playbackNow();
    if (mounted) setState(() => _now = now);
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _checks = const [];
    });
    try {
      await widget.controller.runNetworkCheck((sofar) {
        if (mounted) setState(() => _checks = sofar);
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _test() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Playback test')),
        content: Text(tr('The video playing now stops. A test video then plays muted as H.264, VP9 and AV1 for about 20 seconds each, kept out of your history.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Start'))),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() {
      _samples = const [];
      _testing = '';
    });
    try {
      final samples = await widget.controller.runPlaybackTest((codec) {
        if (mounted) setState(() => _testing = codec.label);
      });
      if (mounted) setState(() => _samples = samples);
    } finally {
      if (mounted) setState(() => _testing = null);
    }
  }

  String get _report {
    final lines = <String>['Lumtub $appVersion · ${Platform.operatingSystem}'];
    if (_checks.isNotEmpty) {
      lines.add('');
      lines.add(tr('Network'));
      for (final c in _checks) {
        final state = c.skipped ? '–' : c.ok ? 'OK' : tr('Failed');
        // Exit addresses are cut short in what is copied.
        final detail = c.detail.replaceAllMapped(RegExp(r'\b\d{1,3}(\.\d{1,3}){3}\b|\b[0-9a-f]{1,4}(:[0-9a-f]{0,4}){4,7}\b', caseSensitive: false), (m) => maskedAddress(m[0]!));
        lines.add('${c.name}: $state${c.ms == null ? '' : ' · ${c.ms} ms'}${c.route.isEmpty ? '' : ' · ${c.route}'}${detail.isEmpty ? '' : ' · $detail'}');
      }
    }
    if (_now.isNotEmpty) {
      lines.add('');
      lines.add(tr('Playing now'));
      _now.forEach((k, v) => lines.add('$k: $v'));
    }
    if (_samples.isNotEmpty) {
      lines.add('');
      lines.add(tr('Playback test'));
      for (final s in _samples) {
        lines.add(s.error != null ? '${s.codec.label}: ${s.error}' : '${s.codec.label}: ${s.picture} · ${s.decoder} · CPU ${s.cpuPercent?.toStringAsFixed(0) ?? '?'}% · ${s.memoryMb} MB · ${tr('{0} dropped', ['${s.dropped}'])}');
      }
    }
    return lines.join('\n');
  }

  Widget _section(String title, Widget trailing) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Row(children: [Expanded(child: Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w600))), trailing]),
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final muted = TextStyle(color: colors.onSurfaceVariant, height: 1.4);
    return AlertDialog(
      title: Text(tr('Diagnostics')),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            _section(tr('Network'), TextButton(onPressed: _checking ? null : _check, child: Text(_checking ? tr('Checking…') : tr('Check again')))),
            Text(tr('Each kind of request is tried on its own. The exit address is asked from Cloudflare; copied results hide its last part.'), style: muted),
            if (_checking && _checks.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
            for (final c in _checks)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(c.skipped ? AppIcons.minus : c.ok ? AppIcons.checkCircle : AppIcons.warningCircle, color: c.skipped ? colors.onSurfaceVariant : c.ok ? colors.primary : colors.error),
                title: Text('${c.name}${c.ms == null ? '' : '  ·  ${c.ms} ms'}'),
                subtitle: Text([if (c.route.isNotEmpty) c.route, if (c.detail.isNotEmpty) c.detail].join('\n'), style: muted),
              ),
            _section(tr('Playing now'), TextButton(onPressed: _readNow, child: Text(tr('Refresh')))),
            if (_now.isEmpty)
              Text(tr('Nothing is playing.'), style: muted)
            else
              for (final MapEntry(:key, :value) in _now.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 150, child: Text(key, style: muted)),
                    Expanded(child: SelectableText(value)),
                  ]),
                ),
            _section(tr('Playback test'), TextButton(onPressed: _testing != null ? null : _test, child: Text(_testing != null ? tr('Testing {0}…', [_testing!]) : tr('Start')))),
            Text(tr('Processor use counts Lumtub and libmpv together, as a share of one core.'), style: muted),
            if (_testing != null) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
            for (final s in _samples)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(s.error == null ? AppIcons.checkCircle : AppIcons.warningCircle, color: s.error == null ? colors.primary : colors.onSurfaceVariant),
                title: Text(s.codec.label),
                subtitle: Text(s.error ?? '${s.picture} · ${s.decoder} · CPU ${s.cpuPercent?.toStringAsFixed(0) ?? '?'}% · ${s.memoryMb} MB · ${tr('{0} dropped', ['${s.dropped}'])}', style: muted),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton.icon(
          icon: Icon(AppIcons.copy, size: 18),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: _report));
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Copied'))));
          },
          label: Text(tr('Copy results')),
        ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Close'))),
      ],
    );
  }
}
