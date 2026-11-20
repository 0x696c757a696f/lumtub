import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app_log.dart';
import '../../friendly_error.dart';
import '../../l10n/l10n.dart';
import '../../learning/learning.dart';
import '../../learning/vocabulary.dart';
import '../../models.dart';
import '../../save_file.dart';
import '../../widgets/pilinara_settings_tiles.dart';
import '../app_icons.dart';
import '../common.dart' show openExternal;
import '../pages/support_page.dart' show afdianPage, kofiPage;
import '../skin_paint.dart';

/// 学习包: the license, the dictionaries, pinyin and the vocabulary book.
Future<void> openLearningPage(BuildContext context, AppController controller) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (context) => _LearningPage(controller: controller)));

Future<void> openVocabularyBook(BuildContext context, AppController controller) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (context) => _VocabularyPage(controller: controller)));

/// What the settings show for the learning pack in one line.
String learningSummary(Learning learning) => learning.licensed
    ? tr('Licensed to {0}', [learning.license!.name.isEmpty ? '—' : learning.license!.name])
    : tr('Tap words for meanings, pinyin, vocabulary book, Anki export');

/// Asks for a license code and keeps it when it is one.
Future<bool> enterLicenseCode(BuildContext context, Learning learning) async {
  final field = TextEditingController();
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(tr('Enter license code')),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: field,
            autofocus: true,
            minLines: 3,
            maxLines: 5,
            decoration: InputDecoration(hintText: 'LT1.…', errorText: error, border: const OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
          FilledButton(
            onPressed: () async {
              if (await learning.enterLicense(field.text)) {
                if (context.mounted) Navigator.pop(context, true);
              } else {
                setState(() => error = tr('This license code is not valid. Copy the whole code and try again.'));
              }
            },
            child: Text(tr('OK')),
          ),
        ],
      ),
    ),
  );
  field.dispose();
  return ok ?? false;
}

class _LearningPage extends StatelessWidget {
  const _LearningPage({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final learning = controller.learning;
    return Scaffold(
      appBar: SkinAppBar(AppBar(title: Text(tr('Learning pack')))),
      body: ListenableBuilder(
        listenable: learning,
        builder: (context, _) {
          final colors = Theme.of(context).colorScheme;
          return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
            if (!learning.licensed) _Pitch(learning: learning),
            if (learning.licensed)
              NormalItem(
                title: tr('License'),
                subtitle: learningSummary(learning),
                leading: Icon(AppIcons.key),
                trailing: TextButton(
                  onPressed: () async {
                    final yes = await confirmDialog(context, title: tr('Remove the license from this device?'), content: tr('You can enter the same code again at any time.'), confirm: tr('Remove'));
                    if (yes) await learning.removeLicense();
                  },
                  child: Text(tr('Remove')),
                ),
              ),
            _ChineseTile(learning: learning),
            SwitchItem(
              title: tr('Show pinyin above Chinese subtitles'),
              subtitle: tr('Above each word, on the video and in the subtitle list'),
              leading: Icon(AppIcons.subtitles),
              value: learning.showPinyin,
              enabled: learning.licensed,
              onChanged: (on) => unawaited(learning.setShowPinyin(on)),
            ),
            NormalItem(
              title: tr('Vocabulary book'),
              subtitle: learning.licensed ? tr('{0} words', [learning.book?.words.length ?? 0]) : tr('Part of the learning pack'),
              leading: Icon(AppIcons.bookOpenText),
              enabled: learning.licensed,
              onTap: () => openVocabularyBook(context, controller),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                tr('How to use it: turn on a Chinese subtitle, then tap any word on the video or in the subtitle list. The video waits while the word is open. Everything stays on this device.'),
                style: TextStyle(color: colors.outline, fontSize: 12, height: 1.5),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                tr('Chinese dictionary: CC-CEDICT by MDBG, under CC BY-SA 4.0.'),
                style: TextStyle(color: colors.outline, fontSize: 12, height: 1.5),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _Pitch extends StatelessWidget {
  const _Pitch({required this.learning});
  final Learning learning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final zh = currentLanguage.isChinese;
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Learn languages from real videos'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final line in [
            tr('Tap any word in a subtitle for an offline dictionary entry'),
            tr('Pinyin above each word'),
            tr('A vocabulary book that keeps the line and the moment in the video'),
            tr('Export your words to Anki or CSV'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(AppIcons.check, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(line)),
              ]),
            ),
          const SizedBox(height: 8),
          Text(
            tr('Chinese now; Japanese and English next. One payment, all your devices, no account, no subscription. Buying it keeps Lumtub alive.'),
            style: TextStyle(color: theme.colorScheme.outline, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(
              onPressed: () => unawaited(openExternal(zh ? afdianPage : '$kofiPage/shop')),
              child: Text(zh ? tr('Buy on Afdian') : tr('Buy on Ko-fi')),
            ),
            OutlinedButton(
              onPressed: () => unawaited(openExternal(zh ? '$kofiPage/shop' : afdianPage)),
              child: Text(zh ? tr('Buy on Ko-fi') : tr('Buy on Afdian')),
            ),
            TextButton(onPressed: () => unawaited(enterLicenseCode(context, learning)), child: Text(tr('Enter license code'))),
          ]),
        ]),
      ),
    );
  }
}

