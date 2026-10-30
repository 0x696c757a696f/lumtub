import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../cast/cast_device.dart';
import '../cast/cast_discovery.dart';
import '../l10n/l10n.dart';
import 'common.dart';
import 'theme.dart';
import 'app_icons.dart';

/// Lists the TVs and Chromecasts on the network and casts the playing video
/// to the one picked.
Future<void> showCastDialog(BuildContext context, AppController controller) =>
    showDialog<void>(context: context, builder: (_) => _CastDialog(controller: controller, messenger: ScaffoldMessenger.of(context)));

/// Pauses the local player, hands the video to [device] at the current
/// position and tells what went wrong in a short message.
Future<void> castTo(AppController controller, CastDevice device, ScaffoldMessengerState messenger) async {
  final player = controller.player;
  if (player == null) return;
  messenger.showSnackBar(SnackBar(content: Text(tr('正在投屏到 {0}…', [device.name]))));
  final wasPlaying = player.state.playing;
  try {
    final media = await controller.castMedia(player.state.position);
    await player.pause();
    await controller.cast.start(device, media, videoId: controller.playing?.id);
    messenger.hideCurrentSnackBar();
  } on CastException catch (e) {
    if (wasPlaying) unawaited(player.play());
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(tr('无法投屏：{0}', [e.message]))));
  }
}

/// Ends casting; the local player waits where the device stopped.
Future<void> stopCasting(AppController controller) async {
  final at = await controller.cast.stop();
  if (at != null) await controller.player?.seek(at);
}

class _CastDialog extends StatefulWidget {
  const _CastDialog({required this.controller, required this.messenger});
  final AppController controller;
  final ScaffoldMessengerState messenger;

  @override
  State<_CastDialog> createState() => _CastDialogState();
}

class _CastDialogState extends State<_CastDialog> {
  final _devices = <CastDevice>[];
  StreamSubscription<CastDevice>? _search;
  var _searching = false;

  @override
  void initState() {
    super.initState();
    _startSearch();
  }

  @override
  void dispose() {
    unawaited(_search?.cancel());
    super.dispose();
  }

  void _startSearch() {
    unawaited(_search?.cancel());
    setState(() {
      _devices.clear();
      _searching = true;
    });
    _search = discoverCastDevices().listen(
      (device) {
        if (mounted) setState(() => _devices.add(device));
      },
      onDone: () {
        if (mounted) setState(() => _searching = false);
      },
    );
  }

  void _pick(CastDevice device) {
    Navigator.of(context).pop();
    unawaited(castTo(widget.controller, device, widget.messenger));
  }

  @override
  Widget build(BuildContext context) {
    final cast = widget.controller.cast;
    return AlertDialog(
      title: Text(tr('投屏')),
      content: SizedBox(
        width: 380,
        child: ListenableBuilder(
          listenable: cast,
          builder: (context, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (cast.device case final current?)
              ListTile(
                leading: const Icon(AppIcons.airplay),
                title: Text(tr('正在投屏到 {0}', [current.name])),
                trailing: TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    unawaited(stopCasting(widget.controller));
                  },
                  child: Text(tr('停止投屏')),
                ),
              ),
            if (_searching) ...[
              const LinearProgressIndicator(),
              Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(tr('正在搜索设备…'), style: TextStyle(color: context.colors.onSurfaceVariant))),
            ] else if (_devices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(tr('没有找到设备。请确认电视和电脑在同一个局域网，电视已开启投屏（DLNA 或 Chromecast），并允许本程序通过 Windows 防火墙。'), style: TextStyle(color: context.colors.onSurfaceVariant, height: 1.5)),
              ),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final device in _devices)
                  ListTile(
                    leading: Icon(device.protocol == CastProtocol.chromecast ? AppIcons.screencast : AppIcons.television),
                    title: Text(device.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(device.protocol == CastProtocol.chromecast ? 'Chromecast' : 'DLNA'),
                    onTap: () => _pick(device),
                  ),
              ]),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _searching ? null : _startSearch, child: Text(tr('刷新'))),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('关闭'))),
      ],
    );
  }
}

/// The small bar shown while casting: device, title, play or pause, a seek
/// slider and 停止投屏. Empty when nothing is cast.
class CastBar extends StatefulWidget {
  const CastBar({super.key, required this.controller});
  final AppController controller;

  @override
  State<CastBar> createState() => _CastBarState();
}

class _CastBarState extends State<CastBar> {
  /// The slider value while it is dragged, in seconds.
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final cast = widget.controller.cast;
    return ListenableBuilder(
      listenable: cast,
      builder: (context, _) {
        final device = cast.device;
        if (device == null) return const SizedBox.shrink();
        final status = cast.status;
        final duration = status?.duration ?? Duration.zero;
        final max = duration.inMilliseconds / 1000;
        final seconds = (_drag ?? (status?.position.inMilliseconds ?? 0) / 1000).clamp(0.0, max > 0 ? max : 1.0);
        final playing = status?.state == CastState.playing;
        final colors = context.colors;
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Material(
            color: colors.secondaryContainer,
            borderRadius: AppStyle.cardRadius,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(AppIcons.airplay, size: 20, color: colors.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(tr('正在投屏到 {0}', [device.name]), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(color: colors.onSecondaryContainer)),
                  ),
                  IconButton(
                    tooltip: playing ? tr('暂停') : tr('播放'),
                    icon: Icon(playing ? AppIcons.pauseFill : AppIcons.playFill),
                    onPressed: () => unawaited(cast.togglePlay()),
                  ),
                  TextButton.icon(onPressed: () => unawaited(stopCasting(widget.controller)), icon: const Icon(AppIcons.screencast, size: 18), label: Text(tr('停止投屏'))),
                ]),
                Row(children: [
                  Text(formatPlaybackTime(Duration(milliseconds: (seconds * 1000).round())), style: context.text.labelMedium),
                  Expanded(
                    child: Slider(
                      value: seconds.toDouble(),
                      max: max > 0 ? max : 1.0,
                      onChanged: max > 0 ? (v) => setState(() => _drag = v) : null,
                      onChangeEnd: (v) {
                        setState(() => _drag = null);
                        unawaited(cast.seek(Duration(milliseconds: (v * 1000).round())));
                      },
                    ),
                  ),
                  Text(formatPlaybackTime(duration), style: context.text.labelMedium),
                ]),
                if (cast.error case final error?) Text(tr('无法投屏：{0}', [error]), style: TextStyle(color: colors.error, fontSize: 12)),
              ]),
            ),
          ),
        );
      },
    );
  }
}
