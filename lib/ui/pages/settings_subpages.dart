// Settings sub-pages adapted from PiliNara (lib/pages/setting/pages/
// play_speed_set.dart, color_select.dart, font_setting.dart, logs.dart,
// lib/pages/setting/widgets/ and lib/pages/about/view.dart).
//
// PiliNara: https://github.com/Starfallan/PiliNara
// Copyright (C) PiliNara contributors.
// Adapted for YTPlus under the GNU General Public License, version 3 or
// later. Changes: the pages read and save YTPlus's settings through
// AppController instead of PiliNara's storage, GetX and SmartDialog are
// removed, and the Bilibili-only options (danmaku, long-press speed,
// dynamic colour on Android) are dropped or replaced by Windows ones.

import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app_log.dart';
import '../../appearance_settings.dart';
import '../../player_settings.dart';
import '../../widgets/pilinara_settings_tiles.dart';
import '../common.dart';
import '../theme.dart';
import 'settings_sections.dart';

const _repository = 'https://github.com/0x696c757a696f/ytplus';

/// Pushes a sub-page that rebuilds whenever [controller] changes.
Future<void> _push(BuildContext context, AppController controller, String title, List<Widget> Function(BuildContext context) children, {List<Widget>? actions}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(title), actions: actions),
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => ListView(padding: const EdgeInsets.only(bottom: 40), children: children(context)),
        ),
      ),
    ));

Widget _header(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall!.copyWith(color: context.colors.primary)),
    );

Widget _tip(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, size: 16, color: context.colors.outline),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: context.colors.outline, fontSize: 12, height: 1.5))),
      ]),
    );

// 隐私设置 › 屏蔽频道

Future<void> openBlockedChannels(BuildContext context, AppController controller) => _push(context, controller, '屏蔽频道', (context) {
      final channels = controller.preferences.blockedChannels;
      return [
        if (channels.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(child: Text('还没有屏蔽任何频道。\n在视频卡片的右键菜单里选“屏蔽此频道”即可添加。', textAlign: TextAlign.center, style: TextStyle(color: context.colors.outline, height: 1.6))),
          ),
        for (final channel in channels)
          ListTile(
            leading: const Icon(Icons.person_off_outlined),
            title: Text(channel.name.isEmpty ? channel.id : channel.name),
            subtitle: Text(channel.id, style: TextStyle(color: context.colors.outline, fontSize: 12)),
            trailing: TextButton(onPressed: () => controller.unblockChannel(channel.id), child: const Text('移除')),
          ),
        _tip(context, '屏蔽的频道不会出现在首页、搜索、相关视频和订阅动态中。名单只保存在本机。'),
      ];
    });

// 播放设置 › 倍速设置 (PiliNara's play_speed_set.dart)

Future<void> openPlaySpeed(BuildContext context, AppController controller) {
  void save(PlayerSettings next) => controller.saveSettings(next);

  Future<void> add(BuildContext context) async {
    final text = TextEditingController();
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加倍速'),
        content: TextField(
          controller: text,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: '自定义倍速', helperText: '0.1 到 5 之间'),
          onSubmitted: (v) => Navigator.pop(context, double.tryParse(v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('取消', style: TextStyle(color: context.colors.outline))),
          TextButton(onPressed: () => Navigator.pop(context, double.tryParse(text.text)), child: const Text('确认')),
        ],
      ),
    );
    text.dispose();
    if (value == null) return;
    if (value < 0.1 || value > 5) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('倍速需在 0.1 到 5 之间')));
      return;
    }
    final speed = (value * 100).round() / 100;
    final speeds = controller.settings.speeds;
    if (speeds.contains(speed)) return;
    save(controller.settings.copyWith(speeds: [...speeds, speed]..sort()));
  }

  Future<void> edit(BuildContext context, double speed) async {
    final settings = controller.settings;
    final action = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.all(12), child: Text('${trimSpeed(speed)}x', style: Theme.of(context).textTheme.titleMedium)),
          ListTile(leading: const Icon(Icons.check_circle_outline), title: const Text('设置为默认倍速'), onTap: () => Navigator.pop(context, 0)),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('删除该项'),
            enabled: settings.speeds.length > 1 && speed != settings.defaultSpeed,
            onTap: () => Navigator.pop(context, 1),
          ),
        ]),
      ),
    );
    if (action == 0) save(controller.settings.copyWith(defaultSpeed: speed));
    if (action == 1) save(controller.settings.copyWith(speeds: [...controller.settings.speeds]..remove(speed)));
  }

  return _push(
    context,
    controller,
    '倍速设置',
    actions: [
      Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            if (await confirmDialog(context, title: '重置倍速？', content: '恢复默认的倍速列表，默认倍速改回 1x。', confirm: '重置')) {
              save(controller.settings.copyWith(speeds: defaultSpeeds, defaultSpeed: 1));
            }
          },
          child: const Text('重置'),
        ),
      ),
      const SizedBox(width: 8),
    ],
    (context) {
      final settings = controller.settings;
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('点击下方按钮设置默认（首选）倍速或删除', style: TextStyle(color: context.colors.outline)),
        ),
        ListTile(title: const Text('默认倍速'), subtitle: Text('${trimSpeed(settings.defaultSpeed)}x')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          child: Row(children: [
            Text('倍速列表', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton(onPressed: () => add(context), child: const Text('添加')),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final speed in settings.speeds)
              speed == settings.defaultSpeed
                  ? FilledButton(onPressed: () => edit(context, speed), child: Text('${trimSpeed(speed)}x'))
                  : FilledButton.tonal(onPressed: () => edit(context, speed), child: Text('${trimSpeed(speed)}x')),
          ]),
        ),
        _tip(context, '播放器底栏的倍速菜单使用这里的列表。'),
      ];
    },
  );
}

