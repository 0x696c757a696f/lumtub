import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/app_controller.dart';
import '../../app_log.dart';
import '../../friendly_error.dart';
import '../../l10n/l10n.dart';
import '../../learning/english_dictionary.dart';
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

/// Unlocks a purchase: asks for the order number, and for Ko-fi the email
/// paid with too, and fetches the code from the license server.
Future<bool> claimPurchase(BuildContext context, Learning learning, {required bool afdianFirst}) async {
  final field = TextEditingController();
  final email = TextEditingController();
  var afdian = afdianFirst;
  var busy = false;
  var agreed = false;
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(builder: (context, setState) {
      Future<void> claim() async {
        if (field.text.trim().isEmpty || (!afdian && email.text.trim().isEmpty) || !agreed || busy) return;
        setState(() {
          busy = true;
          error = null;
        });
        final result = await learning.claimLicense(afdian: afdian, order: field.text, email: email.text);
        if (!context.mounted) return;
        if (result == ClaimResult.ok) {
          Navigator.pop(context, true);
          return;
        }
        setState(() {
          busy = false;
          error = switch (result) {
            ClaimResult.notFound => afdian
                ? tr('No paid order with this number was found. Copy the order number from your Afdian order page.')
                : tr('No Ko-fi purchase with this transaction ID and email was found yet. Check both against your Ko-fi receipt, or wait a minute and try again.'),
            ClaimResult.busy => tr('Too many tries. Wait a minute and try again.'),
            _ => tr('Could not reach the license server. Check your connection, or ask for your code by message.'),
          };
        });
      }

      return AlertDialog(
        title: Text(tr('Unlock your purchase')),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, children: [
              ChoiceChip(label: Text(tr('Afdian')), selected: afdian, onSelected: busy ? null : (_) => setState(() => afdian = true)),
              ChoiceChip(label: const Text('Ko-fi'), selected: !afdian, onSelected: busy ? null : (_) => setState(() => afdian = false)),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: field,
              autofocus: true,
              enabled: !busy,
              onSubmitted: (_) => unawaited(claim()),
              decoration: InputDecoration(
                labelText: afdian ? tr('Afdian order number') : tr('Ko-fi transaction ID'),
                helperText: afdian ? tr('Afdian › My orders › the order › Order number') : tr('On the receipt Ko-fi emailed you'),
                errorText: afdian ? error : null,
                errorMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
            ),
            if (!afdian) ...[
              const SizedBox(height: 12),
              TextField(
                controller: email,
                enabled: !busy,
                keyboardType: TextInputType.emailAddress,
                onSubmitted: (_) => unawaited(claim()),
                decoration: InputDecoration(
                  labelText: tr('Email you paid with on Ko-fi'),
                  errorText: error,
                  errorMaxLines: 3,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 8),
            // Ticked by the buyer, never ahead of time: EU law lets the
            // 14-day withdrawal end only with this express consent.
            CheckboxListTile(
              value: agreed,
              onChanged: busy ? null : (on) => setState(() => agreed = on ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(_consentText()),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
          FilledButton(
            onPressed: busy || !agreed ? null : () => unawaited(claim()),
            child: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(tr('Unlock')),
          ),
        ],
      );
    }),
  );
  final order = field.text.trim();
  field.dispose();
  email.dispose();
  if (ok == true && context.mounted) await _showConfirmation(context, learning, afdian: afdian, order: order);
  return ok ?? false;
}

String _consentText() => tr(
    'I ask for the learning pack to be supplied now, and I understand that once it is, I lose the 14-day right of withdrawal. This does not affect my rights if the pack does not work as described.');

/// The record of the purchase and the consent, to keep: what EU law asks
/// the seller to give on a durable medium.
Future<void> _showConfirmation(BuildContext context, Learning learning, {required bool afdian, required String order}) async {
  final when = learning.lastConsent ?? DateTime.now();
  final stamp = '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')} ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
  final record = [
    tr('Lumtub learning pack'),
    '${afdian ? tr('Afdian') : 'Ko-fi'}: $order',
    tr('Unlocked on {0}', [stamp]),
    tr('You agreed: {0}', [_consentText()]),
    tr('License code: {0}', [learning.license?.code ?? '']),
  ].join('\n');
  // Written to Downloads at once, so the buyer has the confirmation on a
  // durable medium without having to save it.
  String? kept;
  try {
    final folder = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final safe = order.replaceAll(RegExp(r'[^0-9A-Za-z_-]'), '');
    final file = File('${folder.path}${Platform.pathSeparator}Lumtub-purchase-$safe.txt');
    await file.writeAsString('$record\n', flush: true);
    kept = file.path;
  } catch (e) {
    logWarn('Could not save the purchase confirmation: $e');
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('Unlocked')),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(kept == null ? tr('Keep this confirmation of your purchase:') : tr('This confirmation of your purchase was saved to {0}', [kept])),
          const SizedBox(height: 8),
          SelectableText(record, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => unawaited(Clipboard.setData(ClipboardData(text: record))), child: Text(tr('Copy'))),
        FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('OK'))),
      ],
    ),
  );
}

