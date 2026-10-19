import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app_log.dart';
import '../../appearance_settings.dart';
import '../../decoder_status.dart';
import '../../player_settings.dart';
import '../../windows_video_info.dart';
import '../../widgets/pilinara_settings_tiles.dart';
import '../common.dart';
import '../player_shortcuts.dart';
import '../theme.dart';
import 'account_settings.dart';

/// The groups in the settings list, in display order, laid out like
/// PiliNara's settings page.
enum SettingsCategory {
  account('账号', 'Google 登录、导入 YouTube 订阅和播放列表', Icons.account_circle_outlined),
  video('视频设置', '画质、编码、硬解、缓冲、解码状态', Icons.video_settings_outlined),
  play('播放设置', '自动连播、跳过赞助片段、字幕、画面增强、快捷键', Icons.touch_app_outlined),
  style('外观设置', '主题模式、主题色', Icons.style_outlined),
  storage('组件与存储', 'libmpv、yt-dlp 更新与回退，缓存位置和清理', Icons.extension_outlined),
  about('关于', '版本、诊断信息、日志、开源许可', Icons.info_outline);

  const SettingsCategory(this.title, this.subtitle, this.icon);
  final String title;
  final String subtitle;
  final IconData icon;
}

/// One searchable row of a settings group.
class SettingEntry {
  const SettingEntry(this.title, this.builder, {this.subtitle});
  final String title;
  final String? subtitle;
  final WidgetBuilder builder;

  bool matches(String query) => title.toLowerCase().contains(query) || (subtitle?.toLowerCase().contains(query) ?? false);
}

String qualityLabel(int height) => height == 0 ? '自动（不限制）' : '${height}p';

const _hwdecModes = [('auto-safe', '自动（推荐）'), ('d3d11va', 'D3D11VA'), ('d3d11va-copy', 'D3D11VA 复制模式'), ('dxva2-copy', 'DXVA2 复制模式')];
const _scaleModes = [('spline36', 'Spline36（默认）'), ('bilinear', 'Bilinear（最省资源）'), ('lanczos', 'Lanczos（更锐利）')];
const _cacheModes = [('auto', '自动（推荐）'), ('yes', '启用'), ('no', '禁用')];
const _themeModes = [(ThemeMode.system, '跟随系统'), (ThemeMode.light, '浅色'), (ThemeMode.dark, '深色')];

String _labelOf<T>(List<(T, String)> values, T value) {
  for (final (key, label) in values) {
    if (key == value) return label;
  }
  return '$value';
}

