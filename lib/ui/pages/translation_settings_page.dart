import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../l10n/l10n.dart';
import '../../player_settings.dart' show SubtitleLanguage, interfaceTranslationLanguage;
import '../../translation.dart';
import '../../translation_services.dart';
import '../../widgets/pilinara_settings_tiles.dart';
import '../app_icons.dart';
import '../translatable.dart' show TranslationView;

/// 设置 › 翻译与 AI: the service behind 翻译 and translated subtitles, and
/// the one AI interface that AI 翻译 and AI 总结 share.
Future<void> openTranslationSettings(BuildContext context, AppController controller) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(tr('翻译与 AI'))),
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => ListView(padding: const EdgeInsets.only(bottom: 40), children: _items(context, controller)),
        ),
      ),
    ));

List<Widget> _items(BuildContext context, AppController controller) {
  final prefs = controller.preferences;
  final config = prefs.translation;
  final service = config.service;
  final colors = Theme.of(context).colorScheme;
  void saveConfig(TranslationConfig Function(TranslationConfig) change) {
    final now = controller.preferences;
    controller.savePreferences(now.copyWith(translation: change(now.translation)));
  }

  Widget header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall!.copyWith(color: colors.primary)),
      );
  Widget tip(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(AppIcons.info, size: 16, color: colors.outline),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: colors.outline, fontSize: 12, height: 1.5))),
        ]),
      );
  Widget keyItem(TranslationService of, {bool optional = false}) {
    final saved = controller.translationKeys[of.name] ?? '';
    return NormalItem(
      title: optional ? tr('API 密钥（可选）') : tr('API 密钥'),
      subtitle: saved.isEmpty ? tr('未填写') : tr('已填写（{0}）', [_masked(saved)]),
      leading: const Icon(AppIcons.keyFill),
      onTap: () async {
        final typed = await showDialog<String>(context: context, builder: (context) => _KeyDialog(title: tr('{0} 的 API 密钥', [of.label]), initial: saved));
        if (typed != null) await controller.saveTranslationKey(of, typed);
      },
    );
  }

  Widget textItem(String title, String value, String shown, IconData icon, String hint, void Function(String) onSaved, {int maxLines = 1}) => NormalItem(
        title: title,
        subtitle: shown,
        leading: Icon(icon),
        onTap: () async {
          final typed = await showDialog<String>(
            context: context,
            builder: (context) => TextEditDialog(title: title, initialText: value, hintText: hint, maxLines: maxLines, monospace: maxLines > 1),
          );
          if (typed != null) onSaved(maxLines > 1 ? typed.trim() : typed.trim().replaceAll(RegExp(r'\s'), ''));
        },
      );

  final ai = AiTranslator.aiPresets.firstWhere((p) => p.id == config.aiPreset, orElse: () => AiTranslator.aiPresets.first);
  return [
    PopupItem<TranslationService>(
      title: tr('翻译服务'),
      leading: const Icon(AppIcons.translate),
      value: service,
      values: [for (final s in TranslationService.values) (s, s.label)],
      onSelected: (v) => saveConfig((c) => c.copyWith(service: v)),
    ),
    PopupItem<String>(
      title: tr('翻译目标语言'),
      leading: const Icon(AppIcons.translate),
      value: prefs.translateLanguage,
      values: [('', tr('跟随系统语言（{0}）', [SubtitleLanguage.auto.translation.label])), for (final l in TranslationLanguage.all) (l.code, l.label)],
      onSelected: (v) => controller.savePreferences(controller.preferences.copyWith(translateLanguage: v)),
    ),
    SwitchItem(
      title: tr('字幕也用这个服务翻译'),
      subtitle: service == TranslationService.google
          ? tr('选了其它翻译服务后可用；默认使用 YouTube 自带的自动翻译')
          : tr('关闭时使用 YouTube 自带的自动翻译，YouTube 拒绝时才用这个服务'),
      leading: const Icon(AppIcons.subtitles),
      value: prefs.subtitlesByService && service != TranslationService.google,
      enabled: service != TranslationService.google,
      onChanged: (v) => controller.savePreferences(controller.preferences.copyWith(subtitlesByService: v)),
    ),
    if (service == TranslationService.microsoft) ...[
      header(tr('微软翻译')),
      keyItem(service, optional: true),
      if ((controller.translationKeys[service.name] ?? '').isNotEmpty)
        textItem(tr('区域'), config.microsoftRegion, config.microsoftRegion.isEmpty ? tr('全局（未填写）') : config.microsoftRegion, AppIcons.globe, tr('Azure 资源所在区域，如 eastasia'), (v) => saveConfig((c) => c.copyWith(microsoftRegion: v))),
      tip(tr('不填密钥时使用 Microsoft Edge 网页翻译用的免费接口；填了 Azure 密钥则走正式接口。')),
    ],
    if (service == TranslationService.deeplx) ...[
      header('DeepLX'),
      textItem(tr('服务器地址'), config.deeplxServer, config.deeplxServer.isEmpty ? tr('未填写') : config.deeplxServer, AppIcons.hardDrives, tr('例如 http://localhost:1188/translate'), (v) => saveConfig((c) => c.copyWith(deeplxServer: v))),
      keyItem(service, optional: true),
      tip(tr('DeepLX 是开源的 DeepL 网页接口转发服务，可以自己部署；只使用你信任的服务器。')),
    ],
    if (service == TranslationService.baidu) ...[
      header(tr('百度翻译')),
      textItem('APP ID', config.baiduAppId, config.baiduAppId.isEmpty ? tr('未填写') : config.baiduAppId, AppIcons.identificationBadge, tr('百度翻译开放平台的 APP ID'), (v) => saveConfig((c) => c.copyWith(baiduAppId: v))),
      keyItem(service),
    ],
    if (service == TranslationService.deepl) ...[
      header('DeepL'),
      keyItem(service),
      tip(tr('免费版密钥以 :fx 结尾，会自动使用免费接口。')),
    ],
    if (service == TranslationService.libre) ...[
      header('LibreTranslate'),
      textItem(tr('服务器地址'), config.libreServer, config.libreServer.isEmpty ? tr('未填写') : config.libreServer, AppIcons.hardDrives, tr('例如 https://libretranslate.com'), (v) => saveConfig((c) => c.copyWith(libreServer: v))),
      keyItem(service, optional: true),
    ],
    const SizedBox(height: 8),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(alignment: Alignment.centerLeft, child: _TestButton(controller: controller)),
    ),
    header(tr('AI 接口')),
    tip(tr('AI 翻译和 AI 总结共用这一个接口，支持 OpenAI 兼容的 /chat/completions。只在你使用 AI 翻译或点“AI 总结”时才发送文字。')),
      PopupItem<String>(
        title: tr('服务商'),
        leading: const Icon(AppIcons.graph),
        value: ai.id,
        values: [for (final p in AiTranslator.aiPresets) (p.id, p.label)],
        // A preset's own address and model replace those typed for another.
        onSelected: (v) => saveConfig((c) => c.copyWith(aiPreset: v, aiBaseUrl: '', aiModel: '')),
      ),
      textItem(tr('接口地址'), config.aiBaseUrl, config.effectiveAiBaseUrl.isEmpty ? tr('未填写') : config.effectiveAiBaseUrl, AppIcons.link, ai.baseUrl.isEmpty ? tr('OpenAI 兼容接口，如 https://example.com/v1') : ai.baseUrl, (v) => saveConfig((c) => c.copyWith(aiBaseUrl: v))),
      NormalItem(
        title: tr('模型'),
        subtitle: config.effectiveAiModel.isEmpty ? tr('未填写') : config.effectiveAiModel,
        leading: const Icon(AppIcons.cpuFill),
        trailing: IconButton(
          tooltip: tr('从接口获取模型列表'),
          icon: const Icon(AppIcons.listDashes),
          onPressed: () => _pickModel(context, controller, (v) => saveConfig((c) => c.copyWith(aiModel: v))),
        ),
        onTap: () async {
          final typed = await showDialog<String>(
            context: context,
            builder: (context) => TextEditDialog(title: tr('模型'), initialText: config.aiModel, hintText: ai.model.isEmpty ? tr('模型名') : ai.model),
          );
          if (typed != null) saveConfig((c) => c.copyWith(aiModel: typed.trim()));
        },
      ),
      keyItem(TranslationService.ai, optional: ai.id == 'ollama' || ai.id == 'custom'),
    const SizedBox(height: 8),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(alignment: Alignment.centerLeft, child: _TestButton(controller: controller, ai: true)),
    ),
    if (service == TranslationService.ai) ...[
      header(tr('AI 翻译')),
      PopupItem<String>(
        title: tr('提示词'),
        leading: const Icon(AppIcons.notePencil),
        value: config.promptPreset,
        values: [for (final p in AiTranslator.promptPresets) (p.id, p.label), ('custom', tr('自定义'))],
        onSelected: (v) => saveConfig((c) => c.copyWith(promptPreset: v)),
      ),
      if (config.promptPreset == 'custom')
        textItem(
          tr('自定义提示词'),
          config.customPrompt.isEmpty ? AiTranslator.promptPresets.first.text : config.customPrompt,
          config.customPrompt.isEmpty ? tr('未填写，使用“{0}”', [AiTranslator.promptPresets.first.label]) : config.customPrompt,
          AppIcons.notepad,
          '',
          (v) => saveConfig((c) => c.copyWith(customPrompt: v)),
          maxLines: 10,
        ),
      PopupItem<String>(
        title: tr('翻译风格'),
        leading: const Icon(AppIcons.cards),
        value: AiTone.byId(config.aiTone).id,
        values: [for (final t in AiTone.all) (t.id, t.label)],
        onSelected: (v) => saveConfig((c) => c.copyWith(aiTone: v)),
      ),
      textItem(
        tr('术语表'),
        config.aiGlossary,
        config.aiGlossary.trim().isEmpty ? tr('未填写') : tr('{0} 条', [config.aiGlossary.split('\n').where((l) => l.contains('=')).length]),
        AppIcons.bookOpen,
        tr('每行一条：原文=译文，如 Lumtub=Lumtub'),
        (v) => saveConfig((c) => c.copyWith(aiGlossary: v)),
        maxLines: 8,
      ),
      NormalItem(
        title: tr('温度'),
        subtitle: tr('{0}（越低越稳定，越高越灵活）', [config.aiTemperature.toStringAsFixed(1)]),
        leading: const Icon(AppIcons.thermometer),
        onTap: () => pickWithSlider(context, title: tr('温度'), value: config.aiTemperature, min: 0, max: 1.5, divisions: 15, precise: 1, onSelected: (v) => saveConfig((c) => c.copyWith(aiTemperature: v))),
      ),
      NormalItem(
        title: tr('字幕上下文'),
        subtitle: config.aiContext == 0 ? tr('关闭') : tr('带上前 {0} 句，人名和语气更连贯', [config.aiContext]),
        leading: const Icon(AppIcons.listNumbers),
        onTap: () => pickWithSlider(context, title: tr('字幕上下文'), value: config.aiContext.toDouble(), min: 0, max: 10, divisions: 10, suffix: tr(' 句'), onSelected: (v) => saveConfig((c) => c.copyWith(aiContext: v.round()))),
      ),
      tip(tr('使用 OpenAI 兼容的 /chat/completions 接口。提示词里 {target} 换成目标语言，{lines} 换成行数；字幕按行翻译，返回的行数不对时会重试一次。')),
    ] else
      tip(tr('想用 AI 翻译，把上面的“翻译服务”选成“AI 大模型”。')),
    header(tr('语音识别')),
    tip(tr('视频没有字幕时，可以把音频发给语音识别服务生成带时间轴的字幕，播放和 AI 总结都能用。只在你点“用语音识别生成字幕”时才上传这个视频的音频，结果保存在本机，下次不再上传。')),
    PopupItem<String>(
      title: tr('语音识别服务'),
      leading: const Icon(AppIcons.waveform),
      value: config.speech.id,
      values: [for (final p in SpeechPreset.all) (p.id, tr(p.label))],
      onSelected: (v) => saveConfig((c) => c.copyWith(speechPreset: v, speechBaseUrl: '', speechModel: '')),
    ),
    textItem(tr('接口地址'), config.speechBaseUrl, config.effectiveSpeechBaseUrl.isEmpty ? tr('未填写') : config.effectiveSpeechBaseUrl, AppIcons.link,
        config.speech.baseUrl.isEmpty ? tr('OpenAI 兼容接口，如 http://localhost:8000/v1') : config.speech.baseUrl, (v) => saveConfig((c) => c.copyWith(speechBaseUrl: v))),
    textItem(tr('模型'), config.speechModel, config.effectiveSpeechModel.isEmpty ? tr('未填写') : config.effectiveSpeechModel, AppIcons.cpuFill,
        config.speech.model, (v) => saveConfig((c) => c.copyWith(speechModel: v))),
    Builder(builder: (context) {
      final own = controller.translationKeys['speech'] ?? '';
      final shared = own.isEmpty && speechKeyFor(config, controller.translationKeys).isNotEmpty;
      return NormalItem(
        title: config.speech.id == 'custom' ? tr('API 密钥（可选）') : tr('API 密钥'),
        subtitle: own.isNotEmpty ? tr('已填写（{0}）', [_masked(own)]) : shared ? tr('使用 AI 接口的密钥') : tr('未填写'),
        leading: const Icon(AppIcons.keyFill),
        onTap: () async {
          final typed = await showDialog<String>(context: context, builder: (context) => _KeyDialog(title: tr('语音识别的 API 密钥'), initial: own));
          if (typed != null) await controller.saveApiKey('speech', typed);
        },
      );
    }),
    if (config.speech.id == 'groq')
      tip(tr('Groq 的密钥可以在 console.groq.com 免费申请；免费额度每天能识别几个小时的音频。')),
    header(tr('显示')),
    PopupItem<String>(
      title: tr('沉浸式翻译'),
      leading: const Icon(AppIcons.translate),
      value: prefs.immersiveTranslation ? prefs.immersiveLanguage : _off,
      values: [(_off, tr('关闭')), ('', tr('翻译成界面语言（{0}）', [interfaceTranslationLanguage.label])), for (final l in TranslationLanguage.all) (l.code, tr('翻译成{0}', [l.label]))],
      onSelected: (v) => controller.savePreferences(v == _off
          ? controller.preferences.copyWith(immersiveTranslation: false)
          : controller.preferences.copyWith(immersiveTranslation: true, immersiveLanguage: v)),
    ),
    tip(tr('打开后，评论、帖子和直播聊天里的外语内容自动在下方显示译文；界面语言和系统语言的内容不翻。')),
    PopupItem<_Layout>(
      title: tr('译文显示'),
      leading: const Icon(AppIcons.columns),
      value: !prefs.bilingualTranslation ? _Layout.replace : prefs.translationFirst ? _Layout.above : _Layout.below,
      values: [(_Layout.below, tr('原文在上，译文在下')), (_Layout.above, tr('译文在上，原文在下')), (_Layout.replace, tr('译文替换原文'))],
      onSelected: (v) => controller.savePreferences(controller.preferences.copyWith(bilingualTranslation: v != _Layout.replace, translationFirst: v == _Layout.above)),
    ),
    PopupItem<TranslationStyle>(
      title: tr('译文样式'),
      leading: const Icon(AppIcons.paintRoller),
      value: prefs.translationStyle,
      values: [for (final v in TranslationStyle.values) (v, v.label)],
      enabled: prefs.bilingualTranslation || prefs.immersiveTranslation,
      onSelected: (v) => controller.savePreferences(controller.preferences.copyWith(translationStyle: v)),
    ),
    SwitchItem(
      title: tr('跳过已是目标语言的内容'),
      subtitle: tr('按文字判断，中日韩俄等语言比较准；拉丁字母的语言只认得英语'),
      leading: const Icon(AppIcons.skipForward),
      value: prefs.skipSameLanguage,
      onChanged: (v) => controller.savePreferences(controller.preferences.copyWith(skipSameLanguage: v)),
    ),
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: _StylePreview(style: prefs.translationStyle, first: prefs.translationFirst, both: prefs.bilingualTranslation),
    ),
    tip(service == TranslationService.google
        ? tr('只有点“翻译”或使用翻译字幕时才发送要翻译的文字，不需要账号。翻过的内容在本机缓存 7 天，清理缓存时一并删除。')
        : tr('只有点“翻译”或使用翻译字幕时才把要翻译的文字发给所选服务。密钥用 Windows 加密保存在本机，不写进设置文件。翻过的内容在本机缓存 7 天，清理缓存时一并删除。')),
  ];
}

