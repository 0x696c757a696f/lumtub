import 'dart:io';

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
  messenger.showSnackBar(SnackBar(content: Text(tr('Casting to {0}…', [device.name]))));
  final wasPlaying = player.state.playing;
  try {
    final media = await controller.castMedia(player.state.position, device);
    await player.pause();
    await controller.cast.start(device, media, videoId: controller.playing?.id);
    messenger.hideCurrentSnackBar();
  } on CastException catch (e) {
    if (wasPlaying) unawaited(player.play());
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(tr('Cannot cast: {0}', [e.message]))));
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

  static String? _formatName(String? format) => switch (format) {
        'ts' => 'MPEG-TS',
        'hls' => 'HLS',
        'mp4' => 'MP4',
        'mkv' => 'MKV',
        _ => null,
      };

  Future<void> _setFormat(CastDevice device, String format) async {
    final prefs = widget.controller.preferences;
    final formats = {...prefs.castFormats}..remove(device.id);
    if (format.isNotEmpty) formats[device.id] = format;
    await widget.controller.savePreferences(prefs.copyWith(castFormats: formats));
    if (mounted) setState(() {});
  }

  void _pick(CastDevice device) {
    Navigator.of(context).pop();
    unawaited(castTo(widget.controller, device, widget.messenger));
  }

  @override
  Widget build(BuildContext context) {
    final cast = widget.controller.cast;
    return AlertDialog(
      title: Text(tr('Cast')),
      content: SizedBox(
        width: 380,
        child: ListenableBuilder(
          listenable: cast,
          builder: (context, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (cast.device case final current?)
              ListTile(
                leading: const Icon(AppIcons.airplay),
                title: Text(tr('Casting to {0}', [current.name])),
                trailing: TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    unawaited(stopCasting(widget.controller));
                  },
                  child: Text(tr('Stop casting')),
                ),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Cast quality')),
              subtitle: Text(widget.controller.preferences.castMaxHeight > 1080 ? tr('Above 1080p the picture is VP9 or AV1 at up to 60 fps, which needs a newer TV or Chromecast') : tr('1080p H.264, which nearly every TV plays')),
              trailing: DropdownButton<int>(
                value: widget.controller.preferences.castMaxHeight,
                underline: const SizedBox.shrink(),
                items: [
                  DropdownMenuItem(value: 1080, child: Text(tr('Auto (1080p)'))),
                  const DropdownMenuItem(value: 2160, child: Text('4K')),
                  const DropdownMenuItem(value: 4320, child: Text('8K')),
                ],
                onChanged: (height) async {
                  if (height == null) return;
                  await widget.controller.savePreferences(widget.controller.preferences.copyWith(castMaxHeight: height));
                  if (mounted) setState(() {});
                },
              ),
            ),
            if (_searching) ...[
              const LinearProgressIndicator(),
              Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(tr('Searching for devices…'), style: TextStyle(color: context.colors.onSurfaceVariant))),
            ] else if (_devices.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(Platform.isWindows ? tr('No devices found. Make sure the TV and this computer are on the same network, casting (DLNA or Chromecast) is turned on, and this app is allowed through the Windows firewall.') : tr('No devices found. Make sure the TV and this computer are on the same network, casting (DLNA or Chromecast) is on on the TV, and Lumtub may use the local network.'), style: TextStyle(color: context.colors.onSurfaceVariant, height: 1.5)),
              ),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final device in _devices)
                  ListTile(
                    leading: Icon(device.protocol == CastProtocol.chromecast ? AppIcons.screencast : AppIcons.television),
                    title: Text(device.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text([device.protocol == CastProtocol.chromecast ? 'Chromecast' : 'DLNA', if (_formatName(widget.controller.preferences.castFormats[device.id]) case final format?) format].join(' · ')),
                    onTap: () => _pick(device),
                    trailing: PopupMenuButton<String>(
                      tooltip: tr('Cast format'),
                      icon: const Icon(AppIcons.dotsThreeVertical),
                      onSelected: (format) => _setFormat(device, format),
                      itemBuilder: (context) => [
                        for (final format in const ['', 'ts', 'hls', 'mp4', 'mkv'])
                          CheckedPopupMenuItem(value: format, checked: (widget.controller.preferences.castFormats[device.id] ?? '') == format, child: Text(_formatName(format) ?? tr('Auto'))),
                      ],
                    ),
                  ),
              ]),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _searching ? null : _startSearch, child: Text(tr('Refresh'))),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Close'))),
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
                    child: Text(tr('Casting to {0}', [device.name]), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(color: colors.onSecondaryContainer)),
                  ),
                  IconButton(
                    tooltip: playing ? tr('Pause') : tr('Play'),
                    icon: Icon(playing ? AppIcons.pauseFill : AppIcons.playFill),
                    onPressed: () => unawaited(cast.togglePlay()),
                  ),
                  TextButton.icon(onPressed: () => unawaited(stopCasting(widget.controller)), icon: const Icon(AppIcons.screencast, size: 18), label: Text(tr('Stop casting'))),
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
                if (cast.error case final error?) Text(tr('Cannot cast: {0}', [error]), style: TextStyle(color: colors.error, fontSize: 12)),
              ]),
            ),
          ),
        );
      },
    );
  }
}
