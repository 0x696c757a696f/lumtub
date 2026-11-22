import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../l10n/l10n.dart';
import '../../learning/chinese_dictionary.dart';
import '../../learning/english_dictionary.dart';
import '../../learning/japanese_dictionary.dart';
import '../../learning/learning.dart';
import '../../learning/vocabulary.dart';
import '../../learning/wiktionary_dictionary.dart';
import '../app_icons.dart';
import '../motion.dart';
import 'learning_page.dart' show learningPresaleDeadline, showLearningLocked;

/// The dictionary entries for [token], from a line heard at [at]: its
/// readings and meanings, its characters, and a button that keeps it in
/// the vocabulary book with the line. The video waits while it is open.
Future<void> showWordCard(BuildContext context, AppController controller, WordToken token, {required String sentence, String? translation, Duration? at}) async {
  final learning = controller.learning;
  final language = Learning.languageOf(token);
  final ready = switch (language) {
    'zh' => learning.chinese != null,
    'ja' => learning.japanese != null,
    'en' => learning.english != null,
    _ => learning.wiktionary(language) != null,
  };
  if (!ready) return;
  if (!await learning.takeLookup('$language:${token.key.toLowerCase()}')) {
    if (context.mounted) await _trialUsedUp(context, controller);
    return;
  }
  if (!context.mounted) return;
  final player = controller.player;
  final wasPlaying = player?.state.playing ?? false;
  if (wasPlaying) unawaited(player!.pause());
  final when = at ?? player?.state.position ?? Duration.zero;
  await showDialog<void>(
    context: context,
    builder: (context) => switch (language) {
      'zh' => _WordCard(controller: controller, dictionary: learning.chinese!, token: token, sentence: sentence, translation: translation, at: when),
      'ja' => _JapaneseCard(controller: controller, dictionary: learning.japanese!, token: token, sentence: sentence, translation: translation, at: when),
      'en' => _EnglishCard(controller: controller, dictionary: learning.english!, token: token, sentence: sentence, translation: translation, at: when),
      _ => _WiktionaryCard(controller: controller, dictionary: learning.wiktionary(language)!, token: token, sentence: sentence, translation: translation, at: when),
    },
  );
  if (learning.closeTrialCard() && context.mounted) {
    // Told once, as it happens, rather than at the next lookup.
    await showLearningLocked(context, learning, title: tr('The free trial is over'), lead: tr('From now on, {0} free word lookups a day.', [Learning.trialPerDay]));
    return;
  }
  if (wasPlaying && controller.player == player) unawaited(player?.play());
}

/// Today's free word cards are used up: the moment a learner most wants
/// the pack, so its price and the way to buy it are right here.
Future<void> _trialUsedUp(BuildContext context, AppController controller) => showLearningLocked(context, controller.learning,
    title: tr("Today's {0} free word lookups are used up", [Learning.trialPerDay]), lead: tr('More tomorrow.'));

/// Without the pack: how many free word cards today has left, so the
/// last one is no surprise.
class _TrialNote extends StatelessWidget {
  const _TrialNote({required this.learning});
  final Learning learning;

  @override
  Widget build(BuildContext context) {
    if (learning.licensed) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    // Near the end of the trial the note says so plainly, with the
    // pre-sale's last day, while the learner is in the middle of using it.
    final ending = learning.unlocked && learning.trialTotalLeft <= 10;
    final until = learningPresaleDeadline();
    final note = Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        [
          learning.unlocked
              ? learning.trialTotalLeft == 0
                  ? tr('This is the last free trial lookup')
                  : tr('Free trial: {0} word lookups left with everything on', [learning.trialTotalLeft])
              : tr('{0} free lookups left today · the learning pack has no limit', [learning.trialLeft]),
          if (ending && until != null) until,
        ].join(' · '),
        style: TextStyle(fontSize: 11, color: ending ? colors.primary : colors.outline, fontWeight: ending ? FontWeight.w600 : null),
      ),
    );
    return ending ? Entrance(scale: 0.96, child: note) : note;
  }
}

