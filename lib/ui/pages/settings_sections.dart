import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app_log.dart';
import '../../app_preferences.dart';
import '../../appearance_settings.dart';
import '../../decoder_status.dart';
import '../../network_proxy.dart';
import '../../piped_streams.dart';
import '../../player_settings.dart';
import '../../widgets/pilinara_settings_tiles.dart';
import '../../windows_video_info.dart';
import '../common.dart';
import '../player_shortcuts.dart';
import '../theme.dart';
import 'account_settings.dart';
import 'piped_servers_page.dart';
import 'settings_subpages.dart';

/// The groups in the settings list, in display order, named and ordered
/// like PiliNara's settings page. [account] and [about] are drawn at the
/// bottom of the list without a subtitle, as PiliNara draws them.
enum SettingsCategory {
  privacy('隐私设置', '屏蔽频道、观看历史、播放进度', Icons.privacy_tip_outlined),
  recommend('首页与搜索设置', '首页内容、关键词过滤、隐藏 Shorts 和看完的视频', Icons.explore_outlined),
  subscriptions('订阅设置', '订阅动态的刷新和过滤', Icons.dynamic_feed_outlined),
  video('视频设置', '画质、音质、解码、缓冲、音频输出等', Icons.video_settings_outlined),
  play('播放设置', '倍速、自动播放、播放顺序、字幕、音量、全屏、快捷键等', Icons.touch_app_outlined),
  style('外观设置', '主题、字体、页面过渡动画、导航栏、卡片宽度、封面质量等', Icons.style_outlined),
  extra('其它设置', '空降助手、相关视频、视频简介、组件更新、缓存等', Icons.extension_outlined),
  backup('备份与恢复', '导入、导出和重置设置', Icons.settings_backup_restore_rounded),
  account('Google 账号', '登录、同步订阅和播放列表', Icons.account_circle_outlined),
  about('关于', '版本、日志、诊断信息、开源许可', Icons.info_outline);

  const SettingsCategory(this.title, this.subtitle, this.icon);
  final String title;
  final String subtitle;
  final IconData icon;
}

/// One searchable row of a settings group.
class SettingEntry {
  const SettingEntry(this.title, this.builder, {this.subtitle});
  final String title;
  /// Extra words the search matches, such as the mpv option name.
  final String? subtitle;
  final WidgetBuilder builder;

  bool matches(String query) => title.toLowerCase().contains(query) || (subtitle?.toLowerCase().contains(query) ?? false);
}

String qualityLabel(int height) => height == 0 ? '自动（不限制）' : '${height}p';

const _scaleModes = [('spline36', 'Spline36（默认）'), ('bilinear', 'Bilinear（最省资源）'), ('lanczos', 'Lanczos（更锐利）'), ('ewa_lanczossharp', 'EWA Lanczos Sharp（最清晰，GPU 负载高）')];
const _cacheModes = [('auto', '自动（推荐）'), ('yes', '启用'), ('no', '禁用')];
const themeModes = [(ThemeMode.system, '跟随系统'), (ThemeMode.light, '浅色'), (ThemeMode.dark, '深色')];
const _durations = [(0, '不限'), (1, '1 分钟'), (3, '3 分钟'), (5, '5 分钟'), (10, '10 分钟'), (20, '20 分钟')];
const _feedIntervals = [(5, '5 分钟'), (10, '10 分钟'), (30, '30 分钟'), (60, '1 小时'), (180, '3 小时')];
const _hideTimes = [(2, '2 秒'), (3, '3 秒（默认）'), (5, '5 秒'), (10, '10 秒'), (30, '30 秒（便于屏幕阅读器）')];
const _volumeMaxes = [(100, '100%（不增强）'), (130, '130%'), (150, '150%'), (200, '200%')];

String labelOf<T>(List<(T, String)> values, T value) {
  for (final (key, label) in values) {
    if (key == value) return label;
  }
  return '$value';
}

List<(T, String)> _enumValues<T extends Enum>(List<T> values, String Function(T) label) => [for (final v in values) (v, label(v))];

Widget _icon(IconData icon) => Icon(icon);

