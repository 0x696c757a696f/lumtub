import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../appearance_settings.dart';
import '../../decoder_status.dart';
import '../../player_settings.dart';
import '../../windows_video_info.dart';
import '../../widgets/pilinara_settings_tiles.dart';
import '../common.dart';
import '../theme.dart';
import 'account_settings.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});
  final AppController controller;

  PlayerSettings get _settings => controller.settings;
  void _save(PlayerSettings next) => controller.saveSettings(next);

  @override
  Widget build(BuildContext context) {
    final directories = controller.directories;
    final videoInfo = controller.windowsVideoInfo;
    final colors = context.colors;
    final note = TextStyle(color: colors.onSurfaceVariant, fontSize: 12, height: 1.5);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: ListView(padding: const EdgeInsets.fromLTRB(AppStyle.pagePadding, 8, AppStyle.pagePadding, AppStyle.pagePadding), children: [
          Text('设置', style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          const _SectionTitle('账号'),
          PreferenceCard(child: AccountSettings(account: controller.account, note: note)),
          const SizedBox(height: 24),
          const _SectionTitle('外观'),
          PreferenceCard(child: _AppearanceSettings(controller: controller)),
          const SizedBox(height: 24),
          const _SectionTitle('播放与性能'),
          PreferenceCard(child: Column(children: [
            _choice('硬件解码', _settings.hwdec, const {'auto-safe': '自动（推荐）', 'd3d11va': 'D3D11VA', 'no': '软件解码'}, (value) => _save(_settings.copyWith(hwdec: value))),
            const Divider(),
            _choice('视频缩放算法', _settings.scale, const {'spline36': '默认', 'bilinear': 'Bilinear', 'lanczos': 'Lanczos'}, (value) => _save(_settings.copyWith(scale: value))),
            PiliNaraSettingSwitch(title: '色带消除', subtitle: '降低渐变中的色带，可能略增 GPU 负载。', value: _settings.deband, onChanged: (value) => _save(_settings.copyWith(deband: value))),
            PiliNaraSettingSwitch(title: '帧插值', subtitle: '下一段视频生效；会增加 GPU 负载。', value: _settings.interpolation, onChanged: (value) => _save(_settings.copyWith(interpolation: value))),
            PiliNaraSettingSlider(title: '字幕大小', value: _settings.subtitleScale, min: 0.5, max: 3, divisions: 25, description: (value) => '${value.toStringAsFixed(1)}×', onChanged: (value) => _save(_settings.copyWith(subtitleScale: value))),
            PiliNaraSettingSlider(title: '字幕位置', value: _settings.subtitlePosition.toDouble(), min: 0, max: 100, divisions: 100, description: (value) => '${value.round()}%', onChanged: (value) => _save(_settings.copyWith(subtitlePosition: value.round()))),
          ])),
          const SizedBox(height: 24),
          const _SectionTitle('跳过片段'),
          PreferenceCard(child: PiliNaraSettingSwitch(
            title: '用 SponsorBlock 自动跳过赞助广告',
            subtitle: '跳过社区标记的赞助广告、自我推广和求赞求订阅片段，下一段视频生效。开启后每播放一个视频，会向第三方服务器 sponsor.ajay.app 发送视频编号哈希的前 4 位（不发送完整编号、历史或账号信息）。',
            value: _settings.sponsorBlock,
            onChanged: (value) => _save(_settings.copyWith(sponsorBlock: value)),
          )),
          const SizedBox(height: 24),
          const _SectionTitle('视频缓存'),
          PreferenceCard(child: Column(children: [
            _choice('网络缓存', _settings.cacheMode, const {'auto': '自动（推荐）', 'yes': '启用', 'no': '禁用'}, (value) => _save(_settings.copyWith(cacheMode: value))),
            PiliNaraSettingSlider(title: '预读时间', value: _settings.cacheSeconds.toDouble(), min: 1, max: 300, divisions: 299, description: (value) => '${value.round()} 秒', onChanged: (value) => _save(_settings.copyWith(cacheSeconds: value.round()))),
            PiliNaraSettingSlider(title: '内存上限', value: _settings.cacheMemoryMb.toDouble(), min: 16, max: 512, divisions: 496, description: (value) => '${value.round()} MB', onChanged: (value) => _save(_settings.copyWith(cacheMemoryMb: value.round()))),
            Padding(padding: const EdgeInsets.fromLTRB(18, 2, 18, 14), child: Text('这里控制 libmpv 的内存网络缓存，不会把缓存写到磁盘。', style: note)),
          ])),
          const SizedBox(height: 24),
          const _SectionTitle('解码与格式'),
          PreferenceCard(child: PiliNaraSettingSwitch(
            title: '自动选择最省资源的视频编码',
            subtitle: '优先 H.264，确认显卡能硬解 VP9 后改用 VP9；不会自动选择解码最吃力的 AV1。画质上限在播放页的“画质”菜单里设置。',
            value: _settings.autoSelectCodec,
            onChanged: (value) => _save(_settings.copyWith(autoSelectCodec: value)),
          )),
          const SizedBox(height: 12),
          PreferenceCard(child: Column(children: [
            ListTile(
              leading: Icon(Icons.developer_board_outlined, color: colors.primary),
              title: const Text('GPU'),
              subtitle: Text(videoInfo.gpuNames.isEmpty ? '尚未检测到或无法读取' : videoInfo.gpuNames.join('\n')),
              isThreeLine: videoInfo.gpuNames.length > 1,
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.memory_outlined, color: colors.primary),
              title: const Text('当前实际解码方式'),
              subtitle: Text('视频：${controller.currentCodec}\n方式：${controller.currentHwdec}'),
              isThreeLine: true,
              trailing: OutlinedButton(onPressed: controller.playing == null ? null : controller.inspectCurrentDecoder, child: const Text('检测')),
            ),
            const Divider(),
            _decoderRow(context, 'H.264', controller.decodeStates['h264']),
            _decoderRow(context, 'VP9', controller.decodeStates['vp9']),
            _decoderRow(context, 'AV1', controller.decodeStates['av1']),
            const Divider(),
            _extensionRow(context, 'VP9 Video Extensions', videoInfo.vp9Extension, 'https://apps.microsoft.com/detail/9n4d0msmp0pt'),
            _extensionRow(context, 'AV1 Video Extension', videoInfo.av1Extension, 'https://apps.microsoft.com/detail/9mvzqvxjbq9v'),
            Padding(padding: const EdgeInsets.fromLTRB(18, 4, 18, 8), child: Text('状态只会在实际播放对应编码后更新；自动模式本身不代表硬件解码已成功。', style: note)),
            Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 14), child: Text('商店扩展是 Windows Media Foundation 组件，不是 YTPlus 或 libmpv 的必需依赖；安装它也不能让不支持的 GPU 获得硬件解码。', style: note)),
          ])),
          const SizedBox(height: 12),
          PreferenceCard(child: ExpansionTile(
            leading: Icon(Icons.tune, color: colors.primary),
            title: const Text('高级 libmpv 参数'),
            subtitle: const Text('只展示不会改变 media_kit 视频输出的选项。'),
            children: [
              _optionInfo(context, 'hwdec', _settings.hwdec, '硬件解码方式', '下一段视频'),
              _optionInfo(context, 'scale', _settings.scale, '视频缩放算法', '立即'),
              _optionInfo(context, 'deband', _settings.deband ? 'yes' : 'no', '色带消除', '立即'),
              _optionInfo(context, 'interpolation', _settings.interpolation ? 'yes' : 'no', '帧插值', '下一段视频'),
              _optionInfo(context, 'cache', _settings.cacheMode, '网络缓存模式', '立即'),
              _optionInfo(context, 'cache-secs', '${_settings.cacheSeconds}', '缓存预读时间', '立即'),
              _optionInfo(context, 'demuxer-max-bytes', '${_settings.cacheMemoryMb}MiB', '缓存内存上限', '立即'),
              Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), child: OutlinedButton.icon(onPressed: () => _save(const PlayerSettings()), icon: const Icon(Icons.restart_alt), label: const Text('恢复全部播放器默认设置')))),
            ],
          )),
          const SizedBox(height: 24),
          const _SectionTitle('组件'),
          PreferenceCard(child: _Components(controller: controller, note: note)),
          const SizedBox(height: 24),
          const _SectionTitle('存储与缓存'),
          PreferenceCard(child: Column(children: [
            ListTile(
              leading: Icon(Icons.folder_outlined, color: colors.primary),
              title: const Text('当前应用缓存位置'),
              subtitle: Text(_settings.cachePath ?? (directories == null ? '正在准备…' : directories.cache.path)),
              trailing: TextButton(onPressed: () => _changeCacheLocation(context), child: const Text('选择文件夹')),
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.cleaning_services_outlined, color: colors.primary),
              title: const Text('缓存占用'),
              subtitle: Text('${formatBytes(controller.cacheBytes)} · 只清理 YTPlus 创建的缓存目录'),
              trailing: OutlinedButton(onPressed: controller.clearCache, child: const Text('清理')),
            ),
          ])),
          const SizedBox(height: 20),
          Text('YTPlus 只会写入自己的 LocalAppData 目录；安装和首次启动不要求管理员权限。', style: note),
        ]),
      ),
    );
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

  Widget _optionInfo(BuildContext context, String name, String value, String description, String applies) => ListTile(
        dense: true,
        title: Text(name, style: const TextStyle(fontFamily: 'monospace')),
        subtitle: Text('$description · $applies生效'),
        trailing: Text(value, style: TextStyle(color: context.colors.primary, fontFamily: 'monospace')),
      );

  Widget _decoderRow(BuildContext context, String codec, DecoderStatus? status) {
    final value = status ?? const DecoderStatus.unverified();
    return ListTile(
      dense: true,
      title: Text(codec),
      trailing: Text(value.label, style: TextStyle(color: value.isVerified ? context.colors.primary : context.colors.onSurfaceVariant)),
    );
  }

  Widget _extensionRow(BuildContext context, String title, ExtensionStatus status, String storeUrl) {
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
          : Text(label, style: TextStyle(color: status == ExtensionStatus.present ? context.colors.primary : context.colors.onSurfaceVariant)),
    );
  }
}