// 播放设置 › 字幕设置

Future<void> openSubtitleSettings(BuildContext context, AppController controller) => _push(context, controller, '字幕设置', (context) {
      final settings = controller.settings;
      void save(PlayerSettings next) => controller.saveSettings(next);
      return [
        PopupItem<SubtitleMode>(
          title: '自动启用字幕',
          leading: const Icon(Icons.subtitles_outlined),
          value: settings.subtitleMode,
          values: [for (final m in SubtitleMode.values) (m, m.label)],
          onSelected: (v) => save(settings.copyWith(subtitleMode: v)),
        ),
        PopupItem<SubtitleLanguage>(
          title: '首选字幕语言',
          leading: const Icon(Icons.translate_rounded),
          value: settings.subtitleLanguage,
          values: [for (final l in SubtitleLanguage.values) (l, l.label)],
          onSelected: (v) => save(settings.copyWith(subtitleLanguage: v)),
        ),
        _header(context, '样式'),
        SwitchItem(
          title: '由 mpv 绘制字幕（libass）',
          subtitle: '支持特效字幕；关闭时由界面绘制，更省资源。重启后生效',
          leading: const Icon(Icons.layers_outlined),
          value: settings.libassSubtitles,
          onChanged: (v) => save(settings.copyWith(libassSubtitles: v)),
        ),
        NormalItem(
          title: '字幕大小',
          subtitle: '当前：${settings.subtitleScale.toStringAsFixed(1)}×',
          leading: const Icon(Icons.format_size_rounded),
          onTap: () => pickWithSlider(context, title: '字幕大小', value: settings.subtitleScale, min: 0.5, max: 3, divisions: 25, suffix: '×', onSelected: (v) => save(controller.settings.copyWith(subtitleScale: (v * 10).round() / 10))),
        ),
        NormalItem(
          title: '字幕位置',
          subtitle: '当前：${settings.subtitlePosition}%（100 为画面底部）',
          leading: const Icon(Icons.vertical_align_bottom_rounded),
          onTap: () => pickWithSlider(context, title: '字幕位置', value: settings.subtitlePosition.toDouble(), min: 0, max: 100, divisions: 100, suffix: '%', onSelected: (v) => save(controller.settings.copyWith(subtitlePosition: v.round()))),
        ),
        NormalItem(
          title: '描边粗细',
          subtitle: '当前：${settings.subtitleBorder.toStringAsFixed(1)}',
          leading: const Icon(Icons.border_style_rounded),
          onTap: () => pickWithSlider(context, title: '描边粗细', value: settings.subtitleBorder, min: 0, max: 8, divisions: 16, suffix: '', onSelected: (v) => save(controller.settings.copyWith(subtitleBorder: v))),
        ),
        SwitchItem(
          title: '背景色块',
          subtitle: '在字幕后面加半透明黑底，替代描边',
          leading: const Icon(Icons.rectangle_outlined),
          value: settings.subtitleBackground,
          onChanged: (v) => save(settings.copyWith(subtitleBackground: v)),
        ),
        SwitchItem(
          title: '粗体',
          leading: const Icon(Icons.format_bold_rounded),
          value: settings.subtitleBold,
          onChanged: (v) => save(settings.copyWith(subtitleBold: v)),
        ),
        _tip(context, '字幕由 yt-dlp 获取，没有人工字幕时使用自动生成的字幕。语言和启用方式从下一个视频开始生效，样式立即生效。'),
      ];
    });