List<SettingEntry> settingEntries(SettingsCategory category, AppController controller) {
  final settings = controller.settings;
  final prefs = controller.preferences;
  final appearance = controller.appearance;
  void save(PlayerSettings next) => controller.saveSettings(next);
  void savePrefs(AppPreferences next) => controller.savePreferences(next);
  void saveLooks(AppearanceSettings next) => controller.saveAppearance(next);
  final hardware = settings.hwdec != 'no';
  return switch (category) {
    SettingsCategory.privacy => [
        SettingEntry('屏蔽频道', (context) => NormalItem(
              title: '屏蔽频道',
              subtitle: prefs.blockedChannels.isEmpty ? '在视频卡片的右键菜单里选“屏蔽此频道”' : '已屏蔽 ${prefs.blockedChannels.length} 个频道',
              leading: _icon(Icons.block_rounded),
              onTap: () => openBlockedChannels(context, controller),
            ), subtitle: '黑名单'),
        SettingEntry('记录观看历史', (context) => SwitchItem(
              title: '记录观看历史',
              subtitle: '关闭后新看的视频不再出现在“历史”和首页，也不再记录搜索词',
              leading: _icon(Icons.history_rounded),
              value: prefs.recordHistory,
              onChanged: (v) => savePrefs(prefs.copyWith(recordHistory: v)),
            )),
        SettingEntry('记录播放进度', (context) => SwitchItem(
              title: '记录播放进度',
              subtitle: '用于继续播放和卡片上的进度条',
              leading: _icon(Icons.timelapse_rounded),
              value: prefs.recordProgress,
              onChanged: (v) => savePrefs(prefs.copyWith(recordProgress: v)),
            )),
        SettingEntry('清空观看历史', (context) => NormalItem(
              title: '清空观看历史',
              subtitle: '${controller.history.length} 条记录',
              leading: _icon(Icons.delete_sweep_outlined),
              onTap: () async {
                if (await confirmDialog(context, title: '清空观看历史？', content: '只删除本机的记录，不影响 YouTube 账号。')) await controller.clearHistory();
              },
            )),
        SettingEntry('清空搜索记录', (context) => NormalItem(
              title: '清空搜索记录',
              subtitle: '搜索框下方显示的最近搜索',
              leading: _icon(Icons.manage_search_rounded),
              onTap: () async {
                if (await confirmDialog(context, title: '清空搜索记录？', content: '只删除本机保存的搜索词。')) await controller.clearSearchHistory();
              },
            )),
        SettingEntry('清空播放进度', (context) => NormalItem(
              title: '清空播放进度',
              subtitle: '所有视频都从头开始播放',
              leading: _icon(Icons.restart_alt_rounded),
              onTap: () async {
                if (await confirmDialog(context, title: '清空播放进度？', content: '“继续观看”和卡片上的进度条会一并清空。')) controller.clearProgress();
              },
            )),
      ],
    SettingsCategory.recommend => [
        SettingEntry('首页显示为你推荐', (context) => SwitchItem(
              title: '首页显示“为你推荐”',
              subtitle: '根据本机的观看历史、收藏和关注在本机计算，不上传',
              leading: _icon(Icons.auto_awesome_outlined),
              value: prefs.homeShowRecommended,
              onChanged: (v) => savePrefs(prefs.copyWith(homeShowRecommended: v)),
            )),
        SettingEntry('清空不感兴趣', (context) => NormalItem(
              title: '清空“不感兴趣”记录',
              subtitle: '${controller.homeFeed?.notInterested.videos.length ?? 0} 个视频',
              leading: _icon(Icons.thumb_down_off_alt_outlined),
              onTap: () async {
                if (await confirmDialog(context, title: '清空“不感兴趣”记录？', content: '被标记的视频和频道会重新出现在推荐里。')) await controller.clearNotInterested();
              },
            )),
        SettingEntry('首页显示继续观看', (context) => SwitchItem(
              title: '首页显示“继续观看”',
              subtitle: '没看完的视频',
              leading: _icon(Icons.play_circle_outline_rounded),
              value: prefs.homeShowContinue,
              onChanged: (v) => savePrefs(prefs.copyWith(homeShowContinue: v)),
            )),
        SettingEntry('首页显示最近观看', (context) => SwitchItem(
              title: '首页显示“最近观看”',
              leading: _icon(Icons.history_toggle_off_rounded),
              value: prefs.homeShowRecent,
              onChanged: (v) => savePrefs(prefs.copyWith(homeShowRecent: v)),
            )),
        SettingEntry('标题关键词过滤', (context) => NormalItem(
              title: '标题关键词过滤',
              subtitle: prefs.blockedKeywords.isEmpty ? '点击添加' : '${prefs.blockedKeywords.length} 个关键词',
              leading: _icon(Icons.filter_alt_outlined),
              onTap: () async {
                final result = await showDialog<List<String>>(
                  context: context,
                  builder: (context) => ListEditorDialog(title: '标题关键词过滤', initialItems: prefs.blockedKeywords, hintText: '输入关键词，不区分大小写', itemLabel: '关键词'),
                );
                if (result != null) savePrefs(controller.preferences.copyWith(blockedKeywords: result));
              },
            ), subtitle: '屏蔽 关键字'),
        SettingEntry('隐藏 Shorts 短视频', (context) => SwitchItem(
              title: '隐藏 Shorts 短视频',
              subtitle: '隐藏 1 分钟以内的视频',
              leading: _icon(Icons.smartphone_rounded),
              value: prefs.hideShorts,
              onChanged: (v) => savePrefs(prefs.copyWith(hideShorts: v)),
            )),
        SettingEntry('最短视频时长', (context) => NormalItem(
              title: '最短视频时长',
              subtitle: '当前：${labelOf(_durations, prefs.minDurationMinutes)}，更短的视频不显示',
              leading: _icon(Icons.timer_outlined),
              onTap: () => pickFromDialog<int>(context, title: '最短视频时长', value: prefs.minDurationMinutes, values: _durations, onSelected: (v) => savePrefs(prefs.copyWith(minDurationMinutes: v))),
            ), subtitle: '时长过滤'),
        SettingEntry('隐藏已看完的视频', (context) => SwitchItem(
              title: '隐藏已看完的视频',
              subtitle: '根据本机的播放进度判断',
              leading: _icon(Icons.visibility_off_outlined),
              value: prefs.hideWatched,
              onChanged: (v) => savePrefs(prefs.copyWith(hideWatched: v)),
            )),
      ],
    SettingsCategory.subscriptions => [
        SettingEntry('进入订阅页时自动刷新', (context) => SwitchItem(
              title: '进入订阅页时自动刷新',
              subtitle: '关闭后只在点击刷新按钮时更新',
              leading: _icon(Icons.sync_rounded),
              value: prefs.feedAutoRefresh,
              onChanged: (v) => savePrefs(prefs.copyWith(feedAutoRefresh: v)),
            )),
        SettingEntry('自动刷新间隔', (context) => NormalItem(
              title: '自动刷新间隔',
              subtitle: '当前：${labelOf(_feedIntervals, prefs.feedRefreshMinutes)}，间隔内再次进入不重新加载',
              leading: _icon(Icons.update_rounded),
              enabled: prefs.feedAutoRefresh,
              onTap: () => pickFromDialog<int>(context, title: '自动刷新间隔', value: prefs.feedRefreshMinutes, values: _feedIntervals, onSelected: (v) => savePrefs(prefs.copyWith(feedRefreshMinutes: v))),
            )),
        SettingEntry('订阅动态也应用过滤', (context) => SwitchItem(
              title: '订阅动态也应用过滤',
              subtitle: '关键词、Shorts、时长和看完的视频；屏蔽的频道总是隐藏',
              leading: _icon(Icons.filter_list_rounded),
              value: prefs.filterSubscriptions,
              onChanged: (v) => savePrefs(prefs.copyWith(filterSubscriptions: v)),
            )),
        SettingEntry('立即刷新订阅动态', (context) => NormalItem(
              title: '立即刷新订阅动态',
              subtitle: '已关注 ${controller.library?.channels.length ?? 0} 个频道',
              leading: _icon(Icons.refresh_rounded),
              onTap: () => controller.library?.refreshFeed(force: true),
            )),
      ],
    SettingsCategory.video => [
        SettingEntry('开启硬解', (context) => SwitchItem(
              title: '开启硬解',
              subtitle: '以较低功耗播放视频，若异常卡死请关闭',
              leading: _icon(Icons.memory_outlined),
              value: hardware,
              onChanged: (value) => save(settings.copyWith(hwdec: value ? 'auto-safe' : 'no')),
            ), subtitle: '硬件解码 hwdec'),
        SettingEntry('硬解模式', (context) => NormalItem(
              title: '硬解模式',
              subtitle: hardware ? '当前：${settings.hwdec}（此项即 mpv 的 --hwdec，按顺序尝试）' : '已关闭硬解',
              leading: _icon(Icons.developer_board_outlined),
              enabled: hardware,
              onTap: () async {
                final result = await showDialog<List<String>>(
                  context: context,
                  builder: (context) => OrderedMultiSelectDialog<String>(
                    title: '硬解模式',
                    initValues: settings.hwdec.split(','),
                    values: [for (final (name, label) in hwdecChoices) (name, name, label)],
                  ),
                );
                if (result != null && result.isNotEmpty) save(controller.settings.copyWith(hwdec: result.join(',')));
              },
            ), subtitle: 'hwdec D3D11VA D3D12VA DXVA2 NVDEC Vulkan AMF QSV'),
        SettingEntry('硬解编码', (context) => NormalItem(
              title: '硬解编码',
              subtitle: '当前：${settings.hwdecCodecs}（此项即 mpv 的 --hwdec-codecs）',
              leading: _icon(Icons.video_file_outlined),
              enabled: hardware,
              onTap: () async {
                final result = await showDialog<List<String>>(
                  context: context,
                  builder: (context) => OrderedMultiSelectDialog<String>(
                    title: '只对这些编码尝试硬解',
                    ordered: false,
                    initValues: settings.hwdecCodecs.split(','),
                    values: [for (final codec in hwdecCodecChoices) (codec, codec, null)],
                  ),
                );
                if (result != null && result.isNotEmpty) {
                  save(controller.settings.copyWith(hwdecCodecs: [for (final c in hwdecCodecChoices) if (result.contains(c)) c].join(',')));
                }
              },
            ), subtitle: 'hwdec-codecs h264 hevc vp9 av1'),
        SettingEntry('D3D11VA 零拷贝', (context) => SwitchItem(
              title: 'D3D11VA 零拷贝',
              subtitle: '此项即 mpv 的 --d3d11va-zero-copy，只对 d3d11va 有效；其他解码器选不带 -copy 的模式即为零拷贝',
              leading: _icon(Icons.bolt_outlined),
              enabled: hardware,
              value: settings.d3d11vaZeroCopy,
              onChanged: (v) => save(settings.copyWith(d3d11vaZeroCopy: v)),
            ), subtitle: 'd3d11va-zero-copy'),
        SettingEntry('直接解码到显存', (context) => PopupItem<String>(
              title: '直接解码到显存（vd-lavc-dr）',
              leading: _icon(Icons.memory_rounded),
              value: settings.directRendering,
              values: const [('auto', 'auto（默认）'), ('yes', 'yes'), ('no', 'no')],
              onSelected: (v) => save(settings.copyWith(directRendering: v)),
            ), subtitle: 'vd-lavc-dr direct rendering'),
        SettingEntry('默认画质', (context) => NormalItem(
              title: '默认画质',
              subtitle: '当前：${qualityLabel(settings.maxHeight)}',
              leading: _icon(Icons.high_quality_outlined),
              onTap: () => pickFromDialog<int>(context, title: '默认画质', value: settings.maxHeight, values: [for (final h in qualityHeights) (h, qualityLabel(h))], onSelected: controller.setMaxHeight),
            ), subtitle: '清晰度 分辨率'),
        SettingEntry('首选解码格式', (context) => NormalItem(
              title: '首选解码格式',
              subtitle: '当前：${settings.codec.label}',
              leading: _icon(Icons.movie_filter_outlined),
              onTap: () => pickFromDialog<CodecPreference>(
                context,
                title: '首选解码格式',
                value: settings.codec,
                values: _enumValues(CodecPreference.values, (c) => c.label),
                onSelected: (v) => save(settings.copyWith(codec: v)),
              ),
            ), subtitle: '编码 H.264 VP9 AV1'),
        SettingEntry('默认音质', (context) => NormalItem(
              title: '默认音质',
              subtitle: '当前：${settings.audioQuality.label}',
              leading: _icon(Icons.music_note_outlined),
              onTap: () => pickFromDialog<AudioQuality>(
                context,
                title: '默认音质',
                value: settings.audioQuality,
                values: _enumValues(AudioQuality.values, (q) => q.label),
                onSelected: (v) => save(settings.copyWith(audioQuality: v)),
              ),
            )),
        SettingEntry('音频输出设备', (context) {
          final devices = controller.audioDevices;
          String describe(String name) => name == 'auto'
              ? '自动（系统默认）'
              : devices.where((d) => d.name == name).map((d) => d.description.isEmpty ? d.name : d.description).firstOrNull ?? name;
          return NormalItem(
            title: '音频输出设备',
            subtitle: '当前：${describe(settings.audioDevice)}',
            leading: _icon(Icons.speaker_outlined),
            onTap: () => pickFromDialog<String>(
              context,
              title: '音频输出设备',
              value: settings.audioDevice,
              values: [('auto', '自动（系统默认）'), for (final d in devices) if (d.name != 'auto') (d.name, describe(d.name))],
              onSelected: (v) => save(settings.copyWith(audioDevice: v)),
            ),
          );
        }, subtitle: '声卡 耳机 音箱'),
        SettingEntry('音量均衡', (context) => NormalItem(
              title: '音量均衡',
              subtitle: '当前：${audioFilterPresets.where((p) => p.$1 == settings.audioFilter).map((p) => p.$2).firstOrNull ?? '自定义 ${settings.audioFilter}'}',
              leading: _icon(Icons.equalizer_rounded),
              onTap: () => _pickAudioFilter(context, controller),
            ), subtitle: 'loudnorm dynaudnorm af 响度'),
        SettingEntry('画面与音画同步调节', (context) => NormalItem(
              title: '画面与音画同步调节',
              subtitle: settings.picture.isEmpty && settings.audioDelayMs == 0 ? '亮度、对比度、饱和度、伽马、色调、音频延迟' : '已调整',
              leading: _icon(Icons.tune_rounded),
              onTap: () => openPictureSettings(context, controller),
            ), subtitle: '亮度 对比度 饱和度 伽马 色调 音频延迟 audio-delay'),
        SettingEntry('播放来源', (context) => NormalItem(
              title: '播放来源',
              subtitle: '当前：${settings.playbackSource.label}${settings.playbackSource == PlaybackSource.pipedCustom ? ' ${settings.pipedServer}' : ''}。'
                  'Piped 服务器替你从 YouTube 取视频，可避开限速，但它会知道你看了哪个视频；失败、直播或开着字幕时直接连接 YouTube',
              leading: _icon(Icons.dns_outlined),
              onTap: () => pickFromDialog<PlaybackSource>(
                context,
                title: '播放来源',
                value: settings.playbackSource,
                values: _enumValues(PlaybackSource.values, (s) => s.label),
                onSelected: (source) async {
                  if (source != PlaybackSource.pipedCustom) return save(settings.copyWith(playbackSource: source));
                  if (context.mounted) await openPipedServers(context, controller);
                },
              ),
            ), subtitle: 'Piped 服务器 限速 实例 instance'),
        SettingEntry('Piped 服务器', (context) => NormalItem(
              title: 'Piped 服务器',
              subtitle: settings.playbackSource == PlaybackSource.pipedCustom ? '当前：${settings.pipedServer}' : '当前：自动选择最快的服务器。可测速、手动选择，列表每天自动更新',
              leading: _icon(Icons.speed_rounded),
              onTap: () => openPipedServers(context, controller),
            ), subtitle: 'Piped 服务器 测速 列表 更新 instance'),
        SettingEntry('网络代理', (context) {
          final proxy = controller.proxy;
          final now = proxy.url == null ? '当前直接连接' : '当前使用 ${proxy.url}${proxy.isHttp ? '' : '（视频流不支持此类代理，视频流直接连接）'}';
          return NormalItem(
            title: '网络代理',
            subtitle: '${settings.proxyMode.label}。$now',
            leading: _icon(Icons.vpn_lock_outlined),
            onTap: () => pickFromDialog<ProxyMode>(
              context,
              title: '网络代理',
              value: settings.proxyMode,
              values: _enumValues(ProxyMode.values, (m) => m.label),
              onSelected: (mode) async {
                if (mode != ProxyMode.custom) return save(settings.copyWith(proxyMode: mode));
                await _editProxy(context, controller);
              },
            ),
          );
        }, subtitle: 'proxy 代理 Clash v2rayN 系统代理 http-proxy'),
        SettingEntry('缓冲模式', (context) => NormalItem(
              title: '缓冲模式',
              subtitle: '当前：${labelOf(_cacheModes, settings.cacheMode)}。只使用内存，不写入磁盘',
              leading: _icon(Icons.storage_outlined),
              onTap: () => pickFromDialog<String>(context, title: '缓冲模式', value: settings.cacheMode, values: _cacheModes, onSelected: (value) => save(settings.copyWith(cacheMode: value))),
            ), subtitle: '网络缓存'),
        SettingEntry('缓冲大小', (context) => NormalItem(
              title: '缓冲大小',
              subtitle: '当前：${settings.cacheMemoryMb} MB，预读占用的内存上限',
              leading: _icon(Icons.sd_card_outlined),
              onTap: () => pickWithSlider(context, title: '缓冲大小', value: settings.cacheMemoryMb.toDouble(), min: 16, max: 512, divisions: 31, suffix: ' MB', onSelected: (v) => save(settings.copyWith(cacheMemoryMb: v.round()))),
            ), subtitle: '内存上限'),
        SettingEntry('缓冲时长', (context) => NormalItem(
              title: '缓冲时长',
              subtitle: '当前：${settings.cacheSeconds} 秒，最多预读多久的视频',
              leading: _icon(Icons.timer_outlined),
              onTap: () => pickWithSlider(context, title: '缓冲时长', value: settings.cacheSeconds.toDouble(), min: 1, max: 300, divisions: 299, suffix: ' 秒', onSelected: (v) => save(settings.copyWith(cacheSeconds: v.round()))),
            ), subtitle: '预读时间'),
        SettingEntry('视频同步', (context) => NormalItem(
              title: '视频同步',
              subtitle: '当前：${settings.videoSync.mpvValue}，${settings.videoSync.label}（此项即 mpv 的 --video-sync）',
              leading: _icon(Icons.sync_alt_rounded),
              onTap: () => pickFromDialog<VideoSync>(
                context,
                title: '视频同步',
                value: settings.videoSync,
                values: _enumValues(VideoSync.values, (v) => v.label),
                onSelected: (v) => save(settings.copyWith(videoSync: v)),
              ),
            ), subtitle: 'video-sync display-resample'),
        SettingEntry('自动同步', (context) => NormalItem(
              title: '自动同步',
              subtitle: '当前：${settings.autosync == 0 ? '关闭' : settings.autosync}（此项即 mpv 的 --autosync，0 为关闭）',
              leading: _icon(Icons.sync_rounded),
              onTap: () => pickWithSlider(context, title: '自动同步', value: settings.autosync.toDouble(), min: 0, max: 30, divisions: 30, suffix: '', onSelected: (v) => save(controller.settings.copyWith(autosync: v.round()))),
            ), subtitle: 'autosync'),
        SettingEntry('视频缩放算法', (context) => NormalItem(
              title: '视频缩放算法',
              subtitle: '当前：${labelOf(_scaleModes, settings.scale)}',
              leading: _icon(Icons.photo_size_select_large_rounded),
              onTap: () => pickFromDialog<String>(context, title: '视频缩放算法', value: settings.scale, values: _scaleModes, onSelected: (value) => save(settings.copyWith(scale: value))),
            ), subtitle: 'scale 超分辨率'),
        SettingEntry('色带消除', (context) => SwitchItem(
              title: '色带消除',
              subtitle: '减轻渐变中的色带，略增 GPU 负载',
              leading: _icon(Icons.gradient_rounded),
              value: settings.deband,
              onChanged: (value) => save(settings.copyWith(deband: value)),
            ), subtitle: 'deband'),
        SettingEntry('帧插值', (context) => SwitchItem(
              title: '帧插值',
              subtitle: '让画面更平滑，会增加 GPU 负载。下一段视频生效',
              leading: _icon(Icons.animation_rounded),
              value: settings.interpolation,
              onChanged: (value) => save(settings.copyWith(interpolation: value)),
            ), subtitle: 'interpolation'),
        SettingEntry('解码状态', (context) => _DecoderStatus(controller: controller), subtitle: 'GPU 当前解码方式 VP9 AV1 视频扩展'),
        SettingEntry('自定义 mpv 参数', (context) {
          final (options, rejected) = parseMpvConf(settings.mpvConf);
          return NormalItem(
            title: '自定义 mpv 参数',
            subtitle: options.isEmpty ? '按 mpv.conf 格式填写，例如 d3d11va-zero-copy=yes' : '已设置 ${options.length} 项${rejected.isEmpty ? '' : '，${rejected.length} 行无法使用'}',
            leading: _icon(Icons.code_rounded),
            onTap: () => _editMpvConf(context, controller),
          );
        }, subtitle: 'mpv.conf 自定义参数'),
        SettingEntry('高级 libmpv 参数', (context) => _AdvancedOptions(settings: settings, onReset: () => save(PlayerSettings(cachePath: settings.cachePath, decoderResults: settings.decoderResults))), subtitle: '恢复默认设置'),
      ],
    SettingsCategory.play => [
        SettingEntry('倍速设置', (context) => NormalItem(
              title: '倍速设置',
              subtitle: '默认 ${trimSpeed(settings.defaultSpeed)}x，${settings.speeds.length} 档可选',
              leading: _icon(Icons.speed_rounded),
              onTap: () => openPlaySpeed(context, controller),
            ), subtitle: '播放速度'),
        SettingEntry('自动播放', (context) => SwitchItem(
              title: '自动播放',
              subtitle: '打开视频后立即开始播放',
              leading: _icon(Icons.play_arrow_rounded),
              value: prefs.autoPlay,
              onChanged: (v) => savePrefs(prefs.copyWith(autoPlay: v)),
            )),
        SettingEntry('播放顺序', (context) => PopupItem<PlayOrder>(
              title: '播放顺序',
              leading: _icon(Icons.repeat_rounded),
              value: settings.playOrder,
              values: _enumValues(PlayOrder.values, (o) => o.label),
              onSelected: controller.setPlayOrder,
            ), subtitle: '自动连播 循环'),
        SettingEntry('从上次位置继续播放', (context) => SwitchItem(
              title: '从上次位置继续播放',
              subtitle: '再次打开没看完的视频时跳到上次的位置',
              leading: _icon(Icons.history_rounded),
              value: prefs.resumePlayback,
              onChanged: (v) => savePrefs(prefs.copyWith(resumePlayback: v)),
            ), subtitle: '续播 进度'),
        SettingEntry('字幕设置', (context) => NormalItem(
              title: '字幕设置',
              subtitle: '${settings.subtitleMode.label} · ${settings.subtitleLanguage.label} · ${settings.subtitleScale.toStringAsFixed(1)}×',
              leading: _icon(Icons.subtitles_outlined),
              onTap: () => openSubtitleSettings(context, controller),
            ), subtitle: '自动启用字幕 字幕语言 字幕大小'),
        SettingEntry('播放器音量', (context) => NormalItem(
              title: '播放器音量',
              subtitle: '启动时的音量：${settings.defaultVolume}%',
              leading: _icon(Icons.volume_up_outlined),
              onTap: () => pickWithSlider(context, title: '播放器音量', value: settings.defaultVolume.toDouble(), min: 0, max: 100, divisions: 20, suffix: '%', onSelected: (v) => save(settings.copyWith(defaultVolume: v.round()))),
            )),
        SettingEntry('最高音量', (context) => NormalItem(
              title: '最高音量',
              subtitle: '当前：${labelOf(_volumeMaxes, settings.volumeMax)}，超过 100% 可放大声音较小的视频',
              leading: _icon(Icons.campaign_outlined),
              onTap: () => pickFromDialog<int>(context, title: '最高音量', value: settings.volumeMax, values: _volumeMaxes, onSelected: (v) => save(settings.copyWith(volumeMax: v))),
            ), subtitle: '音量增强'),
        SettingEntry('自动全屏', (context) => SwitchItem(
              title: '自动全屏',
              subtitle: '视频开始播放时进入全屏',
              leading: _icon(Icons.fullscreen_rounded),
              value: prefs.autoFullscreen,
              onChanged: (v) => savePrefs(prefs.copyWith(autoFullscreen: v)),
            )),
        SettingEntry('自动退出全屏', (context) => SwitchItem(
              title: '自动退出全屏',
              subtitle: '视频播放结束、没有下一个时退出全屏',
              leading: _icon(Icons.fullscreen_exit_rounded),
              value: prefs.exitFullscreenOnEnd,
              onChanged: (v) => savePrefs(prefs.copyWith(exitFullscreenOnEnd: v)),
            )),
        SettingEntry('最小化时暂停', (context) => SwitchItem(
              title: '最小化时暂停/还原时播放',
              leading: _icon(Icons.minimize_rounded),
              value: prefs.pauseOnMinimize,
              onChanged: (v) => savePrefs(prefs.copyWith(pauseOnMinimize: v)),
            ), subtitle: '后台播放'),
        SettingEntry('延长播放控件显示时间', (context) => NormalItem(
              title: '播放控件显示时间',
              subtitle: '鼠标不动 ${labelOf(_hideTimes, prefs.controlsHideSeconds)} 后隐藏',
              leading: _icon(Icons.touch_app_outlined),
              onTap: () => pickFromDialog<int>(context, title: '播放控件显示时间', value: prefs.controlsHideSeconds, values: _hideTimes, onSelected: (v) => savePrefs(prefs.copyWith(controlsHideSeconds: v))),
            ), subtitle: '控制栏 隐藏'),
        SettingEntry('启用键盘控制', (context) => SwitchItem(
              title: '启用键盘控制',
              subtitle: '空格暂停、方向键快进和音量、F 全屏等',
              leading: _icon(Icons.keyboard_outlined),
              value: prefs.keyboardShortcuts,
              onChanged: (v) => savePrefs(prefs.copyWith(keyboardShortcuts: v)),
            ), subtitle: '快捷键'),
        SettingEntry('快进/快退时长', (context) => NormalItem(
              title: '快进/快退时长',
              subtitle: '← → 方向键：${prefs.seekSeconds} 秒',
              leading: _icon(Icons.fast_forward_outlined),
              enabled: prefs.keyboardShortcuts,
              onTap: () => pickWithSlider(context, title: '快进/快退时长', value: prefs.seekSeconds.toDouble(), min: 1, max: 30, divisions: 29, suffix: ' 秒', onSelected: (v) => savePrefs(prefs.copyWith(seekSeconds: v.round()))),
            ), subtitle: '方向键'),
        SettingEntry('大步快进/快退时长', (context) => NormalItem(
              title: '大步快进/快退时长',
              subtitle: 'J / L 键：${prefs.longSeekSeconds} 秒',
              leading: _icon(Icons.double_arrow_rounded),
              enabled: prefs.keyboardShortcuts,
              onTap: () => pickWithSlider(context, title: '大步快进/快退时长', value: prefs.longSeekSeconds.toDouble(), min: 5, max: 120, divisions: 23, suffix: ' 秒', onSelected: (v) => savePrefs(prefs.copyWith(longSeekSeconds: v.round()))),
            )),
        SettingEntry('音量调节步长', (context) => NormalItem(
              title: '音量调节步长',
              subtitle: '↑ ↓ 方向键和滚轮：每次 ${prefs.volumeStep}%',
              leading: _icon(Icons.volume_down_outlined),
              onTap: () => pickWithSlider(context, title: '音量调节步长', value: prefs.volumeStep.toDouble(), min: 1, max: 20, divisions: 19, suffix: '%', onSelected: (v) => savePrefs(prefs.copyWith(volumeStep: v.round()))),
            )),
        SettingEntry('快捷键说明', (context) => NormalItem(
              title: '快捷键说明',
              subtitle: '查看所有播放器快捷键',
              leading: _icon(Icons.help_outline_rounded),
              onTap: () => showShortcutHelp(context, controller.preferences),
            )),
      ],
    SettingsCategory.style => [
        SettingEntry('主题模式', (context) => PopupItem<ThemeMode>(
              title: '主题模式',
              leading: _icon(Icons.brightness_6_outlined),
              value: appearance.themeMode,
              values: themeModes,
              onSelected: (mode) => saveLooks(appearance.copyWith(themeMode: mode)),
            ), subtitle: '深色 浅色'),
        SettingEntry('纯黑主题', (context) => SwitchItem(
              title: '纯黑主题',
              subtitle: '深色模式使用纯黑背景',
              leading: _icon(Icons.dark_mode_outlined),
              value: appearance.pureBlack,
              onChanged: (v) => saveLooks(appearance.copyWith(pureBlack: v)),
            ), subtitle: 'AMOLED'),
        SettingEntry('应用主题', (context) => NormalItem(
              title: '应用主题',
              subtitle: '当前：${appearance.accentLabel} · ${schemeVariantNames[appearance.schemeVariant]}',
              leading: _icon(Icons.color_lens_outlined),
              trailing: CircleAvatar(radius: 12, backgroundColor: controller.accentColor),
              onTap: () => openColorSelect(context, controller),
            ), subtitle: '主题色 颜色 调色板 动态取色'),
        SettingEntry('App 字体设置', (context) => NormalItem(
              title: 'App 字体设置',
              subtitle: '${fontChoices.where((f) => f.$1 == appearance.fontFamily).map((f) => f.$2).firstOrNull ?? '系统默认'} · 字号 ${(appearance.textScale * 100).round()}%',
              leading: _icon(Icons.text_fields_rounded),
              onTap: () => openFontSettings(context, controller),
            ), subtitle: '字号 字体大小'),
        SettingEntry('页面过渡动画', (context) => NormalItem(
              title: '页面过渡动画',
              subtitle: '当前：${appearance.transition.label}',
              leading: _icon(Icons.animation_outlined),
              onTap: () => pickFromDialog<PageTransition>(
                context,
                title: '页面过渡动画',
                value: appearance.transition,
                values: _enumValues(PageTransition.values, (t) => t.label),
                onSelected: (v) => saveLooks(appearance.copyWith(transition: v)),
              ),
            )),
        SettingEntry('导航栏样式', (context) => PopupItem<NavigationStyle>(
              title: '导航栏样式',
              leading: _icon(Icons.view_sidebar_outlined),
              value: appearance.navigation,
              values: _enumValues(NavigationStyle.values, (n) => n.label),
              onSelected: (v) => saveLooks(appearance.copyWith(navigation: v)),
            ), subtitle: '侧边栏 底栏'),
        SettingEntry('默认启动页', (context) => PopupItem<String>(
              title: '默认启动页',
              leading: _icon(Icons.home_outlined),
              value: prefs.startPage,
              values: startPages,
              onSelected: (v) => savePrefs(prefs.copyWith(startPage: v)),
            )),
        SettingEntry('视频卡片宽度', (context) => NormalItem(
              title: '视频卡片最小宽度',
              subtitle: '当前：${appearance.cardWidth.round()} 像素，越小每行的视频越多',
              leading: _icon(Icons.grid_view_rounded),
              onTap: () => pickWithSlider(context, title: '视频卡片最小宽度', value: appearance.cardWidth, min: 180, max: 420, divisions: 24, suffix: ' 像素', onSelected: (v) => saveLooks(appearance.copyWith(cardWidth: v))),
            ), subtitle: '列宽 列数'),
        SettingEntry('封面图片质量', (context) => NormalItem(
              title: '封面图片质量',
              subtitle: '当前：${appearance.thumbnailQuality.label}',
              leading: _icon(Icons.image_outlined),
              onTap: () => pickFromDialog<ThumbnailQuality>(
                context,
                title: '封面图片质量',
                value: appearance.thumbnailQuality,
                values: _enumValues(ThumbnailQuality.values, (q) => q.label),
                onSelected: (v) => saveLooks(appearance.copyWith(thumbnailQuality: v)),
              ),
            ), subtitle: '缩略图'),
        SettingEntry('视频播放页使用深色主题', (context) => SwitchItem(
              title: '视频播放页使用深色主题',
              leading: _icon(Icons.contrast_rounded),
              value: appearance.darkWatchPage,
              onChanged: (v) => saveLooks(appearance.copyWith(darkWatchPage: v)),
            )),
        SettingEntry('显示底部状态栏', (context) => SwitchItem(
              title: '显示底部状态栏',
              subtitle: '窗口底部的 libmpv 版本和状态信息',
              leading: _icon(Icons.horizontal_rule_rounded),
              value: appearance.showStatusBar,
              onChanged: (v) => saveLooks(appearance.copyWith(showStatusBar: v)),
            )),
      ],
    SettingsCategory.extra => [
        SettingEntry('空降助手', (context) => SwitchItem(
              title: '空降助手',
              subtitle: settings.sponsorBlock ? '已开启 · 跳过 ${settings.sponsorCategories.length} 类片段，点击配置' : '点击配置',
              leading: _icon(Icons.flight_takeoff_rounded),
              value: settings.sponsorBlock,
              onChanged: (v) => save(settings.copyWith(sponsorBlock: v)),
              onTap: () => openSponsorBlock(context, controller),
            ), subtitle: 'SponsorBlock 跳过 赞助 广告'),
        SettingEntry('视频页显示相关视频', (context) => SwitchItem(
              title: '视频页显示相关视频',
              subtitle: '按标题搜索得到；关闭后自动连播只播放队列',
              leading: _icon(Icons.video_library_outlined),
              value: prefs.showRelated,
              onChanged: (v) => savePrefs(prefs.copyWith(showRelated: v)),
            )),
        SettingEntry('默认展开视频简介', (context) => SwitchItem(
              title: '默认展开视频简介',
              leading: _icon(Icons.notes_rounded),
              value: prefs.expandDescription,
              onChanged: (v) => savePrefs(prefs.copyWith(expandDescription: v)),
            )),
        SettingEntry('自动检查组件更新', (context) => SwitchItem(
              title: '自动检查组件更新',
              subtitle: '每天检查一次 libmpv、yt-dlp 和 Deno',
              leading: _icon(Icons.system_update_alt_rounded),
              value: prefs.autoCheckUpdates,
              onChanged: (v) => savePrefs(prefs.copyWith(autoCheckUpdates: v)),
            )),
        SettingEntry('组件管理', (context) => NormalItem(
              title: '组件管理',
              subtitle: 'libmpv ${controller.tools?.libmpv.current?.label ?? '内置'} · yt-dlp ${controller.tools?.ytDlpVersion ?? '未安装'}',
              leading: _icon(Icons.extension_outlined),
              onTap: () => openComponents(context, controller),
            ), subtitle: 'libmpv yt-dlp Deno 检查更新 回退'),
        SettingEntry('缓存路径', (context) => NormalItem(
              title: '缓存路径',
              subtitle: settings.cachePath ?? controller.cacheRoot?.path ?? '正在准备…',
              leading: _icon(Icons.folder_outlined),
              onTap: () => _changeCacheLocation(context, controller),
            ), subtitle: '缓存位置'),
        SettingEntry('清理缓存', (context) => NormalItem(
              title: '清理缓存',
              subtitle: '已占用 ${formatBytes(controller.cacheBytes)}，只清理 YTPlus 创建的缩略图和临时文件',
              leading: _icon(Icons.cleaning_services_outlined),
              onTap: controller.clearCache,
            ), subtitle: '缓存占用'),
        SettingEntry('数据位置', (context) => NormalItem(
              title: '数据位置',
              subtitle: '${controller.directories?.root.path ?? '正在准备…'}\n设置、观看记录、收藏和下载的组件都保存在这里，卸载时会保留',
              leading: _icon(Icons.inventory_2_outlined),
              onTap: controller.directories == null ? null : () => openExternal(controller.directories!.root.path),
            )),
      ],
    SettingsCategory.backup => [
        SettingEntry('导出设置', (context) => NormalItem(
              title: '导出设置',
              subtitle: '保存为 JSON 文件，不含账号、观看记录和本机路径',
              leading: _icon(Icons.upload_file_rounded),
              onTap: () => _exportSettings(context, controller),
            ), subtitle: '备份'),
        SettingEntry('导入设置', (context) => NormalItem(
              title: '导入设置',
              subtitle: '从导出的文件恢复',
              leading: _icon(Icons.download_rounded),
              onTap: () => _importSettings(context, controller),
            ), subtitle: '恢复'),
        SettingEntry('重置所有设置', (context) => NormalItem(
              title: '重置所有设置',
              subtitle: '恢复默认值；观看记录、收藏、播放列表和账号不受影响',
              leading: _icon(Icons.restore_rounded),
              onTap: () async {
                if (await confirmDialog(context, title: '重置所有设置？', content: '播放、外观和隐私设置都会恢复默认值。', confirm: '重置')) await controller.resetSettings();
              },
            ), subtitle: '恢复默认'),
      ],
    SettingsCategory.account => [
        SettingEntry('Google 账号', (context) => AccountSettings(account: controller.account, note: _note(context)), subtitle: '登录、同步订阅和播放列表、退出登录、自定义客户端'),
      ],
    SettingsCategory.about => aboutEntries(controller),
  };
}