class _WordCard extends StatelessWidget {
  const _WordCard({required this.controller, required this.dictionary, required this.token, required this.sentence, required this.translation, required this.at});

  final AppController controller;
  final ChineseDictionary dictionary;
  final WordToken token;
  final String sentence;
  final String? translation;
  final Duration at;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final word = token.text;
    // The reading shown above the word first: 看 kàn before kān.
    final found = dictionary.lookup(word);
    String plain(String s) => s.toLowerCase().replaceAll(' ', '');
    final heard = token.reading == null ? null : plain(token.reading!);
    final entries = heard == null ? found : [...found.where((e) => plain(e.marked) == heard), ...found.where((e) => plain(e.marked) != heard)];
    final chars = word.runes.map(String.fromCharCode).toList();
    final book = controller.learning.book;
    Widget entry(ChineseEntry e, {int senses = 8}) {
      final other = word == e.simplified ? e.traditional : e.simplified;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: e.marked, style: theme.textTheme.titleSmall!.copyWith(color: colors.primary)),
            if (other != word) TextSpan(text: '  $other', style: theme.textTheme.bodySmall!.copyWith(color: colors.outline)),
          ])),
          const SizedBox(height: 2),
          for (final (i, sense) in e.senses.take(senses).indexed)
            Text('${i + 1}. $sense', style: theme.textTheme.bodyMedium),
        ]),
      );
    }

    return AlertDialog(
      title: Row(children: [
        Expanded(child: SelectableText(word, style: _headStyle(theme))),
        _SpeakButton(controller: controller, text: word, language: 'zh'),
        IconButton(
          tooltip: tr('Copy'),
          icon: Icon(AppIcons.copy, size: 18),
          onPressed: () => unawaited(Clipboard.setData(ClipboardData(text: word))),
        ),
      ]),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (entries.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(tr('Not in the dictionary'), style: TextStyle(color: colors.outline))),
            for (final e in entries) entry(e),
            if (chars.length > 1) ...[
              const Divider(),
              for (final c in chars)
                for (final e in dictionary.lookup(c).take(2))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '$c  ', style: theme.textTheme.titleMedium),
                      TextSpan(text: '${e.marked}  ', style: TextStyle(color: colors.primary)),
                      TextSpan(text: e.senses.take(3).join('; '), style: theme.textTheme.bodySmall),
                    ])),
                  ),
            ],
            if (sentence.isNotEmpty) ...[
              const Divider(),
              Text(sentence, style: theme.textTheme.bodyMedium),
              if (controller.mainSubtitleAutomatic) Text(tr('Auto-generated subtitles: a word may be misheard'), style: TextStyle(fontSize: 11, color: colors.outline)),
              if (translation != null && translation!.isNotEmpty) Text(translation!, style: theme.textTheme.bodySmall!.copyWith(color: colors.outline)),
            ],
            _TrialNote(learning: controller.learning),
          ]),
        ),
      ),
      actions: [
        _LineButton(controller: controller, at: at),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Close'))),
        if (!controller.learning.unlocked)
          _LockedAdd(learning: controller.learning)
        else if (book != null)
          ListenableBuilder(
            listenable: book,
            builder: (context, _) {
              final kept = book.contains('zh', word);
              return _KeptSwitch(child: FilledButton.icon(
                key: ValueKey(kept),
                icon: Icon(kept ? AppIcons.check : AppIcons.plus, size: 18),
                label: Text(kept ? tr('In vocabulary book') : tr('Add to vocabulary book')),
                onPressed: kept
                    ? null
                    : () {
                        final playing = controller.playing;
                        unawaited(_addWord(controller, book, at, VocabularyWord(
                          word: word,
                          language: 'zh',
                          reading: token.reading ?? (entries.isEmpty ? '' : entries.first.marked),
                          meaning: entries.isEmpty ? '' : entries.first.senses.take(4).join('; '),
                          sentence: sentence,
                          translation: translation ?? '',
                          videoId: playing?.id ?? '',
                          videoTitle: playing?.title ?? '',
                          at: at,
                          added: DateTime.now(),
                        )));
                      },
              ));
            },
          ),
      ],
    );
  }
}