// 其它设置 › 空降助手

Future<void> openSponsorBlock(BuildContext context, AppController controller) => _push(context, controller, '空降助手', (context) {
      final settings = controller.settings;
      void save(PlayerSettings next) => controller.saveSettings(next);
      return [
        SwitchItem(
          title: '开启空降助手',
          subtitle: '自动跳过赞助、自我推广等片段',
          leading: const Icon(Icons.flight_takeoff_rounded),
          value: settings.sponsorBlock,
          onChanged: (v) => save(settings.copyWith(sponsorBlock: v)),
        ),
        SwitchItem(
          title: '跳过时显示提示',
          leading: const Icon(Icons.notifications_none_rounded),
          value: settings.sponsorNotice,
          enabled: settings.sponsorBlock,
          onChanged: (v) => save(settings.copyWith(sponsorNotice: v)),
        ),
        _header(context, '跳过的片段类型'),
        for (final MapEntry(key: category, value: (name, description)) in sponsorCategoryNames.entries)
          CheckboxListTile(
            title: Text(name),
            subtitle: Text(description, style: TextStyle(color: context.colors.outline, fontSize: 12)),
            value: settings.sponsorCategories.contains(category),
            enabled: settings.sponsorBlock,
            onChanged: (v) {
              final next = {...controller.settings.sponsorCategories};
              v == true ? next.add(category) : next.remove(category);
              save(controller.settings.copyWith(sponsorCategories: next));
            },
          ),
        _tip(context, '片段数据来自 SponsorBlock 社区（sponsor.ajay.app）。查询时只发送视频 ID 哈希值的前 4 位，不发送账号或观看记录。'),
      ];
    });

// 外观设置 › 应用主题 (PiliNara's color_select.dart)

Future<void> openColorSelect(BuildContext context, AppController controller) => _push(context, controller, '选择应用主题', (context) {
      final appearance = controller.appearance;
      final brightness = Theme.of(context).brightness;
      void save(AppearanceSettings next) => controller.saveAppearance(next);
      ColorScheme schemeOf(Color seed) => ColorScheme.fromSeed(seedColor: seed, brightness: brightness, dynamicSchemeVariant: appearance.schemeVariant);
      Widget swatch(Color seed, String label, bool selected, VoidCallback onTap) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Column(children: [
              ColorPalette(colorScheme: schemeOf(seed), selected: selected),
              const SizedBox(height: 3),
              Text(label, style: TextStyle(fontSize: 12, color: selected ? null : context.colors.outline)),
            ]),
          );
      final windows = controller.windowsAccent;
      return [
        PopupItem<ThemeMode>(
          title: '主题模式',
          leading: const Icon(Icons.flashlight_on_outlined),
          value: appearance.themeMode,
          values: themeModes,
          onSelected: (mode) => save(appearance.copyWith(themeMode: mode)),
        ),
        PopupItem<DynamicSchemeVariant>(
          title: '调色板风格',
          leading: const Icon(Icons.palette_outlined),
          value: appearance.schemeVariant,
          values: [for (final e in schemeVariantNames.entries) (e.key, e.value)],
          onSelected: (v) => save(appearance.copyWith(schemeVariant: v)),
        ),
        ListTile(
          title: const Text('跟随 Windows 强调色'),
          subtitle: Text(windows == null ? '无法读取系统强调色' : '在 Windows 设置 › 个性化 › 颜色 中更改', style: TextStyle(color: context.colors.outline, fontSize: 12)),
          enabled: windows != null,
          leading: Checkbox(
            value: appearance.systemAccent,
            onChanged: windows == null ? null : (v) => save(appearance.copyWith(systemAccent: v ?? false)),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
          ),
          onTap: windows == null ? null : () => save(appearance.copyWith(systemAccent: !appearance.systemAccent)),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: appearance.systemAccent && windows != null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(spacing: 22, runSpacing: 18, alignment: WrapAlignment.center, children: [
                    swatch(Color(appearance.customAccent), '自定义', appearance.accentIndex < 0, () async {
                      final color = await showDialog<Color>(
                        context: context,
                        builder: (context) => AlertDialog(
                          clipBehavior: Clip.hardEdge,
                          contentPadding: const EdgeInsets.symmetric(vertical: 16),
                          title: const Text('自定义颜色'),
                          content: SlideColorPicker(color: Color(appearance.customAccent)),
                        ),
                      );
                      if (color != null) save(controller.appearance.copyWith(accentIndex: -1, customAccent: color.toARGB32()));
                    }),
                    for (var i = 0; i < accentChoices.length; i++)
                      swatch(accentChoices[i].$2, accentChoices[i].$1, appearance.accentIndex == i, () => save(controller.appearance.copyWith(accentIndex: i))),
                  ]),
                ),
        ),
        _header(context, '预览'),
        IgnorePointer(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('标题文字', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('次要说明文字', style: TextStyle(color: context.colors.outline)),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    FilledButton(onPressed: () {}, child: const Text('订阅')),
                    FilledButton.tonal(onPressed: () {}, child: const Text('收藏')),
                    OutlinedButton(onPressed: () {}, child: const Text('分享')),
                    Switch(value: true, onChanged: (_) {}),
                  ]),
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(value: 0.6),
                ]),
              ),
            ),
          ),
        ),
      ];
    });