const _off = 'off';

/// Where 翻译 puts the translation; 沉浸式翻译 always keeps both.
enum _Layout { below, above, replace }

String _masked(String key) => key.length <= 8 ? '••••' : '${key.substring(0, 3)}••••${key.substring(key.length - 4)}';

class _TestButton extends StatefulWidget {
  const _TestButton({required this.controller, this.ai = false});
  final AppController controller;

  /// Checks the AI interface instead of the translation service.
  final bool ai;

  @override
  State<_TestButton> createState() => _TestButtonState();
}

class _TestButtonState extends State<_TestButton> {
  bool _testing = false;
  String? _result;
  bool _failed = false;

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    try {
      final text = await (widget.ai ? widget.controller.testAi() : widget.controller.testTranslation());
      if (mounted) {
        setState(() {
          _result = text;
          _failed = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _result = e is TranslationException ? e.message : '$e';
          _failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FilledButton.tonalIcon(
        onPressed: _testing ? null : _test,
        icon: _testing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(AppIcons.playFill),
        label: Text(widget.ai ? tr('测试 AI 接口') : tr('测试翻译')),
      ),
      if (_result != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SelectableText(_result!, style: TextStyle(color: _failed ? colors.error : colors.onSurface)),
        ),
    ]);
  }
}

class _KeyDialog extends StatefulWidget {
  const _KeyDialog({required this.title, required this.initial});
  final String title;
  final String initial;

