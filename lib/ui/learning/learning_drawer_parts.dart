part of 'learning_page.dart';

/// Puts the learning pack into the player's learning drawer: the 精学
/// lock and its pitch, this video's words, and the dictionary for the
/// subtitles' language. Called once at startup.
void installLearningPack() {
  studyUnlocked = (controller) => controller.learning.unlocked;
  studyLockedView = (context, controller) => _StudyLocked(controller: controller);
  addLearningDrawerSection(LearningDrawerSection(
    id: 'vocabulary',
    order: 30,
    title: () => tr('Vocabulary book'),
    shown: (c) => c.learning.book != null && c.playing != null,
    build: (context, c) => _DrawerVocabulary(controller: c),
  ));
  addLearningDrawerSection(LearningDrawerSection(
    id: 'dictionary',
    order: 40,
    title: () => tr('Dictionary'),
    shown: (c) => _drawerPack(c) != null,
    build: (context, c) => _DrawerDictionary(controller: c),
  ));
}

/// The dictionary this video's subtitles need, while it is not ready.
DictionaryPack? _drawerPack(AppController controller) {
  final lines = controller.learningLines;
  if (lines.isEmpty) return null;
  final sample = [for (final line in lines.take(40)) line.text].join('\n');
  final pack = controller.learning.packFor(sample);
  if (pack == null || controller.learning.stateOf(pack) == PackState.ready) return null;
  return pack;
}

class _StudyLocked extends StatelessWidget {
  const _StudyLocked({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(AppIcons.lock, size: 16, color: context.colors.outline),
          const SizedBox(width: 6),
          Expanded(child: Text(tr('Study mode is part of the learning pack'), style: context.text.bodySmall)),
        ]),
        const SizedBox(height: 4),
        Text(learningPriceLine(), style: context.text.bodySmall?.copyWith(color: context.colors.primary, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          FilledButton(onPressed: () => unawaited(buyLearningPack()), child: Text(tr('Buy the learning pack'))),
          TextButton(
            onPressed: () => unawaited(claimPurchase(context, controller.learning, afdianFirst: currentLanguage.isChinese)),
            child: Text(tr('I bought it: unlock')),
          ),
        ]),
      ]);
}

/// The words kept from this video, newest first, and the whole book.
class _DrawerVocabulary extends StatelessWidget {
  const _DrawerVocabulary({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final book = controller.learning.book!;
    return ListenableBuilder(
      listenable: book,
      builder: (context, _) {
        final id = controller.playing?.id;
        final here = [for (final w in book.words.reversed) if (w.videoId == id) w];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (here.isEmpty)
            Text(tr('Tap a word in the subtitles, then Add to vocabulary book: it keeps the line and the moment.'),
                style: context.text.bodySmall?.copyWith(color: context.colors.outline))
          else
            for (final w in here.take(6))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                title: Text(w.reading.isEmpty ? w.word : '${w.word}  ${w.reading}', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: w.meaning.isEmpty ? null : Text(w.meaning, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Text(formatPlaybackTime(w.at), style: context.text.labelSmall?.copyWith(color: context.colors.outline)),
                onTap: () => unawaited(controller.seek(w.at > const Duration(seconds: 1) ? w.at - const Duration(seconds: 1) : Duration.zero)),
              ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => unawaited(openVocabularyBook(context, controller)),
              child: Text(tr('See all {0} words', [book.words.length])),
            ),
          ),
        ]);
      },
    );
  }
}

/// The subtitles are in a language whose dictionary is not here yet:
/// one tap gets it.
class _DrawerDictionary extends StatelessWidget {
  const _DrawerDictionary({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final learning = controller.learning;
    return ListenableBuilder(
      listenable: learning,
      builder: (context, _) {
        final pack = _drawerPack(controller);
        if (pack == null) return Text(tr('Ready. Tap any word in the subtitles.'), style: context.text.bodySmall);
        final state = learning.stateOf(pack);
        final busy = state == PackState.downloading || state == PackState.loading;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('These subtitles are in {0}. Download its dictionary to tap any word for its meaning, offline.', [_packLanguage(pack)]),
              style: context.text.bodySmall),
          const SizedBox(height: 8),
          if (busy)
            LinearProgressIndicator(value: learning.progressOf(pack))
          else
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => unawaited(_getDictionary(context, learning, pack)),
                icon: Icon(AppIcons.downloadSimple, size: 18),
                label: Text(tr('Download the {0} dictionary', [_packLanguage(pack)])),
              ),
            ),
          if (state == PackState.failed)
            Text(tr('Failed: {0}', [learning.errorOf(pack) ?? '']), style: TextStyle(color: context.colors.error, fontSize: 12)),
        ]);
      },
    );
  }
}

/// Downloads [pack]'s dictionary, or, once the free trial is over without
/// the pack, says that dictionaries come with it.
Future<void> _getDictionary(BuildContext context, Learning learning, DictionaryPack pack) =>
    learning.unlocked ? learning.download(pack) : showLearningLocked(context, learning);