class _ChineseTile extends StatelessWidget {
  const _ChineseTile({required this.learning});
  final Learning learning;

  @override
  Widget build(BuildContext context) {
    final state = learning.chineseState;
    final subtitle = switch (state) {
      PackState.missing => tr('Not downloaded · about 4 MB'),
      PackState.downloading => learning.downloadProgress == null ? tr('Downloading…') : tr('Downloading… {0}%', [(learning.downloadProgress! * 100).round()]),
      PackState.loading => learning.licensed ? tr('Loading…') : tr('Downloaded'),
      PackState.ready => tr('Ready'),
      PackState.failed => tr('Failed: {0}', [learning.packError ?? '']),
    };
    return NormalItem(
      title: tr('Chinese dictionary'),
      subtitle: subtitle,
      leading: Icon(AppIcons.translate),
      enabled: learning.licensed,
      trailing: !learning.licensed
          ? null
          : switch (state) {
              PackState.missing || PackState.failed => FilledButton.tonal(onPressed: () => unawaited(learning.downloadChinese()), child: Text(tr('Download'))),
              PackState.downloading || PackState.loading => const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              PackState.ready => IconButton(tooltip: tr('Delete'), icon: Icon(AppIcons.trash, size: 20), onPressed: () => unawaited(learning.deleteChinese())),
            },
    );
  }
}

class _VocabularyPage extends StatefulWidget {
  const _VocabularyPage({required this.controller});
  final AppController controller;

  @override
  State<_VocabularyPage> createState() => _VocabularyPageState();
}

class _VocabularyPageState extends State<_VocabularyPage> {
  VocabularyBook? get _book => widget.controller.learning.book;

  @override
  void initState() {
    super.initState();
    unawaited(_book?.load());
  }

  Future<void> _export({required bool anki}) async {
    final book = _book;
    if (book == null || book.words.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final text = anki ? vocabularyAnki(book.words) : vocabularyCsv(book.words);
      final saved = await saveFileAs(anki ? 'lumtub-vocabulary-anki.txt' : 'lumtub-vocabulary.csv', utf8.encode(text),
          mime: anki ? 'text/plain' : 'text/csv', label: anki ? 'Anki' : 'CSV', extension: anki ? 'txt' : 'csv');
      if (saved) messenger?.showSnackBar(SnackBar(content: Text(anki ? tr('Saved. In Anki, choose File › Import and pick this file.') : tr('Vocabulary exported'))));
    } catch (e) {
      logError('Could not export the vocabulary book', e);
      messenger?.showSnackBar(SnackBar(content: Text(tr('Export failed: {0}', [friendlyFileError(e)]))));
    }
  }

  void _open(VocabularyWord word) {
    if (word.videoId.isEmpty) return;
    final start = word.at > const Duration(seconds: 1) ? word.at - const Duration(seconds: 1) : Duration.zero;
    unawaited(widget.controller.play(
      VideoItem(id: word.videoId, title: word.videoTitle, channel: '', url: 'https://www.youtube.com/watch?v=${word.videoId}'),
      at: start,
    ));
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: SkinAppBar(AppBar(title: Text(tr('Vocabulary book')), actions: [
        TextButton.icon(onPressed: () => unawaited(_export(anki: true)), icon: Icon(AppIcons.downloadSimple, size: 18), label: const Text('Anki')),
        TextButton.icon(onPressed: () => unawaited(_export(anki: false)), icon: Icon(AppIcons.downloadSimple, size: 18), label: const Text('CSV')),
        const SizedBox(width: 8),
      ])),
      body: book == null
          ? const SizedBox.shrink()
          : ListenableBuilder(
              listenable: book,
              builder: (context, _) {
                final words = book.words;
                if (words.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(tr('No words yet. Tap a word in a Chinese subtitle and choose Add to vocabulary book.'), textAlign: TextAlign.center, style: TextStyle(color: colors.outline)),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 40),
                  itemCount: words.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final w = words[i];
                    return ListTile(
                      onTap: w.videoId.isEmpty ? null : () => _open(w),
                      title: Text.rich(TextSpan(children: [
                        TextSpan(text: w.word, style: const TextStyle(fontSize: 18)),
                        if (w.reading.isNotEmpty) TextSpan(text: '  ${w.reading}', style: TextStyle(color: colors.primary)),
                      ])),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (w.meaning.isNotEmpty) Text(w.meaning, maxLines: 2, overflow: TextOverflow.ellipsis),
                        if (w.sentence.isNotEmpty) Text(w.sentence, style: TextStyle(color: colors.outline)),
                        if (w.videoTitle.isNotEmpty) Text('${w.videoTitle} · ${clockOf(w.at)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: colors.outline)),
                      ]),
                      trailing: IconButton(tooltip: tr('Delete'), icon: Icon(AppIcons.trash, size: 18), onPressed: () => unawaited(book.remove(w))),
                    );
                  },
                );
              },
            ),
    );
  }
}