  @override
  State<_KeyDialog> createState() => _KeyDialogState();
}

class _KeyDialogState extends State<_KeyDialog> {
  late final _text = TextEditingController(text: widget.initial);
  bool _shown = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: _text,
            autofocus: true,
            obscureText: !_shown,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: tr('粘贴密钥'),
              suffixIcon: IconButton(
                tooltip: _shown ? tr('隐藏') : tr('显示'),
                icon: Icon(_shown ? AppIcons.eyeSlash : AppIcons.eye),
                onPressed: () => setState(() => _shown = !_shown),
              ),
            ),
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
          ),
        ),
        actions: [
          if (widget.initial.isNotEmpty) TextButton(onPressed: () => Navigator.pop(context, ''), child: Text(tr('删除密钥'))),
          TextButton(onPressed: Navigator.of(context).pop, child: Text(tr('取消'))),
          TextButton(onPressed: () => Navigator.pop(context, _text.text.trim()), child: Text(tr('保存'))),
        ],
      );
}

Future<void> _pickModel(BuildContext context, AppController controller, ValueChanged<String> onSelected) async {
  final config = controller.preferences.translation;
  final messenger = ScaffoldMessenger.of(context);
  List<String> models;
  try {
    models = await controller.listAiModels();
  } on TranslationException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  }
  if (!context.mounted) return;
  if (models.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(tr('接口没有返回模型，可以手动填写'))));
    return;
  }
  final chosen = await showDialog<String>(
    context: context,
    builder: (context) => SelectDialog<String>(title: tr('模型'), value: config.effectiveAiModel, values: [for (final m in models) (m, m)]),
  );
  if (chosen != null) onSelected(chosen);
}

/// The original and its translation, as 翻译 will show them.
class _StylePreview extends StatelessWidget {
  const _StylePreview({required this.style, required this.first, required this.both});
  final TranslationStyle style;
  final bool first;
  final bool both;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const original = Text('This video explains how the new engine works.');
    final translated = Text(tr('这个视频讲解了新引擎的工作原理。'));
    final translation = TranslationView(style: style, child: translated);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!both) translated
        else ...[
          if (first) ...[translation, const SizedBox(height: 4)],
          original,
          if (!first) ...[const SizedBox(height: 4), translation],
        ],
      ]),
    );
  }
}