List<SettingEntry> settingEntries(SettingsCategory category, AppController controller) {
  final settings = controller.settings;
  void save(PlayerSettings next) => controller.saveSettings(next);
  final hardware = settings.hwdec != 'no';
  return switch (category) {
    SettingsCategory.account => [
        SettingEntry('Google 账号', (context) => AccountSettings(account: controller.account, note: _note(context)), subtitle: '登录、同步订阅和播放列表、退出登录、自定义客户端'),
      ],
    SettingsCategory.video => [
        SettingEntry('默认画质', (context) => NormalItem(
              title: '默认画质',
              subtitle: '当前：${qualityLabel(settings.maxHeight)}。也可以在播放页的“画质”菜单里临时切换',
              leading: const Icon(Icons.high_quality_outlined),
              onTap: () => pickFromDialog<int>(context, title: '默认画质', value: settings.maxHeight, values: [for (final h in qualityHeights) (h, qualityLabel(h))], onSelected: controller.setMaxHeight),
            )),
        SettingEntry('自动选择省资源的编码', (context) => SwitchItem(
              title: '自动选择省资源的编码',
              subtitle: '优先 H.264，确认显卡能硬解 VP9 后改用 VP9；1080p 以下不选 AV1',
              leading: const Icon(Icons.auto_awesome_outlined),
              value: settings.autoSelectCodec,
              onChanged: (value) => save(settings.copyWith(autoSelectCodec: value)),
            ), subtitle: 'H.264 VP9 AV1 编码'),
        SettingEntry('开启硬解', (context) => SwitchItem(
              title: '开启硬解',
              subtitle: '用显卡解码，功耗更低；若出现花屏或卡死请关闭。下一段视频生效',
              leading: const Icon(Icons.memory_outlined),
              value: hardware,
              onChanged: (value) => save(settings.copyWith(hwdec: value ? 'auto-safe' : 'no')),
            ), subtitle: '硬件解码 hwdec'),
        SettingEntry('硬解模式', (context) => NormalItem(
              title: '硬解模式',
              subtitle: hardware ? '当前：${_labelOf(_hwdecModes, settings.hwdec)}' : '已关闭硬解',
              leading: const Icon(Icons.developer_board_outlined),
              enabled: hardware,
              onTap: () => pickFromDialog<String>(context, title: '硬解模式', value: settings.hwdec, values: _hwdecModes, onSelected: (value) => save(settings.copyWith(hwdec: value))),
            ), subtitle: 'D3D11VA DXVA2'),
        SettingEntry('缓冲模式', (context) => NormalItem(
              title: '缓冲模式',
              subtitle: '当前：${_labelOf(_cacheModes, settings.cacheMode)}。只使用内存，不写入磁盘',
              leading: const Icon(Icons.storage_outlined),
              onTap: () => pickFromDialog<String>(context, title: '缓冲模式', value: settings.cacheMode, values: _cacheModes, onSelected: (value) => save(settings.copyWith(cacheMode: value))),
            ), subtitle: '网络缓存'),
        SettingEntry('缓冲时长', (context) => NormalItem(
              title: '缓冲时长',
              subtitle: '当前：${settings.cacheSeconds} 秒，最多预读多久的视频',
              leading: const Icon(Icons.timer_outlined),
              onTap: () => pickWithSlider(context, title: '缓冲时长', value: settings.cacheSeconds.toDouble(), min: 1, max: 300, divisions: 299, suffix: ' 秒', onSelected: (v) => save(settings.copyWith(cacheSeconds: v.round()))),
            ), subtitle: '预读时间'),
        SettingEntry('缓冲大小', (context) => NormalItem(
              title: '缓冲大小',
              subtitle: '当前：${settings.cacheMemoryMb} MB，预读占用的内存上限',
              leading: const Icon(Icons.sd_card_outlined),
              onTap: () => pickWithSlider(context, title: '缓冲大小', value: settings.cacheMemoryMb.toDouble(), min: 16, max: 512, divisions: 31, suffix: ' MB', onSelected: (v) => save(settings.copyWith(cacheMemoryMb: v.round()))),
            ), subtitle: '内存上限'),
        SettingEntry('解码状态', (context) => _DecoderStatus(controller: controller), subtitle: 'GPU 当前解码方式 VP9 AV1 视频扩展'),
        SettingEntry('高级 libmpv 参数', (context) => _AdvancedOptions(settings: settings, onReset: () => save(const PlayerSettings())), subtitle: '恢复默认设置'),
      ],
    SettingsCategory.play => [
        SettingEntry('自动连播', (context) => SwitchItem(
              title: '自动连播',
              subtitle: '播放结束后接着播放队列中的下一个，队列放完后播放相关视频',
              leading: const Icon(Icons.playlist_play_rounded),
              value: settings.autoplayNext,
              onChanged: controller.setAutoplayNext,
            )),
        SettingEntry('跳过赞助片段', (context) => SwitchItem(
              title: '跳过赞助片段（SponsorBlock）',
              subtitle: '跳过社区标记的赞助广告、自我推广和求赞求订阅。开启后每个视频会向 sponsor.ajay.app 发送视频编号哈希的前 4 位',
              leading: const Icon(Icons.fast_forward_outlined),
              value: settings.sponsorBlock,
              onChanged: (value) => save(settings.copyWith(sponsorBlock: value)),
            ), subtitle: 'SponsorBlock 广告'),
        SettingEntry('字幕大小', (context) => NormalItem(
              title: '字幕大小',
              subtitle: '当前：${settings.subtitleScale.toStringAsFixed(1)}×',
              leading: const Icon(Icons.format_size_rounded),
              onTap: () => pickWithSlider(context, title: '字幕大小', value: settings.subtitleScale, min: 0.5, max: 3, divisions: 25, suffix: '×', precise: 1, onSelected: (v) => save(settings.copyWith(subtitleScale: v))),
            )),
        SettingEntry('字幕位置', (context) => NormalItem(
              title: '字幕位置',
              subtitle: '当前：${settings.subtitlePosition}%（100% 为画面底部）',
              leading: const Icon(Icons.vertical_align_bottom_rounded),
              onTap: () => pickWithSlider(context, title: '字幕位置', value: settings.subtitlePosition.toDouble(), min: 0, max: 100, divisions: 100, suffix: '%', onSelected: (v) => save(settings.copyWith(subtitlePosition: v.round()))),
            )),
        SettingEntry('视频缩放算法', (context) => NormalItem(
              title: '视频缩放算法',
              subtitle: '当前：${_labelOf(_scaleModes, settings.scale)}',
              leading: const Icon(Icons.photo_size_select_large_rounded),
              onTap: () => pickFromDialog<String>(context, title: '视频缩放算法', value: settings.scale, values: _scaleModes, onSelected: (value) => save(settings.copyWith(scale: value))),
            )),
        SettingEntry('色带消除', (context) => SwitchItem(
              title: '色带消除',
              subtitle: '减轻渐变中的色带，略增 GPU 负载',
              leading: const Icon(Icons.gradient_rounded),
              value: settings.deband,
              onChanged: (value) => save(settings.copyWith(deband: value)),
            ), subtitle: 'deband'),
        SettingEntry('帧插值', (context) => SwitchItem(
              title: '帧插值',
              subtitle: '让画面更平滑，会增加 GPU 负载。下一段视频生效',
              leading: const Icon(Icons.animation_rounded),
              value: settings.interpolation,
              onChanged: (value) => save(settings.copyWith(interpolation: value)),
            ), subtitle: 'interpolation'),
        SettingEntry('快捷键', (context) => NormalItem(
              title: '快捷键',
              subtitle: '空格暂停、方向键快进和音量、F 全屏、I 播放统计等',
              leading: const Icon(Icons.keyboard_outlined),
              onTap: () => showShortcutHelp(context),
            ), subtitle: '键盘 播放统计'),
      ],
    SettingsCategory.style => [
        SettingEntry('主题模式', (context) => NormalItem(
              title: '主题模式',
              subtitle: '当前：${_labelOf(_themeModes, controller.appearance.themeMode)}',
              leading: const Icon(Icons.brightness_6_outlined),
              onTap: () => pickFromDialog<ThemeMode>(
                context,
                title: '主题模式',
                value: controller.appearance.themeMode,
                values: _themeModes,
                onSelected: (mode) => controller.saveAppearance(controller.appearance.copyWith(themeMode: mode)),
              ),
            ), subtitle: '深色 浅色'),
        SettingEntry('主题色', (context) => NormalItem(
              title: '主题色',
              subtitle: '当前：${accentChoices[controller.appearance.accentIndex].$1}',
              leading: const Icon(Icons.color_lens_outlined),
              trailing: CircleAvatar(radius: 12, backgroundColor: controller.appearance.accent),
              onTap: () => _pickAccent(context, controller),
            ), subtitle: '颜色'),
      ],
    SettingsCategory.storage => [
        SettingEntry('组件版本与更新', (context) => _Components(controller: controller), subtitle: 'libmpv yt-dlp Deno 检查更新 回退'),
        SettingEntry('缓存位置', (context) => NormalItem(
              title: '缓存位置',
              subtitle: settings.cachePath ?? controller.directories?.cache.path ?? '正在准备…',
              leading: const Icon(Icons.folder_outlined),
              onTap: () => _changeCacheLocation(context, controller),
            )),
        SettingEntry('清理缓存', (context) => NormalItem(
              title: '清理缓存',
              subtitle: '已占用 ${formatBytes(controller.cacheBytes)}，只清理 YTPlus 创建的缩略图和临时文件',
              leading: const Icon(Icons.cleaning_services_outlined),
              onTap: controller.clearCache,
            ), subtitle: '缓存占用'),
        SettingEntry('数据位置', (context) => NormalItem(
              title: '数据位置',
              subtitle: '${controller.directories?.root.path ?? '正在准备…'}\n设置、观看记录、收藏和下载的组件都保存在这里，卸载时会保留',
              leading: const Icon(Icons.inventory_2_outlined),
              onTap: controller.directories == null ? null : () => openExternal(controller.directories!.root.path),
            )),
      ],
    SettingsCategory.about => [
        SettingEntry('版本', (context) => NormalItem(
              title: 'YTPlus',
              subtitle: '版本 $appVersion',
              leading: const Icon(Icons.smart_display_outlined),
              trailing: TextButton(onPressed: () => openExternal('https://github.com/0x696c757a696f/ytplus/releases'), child: const Text('发布页')),
            ), subtitle: '更新 发布'),
        SettingEntry('复制诊断信息', (context) => NormalItem(
              title: '复制诊断信息',
              subtitle: '版本、系统、显卡、组件和播放设置，反馈问题时请附上',
              leading: const Icon(Icons.content_copy_rounded),
              onTap: () => copyText(context, controller.diagnostics(), '诊断信息已复制'),
            ), subtitle: '反馈 问题'),
        SettingEntry('打开日志文件夹', (context) => NormalItem(
              title: '打开日志文件夹',
              subtitle: 'ytplus.log 只保存在本机，不记录登录凭据和视频流地址',
              leading: const Icon(Icons.description_outlined),
              onTap: controller.directories == null ? null : () => openExternal(controller.directories!.logs.path),
            ), subtitle: '日志'),
        SettingEntry('源代码', (context) => NormalItem(
              title: '源代码',
              subtitle: 'github.com/0x696c757a696f/ytplus · GPLv3',
              leading: const Icon(Icons.code_rounded),
              onTap: () => openExternal('https://github.com/0x696c757a696f/ytplus'),
            ), subtitle: 'GitHub'),
        SettingEntry('开源许可', (context) => NormalItem(
              title: '开源许可',
              subtitle: '部分界面改编自 PiliNara（GPLv3）；播放基于 mpv、media_kit 和 yt-dlp',
              leading: const Icon(Icons.gavel_rounded),
              onTap: () => showLicensePage(context: context, applicationName: 'YTPlus', applicationVersion: appVersion),
            ), subtitle: 'PiliNara mpv media_kit yt-dlp'),
      ],
  };
}

