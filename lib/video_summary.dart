import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'l10n/l10n.dart';
import 'native_core.dart';
import 'translation.dart' show TranslationException;
import 'translation_services.dart';

/// A subtitle file as timed paragraphs for AI 总结, cut by lumtub_core
/// into requests of about [budget] characters, at most [most] of them.
typedef SummaryTranscript = ({List<String> chunks, bool cut});

Future<SummaryTranscript> summaryTranscript(String source, {int budget = 12000, int most = 8}) async {
  if (NativeCore.instance == null) throw TranslationException(NativeCore.missingMessage);
  final input = jsonEncode({'source': source, 'budget': budget, 'most': most});
  final answer = await Isolate.run(() {
    final core = NativeCore.instance!;
    final transcript = core.library.lookupFunction<Pointer<Utf8> Function(Pointer<Uint8>, Size), Pointer<Utf8> Function(Pointer<Uint8>, int)>('lumtub_summary_transcript');
    return core.take(core.withText(input, transcript));
  });
  final json = answer == null ? null : jsonDecode(answer);
  if (json is! Map) return (chunks: const <String>[], cut: false);
  return (chunks: [for (final c in json['chunks'] is List ? json['chunks'] as List : const []) '$c'], cut: json['cut'] == true);
}

/// The language AI 总结 is written in: the interface's.
String get summaryLanguage => switch (currentLanguage.tag) {
      'zh-Hans' => 'Simplified Chinese',
      'zh-Hant' => 'Traditional Chinese',
      _ => currentLanguage.nativeName,
    };

String _system(String language) =>
    'You summarize YouTube videos from their transcripts. Write in $language. '
    'Start with one or two sentences on what the video is about. Then list the main points as 3 to 8 short bullets starting with "- ", '
    'each beginning with the time in square brackets where that part starts, copied from the transcript, like [12:34]. '
    'Use only what the transcript says, keep names as they are, and do not add a heading or a closing remark.';

const _partSystem = 'You condense one part of a YouTube video transcript into notes for a later summary. '
    'List its main points as short bullets starting with "- ", each beginning with the time in square brackets where it starts, like [12:34]. '
    'Use only what the transcript says. Write in the transcript\'s language.';

/// [reply] without the reasoning some models put first.
String _clean(String reply) => reply.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();

/// The summary of [title] from [transcript]: one request for a short video,
/// notes per part and a summary of them for a long one.
Future<String> summarizeTranscript(AiTranslator ai, String title, SummaryTranscript transcript, {void Function(int done, int total)? onProgress}) async {
  final chunks = transcript.chunks;
  if (chunks.isEmpty) throw TranslationException(tr('字幕是空的，无法总结'));
  final system = _system(summaryLanguage);
  if (chunks.length == 1) return _clean(await ai.complete(system, 'Title: $title\n\nTranscript:\n${chunks.first}'));
  final notes = <String>[];
  for (var i = 0; i < chunks.length; i++) {
    onProgress?.call(i, chunks.length + 1);
    notes.add(_clean(await ai.complete(_partSystem, 'Title: $title\nPart ${i + 1} of ${chunks.length}.\n\n${chunks[i]}')));
  }
  onProgress?.call(chunks.length, chunks.length + 1);
  final note = transcript.cut ? '\n\n(The transcript was too long; only its first part is covered.)' : '';
  return _clean(await ai.complete(system, 'Title: $title\n\nNotes on each part of the transcript, in order:\n${notes.join('\n')}$note'));
}
