import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../l10n/l10n.dart';
import '../../learning/chinese_dictionary.dart';
import '../../learning/vocabulary.dart';
import '../app_icons.dart';

/// The dictionary entries for [token], from a line heard at [at]: its
/// readings and meanings, its characters, and a button that keeps it in
/// the vocabulary book with the line. The video waits while it is open.
Future<void> showWordCard(BuildContext context, AppController controller, ChineseToken token, {required String sentence, String? translation, Duration? at}) async {
  final dictionary = controller.learning.chinese;
  if (dictionary == null) return;
  final player = controller.player;
  final wasPlaying = player?.state.playing ?? false;
  if (wasPlaying) unawaited(player!.pause());
  final when = at ?? player?.state.position ?? Duration.zero;
  await showDialog<void>(
    context: context,
    builder: (context) => _WordCard(controller: controller, dictionary: dictionary, token: token, sentence: sentence, translation: translation, at: when),
  );
  if (wasPlaying && controller.player == player) unawaited(player?.play());
}

class _WordCard extends StatelessWidget {
  const _WordCard({required this.controller, required this.dictionary, required this.token, required this.sentence, required this.translation, required this.at});

  final AppController controller;
  final ChineseDictionary dictionary;
  final ChineseToken token;
  final String sentence;
  final String? translation;
  final Duration at;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final word = token.text;
    final entries = dictionary.lookup(word);
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
        Expanded(child: SelectableText(word, style: theme.textTheme.headlineMedium)),
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
              if (translation != null && translation!.isNotEmpty) Text(translation!, style: theme.textTheme.bodySmall!.copyWith(color: colors.outline)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Close'))),
        if (book != null)
          ListenableBuilder(
            listenable: book,
            builder: (context, _) {
              final kept = book.contains('zh', word);
              return FilledButton.icon(
                icon: Icon(kept ? AppIcons.check : AppIcons.plus, size: 18),
                label: Text(kept ? tr('In vocabulary book') : tr('Add to vocabulary book')),
                onPressed: kept
                    ? null
                    : () {
                        final playing = controller.playing;
                        unawaited(book.add(VocabularyWord(
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
              );
            },
          ),
      ],
    );
  }
}