class _EnglishCard extends StatelessWidget {
  const _EnglishCard({required this.controller, required this.dictionary, required this.token, required this.sentence, required this.translation, required this.at});

  final AppController controller;
  final EnglishDictionary dictionary;
  final WordToken token;
  final String sentence;
  final String? translation;
  final Duration at;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final entries = dictionary.lookup(token.key);
    final head = entries.isEmpty ? token.key : entries.last.word;
    final book = controller.learning.book;
    return AlertDialog(
      title: Row(children: [
        Expanded(child: SelectableText(token.text, style: _headStyle(theme))),
        _SpeakButton(controller: controller, text: token.key, language: 'en'),
        IconButton(
          tooltip: tr('Copy'),
          icon: Icon(AppIcons.copy, size: 18),
          onPressed: () => unawaited(Clipboard.setData(ClipboardData(text: token.key))),
        ),
      ]),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (entries.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(tr('Not in the dictionary'), style: TextStyle(color: colors.outline))),
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(TextSpan(children: [
                    if (!_sameHead(entries.length, e.word, token.text)) TextSpan(text: '${e.word}  ', style: theme.textTheme.titleMedium),
                    if (e.phonetic.isNotEmpty) TextSpan(text: '/${e.phonetic}/', style: TextStyle(color: colors.primary)),
                  ])),
                  if (e.tags.isNotEmpty || e.cefr.isNotEmpty || e.collins > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 2),
                      child: Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        if (EnglishEntry.preferCefr && e.cefr.isNotEmpty) _Tag('CEFR ${e.cefr}') else for (final tag in e.tags) _Tag(englishLevelName(tag)),
                        if (e.collins > 0) Text('${'★' * e.collins}${'☆' * (5 - e.collins)}', style: TextStyle(color: colors.outline, fontSize: 12)),
                      ]),
                    ),
                  const SizedBox(height: 2),
                  ..._meaningLines(theme, controller.learning.meanings, e.meanings, e.english, chineseNote: e.chineseReference ? tr('Reference translation, matched by spelling: may not fit this sense') : null),
                  if (e.namedForms.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(e.namedForms.map((f) => '${tr(f.$1)} ${f.$2}').join(' · '), style: theme.textTheme.bodySmall!.copyWith(color: colors.outline)),
                    ),
                ]),
              ),
            if (sentence.isNotEmpty) ...[
              const Divider(),
              Text(sentence, style: theme.textTheme.bodyMedium),
              if (controller.mainSubtitleAutomatic) Text(tr('Auto-generated subtitles: a word may be misheard'), style: TextStyle(fontSize: 11, color: colors.outline)),
              if (translation != null && translation!.isNotEmpty) Text(translation!, style: theme.textTheme.bodySmall!.copyWith(color: colors.outline)),
            ],
            _TrialNote(learning: controller.learning),
          ]),
        ),
      ),
      actions: [
        _LineButton(controller: controller, at: at),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Close'))),
        if (!controller.learning.unlocked)
          _LockedAdd(learning: controller.learning)
        else if (book != null && entries.isNotEmpty)
          ListenableBuilder(
            listenable: book,
            builder: (context, _) {
              final kept = book.contains('en', head);
              final entry = entries.last;
              return _KeptSwitch(child: FilledButton.icon(
                key: ValueKey(kept),
                icon: Icon(kept ? AppIcons.check : AppIcons.plus, size: 18),
                label: Text(kept ? tr('In vocabulary book') : tr('Add to vocabulary book')),
                onPressed: kept
                    ? null
                    : () {
                        final playing = controller.playing;
                        unawaited(_addWord(controller, book, at, VocabularyWord(
                          word: head,
                          language: 'en',
                          reading: entry.phonetic.isEmpty ? '' : '/${entry.phonetic}/',
                          meaning: (entry.meanings.isNotEmpty && controller.learning.meanings != MeaningLanguage.english ? entry.meanings : entry.english).take(3).join('; '),
                          sentence: sentence,
                          translation: translation ?? '',
                          videoId: playing?.id ?? '',
                          videoTitle: playing?.title ?? '',
                          at: at,
                          added: DateTime.now(),
                        )));
                      },
              ));
            },
          ),
      ],
    );
  }
}

