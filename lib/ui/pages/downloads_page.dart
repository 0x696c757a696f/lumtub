import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../downloads/download_manager.dart';
import '../../downloads/download_models.dart';
import '../../downloads/download_selection.dart';
import '../../l10n/l10n.dart';
import '../../models.dart';
import '../download_dialog.dart';
import '../ffmpeg_dialog.dart';
import '../common.dart';
import '../theme.dart';
import '../app_icons.dart';

/// Asks what to download [item] as, then queues it.
Future<void> showDownloadChoice(BuildContext context, AppController controller, VideoItem item) async {
  final choice = await showDialog<DownloadChoice>(
    context: context,
    builder: (context) => DownloadDialog(
      title: item.title,
      loadFormats: () => controller.downloadFormats(item.id),
      defaults: controller.downloads?.defaults ?? const DownloadDefaults(),
      canMerge: controller.downloads?.canMerge ?? false,
      onCover: () => unawaited(_saveExtra(context, controller, () => controller.saveCover(item))),
      onSubtitles: () => unawaited(_chooseSubtitle(context, controller, item)),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice.defaults != null) unawaited(controller.downloads?.setDefaults(choice.defaults!));
  if (await ensureFfmpegForDownload(context, controller, choice.quality)) controller.download(item, choice.quality, selection: choice.selection);
}

/// Runs [save] and says where the file went, with a button to show it.
Future<void> _saveExtra(BuildContext context, AppController controller, Future<String> Function() save) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final path = await save();
    messenger?.showSnackBar(SnackBar(
      content: Text(tr('已保存：{0}', [path.split(Platform.pathSeparator).last])),
      action: Platform.isWindows ? SnackBarAction(label: tr('打开文件夹'), onPressed: () => unawaited(openInExplorer(path, select: true))) : null,
    ));
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(tr('保存失败：{0}', ['$e'.replaceFirst('Bad state: ', '')]))));
  }
}

/// Picks one of [item]'s subtitles and the file type, then saves it.
Future<void> _chooseSubtitle(BuildContext context, AppController controller, VideoItem item) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  List<SubtitleOption> options;
  try {
    options = await controller.subtitleOptionsFor(item);
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(tr('无法读取字幕列表'))));
    return;
  }
  if (!context.mounted) return;
  if (options.isEmpty) {
    messenger?.showSnackBar(SnackBar(content: Text(tr('这个视频没有字幕'))));
    return;
  }
  final picked = await showDialog<(SubtitleOption, bool)>(context: context, builder: (context) => _SubtitleSaveDialog(options: options));
  if (picked == null || !context.mounted) return;
  await _saveExtra(context, controller, () => controller.saveSubtitle(item, picked.$1, srt: picked.$2));
}

class _SubtitleSaveDialog extends StatefulWidget {
  const _SubtitleSaveDialog({required this.options});
  final List<SubtitleOption> options;

  @override
  State<_SubtitleSaveDialog> createState() => _SubtitleSaveDialogState();
}

class _SubtitleSaveDialogState extends State<_SubtitleSaveDialog> {
  late SubtitleOption _option = widget.options.first;
  bool _srt = true;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr('下载字幕')),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Flexible(
              child: SingleChildScrollView(
                child: RadioGroup<SubtitleOption>(
                  groupValue: _option,
                  onChanged: (v) => setState(() => _option = v ?? _option),
                  child: Column(children: [
                    for (final o in widget.options)
                      RadioListTile<SubtitleOption>(
                        dense: true,
                        value: o,
                        title: Text(o.kind == SubtitleKind.translated ? tr('{0}（YouTube 翻译）', [SubtitleOption.languageName(o.language, o.name)]) : o.label),
                      ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: true, label: Text('SRT')), ButtonSegment(value: false, label: Text('WebVTT'))],
              selected: {_srt},
              onSelectionChanged: (v) => setState(() => _srt = v.first),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('取消'))),
          FilledButton(onPressed: () => Navigator.pop(context, (_option, _srt)), child: Text(tr('保存'))),
        ],
      );
}

/// Shows [path] in Windows Explorer; a file is selected in its folder.
Future<void> openInExplorer(String path, {bool select = false}) async {
  if (!Platform.isWindows) return;
  await Process.start('explorer.exe', [select ? '/select,$path' : path]);
}