// 外观设置 › App 字体设置 (PiliNara's font_setting.dart)

Future<void> openFontSettings(BuildContext context, AppController controller) => _push(context, controller, 'App 字体设置', (context) {
      final appearance = controller.appearance;
      void save(AppearanceSettings next) => controller.saveAppearance(next);
      final theme = Theme.of(context);
      return [
        _header(context, '字体'),
        RadioGroup<String?>(
          groupValue: appearance.fontFamily,
          onChanged: (v) => save(v == null ? appearance.copyWith(clearFontFamily: true) : appearance.copyWith(fontFamily: v)),
          child: Column(children: [
            for (final (family, label) in fontChoices)
              RadioListTile<String?>(
                value: family,
                title: Text(label, style: TextStyle(fontFamily: family)),
                subtitle: family == null ? null : Text(family, style: TextStyle(color: context.colors.outline, fontSize: 12)),
              ),
          ]),
        ),
        _header(context, '字号'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            Expanded(
              child: Slider(
                min: 0.8,
                max: 1.4,
                divisions: 12,
                value: appearance.textScale,
                label: '${(appearance.textScale * 100).round()}%',
                onChanged: (v) => save(controller.appearance.copyWith(textScale: (v * 100).round() / 100)),
              ),
            ),
            SizedBox(width: 48, child: Text('${(appearance.textScale * 100).round()}%')),
            TextButton(onPressed: () => save(controller.appearance.copyWith(textScale: 1, fontFamily: bundledFont)), child: const Text('重置')),
          ]),
        ),
        _header(context, '预览'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('YTPlus 让 YouTube 在 Windows 上更好用', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('The quick brown fox jumps over the lazy dog. 0123456789', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 6),
            Text('频道名称 · 12 万次观看 · 3 天前', style: theme.textTheme.labelMedium!.copyWith(color: context.colors.outline)),
          ]),
        ),
        _tip(context, '注：Noto Sans CJK SC 随 YTPlus 安装（SIL OFL 1.1 许可），其余是 Windows 自带的中文字体，部分字体可能缺少某些字重。'),
      ];
    });

// 视频设置 › 画面与音画同步调节 (PiliNara's video picture panel)

Future<void> openPictureSettings(BuildContext context, AppController controller) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => _PictureSettingsPage(controller: controller)),
    );

class _PictureSettingsPage extends StatefulWidget {
  const _PictureSettingsPage({required this.controller});
  final AppController controller;

  @override
  State<_PictureSettingsPage> createState() => _PictureSettingsPageState();
}

class _PictureSettingsPageState extends State<_PictureSettingsPage> {
  late final Map<String, int> _picture = {...widget.controller.settings.picture};
  late int _audioDelay = widget.controller.settings.audioDelayMs;

  void _save() => widget.controller.saveSettings(widget.controller.settings.copyWith(picture: {
        for (final entry in _picture.entries)
          if (entry.value != 0) entry.key: entry.value,
      }, audioDelayMs: _audioDelay));

