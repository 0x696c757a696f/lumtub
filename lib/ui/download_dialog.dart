
import 'package:material_ui/material_ui.dart';

import '../downloads/download_formats.dart';
import '../downloads/download_models.dart';
import '../downloads/download_selection.dart';
import '../downloads/download_subtitles.dart';
import '../l10n/l10n.dart';
import '../models.dart';
import '../translation.dart';
import '../video_codec.dart';
import 'app_icons.dart';
import 'common.dart';
import 'theme.dart';

/// What the download dialog returns: the formats picked, or just a simple
/// [quality] when the formats could not be read.
class DownloadChoice {
  const DownloadChoice(this.quality, {this.selection, this.defaults});
  /// For a [selection], only whether it is audio.
  final DownloadQuality quality;
  final DownloadSelection? selection;
  /// The options to offer next time.
  final DownloadDefaults? defaults;
}

/// Lets the user pick the codec, height and container of a download from the
/// formats the video really has.
class DownloadDialog extends StatefulWidget {
  const DownloadDialog({
    super.key,
    required this.title,
    required this.loadFormats,
    this.loadSubtitles,
    this.subtitleLanguages = const [],
    this.defaults = const DownloadDefaults(),
    this.onCover,
    this.onSubtitles,
  });
  final String title;
  final Future<DownloadFormats> Function() loadFormats;
  /// The subtitles that can go inside the video; null offers none.
  final Future<SubtitleChoices> Function()? loadSubtitles;
  /// The languages picked first: 第一字幕语言, then the second subtitle's.
  final List<TranslationLanguage> subtitleLanguages;
  final DownloadDefaults defaults;
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

