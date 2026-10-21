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

/// Asks what to download [item] as, then queues it.
Future<void> showDownloadChoice(BuildContext context, AppController controller, VideoItem item) async {
  final choice = await showDialog<DownloadChoice>(
    context: context,
    builder: (context) => DownloadDialog(
      title: item.title,
      loadFormats: () => controller.downloadFormats(item.id),
      defaults: controller.downloads?.defaults ?? const DownloadDefaults(),
      canMerge: controller.downloads?.canMerge ?? false,
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice.defaults != null) unawaited(controller.downloads?.setDefaults(choice.defaults!));
  if (await ensureFfmpegForDownload(context, controller, choice.quality)) controller.download(item, choice.quality, selection: choice.selection);
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
              icon: const Icon(Icons.folder_open_rounded),
              label: Text(tr('更改位置')),
            ),
            FilledButton.tonalIcon(
              onPressed: () => unawaited(openInExplorer(manager.directory)),
              icon: const Icon(Icons.open_in_new_rounded),
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
            icon: Icons.download_for_offline_outlined,
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
        final file = task.filePath == null ? null : File(task.filePath!);
        final size = file != null && file.existsSync() ? ' · ${formatBytes(file.lengthSync())}' : '';
        return '${tr('已完成')} · ${task.qualityLabel}$size';
      case DownloadStatus.failed:
        return tr('下载失败：{0}', [task.error ?? '']);
      case DownloadStatus.cancelled:
        return tr('已取消');
    }
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
          child: Image.network(item.thumbnail, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ColoredBox(color: colors.surfaceContainerHighest)),
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
        if (task.active) button(Icons.pause_rounded, tr('暂停'), () => manager.pause(task.id)),
        if (task.status == DownloadStatus.paused) button(Icons.play_arrow_rounded, tr('继续'), () => manager.resume(task.id)),
        if (task.active || task.status == DownloadStatus.paused) button(Icons.close_rounded, tr('取消'), () => manager.cancel(task.id)),
        if (failed || task.status == DownloadStatus.cancelled) button(Icons.refresh_rounded, tr('重试'), () => manager.retry(task.id)),
        if (task.status == DownloadStatus.done && task.filePath != null)
          button(Icons.folder_open_rounded, tr('打开所在文件夹'), () => unawaited(openInExplorer(task.filePath!, select: true))),
        if (!task.active) button(Icons.delete_outline_rounded, tr('删除'), () => _confirmDelete(context)),
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