  Widget _slider(String label, int value, int min, int max, String suffix, ValueChanged<int> onChanged, VoidCallback onReset) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(children: [
          SizedBox(width: 72, child: Text(label)),
          Expanded(
            child: Slider(
              value: value.toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              label: '$value$suffix',
              onChanged: (v) => onChanged(v.round()),
              onChangeEnd: (_) => _save(),
            ),
          ),
          SizedBox(width: 64, child: Text('$value$suffix', textAlign: TextAlign.end)),
          IconButton(tooltip: '重置', icon: const Icon(Icons.restart_alt_rounded, size: 20), onPressed: value == 0 ? null : onReset),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('画面与音画同步调节'),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _picture.clear();
                _audioDelay = 0;
              });
              for (final (key, _) in pictureProperties) {
                controller.previewProperty(key, '0');
              }
              controller.previewProperty('audio-delay', '0');
              _save();
            },
            child: const Text('全部重置'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        _header(context, '画面'),
        for (final (key, label) in pictureProperties)
          _slider(label, _picture[key] ?? 0, -100, 100, '', (v) {
            setState(() => _picture[key] = v);
            controller.previewProperty(key, '$v');
          }, () {
            setState(() => _picture[key] = 0);
            controller.previewProperty(key, '0');
            _save();
          }),
        _header(context, '音画同步'),
        _slider('音频延迟', _audioDelay, -2000, 2000, ' ms', (v) {
          setState(() => _audioDelay = (v / 10).round() * 10);
          controller.previewProperty('audio-delay', '${_audioDelay / 1000}');
        }, () {
          setState(() => _audioDelay = 0);
          controller.previewProperty('audio-delay', '0');
          _save();
        }),
        _tip(context, '拖动时立即在正在播放的视频上预览。音频延迟为正时声音推后，为负时声音提前。这些值对之后的所有视频都生效。'),
      ]),
    );
  }
}

// 其它设置 › 组件管理

Future<void> openComponents(BuildContext context, AppController controller) => _push(context, controller, '组件管理', (context) {
      final tools = controller.tools;
      if (tools == null || !controller.ready) return [const NormalItem(title: '正在准备组件…')];
      final libmpv = tools.libmpv;
      final current = libmpv.current;
      final next = libmpv.selected;
      final pendingRestart = next != null && next != current;
      return [
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
          subtitle: '只从官方 GitHub Release 下载并校验 SHA-256，重启后启用',
          leading: const Icon(Icons.system_update_alt_rounded),
          enabled: !controller.checking,
          onTap: controller.checkUpdates,
        ),
        _tip(context, '新 libmpv 出错时会自动改回内置版本。yt-dlp 更新后若无法播放，可以回退到上一版。'),
      ];
    });

// 关于 (PiliNara's about/view.dart)