class _JapaneseCard extends StatelessWidget {
  const _JapaneseCard({required this.controller, required this.dictionary, required this.token, required this.sentence, required this.translation, required this.at});

  final AppController controller;
  final JapaneseDictionary dictionary;
  final WordToken token;
  final String sentence;
  final String? translation;
  final Duration at;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final matches = dictionary.lookUpInflected(token.key);
    final all = [for (final (match, list) in matches) for (final e in list) (match.base, e)].take(6).toList();
    // Entries the word is the usual spelling of come in full; others, such
    // as 嘱する that JMdict lists 属する as a rare spelling of, in one grey
    // line below, so the word meant is not lost among them.
    bool usual(String base, JapaneseEntry e) => e.headword == base || (e.kanji.isEmpty && e.kana.first == base);
    final entries = [for (final (base, e) in all) if (usual(base, e)) e];
    final aside = entries.isEmpty ? const <JapaneseEntry>[] : [for (final (base, e) in all) if (!usual(base, e)) e];
    if (entries.isEmpty) entries.addAll([for (final (_, e) in all) e]);
    final firstMatch = matches.isEmpty ? null : matches.first.$1;
    final head = entries.isEmpty ? token.key : entries.first.headword;
    final book = controller.learning.book;
    return AlertDialog(
      title: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (token.reading != null) Text(token.reading!, style: theme.textTheme.bodyMedium!.copyWith(color: colors.primary)),
            SelectableText(token.text, style: _headStyle(theme)),
          ]),
        ),
        _SpeakButton(controller: controller, text: head, language: 'ja'),
        IconButton(
          tooltip: tr('Copy'),
          icon: Icon(AppIcons.copy, size: 18),
          onPressed: () => unawaited(Clipboard.setData(ClipboardData(text: head))),
        ),
      ]),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (firstMatch != null && firstMatch.steps.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('${firstMatch.base} ← ${firstMatch.steps.reversed.join(' · ')}', style: theme.textTheme.bodySmall!.copyWith(color: colors.outline)),
              ),
            if (entries.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(tr('Not in the dictionary'), style: TextStyle(color: colors.outline))),
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // One entry spelt and read as the title says: nothing to add.
                  if (!_sameHead(entries.length, e.headword, token.text) || e.kana.take(3).join('・') != (token.reading ?? e.kana.first))
                    Text.rich(TextSpan(children: [
                      TextSpan(text: e.headword, style: theme.textTheme.titleMedium),
                      TextSpan(text: '  ${e.kana.take(3).join('・')}', style: TextStyle(color: colors.primary)),
                    ])),
                  const SizedBox(height: 2),
                  ..._meaningLines(theme, controller.learning.meanings, e.chinese, [for (final (i, sense) in e.senses.indexed) '${i + 1}. $sense']),
                ]),
              ),
            for (final e in aside)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${e.headword} ${e.kana.first} · ${(e.chinese.isNotEmpty && controller.learning.meanings != MeaningLanguage.english ? e.chinese : e.senses).firstOrNull ?? ''}',
                  style: theme.textTheme.bodySmall!.copyWith(color: colors.outline),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (sentence.isNotEmpty) ...[
              const Divider(),
              Text(sentence, style: theme.textTheme.bodyMedium),
              if (controller.mainSubtitleAutomatic) Text(tr('Auto-generated subtitles: a word may be misheard'), style: TextStyle(fontSize: 11, color: colors.outline)),
              if (translation != null && translation!.isNotEmpty) Text(translation!, style: theme.textTheme.bodySmall!.copyWith(color: colors.outline)),
            ],
            const SizedBox(height: 8),
            Text(
              entries.any((e) => e.chinese.isNotEmpty)
                  ? tr('From JMdict (EDRDG) with Chinese from Wiktionary and WikDict, CC BY-SA')
                  : tr('From JMdict (EDRDG), CC BY-SA 4.0'),
              style: TextStyle(fontSize: 11, color: colors.outline),
            ),
            _TrialNote(learning: controller.learning),
          ]),
        ),
      ),
      actions: [
        _LineButton(controller: controller, at: at),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Close'))),
        if (!controller.learning.unlocked)
          _LockedAdd(learning: controller.learning)
        else if (book != null && entries.isNotEmpty)
          ListenableBuilder(
            listenable: book,
            builder: (context, _) {
              final kept = book.contains('ja', head);
              final entry = entries.first;
              return _KeptSwitch(child: FilledButton.icon(
                key: ValueKey(kept),
                icon: Icon(kept ? AppIcons.check : AppIcons.plus, size: 18),
                label: Text(kept ? tr('In vocabulary book') : tr('Add to vocabulary book')),
                onPressed: kept
                    ? null
                    : () {
                        final playing = controller.playing;
                        unawaited(_addWord(controller, book, at, VocabularyWord(
                          word: head,
                          language: 'ja',
                          reading: entry.kana.first,
                          meaning: (entry.chinese.isNotEmpty && controller.learning.meanings != MeaningLanguage.english ? entry.chinese : entry.senses).take(3).join('; '),
                          sentence: sentence,
                          translation: translation ?? '',
                          videoId: playing?.id ?? '',
                          videoTitle: playing?.title ?? '',
                          at: at,
                          added: DateTime.now(),
                        )));
                      },
              ));
            },
          ),
      ],
    );
  }
}

