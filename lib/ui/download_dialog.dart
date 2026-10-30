import 'package:flutter/material.dart';

import '../downloads/download_formats.dart';
import '../downloads/download_models.dart';
import '../downloads/download_selection.dart';
import '../l10n/l10n.dart';
import '../video_codec.dart';
import 'theme.dart';
import 'app_icons.dart';

/// What the download dialog returns: the formats picked, or just a simple
/// [quality] when the formats could not be read.
class DownloadChoice {
  const DownloadChoice(this.quality, {this.selection, this.defaults});
  /// For a [selection], only whether it is audio (what ffmpeg is needed for).
  final DownloadQuality quality;
  final DownloadSelection? selection;
  /// The options to offer next time.
  final DownloadDefaults? defaults;
}

/// Lets the user pick the codec, height and container of a download from the
/// formats the video really has.
class DownloadDialog extends StatefulWidget {
  const DownloadDialog({super.key, required this.title, required this.loadFormats, this.defaults = const DownloadDefaults(), this.canMerge = true, this.onCover, this.onSubtitles});
  final String title;
  final Future<DownloadFormats> Function() loadFormats;
  final DownloadDefaults defaults;
  /// Whether ffmpeg is there; without it the video comes as a single file.
  final bool canMerge;
  /// Saves just the cover or a subtitle instead; the dialog closes first.
  final VoidCallback? onCover;
  final VoidCallback? onSubtitles;

  @override
  State<DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<DownloadDialog> {
  DownloadFormats? _formats;
  Object? _error;

  /// The codec chosen: null is auto. [_codecChosen] is false while a
  /// remembered codec is missing from the video and nothing was picked yet.
  VideoCodec? _codec;
  bool _audioOnly = false;
  bool _codecChosen = true;
  VideoCodec? _missing;
  int? _wantedHeight;
  DownloadContainer _container = DownloadContainer.auto;
  String? _containerNote;

  @override
  void initState() {
    super.initState();
    widget.loadFormats().then((formats) {
      if (!mounted) return;
      if (formats.video.isEmpty && formats.audio.isEmpty) throw StateError(tr('没有找到可下载的格式'));
      setState(() {
        _formats = formats;
        _applyDefaults(formats);
      });
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e);
    });
  }

  void _applyDefaults(DownloadFormats formats) {
    final d = widget.defaults;
    _wantedHeight = d.height;
    _container = d.container;
    if (d.codec == DownloadDefaults.audioOnly && formats.audio.isNotEmpty) {
      _audioOnly = true;
    } else if (d.videoCodec != null) {
      if (formats.codecs.contains(d.videoCodec)) {
        _codec = d.videoCodec;
      } else {
        _missing = d.videoCodec;
        _codecChosen = false;
      }
    }
    _checkContainer();
  }

  /// Back to automatic when the container cannot hold the picked streams.
  void _checkContainer() {
    final formats = _formats;
    if (formats == null || _audioOnly || !_codecChosen || _container == DownloadContainer.auto) return;
    final plan = planDownload(formats, codec: _codec, height: _wantedHeight, container: _container);
    if (plan.problem != null) {
      _containerNote = tr('{0}：{1}，已改为自动封装', [_container.label, plan.problem]);
      _container = DownloadContainer.auto;
    }
  }

  List<int> get _heights => _formats!.heightsFor(_codec);

  DownloadPlan? get _plan {
    final formats = _formats;
    if (formats == null || !_codecChosen) return null;
    return planDownload(formats, codec: _codec, height: _wantedHeight, container: _container, audioOnly: _audioOnly);
  }

  void _pickCodec(VideoCodec? codec, {bool audioOnly = false}) => setState(() {
        _codec = codec;
        _audioOnly = audioOnly;
        _codecChosen = true;
        _containerNote = null;
        _checkContainer();
      });

  /// What to remember; the height only when it was picked, not just the top.
  DownloadDefaults get _remember => DownloadDefaults(
        codec: _audioOnly ? DownloadDefaults.audioOnly : _codec?.name ?? DownloadDefaults.auto,
        height: _wantedHeight,
        container: _container,
      );