List<SettingEntry> aboutEntries(AppController controller) => [
      SettingEntry('版本', (context) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(children: [
              Icon(Icons.smart_display_rounded, size: 72, color: context.colors.primary),
              const SizedBox(height: 4),
              Text('YTPlus', style: Theme.of(context).textTheme.titleMedium!.copyWith(height: 2)),
              Text('使用 Flutter 和 mpv 开发的 YouTube 第三方客户端', style: TextStyle(color: context.colors.outline)),
              const SizedBox(height: 8),
              ListTile(
                title: const Text('当前版本'),
                leading: const Icon(Icons.commit_outlined),
                trailing: Text(appVersion, style: TextStyle(fontSize: 14, color: context.colors.outline)),
                onTap: () => copyText(context, appVersion, '版本号已复制'),
              ),
            ]),
          ), subtitle: '当前版本 更新'),
      SettingEntry('检查更新', (context) => NormalItem(
            title: '检查更新',
            subtitle: '打开 GitHub 发布页下载新版本',
            leading: const Icon(Icons.update_rounded),
            onTap: () => openExternal('$_repository/releases'),
          ), subtitle: '发布页 新版本'),
      SettingEntry('源代码', (context) => NormalItem(
            title: 'Github 仓库',
            subtitle: 'github.com/0x696c757a696f/ytplus',
            leading: const Icon(Icons.code_rounded),
            onTap: () => openExternal(_repository),
          ), subtitle: 'GitHub 源代码'),
      SettingEntry('问题反馈', (context) => NormalItem(
            title: '问题反馈',
            subtitle: '在 GitHub 提交 issue，请附上诊断信息和错误日志',
            leading: const Icon(Icons.feedback_outlined),
            onTap: () => openExternal('$_repository/issues'),
          ), subtitle: 'issue bug'),
      SettingEntry('错误日志', (context) => NormalItem(
            title: '错误日志',
            subtitle: '只保存在本机，不记录登录凭据和视频流地址',
            leading: const Icon(Icons.bug_report_outlined),
            onTap: () => openLogs(context, controller),
          ), subtitle: '日志 log'),
      SettingEntry('复制诊断信息', (context) => NormalItem(
            title: '复制诊断信息',
            subtitle: '版本、系统、显卡、组件和播放设置',
            leading: const Icon(Icons.content_copy_rounded),
            onTap: () => copyText(context, controller.diagnostics(), '诊断信息已复制'),
          ), subtitle: '反馈 问题'),
      SettingEntry('开源许可', (context) => NormalItem(
            title: '开源许可',
            subtitle: 'GPLv3；部分界面改编自 PiliNara，播放基于 mpv、media_kit 和 yt-dlp',
            leading: const Icon(Icons.gavel_rounded),
            onTap: () => showLicensePage(context: context, applicationName: 'YTPlus', applicationVersion: appVersion),
          ), subtitle: 'PiliNara mpv media_kit yt-dlp license'),
    ];

// 关于 › 错误日志 (PiliNara's logs.dart)

Future<void> openLogs(BuildContext context, AppController controller) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (context) => _LogsPage(controller: controller)));

class _LogsPage extends StatefulWidget {
  const _LogsPage({required this.controller});
  final AppController controller;

  @override
  State<_LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<_LogsPage> {
  String? _text;

  Directory? get _directory => widget.controller.directories?.logs;

  File? _file(String name) => _directory == null ? null : File('${_directory!.path}${Platform.pathSeparator}$name');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final parts = <String>[];
    for (final name in const ['ytplus.old.log', 'ytplus.log']) {
      try {
        final file = _file(name);
        if (file != null && await file.exists()) parts.add(await file.readAsString());
      } on FileSystemException {
        // An unreadable log is shown as empty.
      }
    }
    if (mounted) setState(() => _text = parts.join());
  }

  Future<void> _clear() async {
    if (!await confirmDialog(context, title: '清空日志？', content: '删除本机保存的 YTPlus 日志。', confirm: '清空')) return;
    for (final name in const ['ytplus.old.log', 'ytplus.log']) {
      try {
        final file = _file(name);
        if (file != null && await file.exists()) await file.writeAsString('');
      } on FileSystemException {
        // Keep going; the rest of the log is still cleared.
      }
    }
    await _load();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已清空')));
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    final lines = text == null ? const <String>[] : text.split('\n').where((l) => l.isNotEmpty).toList().reversed.toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志'),
        actions: [
          PopupMenuButton<int>(
            onSelected: (value) => switch (value) {
              0 => copyText(context, text ?? '', '复制成功'),
              1 => openExternal('$_repository/issues'),
              2 => _directory == null ? null : openExternal(_directory!.path),
              _ => _clear(),
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 0, child: Text('复制日志')),
              PopupMenuItem(value: 1, child: Text('错误反馈')),
              PopupMenuItem(value: 2, child: Text('打开日志文件夹')),
              PopupMenuItem(value: 3, child: Text('清空日志')),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: text == null
          ? const Center(child: CircularProgressIndicator())
          : lines.isEmpty
              ? Center(child: Text('暂无日志', style: TextStyle(color: context.colors.outline)))
              : SelectionArea(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                    itemCount: lines.length,
                    separatorBuilder: (context, i) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final line = lines[i];
                      final space = line.indexOf(' ');
                      final time = space > 0 ? line.substring(0, space).replaceFirst('T', ' ').split('.').first : '';
                      final rest = space > 0 ? line.substring(space + 1) : line;
                      final error = rest.startsWith('ERROR') || rest.startsWith('错误');
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (time.isNotEmpty) Text(time, style: TextStyle(fontSize: 12, color: context.colors.outline)),
                          Text(rest, style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: error ? context.colors.error : null)),
                        ]),
                      );
                    },
                  ),
                ),
    );
  }
}