String trimSpeed(double speed) => speed.toString().replaceFirst(RegExp(r'\.0$'), '');

TextStyle _note(BuildContext context) => TextStyle(color: context.colors.outline, fontSize: 12, height: 1.5);

Future<void> _exportSettings(BuildContext context, AppController controller) async {
  final now = DateTime.now();
  final name = 'YTPlus_设置_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.json';
  final location = await getSaveLocation(suggestedName: name, acceptedTypeGroups: const [XTypeGroup(label: 'JSON', extensions: ['json'])]);
  if (location == null) return;
  try {
    await XFile.fromData(Uint8List.fromList(utf8.encode(controller.exportSettings())), mimeType: 'application/json', name: name).saveTo(location.path);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('设置已导出')));
  } catch (e) {
    logError('导出设置失败', e);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败：$e')));
  }
}

Future<void> _importSettings(BuildContext context, AppController controller) async {
  final file = await openFile(acceptedTypeGroups: const [XTypeGroup(label: 'JSON', extensions: ['json'])]);
  if (file == null) return;
  final String text;
  try {
    text = await file.readAsString();
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('无法读取文件：$e')));
    return;
  }
  final ok = await controller.importSettings(text);
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? '设置已导入' : '这不是 YTPlus 导出的设置文件')));
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
      // Its own key: an unkeyed tile shares the page's PageStorage slot with
      // the list's scroll offset, and reads that double as its open state.
      key: const PageStorageKey('expand:decoder'),
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
      key: const PageStorageKey('expand:mpv'),
      leading: const Icon(Icons.tune_rounded),
      title: Text('高级 libmpv 参数', style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text('查看实际传给 libmpv 的参数，或恢复默认', style: _subtitle(context)),
      children: [
        option('hwdec', settings.hwdec, '硬件解码方式', '下一段视频'),
        option('scale', settings.scale, '视频缩放算法', '立即'),
        option('deband', settings.deband ? 'yes' : 'no', '色带消除', '立即'),
        option('interpolation', settings.interpolation ? 'yes' : 'no', '帧插值', '下一段视频'),
        option('hwdec-codecs', settings.hwdecCodecs, '硬解编码', '下一段视频'),
        option('d3d11va-zero-copy', settings.d3d11vaZeroCopy ? 'yes' : 'no', 'D3D11VA 零拷贝', '下一段视频'),
        option('vd-lavc-dr', settings.directRendering, '直接解码到显存', '下一段视频'),
        option('video-sync', settings.videoSync.mpvValue, '视频同步', '立即'),
        option('autosync', settings.autosync == 0 ? 'no' : '${settings.autosync}', '自动同步', '立即'),
        option('af', settings.audioFilter.isEmpty ? '（无）' : settings.audioFilter, '音频滤镜', '立即'),
        for (final (key, value) in settings.customOptions.entries.map((e) => (e.key, e.value))) option(key, value, '自定义参数', '立即或下一段视频'),
        option('cache', settings.cacheMode, '网络缓存模式', '立即'),
        option('cache-secs', '${settings.cacheSeconds}', '缓存预读时间', '立即'),
        option('demuxer-max-bytes', '${settings.cacheMemoryMb}MiB', '缓存内存上限', '立即'),
        option('volume-max', '${settings.volumeMax}', '最高音量', '立即'),
        option('audio-device', settings.audioDevice, '音频输出设备', '立即'),
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

Future<void> _pickAudioFilter(BuildContext context, AppController controller) async {
  const custom = '\u0000custom';
  final current = controller.settings.audioFilter;
  final preset = audioFilterPresets.any((p) => p.$1 == current);
  final chosen = await showDialog<String>(
    context: context,
    builder: (context) => SelectDialog<String>(
      title: '音量均衡',
      value: preset ? current : custom,
      values: [...audioFilterPresets, (custom, preset ? '自定义' : '自定义：$current')],
    ),
  );
  if (chosen == null || !context.mounted) return;
  if (chosen != custom) {
    await controller.saveSettings(controller.settings.copyWith(audioFilter: chosen));
    return;
  }
  final text = await showDialog<String>(
    context: context,
    builder: (context) => TextEditDialog(title: '自定义音频滤镜', initialText: preset ? '' : current, hintText: '例如 loudnorm=I=-14:LRA=7:TP=-2', monospace: true),
  );
  if (text != null) await controller.saveSettings(controller.settings.copyWith(audioFilter: text.trim().replaceAll(RegExp(r'[\r\n]'), '')));
}

Future<void> editPipedServer(BuildContext context, AppController controller) async {
  final text = await showDialog<String>(
    context: context,
    builder: (context) => TextEditDialog(
      title: 'Piped 服务器',
      initialText: controller.settings.pipedServer,
      hintText: '例如 https://pipedapi.kavin.rocks',
      helper: (text) {
        final colors = context.colors;
        final server = normalizePipedServer(text);
        return Text(server == null ? '请填写 Piped 的 API 地址（https://…）' : '将使用 $server', style: TextStyle(fontSize: 12, color: server == null ? colors.error : colors.outline));
      },
    ),
  );
  final server = text == null ? null : normalizePipedServer(text);
  if (server != null) await controller.saveSettings(controller.settings.copyWith(playbackSource: PlaybackSource.pipedCustom, pipedServer: server));
}

Future<void> _editProxy(BuildContext context, AppController controller) async {
  final text = await showDialog<String>(
    context: context,
    builder: (context) => TextEditDialog(
      title: '代理地址',
      initialText: controller.settings.proxyAddress,
      hintText: '例如 127.0.0.1:7890 或 socks5://127.0.0.1:7891',
      helper: (text) {
        final colors = context.colors;
        final address = NetworkProxy.normalize(text);
        return Text(
          address == null ? '请填写 主机:端口，可加 http:// 或 socks5:// 前缀' : '将使用 $address${address.startsWith('http://') ? '' : '。视频流只支持 HTTP 代理，会直接连接'}',
          style: TextStyle(fontSize: 12, color: address == null ? colors.error : colors.outline),
        );
      },
    ),
  );
  final address = text == null ? null : NetworkProxy.normalize(text);
  if (address != null) await controller.saveSettings(controller.settings.copyWith(proxyMode: ProxyMode.custom, proxyAddress: address));
}

Future<void> _editMpvConf(BuildContext context, AppController controller) async {
  final text = await showDialog<String>(
    context: context,
    builder: (context) => TextEditDialog(
      title: '自定义 mpv 参数',
      initialText: controller.settings.mpvConf,
      hintText: '# 每行一个，和 mpv.conf 相同\nd3d11va-zero-copy=yes\nhwdec-codecs = h264,vc1,hevc,vp8,vp9,av1,prores,ffv1\nvd-lavc-dr = auto',
      monospace: true,
      maxLines: 14,
      helper: (text) {
        final (options, rejected) = parseMpvConf(text);
        final colors = context.colors;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('可用 ${options.length} 项，在其它设置之后应用。部分参数下一段视频或重启后生效。', style: TextStyle(fontSize: 12, color: colors.outline)),
          for (final (line, reason) in rejected) Text('不会应用：$line（$reason）', style: TextStyle(fontSize: 12, color: colors.error)),
        ]);
      },
    ),
  );
  if (text != null) await controller.saveSettings(controller.settings.copyWith(mpvConf: text));
}

TextStyle _subtitle(BuildContext context) => Theme.of(context).textTheme.labelMedium!.copyWith(color: context.colors.outline);
