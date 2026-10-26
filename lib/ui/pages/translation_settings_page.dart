import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../l10n/l10n.dart';
import '../../player_settings.dart' show SubtitleLanguage;
import '../../translation.dart';
import '../../translation_services.dart';
import '../../widgets/pilinara_settings_tiles.dart';
import '../translatable.dart' show TranslationView;

/// 设置 › 翻译服务: the service behind 翻译 and translated subtitles, its
/// API key and, for AI models, the endpoint and prompt.
Future<void> openTranslationSettings(BuildContext context, AppController controller) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(tr('翻译服务'))),
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall!.copyWith(color: colors.primary)),
      );
  Widget tip(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 16, color: colors.outline),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: colors.outline, fontSize: 12, height: 1.5))),
        ]),
      );
  Widget keyItem(TranslationService of, {bool optional = false}) {
    final saved = controller.translationKeys[of.name] ?? '';
    return NormalItem(
      title: optional ? tr('API 密钥（可选）') : tr('API 密钥'),
      subtitle: saved.isEmpty ? tr('未填写') : tr('已填写（{0}）', [_masked(saved)]),
      leading: const Icon(Icons.key_rounded),
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
      leading: const Icon(Icons.g_translate_rounded),
      value: service,
      values: [for (final s in TranslationService.values) (s, s.label)],
      onSelected: (v) => saveConfig((c) => c.copyWith(service: v)),
    ),
    PopupItem<String>(
      title: tr('翻译目标语言'),
      leading: const Icon(Icons.translate_rounded),
      value: prefs.translateLanguage,
      values: [('', tr('跟随系统语言（{0}）', [SubtitleLanguage.auto.translation.label])), for (final l in TranslationLanguage.all) (l.code, l.label)],
      onSelected: (v) => controller.savePreferences(controller.preferences.copyWith(translateLanguage: v)),
    ),
    SwitchItem(
      title: tr('字幕也用这个服务翻译'),
      subtitle: service == TranslationService.google
          ? tr('选了其它翻译服务后可用；默认使用 YouTube 自带的自动翻译')
          : tr('关闭时使用 YouTube 自带的自动翻译，YouTube 拒绝时才用这个服务'),
      leading: const Icon(Icons.subtitles_outlined),
      value: prefs.subtitlesByService && service != TranslationService.google,
      enabled: service != TranslationService.google,
      onChanged: (v) => controller.savePreferences(controller.preferences.copyWith(subtitlesByService: v)),
    ),
    if (service == TranslationService.microsoft) ...[
      header(tr('微软翻译')),
      keyItem(service, optional: true),
      if ((controller.translationKeys[service.name] ?? '').isNotEmpty)
        textItem(tr('区域'), config.microsoftRegion, config.microsoftRegion.isEmpty ? tr('全局（未填写）') : config.microsoftRegion, Icons.public_rounded, tr('Azure 资源所在区域，如 eastasia'), (v) => saveConfig((c) => c.copyWith(microsoftRegion: v))),
      tip(tr('不填密钥时使用 Microsoft Edge 网页翻译用的免费接口；填了 Azure 密钥则走正式接口。')),
    ],
    if (service == TranslationService.deeplx) ...[
      header('DeepLX'),
      textItem(tr('服务器地址'), config.deeplxServer, config.deeplxServer.isEmpty ? tr('未填写') : config.deeplxServer, Icons.dns_outlined, tr('例如 http://localhost:1188/translate'), (v) => saveConfig((c) => c.copyWith(deeplxServer: v))),
      keyItem(service, optional: true),
      tip(tr('DeepLX 是开源的 DeepL 网页接口转发服务，可以自己部署；只使用你信任的服务器。')),
    ],
    if (service == TranslationService.baidu) ...[
      header(tr('百度翻译')),
      textItem('APP ID', config.baiduAppId, config.baiduAppId.isEmpty ? tr('未填写') : config.baiduAppId, Icons.badge_outlined, tr('百度翻译开放平台的 APP ID'), (v) => saveConfig((c) => c.copyWith(baiduAppId: v))),
      keyItem(service),
    ],
    if (service == TranslationService.deepl) ...[
      header('DeepL'),
      keyItem(service),
      tip(tr('免费版密钥以 :fx 结尾，会自动使用免费接口。')),
    ],
    if (service == TranslationService.libre) ...[
      header('LibreTranslate'),
      textItem(tr('服务器地址'), config.libreServer, config.libreServer.isEmpty ? tr('未填写') : config.libreServer, Icons.dns_outlined, tr('例如 https://libretranslate.com'), (v) => saveConfig((c) => c.copyWith(libreServer: v))),
      keyItem(service, optional: true),
    ],
    if (service == TranslationService.ai) ...[
      header(tr('AI 大模型')),
      PopupItem<String>(
        title: tr('服务商'),
        leading: const Icon(Icons.hub_outlined),
        value: ai.id,
        values: [for (final p in AiTranslator.aiPresets) (p.id, p.label)],
        // A preset's own address and model replace those typed for another.
        onSelected: (v) => saveConfig((c) => c.copyWith(aiPreset: v, aiBaseUrl: '', aiModel: '')),
      ),
      textItem(tr('接口地址'), config.aiBaseUrl, config.effectiveAiBaseUrl.isEmpty ? tr('未填写') : config.effectiveAiBaseUrl, Icons.link_rounded, ai.baseUrl.isEmpty ? tr('OpenAI 兼容接口，如 https://example.com/v1') : ai.baseUrl, (v) => saveConfig((c) => c.copyWith(aiBaseUrl: v))),
      NormalItem(
        title: tr('模型'),
        subtitle: config.effectiveAiModel.isEmpty ? tr('未填写') : config.effectiveAiModel,
        leading: const Icon(Icons.memory_rounded),
        trailing: IconButton(
          tooltip: tr('从接口获取模型列表'),
          icon: const Icon(Icons.list_alt_rounded),
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
      keyItem(service, optional: ai.id == 'ollama' || ai.id == 'custom'),
      PopupItem<String>(
        title: tr('提示词'),
        leading: const Icon(Icons.edit_note_rounded),
        value: config.promptPreset,
        values: [for (final p in AiTranslator.promptPresets) (p.id, p.label), ('custom', tr('自定义'))],
        onSelected: (v) => saveConfig((c) => c.copyWith(promptPreset: v)),
      ),
      if (config.promptPreset == 'custom')
        textItem(
          tr('自定义提示词'),
          config.customPrompt.isEmpty ? AiTranslator.promptPresets.first.text : config.customPrompt,
          config.customPrompt.isEmpty ? tr('未填写，使用“{0}”', [AiTranslator.promptPresets.first.label]) : config.customPrompt,
          Icons.notes_rounded,
          '',
          (v) => saveConfig((c) => c.copyWith(customPrompt: v)),
          maxLines: 10,
        ),
      PopupItem<String>(
        title: tr('翻译风格'),
        leading: const Icon(Icons.style_outlined),
        value: AiTone.byId(config.aiTone).id,
        values: [for (final t in AiTone.all) (t.id, t.label)],
        onSelected: (v) => saveConfig((c) => c.copyWith(aiTone: v)),
      ),
      textItem(
        tr('术语表'),
        config.aiGlossary,
        config.aiGlossary.trim().isEmpty ? tr('未填写') : tr('{0} 条', [config.aiGlossary.split('\n').where((l) => l.contains('=')).length]),
        Icons.menu_book_outlined,
        tr('每行一条：原文=译文，如 Lumtub=Lumtub'),
        (v) => saveConfig((c) => c.copyWith(aiGlossary: v)),
        maxLines: 8,
      ),
      NormalItem(
        title: tr('温度'),
        subtitle: tr('{0}（越低越稳定，越高越灵活）', [config.aiTemperature.toStringAsFixed(1)]),
        leading: const Icon(Icons.thermostat_rounded),
        onTap: () => pickWithSlider(context, title: tr('温度'), value: config.aiTemperature, min: 0, max: 1.5, divisions: 15, precise: 1, onSelected: (v) => saveConfig((c) => c.copyWith(aiTemperature: v))),
      ),
      NormalItem(
        title: tr('字幕上下文'),
        subtitle: config.aiContext == 0 ? tr('关闭') : tr('带上前 {0} 句，人名和语气更连贯', [config.aiContext]),
        leading: const Icon(Icons.format_list_numbered_rounded),
        onTap: () => pickWithSlider(context, title: tr('字幕上下文'), value: config.aiContext.toDouble(), min: 0, max: 10, divisions: 10, suffix: tr(' 句'), onSelected: (v) => saveConfig((c) => c.copyWith(aiContext: v.round()))),
      ),
      tip(tr('使用 OpenAI 兼容的 /chat/completions 接口。提示词里 {target} 换成目标语言，{lines} 换成行数；字幕按行翻译，返回的行数不对时会重试一次。')),
    ],
    const SizedBox(height: 8),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(alignment: Alignment.centerLeft, child: _TestButton(controller: controller)),
    ),
    header(tr('显示')),
    SwitchItem(
      title: tr('双语对照'),
      subtitle: tr('评论、简介和动态的译文和原文一起显示；关闭时译文替换原文'),
      leading: const Icon(Icons.vertical_split_outlined),
      value: prefs.bilingualTranslation,
      onChanged: (v) => controller.savePreferences(controller.preferences.copyWith(bilingualTranslation: v)),
    ),
    PopupItem<TranslationStyle>(
      title: tr('译文样式'),
      leading: const Icon(Icons.format_paint_outlined),
      value: prefs.translationStyle,
      values: [for (final v in TranslationStyle.values) (v, v.label)],
      enabled: prefs.bilingualTranslation,
      onSelected: (v) => controller.savePreferences(controller.preferences.copyWith(translationStyle: v)),
    ),
    SwitchItem(
      title: tr('译文在上方'),
      leading: const Icon(Icons.swap_vert_rounded),
      value: prefs.translationFirst,
      enabled: prefs.bilingualTranslation,
      onChanged: (v) => controller.savePreferences(controller.preferences.copyWith(translationFirst: v)),
    ),
    SwitchItem(
      title: tr('跳过已是目标语言的内容'),
      subtitle: tr('按文字判断，中日韩俄等语言比较准；拉丁字母的语言只认得英语'),
      leading: const Icon(Icons.skip_next_outlined),
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

String _masked(String key) => key.length <= 8 ? '••••' : '${key.substring(0, 3)}••••${key.substring(key.length - 4)}';

class _TestButton extends StatefulWidget {
  const _TestButton({required this.controller});
  final AppController controller;

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
      final text = await widget.controller.testTranslation();
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
        icon: _testing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow_rounded),
        label: Text(tr('测试翻译')),
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
                icon: Icon(_shown ? Icons.visibility_off_outlined : Icons.visibility_outlined),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!both) translated
        else ...[
          if (first) ...[translation, const SizedBox(height: 6)],
          original,
          if (!first) ...[const SizedBox(height: 6), translation],
        ],
      ]),
    );
  }
}
