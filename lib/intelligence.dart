import 'dart:math';
import 'dart:typed_data';

import 'l10n/l10n.dart';
import 'speech_subtitles.dart';
import 'translation.dart' show TranslationException;
import 'translation_services.dart';

/// What can do the AI work: the system's own models, a pack downloaded
/// to this device, or a service the user set up with a key.
enum ProviderKind { system, local, cloud }

enum Capability { transcribe, translate, complete, embed }

/// Where a text came from, kept with it so machine-made text is shown as
/// such and counts for less than a person's.
enum TextOrigin {
  human('human'),
  youtubeAuto('youtube-auto'),
  machineLocal('machine-local'),
  machineCloud('machine-cloud');

  const TextOrigin(this.id);

  /// How lumtub.db stores it.
  final String id;

  bool get machine => this == machineLocal || this == machineCloud;
}

/// Subtitles recognized from a video's audio.
class Transcript {
  const Transcript({required this.vtt, required this.origin, required this.model, this.language});
  final String vtt;
  final TextOrigin origin;

  /// The model that made it, such as `whisper-large-v3`.
  final String model;

  /// The language heard, as a tag, when the recognizer says.
  final String? language;
}

/// One way to do some of the AI work. Each says what it can do now; the
/// ones it cannot do throw [UnsupportedError].
abstract class IntelligenceProvider {
  const IntelligenceProvider();

  /// Stable, for logs and for what lumtub.db records as the maker.
  String get id;
  ProviderKind get kind;

  /// Whether it works without sending anything off this device.
  bool get offline => kind != ProviderKind.cloud;

  bool can(Capability capability);

  /// The model used for [capability], if known.
  String modelFor(Capability capability) => '';

  /// Subtitles for audio in [parts], each with where it starts in the
  /// video; [language] is a hint. [onProgress] counts parts done.
  Future<Transcript> transcribe(List<SpeechPart> parts, {String? language, void Function(int done, int total)? onProgress, bool Function()? cancelled}) =>
      throw UnsupportedError('$id cannot transcribe');

  /// [text] in [target], line for line.
  Future<String> translate(String text, String target) => throw UnsupportedError('$id cannot translate');

  /// One answer to [prompt] under [system].
  Future<String> complete(String system, String prompt, {double temperature = 0.3}) => throw UnsupportedError('$id cannot write');

  /// One vector for each of [texts].
  Future<List<Float32List>> embed(List<String> texts) => throw UnsupportedError('$id cannot embed');
}

/// The AI work the app asks for, done by the first provider able to,
/// in [order]: the system's models first, then a downloaded pack, then a
/// service the user set up.
class Intelligence {
  Intelligence(this.providers, {this.order = ProviderKind.values});

  final List<IntelligenceProvider> providers;
  final List<ProviderKind> order;

  /// The provider that [capability] goes to now, if any.
  IntelligenceProvider? providerFor(Capability capability) {
    for (final kind in order) {
      for (final provider in providers) {
        if (provider.kind == kind && provider.can(capability)) return provider;
      }
    }
    return null;
  }

  bool can(Capability capability) => providerFor(capability) != null;

  /// What lumtub.db records as the maker of a [capability] result:
  /// `<provider>:<model>`.
  String makerOf(Capability capability) {
    final provider = providerFor(capability);
    if (provider == null) return '';
    final model = provider.modelFor(capability);
    return model.isEmpty ? provider.id : '${provider.id}:$model';
  }

  IntelligenceProvider _for(Capability capability) =>
      providerFor(capability) ??
      (throw TranslationException(switch (capability) {
        Capability.transcribe => tr('Set up the speech recognition service and key under Translation & AI first'),
        Capability.complete || Capability.translate => tr('Set up the AI interface and key under Translation & AI first'),
        Capability.embed => tr('No AI model on this device can do this yet'),
      }));

  Future<Transcript> transcribe(List<SpeechPart> parts, {String? language, void Function(int done, int total)? onProgress, bool Function()? cancelled}) async =>
      _for(Capability.transcribe).transcribe(parts, language: language, onProgress: onProgress, cancelled: cancelled);

  Future<String> translate(String text, String target) async => _for(Capability.translate).translate(text, target);

  Future<String> complete(String system, String prompt, {double temperature = 0.3}) async => _for(Capability.complete).complete(system, prompt, temperature: temperature);

  Future<List<Float32List>> embed(List<String> texts) async => _for(Capability.embed).embed(texts);
}

/// The services set up under 翻译与 AI: 语音识别 through an
/// OpenAI-compatible `/audio/transcriptions`, AI 总结 and AI translation
/// through Chat Completions. They behave as they did before the providers.
class CloudIntelligence extends IntelligenceProvider {
  const CloudIntelligence({this.speech, this.ai});

  final SpeechRecognizer? speech;
  final AiTranslator? ai;

  /// Parts sent at once: twice as fast without the burst a free tier
  /// answers with 429.
  static const speechAtOnce = 2;

  @override
  String get id => 'cloud';

  @override
  ProviderKind get kind => ProviderKind.cloud;

  @override
  bool can(Capability capability) => switch (capability) {
        Capability.transcribe => speech != null,
        Capability.translate || Capability.complete => ai != null,
        Capability.embed => false,
      };

  @override
  String modelFor(Capability capability) => switch (capability) {
        Capability.transcribe => speech?.model ?? '',
        Capability.translate || Capability.complete => ai?.model ?? '',
        Capability.embed => '',
      };

  @override
  Future<Transcript> transcribe(List<SpeechPart> parts, {String? language, void Function(int done, int total)? onProgress, bool Function()? cancelled}) async {
    final recognizer = speech;
    if (recognizer == null) return super.transcribe(parts);
    final answers = List<({Duration offset, Map<String, dynamic> answer})?>.filled(parts.length, null);
    var done = 0;
    var next = 0;
    onProgress?.call(0, parts.length);
    Future<void> worker() async {
      while (next < parts.length) {
        if (cancelled?.call() ?? false) throw TranslationException(tr('Speech recognition was cancelled'));
        final i = next++;
        answers[i] = (offset: parts[i].offset, answer: await recognizer.transcribe(parts[i].file, language: language));
        onProgress?.call(++done, parts.length);
      }
    }

    await Future.wait([for (var i = 0; i < min(speechAtOnce, parts.length); i++) worker()]);
    final heard = [for (final a in answers) a!];
    final vtt = await speechVtt(heard);
    return Transcript(
      vtt: vtt,
      origin: TextOrigin.machineCloud,
      model: recognizer.model,
      language: heard.isEmpty ? null : speechLanguageTag(heard.first.answer['language']),
    );
  }

  @override
  Future<String> translate(String text, String target) => ai == null ? super.translate(text, target) : ai!.translate(text, target);

  @override
  Future<String> complete(String system, String prompt, {double temperature = 0.3}) =>
      ai == null ? super.complete(system, prompt) : ai!.complete(system, prompt, temperature: temperature);
}