  /// The video's subtitles, null while they are read or when they cannot be.
  SubtitleChoices? _subtitles;
  bool _subtitlesFailed = false;
  /// Every subtitle offered: the video's own, then translations.
  final List<SubtitleOption> _offered = [];
  final Set<SubtitlePick> _tracks = {};
  bool _bilingual = false;
  SubtitlePick? _top;
  SubtitlePick? _bottom;
  bool _srt = false;

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
    widget.loadSubtitles?.call().then((choices) {
      if (mounted) setState(() => _applySubtitles(choices));
    }).catchError((Object _) {
      if (mounted) setState(() => _subtitlesFailed = true);
    });
  }

  /// Offers [choices], with the picks remembered from last time in the
  /// languages they were in, else 第一字幕语言.
  void _applySubtitles(SubtitleChoices choices) {
    _subtitles = choices;
    _offered.addAll(choices.own);
    for (final target in widget.subtitleLanguages) {
      if (choices.own.any((o) => SubtitleChoices.targetOf(o.language) == target)) continue;
      final translation = choices.translation(target);
      if (translation != null) _offer(translation);
    }
    SubtitlePick? find(String language) {
      final option = choices.inLanguage(language);
      if (option == null) return null;
      _offer(option);
      return SubtitlePick.of(option);
    }

    final remembered = widget.defaults.subtitles;
    if (remembered != null) {
      for (final pick in remembered.tracks) {
        final found = find(pick.language);
        if (found != null) _tracks.add(found);
      }
      _srt = remembered.srt;
      if (remembered.bilingual) {
        _top = find(remembered.top!.language);
        _bottom = find(remembered.bottom!.language);
        _bilingual = _top != null && _bottom != null && _top != _bottom;
      }
    } else if (widget.subtitleLanguages.isNotEmpty) {
      final first = find(widget.subtitleLanguages.first.youtube);
      if (first != null) _tracks.add(first);
    }
    // 第一字幕语言 over the language spoken.
    if (widget.subtitleLanguages.isNotEmpty) _top ??= find(widget.subtitleLanguages.first.youtube);
    _top ??= _offered.isEmpty ? null : SubtitlePick.of(_offered.first);
    _bottom ??= _bottomFor(_top);
  }

  /// A line under [top]: the video's own language, else the second
  /// subtitle language, else anything else.
  SubtitlePick? _bottomFor(SubtitlePick? top) {
    final original = _subtitles?.original;
    final candidates = [
      if (original != null) SubtitlePick.of(original),
      for (final target in widget.subtitleLanguages.skip(1))
        if (_offered.where((o) => SubtitleChoices.targetOf(o.language) == target).firstOrNull case final o?) SubtitlePick.of(o),
      for (final o in _offered) SubtitlePick.of(o),
    ];
    return candidates.where((p) => p != top && (top == null || SubtitleChoices.targetOf(p.language) != SubtitleChoices.targetOf(top.language) || SubtitleChoices.targetOf(p.language) == null)).firstOrNull ??
        candidates.where((p) => p != top).firstOrNull;
  }

  void _offer(SubtitleOption option) {
    if (!_offered.any((o) => o.language == option.language && o.kind == option.kind)) _offered.add(option);
  }

  /// What goes inside the file, null when nothing was offered.
  DownloadSubtitles? get _pickedSubtitles => _subtitles == null || _offered.isEmpty
      ? null
      : DownloadSubtitles(tracks: [for (final o in _offered) if (_tracks.contains(SubtitlePick.of(o))) SubtitlePick.of(o)], top: _bilingual ? _top : null, bottom: _bilingual ? _bottom : null, srt: _srt);

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
        subtitles: _pickedSubtitles ?? widget.defaults.subtitles,
      );

  /// [selection] with the subtitles picked.
  DownloadSelection _withSubtitles(DownloadSelection selection) {
    final picked = _pickedSubtitles;
    return picked == null || selection.audioOnly ? selection : selection.withSubtitles(picked);
  }

  void _submit(DownloadSelection selection) => Navigator.pop(
        context,
        DownloadChoice(selection.audioOnly ? DownloadQuality.audio : DownloadQuality.best, selection: _withSubtitles(selection), defaults: _remember),
      );

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final selection = plan?.selection;
    // A phone shows it as a sheet under the player, which stays in view.
    return PanelDialog(
      title: Text(tr('Download video')),
      content: SizedBox(width: 460, child: SingleChildScrollView(child: _body(context))),
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
      // Android joins the streams in lumtub_core, which picks the container
      // from the codecs.
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
      if (!_audioOnly && widget.loadSubtitles != null) ...[
        const SizedBox(height: 12),
        _subtitleSection(context),
      ],
      const SizedBox(height: 16),
      if (plan?.selection != null) Text(_summary(_withSubtitles(plan!.selection!)), style: context.text.titleSmall),
    ]);
  }

  /// The subtitles put inside the video: tracks to switch between, a
  /// bilingual track, and the file type of the copies kept beside it.
  Widget _subtitleSection(BuildContext context) {
    final choices = _subtitles;
    if (choices == null || _offered.isEmpty) {
      final note = _subtitlesFailed ? tr("Couldn't read the subtitle list") : choices == null ? tr('Reading subtitles…') : tr('This video has no subtitles');
      return _section(context, tr('Subtitles'), [Text(note, style: context.text.bodySmall)]);
    }
    final translatable = [for (final l in TranslationLanguage.all) if (!_offered.any((o) => SubtitleChoices.targetOf(o.language) == l)) l];
    Widget pairMenu(String label, SubtitlePick? value, ValueChanged<SubtitlePick> onPicked) => Row(children: [
          SizedBox(width: 72, child: Text(label, style: context.text.bodyMedium)),
          Expanded(
            child: DropdownButton<SubtitlePick>(
              isExpanded: true,
              value: value != null && _offered.any(value.matches) ? value : null,
              items: [for (final o in _offered) DropdownMenuItem(value: SubtitlePick.of(o), child: Text(SubtitleChoices.labelOf(o), overflow: TextOverflow.ellipsis))],
              onChanged: (p) {
                if (p != null) setState(() => onPicked(p));
              },
            ),
          ),
        ]);
    final picked = _pickedSubtitles;
    final plan = _plan?.selection;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _section(context, tr('Subtitles inside the video'), [
        for (final o in _offered)
          FilterChip(
            label: Text(SubtitleChoices.labelOf(o)),
            selected: _tracks.contains(SubtitlePick.of(o)),
            onSelected: (on) => setState(() => on ? _tracks.add(SubtitlePick.of(o)) : _tracks.remove(SubtitlePick.of(o))),
          ),
        if (translatable.isNotEmpty)
          PopupMenuButton<TranslationLanguage>(
            tooltip: tr('Translate into…'),
            itemBuilder: (context) => [for (final l in translatable) PopupMenuItem(value: l, child: Text(l.label))],
            onSelected: (target) {
              final option = choices.translation(target);
              if (option == null) return;
              setState(() {
                _offer(option);
                _tracks.add(SubtitlePick.of(option));
              });
            },
            child: Chip(avatar: Icon(AppIcons.translate, size: 16), label: Text(tr('Translate into…'))),
          ),
      ]),
      const SizedBox(height: 4),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(tr('Bilingual subtitles')),
        subtitle: Text(tr('One more track with two lines: the top language over the bottom one')),
        value: _bilingual,
        onChanged: _offered.length < 2 ? null : (on) => setState(() => _bilingual = on),
      ),
      if (_bilingual) ...[
        pairMenu(tr('Top line'), _top, (p) {
          _top = p;
          if (_bottom == p) _bottom = _bottomFor(p);
        }),
        pairMenu(tr('Bottom line'), _bottom, (p) {
          _bottom = p;
          if (_top == p) _top = _bottomFor(p);
        }),
      ],
      if (picked != null && !picked.isEmpty) ...[
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(tr('Save the subtitle files beside the video as SRT')),
          value: _srt,
          onChanged: (on) => setState(() => _srt = on ?? false),
        ),
        if (plan?.container == DownloadContainer.webm) Text(tr('WebM cannot hold subtitles, so the video is saved as MKV'), style: context.text.bodySmall),
      ],
    ]);
  }

  /// The summary of the selection, such as
  /// `当前选择: VP9 · 1080p · 自动封装（WebM） · 约 850 MB`.
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