class _AppearanceSettings extends StatelessWidget {
  const _AppearanceSettings({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final appearance = controller.appearance;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('主题'),
        const SizedBox(height: 10),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text('跟随系统')),
            ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('浅色')),
            ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('深色')),
          ],
          selected: {appearance.themeMode},
          showSelectedIcon: false,
          onSelectionChanged: (value) => controller.saveAppearance(appearance.copyWith(themeMode: value.first)),
        ),
        const SizedBox(height: 18),
        const Text('主题色'),
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (var i = 0; i < accentChoices.length; i++)
            Tooltip(
              message: accentChoices[i].$1,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => controller.saveAppearance(appearance.copyWith(accentIndex: i)),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accentChoices[i].$2,
                    shape: BoxShape.circle,
                    border: Border.all(color: i == appearance.accentIndex ? context.colors.onSurface : Colors.transparent, width: 2.5),
                  ),
                  child: i == appearance.accentIndex ? const Icon(Icons.check_rounded, color: Colors.white, size: 20) : null,
                ),
              ),
            ),
        ]),
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(text, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: context.colors.primary)),
      );
}

/// Versions of libmpv, yt-dlp and Deno, with updates and rollback.
class _Components extends StatelessWidget {
  const _Components({required this.controller, required this.note});
  final AppController controller;
  final TextStyle note;