  void _submit(DownloadSelection selection) => Navigator.pop(
        context,
        DownloadChoice(selection.audioOnly ? DownloadQuality.audio : DownloadQuality.best, selection: selection, defaults: _remember),
      );

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final selection = plan?.selection;
    return AlertDialog(
      title: Text(tr('下载视频')),
      content: SizedBox(width: 460, child: SingleChildScrollView(child: _body(context))),
      actionsOverflowButtonSpacing: 4,
      actions: [
        if (widget.onCover != null)
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              widget.onCover!();
            },
            icon: const Icon(AppIcons.image, size: 18),
            label: Text(tr('下载封面')),
          ),
        if (widget.onSubtitles != null)
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              widget.onSubtitles!();
            },
            icon: const Icon(AppIcons.subtitles, size: 18),
            label: Text(tr('下载字幕')),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('取消'))),
        if (_formats != null) FilledButton(onPressed: selection == null ? null : () => _submit(selection), child: Text(tr('开始下载'))),
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (_error != null) return _fallback(context);
    final formats = _formats;
    if (formats == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Row(children: [
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 16),
          Expanded(child: Text(tr('正在读取视频格式…'))),
        ]),
      );
    }
    final plan = _plan;
    final heights = _audioOnly || !_codecChosen ? const <int>[] : _heights;
    final video = _codecChosen && !_audioOnly ? formats.pickVideo(_codec, height: _wantedHeight) : null;
    final audio = formats.audioBest;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
      const SizedBox(height: 12),
      _section(context, tr('视频编码'), [
        if (formats.video.isNotEmpty) _chip(tr('自动（最佳可用格式）'), selected: _codecChosen && !_audioOnly && _codec == null, onTap: () => _pickCodec(null)),
        for (final c in formats.codecs) _chip(c.label, selected: _codecChosen && !_audioOnly && _codec == c, onTap: () => _pickCodec(c)),
        if (audio.isNotEmpty) _chip(tr('仅音频'), selected: _audioOnly, onTap: () => _pickCodec(null, audioOnly: true)),
      ]),
      if (_missing != null && !_codecChosen)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(tr('该视频没有 {0} 格式，请选择其他编码', [_missing!.label]), style: TextStyle(color: context.colors.error)),
        ),
      if (heights.isNotEmpty) ...[
        const SizedBox(height: 12),
        _section(context, tr('视频画质'), [
          for (final h in heights)
            _chip('${h}p', selected: h == video?.height, onTap: () => setState(() {
                  _wantedHeight = h;
                  _containerNote = null;
                  _checkContainer();
                })),
        ]),
      ],
      if (video != null) ...[
        const SizedBox(height: 12),
        _section(context, tr('文件封装格式'), [
          for (final c in DownloadContainer.values)
            () {
              final problem = c == DownloadContainer.auto ? null : planContainer(c, video.codec, audio).problem;
              return _chip(c.label, selected: _container == c, tooltip: problem, onTap: problem == null ? () => setState(() {
                    _container = c;
                    _containerNote = null;
                  }) : null);
            }(),
        ]),
        for (final c in DownloadContainer.values)
          if (c != DownloadContainer.auto && planContainer(c, video.codec, audio).problem != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${c.label}：${planContainer(c, video.codec, audio).problem}', style: context.text.bodySmall),
            ),
        if (_containerNote != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_containerNote!, style: context.text.bodySmall)),
      ],
      const SizedBox(height: 16),
      if (plan?.selection != null) Text(_summary(plan!.selection!), style: context.text.titleSmall),
      if (!widget.canMerge && !_audioOnly) ...[
        const SizedBox(height: 8),
        Text(tr('没有 ffmpeg 时无法合并画面和声音，视频会下载为 YouTube 提供的单文件格式（通常为 360p）。首次选择高画质时可以按需安装 ffmpeg。'), style: context.text.bodySmall),
      ],
    ]);
  }

  /// 当前选择: `VP9 · 1080p · 自动封装（WebM） · 约 850 MB`.
  String _summary(DownloadSelection s) {
    final parts = s.audioOnly
        ? [tr('仅音频')]
        : [
            s.codec!.label,
            '${s.height}p',
            _container == DownloadContainer.auto ? tr('自动封装（{0}）', [s.container.label]) : s.container.label,
          ];
    if (s.size != null) parts.add(approximateSize(s.size!));
    return tr('当前选择：{0}', [parts.join(' · ')]);
  }

  Widget _section(BuildContext context, String title, List<Widget> chips) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: context.text.labelLarge),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 6, children: chips),
      ]);

  Widget _chip(String label, {required bool selected, VoidCallback? onTap, String? tooltip}) {
    final chip = ChoiceChip(label: Text(label), selected: selected, onSelected: onTap == null ? null : (_) => onTap());
    return tooltip == null ? chip : Tooltip(message: tooltip, child: chip);
  }

  /// The formats could not be read: say why, and offer the simple choices.
  Widget _fallback(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(tr('无法读取视频格式：{0}', ['$_error'.replaceFirst('Bad state: ', '')]), maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.colors.error)),
        const SizedBox(height: 8),
        Text(tr('可以改用简单选项下载。'), style: context.text.bodySmall),
        const SizedBox(height: 8),
        for (final q in DownloadQuality.values)
          ListTile(dense: true, title: Text(q.label), onTap: () => Navigator.pop(context, DownloadChoice(q))),
      ]);
}
