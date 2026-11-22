part of 'learning_page.dart';

/// Puts the learning pack into the player's learning drawer: the 精学
/// lock and its pitch, this video's words, and the dictionary for the
/// subtitles' language. Called once at startup.
void installLearningPack() {
  studyUnlocked = (controller) => controller.learning.unlocked;
  studyLockedView = (context, controller) => _StudyLocked(controller: controller);
  addLearningDrawerSection(LearningDrawerSection(
    id: 'video-words',
    order: 25,
    title: () => tr('Words in this video'),
    shown: (c) => c.learning.book != null && c.playing != null && c.learningLines.isNotEmpty && _drawerPack(c) == null,
    build: (context, c) => _DrawerVideoWords(controller: c),
  ));
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
        const LearningPriceTag(size: 14),
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

/// How much of this video the learner knows, how hard that makes it, and
/// the new words said most often: learnt first, they open up the most.
class _DrawerVideoWords extends StatelessWidget {
  const _DrawerVideoWords({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final learning = controller.learning;
    if (!learning.unlocked) {
      return Row(children: [
        Icon(AppIcons.lock, size: 16, color: context.colors.outline),
        const SizedBox(width: 6),
        Expanded(child: Text(tr('See how much of this video you understand, and its key new words, with the learning pack'), style: context.text.bodySmall)),
      ]);
    }
    final known = knownWordsOf(learning.book!);
    final lines = controller.learningLines;
    return ListenableBuilder(
      listenable: known,
      builder: (context, _) => FutureBuilder<VideoWords?>(
        future: videoWordsOf(learning, known, controller.playing!.id, [for (final l in lines) l.text]),
        builder: (context, snapshot) {
          final words = snapshot.data;
          if (words == null) {
            return snapshot.connectionState == ConnectionState.done ? const SizedBox.shrink() : const LinearProgressIndicator(minHeight: 2);
          }
          final colors = context.colors;
          final (label, color) = switch (words.level) {
            VideoLevel.easy => (tr('Easy for you'), Colors.green.shade600),
            VideoLevel.right => (tr('Just right for learning'), colors.primary),
            VideoLevel.hard => (tr('Challenging'), Colors.orange.shade700),
            VideoLevel.tooHard => (tr('Very hard for now'), colors.error),
          };
          return Entrance(
            scale: 0.97,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: words.known),
                  duration: Motion.of(const Duration(milliseconds: 700)),
                  curve: Ease.curve,
                  builder: (context, v, _) => Text('${(v * 100).round()}%', style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: color)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(tr('of what is said you know'), style: context.text.bodySmall?.copyWith(color: colors.outline)),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                ),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: words.known, minHeight: 5, color: color, backgroundColor: colors.surfaceContainerHighest),
              ),
              const SizedBox(height: 6),
              Text(
                tr('{0} different words, {1} new to you · {2} lines with just one new word', [words.words, words.newWords, words.oneNew.length]),
                style: context.text.bodySmall?.copyWith(color: colors.outline),
              ),
              if (words.often.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(tr('Learn these first: the new words said most'), style: context.text.labelMedium),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final (token, count) in words.often)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text.rich(TextSpan(children: [
                        TextSpan(text: token.text),
                        TextSpan(text: ' ×$count', style: TextStyle(fontSize: 11, color: colors.outline)),
                      ])),
                      onPressed: () => unawaited(showWordCard(context, controller, token, sentence: _lineWith(lines, token))),
                    ),
                ]),
              ],
            ]),
          );
        },
      ),
    );
  }
}

/// The first line saying [token], for its word card.
String _lineWith(List<SubtitleCue> lines, WordToken token) => lines.firstWhere((l) => l.text.contains(token.text), orElse: () => lines.first).text;