/// An exam list's name on a word card.
class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(border: Border.all(color: colors.outlineVariant), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
    );
  }
}

/// A word from a Wiktionary dictionary: Chinese meanings where the
/// Chinese Wiktionary has them, then English ones.
class _WiktionaryCard extends StatelessWidget {
  const _WiktionaryCard({required this.controller, required this.dictionary, required this.token, required this.sentence, required this.translation, required this.at});

  final AppController controller;
  final WiktionaryDictionary dictionary;
  final WordToken token;
  final String sentence;
  final String? translation;
  final Duration at;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final language = dictionary.language;
    final all = dictionary.lookup(token.key);
    // A form with no meaning of its own shows only as a note on its word.
    final entries = all.where((e) => e.hasMeanings).toList();
    final formOf = {...all.where((e) => e.form && e.hasMeanings).map((e) => e.word), ...all.where((e) => !e.hasMeanings).expand((e) => e.lemmas)};
    final head = entries.isEmpty ? token.key : entries.first.word;
    final book = controller.learning.book;
    return AlertDialog(
      title: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (token.reading != null) Text(token.reading!, style: TextStyle(color: colors.primary, fontSize: 13)),
            SelectableText(token.text, style: _headStyle(theme)),
          ]),
        ),
        _SpeakButton(controller: controller, text: token.key, language: language),
        IconButton(
          tooltip: tr('Copy'),
          icon: Icon(AppIcons.copy, size: 18),
          onPressed: () => unawaited(Clipboard.setData(ClipboardData(text: token.key))),
        ),
      ]),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (entries.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(tr('Not in the dictionary'), style: TextStyle(color: colors.outline))),
            if (formOf.isNotEmpty && entries.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(tr('A form of {0}', [formOf.join(', ')]), style: theme.textTheme.bodySmall!.copyWith(color: colors.outline)),
              ),
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(TextSpan(children: [
                    if (!_sameHead(entries.length, e.word, token.text)) TextSpan(text: '${e.word}  ', style: theme.textTheme.titleMedium),
                    if (e.reading.isNotEmpty && e.reading != e.word) TextSpan(text: '${e.reading}  ', style: TextStyle(color: colors.primary)),
                    if (e.ipa.isNotEmpty) TextSpan(text: '/${e.ipa}/', style: TextStyle(color: colors.outline)),
                  ])),
                  if (e.level > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: _Tag(switch (e.level) {
                        1 => tr('Korean beginner'),
                        2 => tr('Korean intermediate'),
                        _ => tr('Korean advanced'),
                      }),
                    ),
                  const SizedBox(height: 2),
                  ..._meaningLines(theme, controller.learning.meanings, e.chinese, e.english),
                ]),
              ),
            if (sentence.isNotEmpty) ...[
              const Divider(),
              Text(sentence, style: theme.textTheme.bodyMedium),
              if (controller.mainSubtitleAutomatic) Text(tr('Auto-generated subtitles: a word may be misheard'), style: TextStyle(fontSize: 11, color: colors.outline)),
              if (translation != null && translation!.isNotEmpty) Text(translation!, style: theme.textTheme.bodySmall!.copyWith(color: colors.outline)),
            ],
            const SizedBox(height: 8),
            Text(
              entries.isNotEmpty && entries.every((e) => e.source == 'krdict')
                  ? tr('From the Korean Basic Dictionary (National Institute of Korean Language), CC BY-SA 2.0 KR')
                  : entries.any((e) => e.source == 'krdict')
                      ? tr('From the Korean Basic Dictionary (CC BY-SA 2.0 KR) and Wiktionary (CC BY-SA 4.0)')
                      : tr('From Wiktionary, CC BY-SA 4.0'),
              style: TextStyle(fontSize: 11, color: colors.outline),
            ),
            _TrialNote(learning: controller.learning),
          ]),
        ),
      ),
      actions: [
        _LineButton(controller: controller, at: at),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Close'))),
        if (!controller.learning.unlocked)
          _LockedAdd(learning: controller.learning)
        else if (book != null && entries.isNotEmpty)
          ListenableBuilder(
            listenable: book,
            builder: (context, _) {
              final kept = book.contains(language, head);
              final entry = entries.first;
              return _KeptSwitch(child: FilledButton.icon(
                key: ValueKey(kept),
                icon: Icon(kept ? AppIcons.check : AppIcons.plus, size: 18),
                label: Text(kept ? tr('In vocabulary book') : tr('Add to vocabulary book')),
                onPressed: kept
                    ? null
                    : () {
                        final playing = controller.playing;
                        unawaited(_addWord(controller, book, at, VocabularyWord(
                          word: head,
                          language: language,
                          reading: entry.reading.isNotEmpty ? entry.reading : (entry.ipa.isEmpty ? '' : '/${entry.ipa}/'),
                          meaning: (entry.chinese.isNotEmpty && controller.learning.meanings != MeaningLanguage.english ? entry.chinese : entry.english).take(3).join('; '),
                          sentence: sentence,
                          translation: translation ?? '',
                          videoId: playing?.id ?? '',
                          videoTitle: playing?.title ?? '',
                          at: at,
                          added: DateTime.now(),
                        )));
                      },
              ));
            },
          ),
      ],
    );
  }
}

