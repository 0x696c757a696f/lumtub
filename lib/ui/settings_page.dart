import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../decoder_status.dart';
import '../player_settings.dart';
import '../windows_video_info.dart';
import '../widgets/pilinara_settings_tiles.dart';
import 'common.dart';
import 'theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});
  final AppController controller;

  PlayerSettings get _settings => controller.settings;
  void _save(PlayerSettings next) => controller.saveSettings(next);

  @override
  Widget build(BuildContext context) {
    final directories = controller.directories;
    final videoInfo = controller.windowsVideoInfo;
    return ListView(padding: const EdgeInsets.fromLTRB(28, 12, 28, 28), children: [
      const Text('设置', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
      const SizedBox(height: 20),
      const _SectionTitle('播放与性能'),
      PreferenceCard(child: Column(children: [
        _choice('硬件解码', _settings.hwdec, const {'auto-safe': '自动（推荐）', 'd3d11va': 'D3D11VA', 'no': '软件解码'}, (value) => _save(_settings.copyWith(hwdec: value))),
        const Divider(height: 1),
        _choice('视频缩放算法', _settings.scale, const {'spline36': '默认', 'bilinear': 'Bilinear', 'lanczos': 'Lanczos'}, (value) => _save(_settings.copyWith(scale: value))),
        PiliNaraSettingSwitch(title: '色带消除', subtitle: '降低渐变中的色带，可能略增 GPU 负载。', value: _settings.deband, onChanged: (value) => _save(_settings.copyWith(deband: value))),
        PiliNaraSettingSwitch(title: '帧插值', subtitle: '下一段视频生效；会增加 GPU 负载。', value: _settings.interpolation, onChanged: (value) => _save(_settings.copyWith(interpolation: value))),
        _slider('字幕大小', _settings.subtitleScale, 0.5, 3, '${_settings.subtitleScale.toStringAsFixed(1)}×', (value) => _save(_settings.copyWith(subtitleScale: value)), divisionsPerUnit: 10),
        _slider('字幕位置', _settings.subtitlePosition.toDouble(), 0, 100, '${_settings.subtitlePosition}%', (value) => _save(_settings.copyWith(subtitlePosition: value.round()))),
      ])),
      const SizedBox(height: 18),
      const _SectionTitle('视频缓存'),
      PreferenceCard(child: Column(children: [
        _choice('网络缓存', _settings.cacheMode, const {'auto': '自动（推荐）', 'yes': '启用', 'no': '禁用'}, (value) => _save(_settings.copyWith(cacheMode: value))),
        _slider('预读时间', _settings.cacheSeconds.toDouble(), 1, 300, '${_settings.cacheSeconds} 秒', (value) => _save(_settings.copyWith(cacheSeconds: value.round()))),
        _slider('内存上限', _settings.cacheMemoryMb.toDouble(), 16, 512, '${_settings.cacheMemoryMb} MB', (value) => _save(_settings.copyWith(cacheMemoryMb: value.round()))),
        const Padding(padding: EdgeInsets.fromLTRB(18, 2, 18, 14), child: Text('这里控制 libmpv 的内存网络缓存。它不会移动 RAM 缓存到磁盘。', style: TextStyle(color: Colors.white54, fontSize: 12))),
      ])),
      const SizedBox(height: 18),
      const _SectionTitle('解码与格式'),
      PreferenceCard(child: PiliNaraSettingSwitch(
        title: '自动选择最省资源的视频编码',
        subtitle: '只会影响自动格式选择，不会降低手动指定的画质。',
        value: _settings.autoSelectCodec,
        onChanged: (value) => _save(_settings.copyWith(autoSelectCodec: value)),
      )),
      const SizedBox(height: 10),
      PreferenceCard(child: Column(children: [
        ListTile(
          leading: const Icon(Icons.developer_board_outlined, color: AppColors.accent),
          title: const Text('GPU'),
          subtitle: Text(videoInfo.gpuNames.isEmpty ? '尚未检测到或无法读取' : videoInfo.gpuNames.join('\n')),
          isThreeLine: videoInfo.gpuNames.length > 1,
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.memory_outlined, color: AppColors.accent),
          title: const Text('当前实际解码方式'),
          subtitle: Text('视频：${controller.currentCodec}\n方式：${controller.currentHwdec}'),
          isThreeLine: true,
          trailing: OutlinedButton(onPressed: controller.playing == null ? null : controller.inspectCurrentDecoder, child: const Text('检测')),
        ),
        const Divider(height: 1),
        _decoderRow('H.264', controller.decodeStates['h264']),
        _decoderRow('VP9', controller.decodeStates['vp9']),
        _decoderRow('AV1', controller.decodeStates['av1']),
        const Divider(height: 1),
        _extensionRow('VP9 Video Extensions', videoInfo.vp9Extension, 'https://apps.microsoft.com/detail/9n4d0msmp0pt'),
        _extensionRow('AV1 Video Extension', videoInfo.av1Extension, 'https://apps.microsoft.com/detail/9mvzqvxjbq9v'),
        const Padding(padding: EdgeInsets.fromLTRB(18, 4, 18, 14), child: Text('状态只会在实际播放对应编码后更新；自动模式本身不代表硬件解码已成功。', style: TextStyle(color: Colors.white54, fontSize: 12))),
        const Padding(padding: EdgeInsets.fromLTRB(18, 0, 18, 14), child: Text('商店扩展是 Windows Media Foundation 组件，不是 YTPlus 或 libmpv 的必需依赖；安装它也不能让不支持的 GPU 获得硬件解码。', style: TextStyle(color: Colors.white54, fontSize: 12))),
      ])),
      const SizedBox(height: 14),
      PreferenceCard(child: ExpansionTile(
        leading: const Icon(Icons.tune, color: AppColors.accent),
        title: const Text('高级 libmpv 参数'),
        subtitle: const Text('只展示不会改变 media_kit 视频输出的选项。'),
        children: [
          _optionInfo('hwdec', _settings.hwdec, '硬件解码方式', '下一段视频'),
          _optionInfo('scale', _settings.scale, '视频缩放算法', '立即'),
          _optionInfo('deband', _settings.deband ? 'yes' : 'no', '色带消除', '立即'),
          _optionInfo('interpolation', _settings.interpolation ? 'yes' : 'no', '帧插值', '下一段视频'),
          _optionInfo('cache', _settings.cacheMode, '网络缓存模式', '立即'),
          _optionInfo('cache-secs', '${_settings.cacheSeconds}', '缓存预读时间', '立即'),
          _optionInfo('demuxer-max-bytes', '${_settings.cacheMemoryMb}MiB', '缓存内存上限', '立即'),
          Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), child: OutlinedButton.icon(onPressed: () => _save(const PlayerSettings()), icon: const Icon(Icons.restart_alt), label: const Text('恢复全部播放器默认设置'))),),
        ],
      )),
      const SizedBox(height: 18),
      const _SectionTitle('存储与缓存'),
      PreferenceCard(child: Column(children: [
        ListTile(
          leading: const Icon(Icons.folder_outlined, color: AppColors.accent),
          title: const Text('当前应用缓存位置'),
          subtitle: Text(_settings.cachePath ?? (directories == null ? '正在准备…' : directories.cache.path)),
          trailing: TextButton(onPressed: () => _changeCacheLocation(context), child: const Text('选择文件夹')),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.cleaning_services_outlined, color: AppColors.accent),
          title: const Text('缓存占用'),
          subtitle: Text('${formatBytes(controller.cacheBytes)} · 只清理 YTPlus 创建的缓存目录'),
          trailing: OutlinedButton(onPressed: controller.clearCache, child: const Text('清理')),
        ),
      ])),
      const SizedBox(height: 20),
      const Text('YTPlus 只会写入自己的 LocalAppData 目录；安装和首次启动不要求管理员权限。', style: TextStyle(color: Colors.white54, height: 1.5)),
    ]);
  }

  Future<void> _changeCacheLocation(BuildContext context) async {
    if (controller.cacheRoot == null) return;
    if (!controller.ensureNotPlaying('请先返回列表并停止当前视频，再迁移缓存。')) return;
    final selected = await getDirectoryPath(initialDirectory: controller.cacheRoot!.path);
    if (selected == null || !context.mounted) return;
    await controller.changeCacheLocation(selected, (targetPath) => showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('迁移现有缓存？'),
      content: Text('新位置：$targetPath\n\n只迁移 YTPlus 创建的缩略图、临时文件、yt-dlp 和 mpv 缓存目录。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('不迁移')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('迁移')),
      ],
    )));
  }

  Widget _choice(String label, String selected, Map<String, String> choices, ValueChanged<String> onChanged) => PiliNaraSettingChoice(
        title: label,
        value: selected,
        choices: choices,
        onSelected: onChanged,
      );

  Widget _slider(String label, double value, double min, double max, String description, ValueChanged<double> onChanged, {int divisionsPerUnit = 1}) => PiliNaraSettingSlider(
        title: label,
        value: value,
        min: min,
        max: max,
        description: description,
        divisions: ((max - min) * divisionsPerUnit).round(),
        onChanged: onChanged,
      );

  Widget _optionInfo(String name, String value, String description, String applies) => ListTile(
        dense: true,
        title: Text(name, style: const TextStyle(fontFamily: 'monospace')),
        subtitle: Text('$description · $applies生效'),
        trailing: Text(value, style: const TextStyle(color: AppColors.accent, fontFamily: 'monospace')),
      );

  Widget _decoderRow(String codec, DecoderStatus? status) {
    final value = status ?? const DecoderStatus.unverified();
    return ListTile(
      dense: true,
      title: Text(codec),
      trailing: Text(value.label, style: TextStyle(color: value.isVerified ? AppColors.accent : Colors.white54)),
    );
  }

  Widget _extensionRow(String title, ExtensionStatus status, String storeUrl) {
    final label = switch (status) {
      ExtensionStatus.present => '已安装',
      ExtensionStatus.missing => '未安装',
      ExtensionStatus.unknown => '尚未验证',
    };
    return ListTile(
      dense: true,
      title: Text(title),
      subtitle: const Text('Windows Media Foundation 扩展'),
      trailing: status == ExtensionStatus.missing
          ? TextButton(onPressed: () => controller.openStore(storeUrl), child: const Text('在商店查看'))
          : Text(label, style: TextStyle(color: status == ExtensionStatus.present ? AppColors.accent : Colors.white54)),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      );
}