Future<void> _pickEnglishLevel(BuildContext context, Learning learning) async {
  final current = learning.englishLevel ?? -1;
  final picked = await showDialog<int>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(tr('My English level')),
      children: [
        for (final level in [-1, for (final l in EnglishLevel.values) if (l != EnglishLevel.beyond) l.index])
          ListTile(
            dense: true,
            leading: Icon(level == current ? AppIcons.radioButton : AppIcons.circle),
            title: Text(level < 0 ? tr("Don't mark hard words") : tr(EnglishLevel.values[level].label)),
            subtitle: level < 0 ? null : Text(level == EnglishLevel.gre.index ? tr('Only rare words stand out') : tr('Words from later lists stand out')),
            onTap: () => Navigator.pop(context, level),
          ),
      ],
    ),
  );
  if (picked != null && picked != current) await learning.setEnglishLevel(picked < 0 ? null : picked);
}

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
            for (final pack in DictionaryPack.values) _PackTile(learning: learning, pack: pack),
            SwitchItem(
              title: tr('Show pinyin and kana above subtitles'),
              subtitle: tr('Above each word, on the video and in the subtitle list'),
              leading: Icon(AppIcons.subtitles),
              value: learning.showPinyin,
              enabled: learning.licensed,
              onChanged: (on) => unawaited(learning.setShowPinyin(on)),
            ),
            NormalItem(
              title: tr('My English level'),
              subtitle: learning.englishLevel == null
                  ? tr('Hard words are not marked')
                  : tr('{0}. Harder words stand out in color', [tr(EnglishLevel.values[learning.englishLevel!].label)]),
              leading: Icon(AppIcons.graduationCap),
              enabled: learning.licensed,
              onTap: () => unawaited(_pickEnglishLevel(context, learning)),
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
                tr('How to use it: download a dictionary, turn on a Chinese, English or Japanese subtitle, then tap any word on the video or in the subtitle list. The video waits while the word is open. Everything stays on this device.'),
                style: TextStyle(color: colors.outline, fontSize: 12, height: 1.5),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                tr('Chinese dictionary: CC-CEDICT by MDBG, under CC BY-SA 4.0. English dictionary: ECDICT by skywind3000, under the MIT license. Japanese dictionary: JMdict by the Electronic Dictionary Research and Development Group, under CC BY-SA 4.0.'),
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
            tr('Pinyin above Chinese, kana above Japanese'),
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
            tr('Chinese, English, Japanese, Korean, Spanish, French, German, Italian and Russian. One payment, all your devices, no account, no subscription. Buying it keeps Lumtub alive.'),
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
            TextButton(onPressed: () => unawaited(claimPurchase(context, learning, afdianFirst: zh)), child: Text(tr('I bought it: unlock'))),
            TextButton(onPressed: () => unawaited(enterLicenseCode(context, learning)), child: Text(tr('Enter license code'))),
          ]),
        ]),
      ),
    );
  }
}

class _PackTile extends StatelessWidget {
  const _PackTile({required this.learning, required this.pack});
  final Learning learning;
  final DictionaryPack pack;

  @override
  Widget build(BuildContext context) {
    final state = learning.stateOf(pack);
    final progress = learning.progressOf(pack);
    final size = switch (pack) {
      DictionaryPack.chinese => '4 MB',
      DictionaryPack.english => '2 MB',
      DictionaryPack.japanese => '7 MB',
      DictionaryPack.korean => '8 MB',
      _ => tr('a few MB'),
    };
    final subtitle = switch (state) {
      PackState.missing => tr('Not downloaded · about {0}', [size]),
      PackState.downloading => progress == null ? tr('Downloading…') : tr('Downloading… {0}%', [(progress * 100).round()]),
      PackState.loading => learning.licensed ? tr('Loading…') : tr('Downloaded'),
      PackState.downloaded => tr('Downloaded · read when its subtitles play'),
      PackState.ready => tr('Ready'),
      PackState.failed => tr('Failed: {0}', [learning.errorOf(pack) ?? '']),
    };
    return NormalItem(
      title: switch (pack) {
        DictionaryPack.chinese => tr('Chinese dictionary (Chinese–English)'),
        DictionaryPack.english => tr('English dictionary (English–Chinese)'),
        DictionaryPack.japanese => tr('Japanese dictionary (Japanese–English, with kana)'),
        DictionaryPack.korean => tr('Korean dictionary (Korean–Chinese, KRDict)'),
        DictionaryPack.spanish => tr('Spanish dictionary'),
        DictionaryPack.french => tr('French dictionary'),
        DictionaryPack.german => tr('German dictionary'),
        DictionaryPack.italian => tr('Italian dictionary'),
        DictionaryPack.russian => tr('Russian dictionary'),
      },
      subtitle: subtitle,
      leading: Icon(AppIcons.translate),
      enabled: learning.licensed,
      trailing: !learning.licensed
          ? null
          : switch (state) {
              PackState.missing || PackState.failed => FilledButton.tonal(onPressed: () => unawaited(learning.download(pack)), child: Text(tr('Download'))),
              PackState.downloading || PackState.loading => const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              PackState.ready || PackState.downloaded => IconButton(tooltip: tr('Delete'), icon: Icon(AppIcons.trash, size: 20), onPressed: () => unawaited(learning.delete(pack))),
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
                      child: Text(tr('No words yet. Tap a word in a subtitle and choose Add to vocabulary book.'), textAlign: TextAlign.center, style: TextStyle(color: colors.outline)),
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