/// The word at the top of a card: plain letters, as a skin's title face
/// may set every letter as a capital.
TextStyle _headStyle(ThemeData theme) => theme.textTheme.bodyLarge!.copyWith(fontSize: 26, fontWeight: FontWeight.w600, height: 1.25);

/// Whether the only entry is spelt as the card's title already shows it.
bool _sameHead(int entries, String headword, String title) => entries == 1 && headword.toLowerCase() == title.toLowerCase();

/// A word's meanings as [meanings] asks: the chosen language's, and below
/// Chinese ones a few English ones in grey; the other language's when the
/// word has none in the chosen one.
List<Widget> _meaningLines(ThemeData theme, MeaningLanguage meanings, List<String> chinese, List<String> english, {String? chineseNote}) {
  final main = theme.textTheme.bodyMedium;
  final aside = theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.outline);
  final first = switch (meanings) {
    MeaningLanguage.english => english.isNotEmpty ? english : chinese,
    _ => chinese.isNotEmpty ? chinese : english,
  };
  final more = meanings == MeaningLanguage.chineseFirst && identical(first, chinese) ? english.take(3) : const <String>[];
  return [
    if (chineseNote != null && identical(first, chinese) && chinese.isNotEmpty) Text(chineseNote, style: aside),
    for (final line in first.take(8)) Text(line, style: main),
    for (final line in more) Text(line, style: aside),
  ];
}