TextStyle _note(BuildContext context) => TextStyle(color: context.colors.outline, fontSize: 12, height: 1.5);

Future<void> _pickAccent(BuildContext context, AppController controller) async {
  final appearance = controller.appearance;
  final index = await showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('主题色'),
      content: Wrap(spacing: 14, runSpacing: 14, children: [
        for (var i = 0; i < accentChoices.length; i++)
          Tooltip(
            message: accentChoices[i].$1,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.pop(context, i),
              child: Container(
                width: 40,
                height: 40,
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
    ),
  );
  if (index != null && index != appearance.accentIndex) controller.saveAppearance(appearance.copyWith(accentIndex: index));
}

Future<void> _changeCacheLocation(BuildContext context, AppController controller) async {
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

/// GPU, the decoder in use, which codecs were verified to decode in
/// hardware, and the optional Windows video extensions.
class _DecoderStatus extends StatelessWidget {
  const _DecoderStatus({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final info = controller.windowsVideoInfo;
    final colors = context.colors;
    return ExpansionTile(
      leading: const Icon(Icons.speed_rounded),
      title: Text('解码状态', style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text('当前：${controller.currentCodec} · ${controller.currentHwdec}', style: _subtitle(context)),
      children: [
        ListTile(dense: true, title: const Text('GPU'), subtitle: Text(info.gpuNames.isEmpty ? '尚未检测到或无法读取' : info.gpuNames.join('\n'))),
        ListTile(
          dense: true,
          title: const Text('当前实际解码方式'),
          subtitle: Text('视频：${controller.currentCodec}\n方式：${controller.currentHwdec}'),
          trailing: OutlinedButton(onPressed: controller.playing == null ? null : controller.inspectCurrentDecoder, child: const Text('检测')),
        ),
        for (final (key, label) in const [('h264', 'H.264'), ('vp9', 'VP9'), ('av1', 'AV1')])
          ListTile(
            dense: true,
            title: Text('$label 硬件解码'),
            trailing: Builder(builder: (context) {
              final status = controller.decodeStates[key] ?? const DecoderStatus.unverified();
              return Text(status.label, style: TextStyle(color: status.isVerified ? colors.primary : colors.onSurfaceVariant));
            }),
          ),
        _extension(context, 'VP9 Video Extensions', info.vp9Extension, 'https://apps.microsoft.com/detail/9n4d0msmp0pt'),
        _extension(context, 'AV1 Video Extension', info.av1Extension, 'https://apps.microsoft.com/detail/9mvzqvxjbq9v'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text('状态只在实际播放对应编码后更新。商店扩展是 Windows Media Foundation 组件，不是 YTPlus 必需的，也不能让不支持的显卡获得硬件解码。', style: _note(context)),
        ),
      ],
    );
  }

  Widget _extension(BuildContext context, String title, ExtensionStatus status, String storeUrl) {
    final colors = context.colors;
    return ListTile(
      dense: true,
      title: Text(title),
      trailing: switch (status) {
        ExtensionStatus.missing => TextButton(onPressed: () => controller.openStore(storeUrl), child: const Text('在商店查看')),
        ExtensionStatus.present => Text('已安装', style: TextStyle(color: colors.primary)),
        ExtensionStatus.unknown => Text('尚未验证', style: TextStyle(color: colors.onSurfaceVariant)),
      },
    );
  }
}

class _AdvancedOptions extends StatelessWidget {
  const _AdvancedOptions({required this.settings, required this.onReset});
  final PlayerSettings settings;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    Widget option(String name, String value, String description, String applies) => ListTile(
          dense: true,
          title: Text(name, style: const TextStyle(fontFamily: 'monospace')),
          subtitle: Text('$description · $applies生效'),
          trailing: Text(value, style: TextStyle(color: context.colors.primary, fontFamily: 'monospace')),
        );
    return ExpansionTile(
      leading: const Icon(Icons.tune_rounded),
      title: Text('高级 libmpv 参数', style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text('查看实际传给 libmpv 的参数，或恢复默认', style: _subtitle(context)),
      children: [
        option('hwdec', settings.hwdec, '硬件解码方式', '下一段视频'),
        option('scale', settings.scale, '视频缩放算法', '立即'),
        option('deband', settings.deband ? 'yes' : 'no', '色带消除', '立即'),
        option('interpolation', settings.interpolation ? 'yes' : 'no', '帧插值', '下一段视频'),
        option('cache', settings.cacheMode, '网络缓存模式', '立即'),
        option('cache-secs', '${settings.cacheSeconds}', '缓存预读时间', '立即'),
        option('demuxer-max-bytes', '${settings.cacheMemoryMb}MiB', '缓存内存上限', '立即'),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: OutlinedButton.icon(onPressed: onReset, icon: const Icon(Icons.restart_alt), label: const Text('恢复全部播放器默认设置')),
          ),
        ),
      ],
    );
  }
}

TextStyle _subtitle(BuildContext context) => Theme.of(context).textTheme.labelMedium!.copyWith(color: context.colors.outline);

/// Versions of libmpv, yt-dlp and Deno, with updates and rollback.
class _Components extends StatelessWidget {
  const _Components({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final tools = controller.tools;
    if (tools == null || !controller.ready) return const NormalItem(title: '组件', subtitle: '正在准备组件…');
    final libmpv = tools.libmpv;
    final current = libmpv.current;
    final next = libmpv.selected;
    final pendingRestart = next != null && next != current;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      NormalItem(
        title: 'libmpv',
        subtitle: [
          '${libmpv.usesDownload ? '已更新' : '内置'}：${current?.label ?? '未知版本'}',
          if (pendingRestart) '重启后使用 ${next.label}',
        ].join('\n'),
        leading: const Icon(Icons.movie_outlined),
        trailing: libmpv.usesDownload || pendingRestart ? TextButton(onPressed: controller.rollBackLibmpv, child: const Text('改回内置')) : null,
      ),
      NormalItem(
        title: 'yt-dlp',
        subtitle: tools.ytDlpVersion ?? '未安装',
        leading: const Icon(Icons.terminal_rounded),
        trailing: tools.canRollBackYtDlp ? TextButton(onPressed: controller.rollBackYtDlp, child: const Text('回退上一版')) : null,
      ),
      NormalItem(title: 'Deno', subtitle: tools.denoVersion ?? '未安装', leading: const Icon(Icons.code_rounded)),
      NormalItem(
        title: controller.checking ? '正在检查更新…' : '立即检查更新',
        subtitle: '每天自动检查一次，只从官方 GitHub Release 下载并校验 SHA-256，重启后启用。新 libmpv 出错时会自动改回内置版本',
        leading: const Icon(Icons.system_update_alt_rounded),
        enabled: !controller.checking,
        onTap: controller.checkUpdates,
      ),
    ]);
  }
}
