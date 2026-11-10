import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../l10n/l10n.dart';
import '../../player_settings.dart' show interfaceTranslationLanguage;
import '../../translation.dart';
import '../../translation_services.dart';
import '../../widgets/pilinara_settings_tiles.dart';
import '../app_icons.dart';
import '../common.dart' show dialogWidth;
import '../translatable.dart' show TranslationView;
import '../skin_paint.dart';

/// 设置 › 翻译与 AI: the service behind 翻译 and translated subtitles, and
/// the one AI interface that AI 翻译 and AI 总结 share.
Future<void> openTranslationSettings(BuildContext context, AppController controller) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: SkinAppBar(AppBar(title: Text(tr('Translation & AI')))),
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
  Widget keyItem(TranslationService of, {bool optional = false, String? name}) {
    final keyName = name ?? of.name;
    final saved = controller.translationKeys[keyName] ?? '';
    return NormalItem(
      title: optional ? tr('API key (optional)') : tr('API key'),
      subtitle: saved.isEmpty ? tr('Not set') : tr('Set ({0})', [_masked(saved)]),
      leading: const Icon(AppIcons.keyFill),
      onTap: () async {
        final typed = await showDialog<String>(context: context, builder: (context) => _KeyDialog(title: tr('API key for {0}', [of.label]), initial: saved));
        if (typed != null) await controller.saveApiKey(keyName, typed);
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
      title: tr('Translation service'),
      leading: Icon(AppIcons.translate),
      value: service,
      values: [for (final s in TranslationService.values) (s, s.label)],
      onSelected: (v) => saveConfig((c) => c.copyWith(service: v)),
    ),
    PopupItem<String>(
      title: tr('Translation target language'),
      leading: Icon(AppIcons.translate),
      value: prefs.translateLanguage,
      values: [('', tr('Interface language ({0})', [interfaceTranslationLanguage.label])), for (final l in TranslationLanguage.all) (l.code, l.label)],
      onSelected: (v) => controller.savePreferences(controller.preferences.copyWith(translateLanguage: v)),
    ),
    SwitchItem(
      title: tr('Translate subtitles with this service too'),
      subtitle: service == TranslationService.google
          ? tr("Available once another service is chosen; YouTube's own auto-translate is used by default")
          : tr("When off, YouTube's own auto-translate is used, and this service only when YouTube refuses"),
      leading: Icon(AppIcons.subtitles),
      value: prefs.subtitlesByService && service != TranslationService.google,
      enabled: service != TranslationService.google,
      onChanged: (v) => controller.savePreferences(controller.preferences.copyWith(subtitlesByService: v)),
    ),
    if (service == TranslationService.microsoft) ...[
      header(tr('Microsoft Translator')),
      keyItem(service, optional: true),
      if ((controller.translationKeys[service.name] ?? '').isNotEmpty)
        textItem(tr('Azure region'), config.microsoftRegion, config.microsoftRegion.isEmpty ? tr('Global (not set)') : config.microsoftRegion, AppIcons.globe, tr('Region of the Azure resource, such as eastasia'), (v) => saveConfig((c) => c.copyWith(microsoftRegion: v))),
      tip(tr('Without a key it uses the free endpoint Microsoft Edge translates pages with; with an Azure key it uses the official API.')),
    ],
    if (service == TranslationService.deeplx) ...[
      header('DeepLX'),
      textItem(tr('Server address'), config.deeplxServer, config.deeplxServer.isEmpty ? tr('Not set') : config.deeplxServer, AppIcons.hardDrives, tr('e.g. http://localhost:1188/translate'), (v) => saveConfig((c) => c.copyWith(deeplxServer: v))),
      keyItem(service, optional: true),
      tip(tr("DeepLX is an open-source bridge to DeepL's web translator that you can host yourself; use only servers you trust.")),
    ],
    if (service == TranslationService.baidu) ...[
      header(tr('Baidu Translate')),
      textItem('APP ID', config.baiduAppId, config.baiduAppId.isEmpty ? tr('Not set') : config.baiduAppId, AppIcons.identificationBadge, tr('APP ID from the Baidu Translate open platform'), (v) => saveConfig((c) => c.copyWith(baiduAppId: v))),
      keyItem(service),
    ],
    if (service == TranslationService.deepl) ...[
      header('DeepL'),
      keyItem(service),
      tip(tr('Free keys end in :fx and use the free endpoint automatically.')),
    ],
    if (service == TranslationService.libre) ...[
      header('LibreTranslate'),
      textItem(tr('Server address'), config.libreServer, config.libreServer.isEmpty ? tr('Not set') : config.libreServer, AppIcons.hardDrives, tr('For example https://libretranslate.com'), (v) => saveConfig((c) => c.copyWith(libreServer: v))),
      keyItem(service, optional: true),
    ],
    const SizedBox(height: 8),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(alignment: AlignmentDirectional.centerStart, child: _TestButton(controller: controller)),
    ),
    header(tr('AI interface')),
    tip(tr('AI translation and AI summary share this one interface (OpenAI-compatible /chat/completions). Text is sent only when you use AI translation or click AI summary.')),
      PopupItem<String>(
        title: tr('Provider'),
        leading: Icon(AppIcons.graph),
        value: ai.id,
        values: [for (final p in AiTranslator.aiPresets) (p.id, p.label)],
        // A preset's own address and model replace those typed for another.
        onSelected: (v) => saveConfig((c) => c.copyWith(aiPreset: v, aiBaseUrl: '', aiModel: '')),
      ),
      textItem(tr('Endpoint'), config.aiBaseUrl, config.effectiveAiBaseUrl.isEmpty ? tr('Not set') : config.effectiveAiBaseUrl, AppIcons.link, ai.baseUrl.isEmpty ? tr('OpenAI-compatible endpoint, such as https://example.com/v1') : ai.baseUrl, (v) => saveConfig((c) => c.copyWith(aiBaseUrl: v))),
      NormalItem(
        title: tr('Model'),
        subtitle: config.effectiveAiModel.isEmpty ? tr('Not set') : config.effectiveAiModel,
        leading: const Icon(AppIcons.cpuFill),
        trailing: IconButton(
          tooltip: tr('Get the model list from the endpoint'),
          icon: Icon(AppIcons.listDashes),
          onPressed: () => _pickModel(context, controller, (v) => saveConfig((c) => c.copyWith(aiModel: v))),
        ),
        onTap: () async {
          final typed = await showDialog<String>(
            context: context,
            builder: (context) => TextEditDialog(title: tr('Model'), initialText: config.aiModel, hintText: ai.model.isEmpty ? tr('Model name') : ai.model),
          );
          if (typed != null) saveConfig((c) => c.copyWith(aiModel: typed.trim()));
        },
      ),
      keyItem(TranslationService.ai, optional: ai.id == 'ollama' || ai.id == 'custom', name: aiKeyName(config)),
    const SizedBox(height: 8),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(alignment: AlignmentDirectional.centerStart, child: _TestButton(controller: controller, ai: true)),
    ),
    if (service == TranslationService.ai) ...[
      header(tr('AI translation')),
      PopupItem<String>(
        title: tr('Prompt'),
        leading: Icon(AppIcons.notePencil),
        value: config.promptPreset,
        values: [for (final p in AiTranslator.promptPresets) (p.id, p.label), ('custom', tr('Custom'))],
        onSelected: (v) => saveConfig((c) => c.copyWith(promptPreset: v)),
      ),
      if (config.promptPreset == 'custom')
        textItem(
          tr('Custom prompt'),
          config.customPrompt.isEmpty ? AiTranslator.promptPresets.first.text : config.customPrompt,
          config.customPrompt.isEmpty ? tr('Not set, using “{0}”', [AiTranslator.promptPresets.first.label]) : config.customPrompt,
          AppIcons.notepad,
          '',
          (v) => saveConfig((c) => c.copyWith(customPrompt: v)),
          maxLines: 10,
        ),
      PopupItem<String>(
        title: tr('Translation style'),
        leading: Icon(AppIcons.cards),
        value: AiTone.byId(config.aiTone).id,
        values: [for (final t in AiTone.all) (t.id, t.label)],
        onSelected: (v) => saveConfig((c) => c.copyWith(aiTone: v)),
      ),
      textItem(
        tr('Glossary'),
        config.aiGlossary,
        config.aiGlossary.trim().isEmpty ? tr('Not set') : tr('{0} entries', [config.aiGlossary.split('\n').where((l) => l.contains('=')).length]),
        AppIcons.bookOpen,
        tr('One per line: original=translation, e.g. Lumtub=Lumtub'),
        (v) => saveConfig((c) => c.copyWith(aiGlossary: v)),
        maxLines: 8,
      ),
      NormalItem(
        title: tr('Temperature'),
        subtitle: tr('{0} (lower is steadier, higher is freer)', [config.aiTemperature.toStringAsFixed(1)]),
        leading: Icon(AppIcons.thermometer),
        onTap: () => pickWithSlider(context, title: tr('Temperature'), value: config.aiTemperature, min: 0, max: 1.5, divisions: 15, precise: 1, onSelected: (v) => saveConfig((c) => c.copyWith(aiTemperature: v))),
      ),
      NormalItem(
        title: tr('Subtitle context'),
        subtitle: config.aiContext == 0 ? tr('Close') : tr('Sends the previous {0} lines so names and tone stay consistent', [config.aiContext]),
        leading: Icon(AppIcons.listNumbers),
        onTap: () => pickWithSlider(context, title: tr('Subtitle context'), value: config.aiContext.toDouble(), min: 0, max: 10, divisions: 10, suffix: tr(' lines'), onSelected: (v) => saveConfig((c) => c.copyWith(aiContext: v.round()))),
      ),
      tip(tr('Uses an OpenAI-compatible /chat/completions endpoint. In the prompt, {target} becomes the target language and {lines} the number of lines. Subtitles are translated line by line, and a reply with the wrong number of lines is retried once.')),
    ] else
      tip(tr('To translate with AI, set “Translation service” above to “AI model”.')),
    header(tr('Speech recognition')),
    tip(tr('When a video has no subtitles, its audio can be sent to a speech recognition service to make timed subtitles for playback and AI summary. The audio is uploaded only when you click “Make subtitles with speech recognition”; the result is kept on this computer and not uploaded again.')),
    PopupItem<String>(
      title: tr('Speech recognition service'),
      leading: Icon(AppIcons.waveform),
      value: config.speech.id,
      values: [for (final p in SpeechPreset.all) (p.id, tr(p.label))],
      onSelected: (v) => saveConfig((c) => c.copyWith(speechPreset: v, speechBaseUrl: '', speechModel: '')),
    ),
    textItem(tr('Endpoint'), config.speechBaseUrl, config.effectiveSpeechBaseUrl.isEmpty ? tr('Not set') : config.effectiveSpeechBaseUrl, AppIcons.link,
        config.speech.baseUrl.isEmpty ? tr('OpenAI-compatible interface, such as http://localhost:8000/v1') : config.speech.baseUrl, (v) => saveConfig((c) => c.copyWith(speechBaseUrl: v))),
    textItem(tr('Model'), config.speechModel, config.effectiveSpeechModel.isEmpty ? tr('Not set') : config.effectiveSpeechModel, AppIcons.cpuFill,
        config.speech.model, (v) => saveConfig((c) => c.copyWith(speechModel: v))),
    Builder(builder: (context) {
      final own = controller.translationKeys[speechKeyName(config)] ?? '';
      final shared = own.isEmpty && speechKeyFor(config, controller.translationKeys).isNotEmpty;
      return NormalItem(
        title: config.speech.id == 'custom' ? tr('API key (optional)') : tr('API key'),
        subtitle: own.isNotEmpty ? tr('Set ({0})', [_masked(own)]) : shared ? tr('Uses the AI interface key') : tr('Not set'),
        leading: const Icon(AppIcons.keyFill),
        onTap: () async {
          final typed = await showDialog<String>(context: context, builder: (context) => _KeyDialog(title: tr('Speech recognition API key'), initial: own));
          if (typed != null) await controller.saveApiKey(speechKeyName(config), typed);
        },
      );
    }),
    if (config.speech.id == 'groq')
      tip(tr('Get a free Groq key at console.groq.com; its free tier covers a few hours of audio a day.')),
    header(tr('Show')),
    PopupItem<String>(
      title: tr('Immersive translation'),
      leading: Icon(AppIcons.translate),
      value: prefs.immersiveTranslation ? prefs.immersiveLanguage : _off,
      values: [(_off, tr('Close')), ('', tr('Into the interface language ({0})', [interfaceTranslationLanguage.label])), for (final l in TranslationLanguage.all) (l.code, tr('Into {0}', [l.label]))],
      onSelected: (v) => controller.savePreferences(v == _off
          ? controller.preferences.copyWith(immersiveTranslation: false)
          : controller.preferences.copyWith(immersiveTranslation: true, immersiveLanguage: v)),
    ),
    tip(tr('When on, foreign-language comments, posts and live chat show a translation underneath; text in the interface or system language is left alone.')),
    PopupItem<_Layout>(
      title: tr('Translation layout'),
      leading: Icon(AppIcons.columns),
      value: !prefs.bilingualTranslation ? _Layout.replace : prefs.translationFirst ? _Layout.above : _Layout.below,
      values: [(_Layout.below, tr('Original above, translation below')), (_Layout.above, tr('Translation above, original below')), (_Layout.replace, tr('Translation replaces the original'))],
      onSelected: (v) => controller.savePreferences(controller.preferences.copyWith(bilingualTranslation: v != _Layout.replace, translationFirst: v == _Layout.above)),
    ),
    PopupItem<TranslationStyle>(
      title: tr('Translation look'),
      leading: Icon(AppIcons.paintRoller),
      value: prefs.translationStyle,
      values: [for (final v in TranslationStyle.values) (v, v.label)],
      enabled: prefs.bilingualTranslation || prefs.immersiveTranslation,
      onSelected: (v) => controller.savePreferences(controller.preferences.copyWith(translationStyle: v)),
    ),
    SwitchItem(
      title: tr('Skip text already in the target language'),
      subtitle: tr('Judged from the script: reliable for Chinese, Japanese, Korean, Russian and the like; of Latin-script languages only English is recognised'),
      leading: Icon(AppIcons.skipForward),
      value: prefs.skipSameLanguage,
      onChanged: (v) => controller.savePreferences(controller.preferences.copyWith(skipSameLanguage: v)),
    ),
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: _StylePreview(style: prefs.translationStyle, first: prefs.translationFirst, both: prefs.bilingualTranslation),
    ),
    tip(service == TranslationService.google
        ? tr('Text is sent only when you tap Translate or use translated subtitles; no account needed. Translations are cached on this computer for 7 days and removed when you clear the cache.')
        : tr('Text goes to the chosen service only when you tap Translate or use translated subtitles. Keys are encrypted with Windows on this computer and kept out of the settings file. Translations are cached on this computer for 7 days and removed when you clear the cache.')),
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
        label: Text(widget.ai ? tr('Test AI interface') : tr('Test translation')),
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
          width: dialogWidth(context, 420),
          child: TextField(
            controller: _text,
            autofocus: true,
            obscureText: !_shown,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: tr('Paste the key'),
              suffixIcon: IconButton(
                tooltip: _shown ? tr('Hide') : tr('Show'),
                icon: Icon(_shown ? AppIcons.eyeSlash : AppIcons.eye),
                onPressed: () => setState(() => _shown = !_shown),
              ),
            ),
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
          ),
        ),
        actions: [
          if (widget.initial.isNotEmpty) TextButton(onPressed: () => Navigator.pop(context, ''), child: Text(tr('Delete key'))),
          TextButton(onPressed: Navigator.of(context).pop, child: Text(tr('Cancel'))),
          TextButton(onPressed: () => Navigator.pop(context, _text.text.trim()), child: Text(tr('Save'))),
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
    messenger.showSnackBar(SnackBar(content: Text(tr('The endpoint listed no models; type one in instead'))));
    return;
  }
  final chosen = await showDialog<String>(
    context: context,
    builder: (context) => SelectDialog<String>(title: tr('Model'), value: config.effectiveAiModel, values: [for (final m in models) (m, m)]),
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
    final translated = Text(tr('This video explains how the new engine works.'));
    final translation = TranslationView(style: style, child: translated);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: colors.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
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