  @override
  Widget build(BuildContext context) {
    final tools = controller.tools;
    if (tools == null || !controller.ready) return const ListTile(title: Text('正在准备组件…'));
    final libmpv = tools.libmpv;
    final current = libmpv.current;
    final next = libmpv.selected;
    final pendingRestart = next != null && next != current;
    final colors = context.colors;
    return Column(children: [
      ListTile(
        leading: Icon(Icons.movie_outlined, color: colors.primary),
        title: const Text('libmpv'),
        subtitle: Text([
          '${libmpv.usesDownload ? '已更新' : '内置'}：${current?.label ?? '未知版本'}',
          if (pendingRestart) '重启后使用 ${next.label}',
        ].join('\n')),
        trailing: libmpv.usesDownload || pendingRestart ? TextButton(onPressed: controller.rollBackLibmpv, child: const Text('改回内置')) : null,
      ),
      const Divider(),
      ListTile(
        leading: Icon(Icons.terminal_rounded, color: colors.primary),
        title: const Text('yt-dlp'),
        subtitle: Text(tools.ytDlpVersion ?? '未安装'),
        trailing: tools.canRollBackYtDlp ? TextButton(onPressed: controller.rollBackYtDlp, child: const Text('回退上一版')) : null,
      ),
      const Divider(),
      ListTile(
        leading: Icon(Icons.code_rounded, color: colors.primary),
        title: const Text('Deno'),
        subtitle: Text(tools.denoVersion ?? '未安装'),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
        child: Text('每天自动检查一次，只从官方 GitHub Release 下载并校验 SHA-256。新版本在重启后启用；新 libmpv 第一次播放失败或导致崩溃时，下次启动会自动改回内置版本。没有网络时继续使用已安装的版本。', style: note),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: OutlinedButton.icon(
            onPressed: controller.checking ? null : controller.checkUpdates,
            icon: const Icon(Icons.system_update_alt_rounded),
            label: Text(controller.checking ? '正在检查…' : '立即检查更新'),
          ),
        ),
      ),
    ]);
  }
}
