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
      if (formats.video.isEmpty && formats.audio.isEmpty) throw StateError(tr('No downloadable formats found'));
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
      _containerNote = tr('{0}: {1}; switched to automatic container', [_container.label, plan.problem]);
      _container = DownloadContainer.auto;
    }
  }

  List<int> get _heights => _formats!.heightsFor(_codec);

  /// The most frames a second at [height] in the chosen codec.
  double? _fps(int height) => _formats!.video
      .where((f) => f.height == height && (_codec == null || f.codec == _codec))
      .fold<double?>(null, (most, f) => f.fps == null || (most != null && most >= f.fps!) ? most : f.fps);

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
      title: Text(tr('Download video')),
      content: SizedBox(width: 460, child: SingleChildScrollView(child: _body(context))),
      actionsOverflowButtonSpacing: 4,
      actions: [
        if (widget.onCover != null)
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              widget.onCover!();
            },
            icon: Icon(AppIcons.image, size: 18),
            label: Text(tr('Download cover')),
          ),
        if (widget.onSubtitles != null)
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              widget.onSubtitles!();
            },
            icon: Icon(AppIcons.subtitles, size: 18),
            label: Text(tr('Download subtitles')),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
        if (_formats != null) FilledButton(onPressed: selection == null ? null : () => _submit(selection), child: Text(tr('Start download'))),
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
          Expanded(child: Text(tr('Reading video formats…'))),
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
      _section(context, tr('Video codec'), [
        if (formats.video.isNotEmpty) _chip(tr('Auto (best available format)'), selected: _codecChosen && !_audioOnly && _codec == null, onTap: () => _pickCodec(null)),
        for (final c in formats.codecs) _chip(c.label, selected: _codecChosen && !_audioOnly && _codec == c, onTap: () => _pickCodec(c)),
        if (audio.isNotEmpty) _chip(tr('Audio only'), selected: _audioOnly, onTap: () => _pickCodec(null, audioOnly: true)),
      ]),
      if (_missing != null && !_codecChosen)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(tr('This video has no {0} format; choose another codec', [_missing!.label]), style: TextStyle(color: context.colors.error)),
        ),
      if (heights.isNotEmpty) ...[
        const SizedBox(height: 12),
        _section(context, tr('Video quality'), [
          for (final h in heights)
            _chip(heightLabel(h, _fps(h)), selected: h == video?.height, onTap: () => setState(() {
                  _wantedHeight = h;
                  _containerNote = null;
                  _checkContainer();
                })),
        ]),
      ],
      if (video != null) ...[
        const SizedBox(height: 12),
        _section(context, tr('Container'), [
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
              child: Text(tr('{0}: {1}', [c.label, planContainer(c, video.codec, audio).problem]), style: context.text.bodySmall),
            ),
        if (_containerNote != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_containerNote!, style: context.text.bodySmall)),
      ],
      const SizedBox(height: 16),
      if (plan?.selection != null) Text(_summary(plan!.selection!), style: context.text.titleSmall),
      if (!widget.canMerge && !_audioOnly) ...[
        const SizedBox(height: 8),
        Text(tr('Without ffmpeg, video and audio cannot be merged, so videos download as the single-file format YouTube provides (usually 360p). You can install ffmpeg on demand the first time you pick a high quality.'), style: context.text.bodySmall),
      ],
    ]);
  }

  /// 当前选择: `VP9 · 1080p · 自动封装（WebM） · 约 850 MB`.
  String _summary(DownloadSelection s) {
    final parts = s.audioOnly
        ? [tr('Audio only')]
        : [
            s.codec!.label,
            heightLabel(s.height!, _formats?.video.where((f) => f.id == s.videoId).firstOrNull?.fps),
            _container == DownloadContainer.auto ? tr('Automatic container ({0})', [s.container.label]) : s.container.label,
          ];
    if (s.size != null) parts.add(approximateSize(s.size!));
    return tr('Current selection: {0}', [parts.join(' · ')]);
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
        Text(tr('Could not read video formats: {0}', ['$_error'.replaceFirst('Bad state: ', '')]), maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.colors.error)),
        const SizedBox(height: 8),
        Text(tr('You can download with the simple options instead.'), style: context.text.bodySmall),
        const SizedBox(height: 8),
        for (final q in DownloadQuality.values)
          ListTile(dense: true, title: Text(q.label), onTap: () => Navigator.pop(context, DownloadChoice(q))),
      ]);
}