/// 下载: queued, running, finished and failed downloads.
class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final manager = controller.downloads;
    if (manager == null) return const SizedBox.shrink();
    // Progress ticks reach only this page, not the whole app.
    return ListenableBuilder(listenable: Listenable.merge([manager, manager.progress]), builder: (context, _) => _page(context, manager));
  }

  Widget _page(BuildContext context, DownloadManager manager) {
    final tasks = manager.tasks;
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: PageHeader(
          tr('下载'),
          subtitle: tr('{0} 个视频 · 最多同时下载 {1} 个', [tasks.length, manager.maxConcurrent]),
          trailing: Wrap(spacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () => _changeDirectory(context, manager),
              icon: const Icon(AppIcons.folderOpen),
              label: Text(tr('更改位置')),
            ),
            FilledButton.tonalIcon(
              onPressed: () => unawaited(openInExplorer(manager.directory)),
              icon: const Icon(AppIcons.arrowSquareOut),
              label: Text(tr('打开文件夹')),
            ),
          ]),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppStyle.pagePadding),
          child: Text(tr('保存位置：{0}', [manager.directory]), style: context.text.bodySmall),
        ),
      ),
      if (tasks.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: StatusView(
            icon: AppIcons.arrowCircleDown,
            title: tr('还没有下载'),
            message: tr('在视频的菜单或播放页点“下载”，视频会保存到本机，之后可以离线播放。'),
          ),
        )
      else
        SliverList.builder(
          itemCount: tasks.length,
          itemBuilder: (context, i) => _DownloadTile(controller: controller, manager: manager, task: tasks[i]),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: AppStyle.pagePadding)),
    ]);
  }

  Future<void> _changeDirectory(BuildContext context, DownloadManager manager) async {
    final selected = await getDirectoryPath(initialDirectory: manager.directory);
    if (selected != null) await manager.setDirectory(selected);
  }
}

/// "1.2 MB/s", or empty when yt-dlp gave no speed.
String formatSpeed(double? bytesPerSecond) => bytesPerSecond == null ? '' : '${formatBytes(bytesPerSecond.round())}/s';

/// "1:05" for [seconds], or empty when unknown.
String formatEta(int? seconds) => seconds == null ? '' : formatPlaybackTime(Duration(seconds: seconds));

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({required this.controller, required this.manager, required this.task});
  final AppController controller;
  final DownloadManager manager;
  final DownloadTask task;

  String _status() {
    switch (task.status) {
      case DownloadStatus.queued:
        return tr('等待中');
      case DownloadStatus.downloading:
        final parts = [
          if (task.fraction != null) '${(task.fraction! * 100).toStringAsFixed(1)}%',
          if (task.total != null) '${formatBytes(task.downloaded)} / ${formatBytes(task.total!)}',
          formatSpeed(task.speed),
          if (task.eta != null) tr('剩余 {0}', [formatEta(task.eta)]),
        ].where((s) => s.isNotEmpty);
        return parts.isEmpty ? tr('正在下载…') : parts.join(' · ');
      case DownloadStatus.paused:
        return tr('已暂停');
      case DownloadStatus.done:
        final bytes = task.filePath == null ? null : _sizes[task.filePath!] ??= _sizeOf(task.filePath!);
        final size = bytes == null ? '' : ' · ${formatBytes(bytes)}';
        return '${tr('已完成')} · ${task.qualityLabel}$size';
      case DownloadStatus.failed:
        return tr('下载失败：{0}', [task.error ?? '']);
      case DownloadStatus.cancelled:
        return tr('已取消');
    }
  }

  // The list rebuilds twice a second while a download runs; a finished
  // file keeps its size.
  static final _sizes = <String, int?>{};

  static int? _sizeOf(String path) {
    final file = File(path);
    return file.existsSync() ? file.lengthSync() : null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final item = task.item;
    final failed = task.status == DownloadStatus.failed;
    final running = task.status == DownloadStatus.downloading;
    IconButton button(IconData icon, String tooltip, VoidCallback onPressed) => IconButton(tooltip: tooltip, icon: Icon(icon), onPressed: onPressed);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppStyle.pagePadding, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 96,
          height: 54,
          child: Image.network(
            item.thumbnail,
            cacheWidth: (96 * MediaQuery.devicePixelRatioOf(context)).ceil(),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => ColoredBox(color: colors.surfaceContainerHighest),
          ),
        ),
      ),
      title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_status(), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: failed ? colors.error : null)),
        if (running || task.status == DownloadStatus.paused)
          Padding(padding: const EdgeInsets.only(top: 4), child: LinearProgressIndicator(value: task.fraction, minHeight: 3)),
      ]),
      onTap: task.status == DownloadStatus.done ? () => controller.play(item) : null,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (task.active) button(AppIcons.pauseFill, tr('暂停'), () => manager.pause(task.id)),
        if (task.status == DownloadStatus.paused) button(AppIcons.playFill, tr('继续'), () => manager.resume(task.id)),
        if (task.active || task.status == DownloadStatus.paused) button(AppIcons.x, tr('取消'), () => manager.cancel(task.id)),
        if (failed || task.status == DownloadStatus.cancelled) button(AppIcons.arrowsClockwise, tr('重试'), () => manager.retry(task.id)),
        if (task.status == DownloadStatus.done && task.filePath != null)
          button(AppIcons.folderOpen, tr('打开所在文件夹'), () => unawaited(openInExplorer(task.filePath!, select: true))),
        if (!task.active) button(AppIcons.trash, tr('删除'), () => _confirmDelete(context)),
      ]),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    if (task.status != DownloadStatus.done) return unawaited(manager.remove(task.id, deleteFiles: true));
    final choice = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('删除这个下载？')),
        content: Text(tr('可以只从列表移除，也可以同时删除磁盘上的视频文件。')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('取消'))),
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('只移除'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('同时删除文件'))),
        ],
      ),
    );
    if (choice != null) await manager.remove(task.id, deleteFiles: choice);
  }
}