/// 读这个词: the word in the voice chosen in the learning pack's settings.
class _SpeakButton extends StatefulWidget {
  const _SpeakButton({required this.controller, required this.text, required this.language});
  final AppController controller;
  final String text;
  final String language;

  @override
  State<_SpeakButton> createState() => _SpeakButtonState();
}

class _SpeakButtonState extends State<_SpeakButton> {
  bool _busy = false;

  Future<void> _speak() async {
    setState(() => _busy = true);
    final said = await widget.controller.sayAloud(widget.text, widget.language);
    if (!mounted) return;
    setState(() => _busy = false);
    // A snack bar would sit behind the word card, unseen.
    final message = said.problem ?? said.note;
    if (message != null) {
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          content: Text(message),
          actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: Text(tr('OK')))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => !widget.controller.learning.unlocked
      ? IconButton(
          tooltip: tr('Read aloud: a learning pack feature'),
          icon: Icon(AppIcons.lock, size: 18),
          onPressed: () => unawaited(showLearningLocked(context, widget.controller.learning)),
        )
      : IconButton(
        tooltip: tr('Read aloud'),
        icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(AppIcons.speakerHigh, size: 20),
        onPressed: _busy || widget.text.isEmpty ? null : () => unawaited(_speak()),
      );
}

/// 听原句: the line the word is from, once more from the video.
class _LineButton extends StatelessWidget {
  const _LineButton({required this.controller, required this.at});
  final AppController controller;
  final Duration at;

  @override
  Widget build(BuildContext context) {
    if (controller.player == null || controller.learningLines.isEmpty) return const SizedBox.shrink();
    return TextButton.icon(
      icon: Icon(AppIcons.playCircle, size: 16),
      label: Text(tr('Hear the line')),
      onPressed: () => unawaited(controller.playLineOnce(at)),
    );
  }
}

/// Keeps [word] in [book], and the line it was heard in for Anki.
Future<void> _addWord(AppController controller, VocabularyBook book, Duration at, VocabularyWord word) async {
  await book.add(word);
  await controller.keepWordSound(word.key, at);
}

/// An English level as the learner knows it: the Chinese exam with a
/// Chinese interface, else about where it sits on the CEFR scale.
String englishLevelName(EnglishLevel level) => currentLanguage.isChinese || level == EnglishLevel.beyond ? tr(level.label) : '≈ ${level.cefr}';

/// 加入生词本, locked: the free trial is over and the pack is not bought.
class _LockedAdd extends StatelessWidget {
  const _LockedAdd({required this.learning});
  final Learning learning;

  @override
  Widget build(BuildContext context) => FilledButton.tonalIcon(
        icon: Icon(AppIcons.lock, size: 16),
        label: Text(tr('Add to vocabulary book')),
        onPressed: () => unawaited(showLearningLocked(context, learning)),
      );
}

/// 加入生词本 turning into 已在生词本: the new button grows in, so the
/// tap is seen to have kept the word.
class _KeptSwitch extends StatelessWidget {
  const _KeptSwitch({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: Motion.of(Ease.move),
        switchInCurve: Ease.curve,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(animation), child: child),
        ),
        child: child,
      );
}
