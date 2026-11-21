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
import '../../learning/anki_connect.dart';
import '../../learning/english_dictionary.dart';
import '../../learning/learning.dart';
import '../../learning/vocabulary.dart';
import '../../learning/word_voice.dart' show azureVoiceKey, azureVoiceRegion, googleVoiceKey;
import '../../models.dart';
import '../../save_file.dart';
import '../../widgets/settings_tiles.dart';
import '../app_icons.dart';
import '../common.dart' show openExternal;
import '../pages/support_page.dart' show afdianPage, kofiPage;
import '../skin_paint.dart';
import 'word_card.dart' show englishLevelName;

/// 学习包: the license, the dictionaries, pinyin and the vocabulary book.
Future<void> openLearningPage(BuildContext context, AppController controller) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (context) => _LearningPage(controller: controller)));

Future<void> openVocabularyBook(BuildContext context, AppController controller) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (context) => _VocabularyPage(controller: controller)));

/// What the settings show for the learning pack in one line.
String learningSummary(Learning learning) => learning.licensed
    ? tr('Licensed to {0}', [learning.license!.name.isEmpty ? '—' : learning.license!.name])
    : tr('Tap words for meanings, pinyin, vocabulary book, Anki export');

/// Unlocks a purchase: asks for the order number, and for Ko-fi and Polar
/// the email paid with too, and fetches the code from the license server.
Future<bool> claimPurchase(BuildContext context, Learning learning, {required bool afdianFirst}) async {
  final field = TextEditingController();
  final email = TextEditingController();
  var source = afdianFirst ? PurchaseSource.afdian : PurchaseSource.polar;
  var busy = false;
  var agreed = false;
  String? error;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(builder: (context, setState) {
      Future<void> claim() async {
        if (field.text.trim().isEmpty || (source.needsEmail && email.text.trim().isEmpty) || !agreed || busy) return;
        setState(() {
          busy = true;
          error = null;
        });
        final result = await learning.claimLicense(source: source, order: field.text, email: email.text);
        if (!context.mounted) return;
        if (result == ClaimResult.ok) {
          Navigator.pop(context, true);
          return;
        }
        setState(() {
          busy = false;
          error = switch (result) {
            ClaimResult.notFound => switch (source) {
                PurchaseSource.afdian => tr('No paid order with this number was found. Copy the order number from your Afdian order page.'),
                PurchaseSource.polar => tr('No Polar order with this ID and email was found yet. Check both against the page shown after paying or your Polar receipt, or wait a minute and try again.'),
                PurchaseSource.kofi => tr('No Ko-fi purchase with this transaction ID and email was found yet. Check both against your Ko-fi receipt, or wait a minute and try again.'),
              },
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
              for (final s in PurchaseSource.values)
                ChoiceChip(label: Text(_sourceName(s)), selected: source == s, onSelected: busy ? null : (_) => setState(() => source = s)),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: field,
              autofocus: true,
              enabled: !busy,
              onSubmitted: (_) => unawaited(claim()),
              decoration: InputDecoration(
                labelText: switch (source) {
                  PurchaseSource.afdian => tr('Afdian order number'),
                  PurchaseSource.polar => tr('Polar order ID'),
                  PurchaseSource.kofi => tr('Ko-fi transaction ID'),
                },
                helperText: switch (source) {
                  PurchaseSource.afdian => tr('Afdian › My orders › the order › Order number'),
                  PurchaseSource.polar => tr('Shown on the page after paying'),
                  PurchaseSource.kofi => tr('On the receipt Ko-fi emailed you'),
                },
                errorText: source.needsEmail ? null : error,
                errorMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
            ),
            if (source.needsEmail) ...[
              const SizedBox(height: 12),
              TextField(
                controller: email,
                enabled: !busy,
                keyboardType: TextInputType.emailAddress,
                onSubmitted: (_) => unawaited(claim()),
                decoration: InputDecoration(
                  labelText: source == PurchaseSource.polar ? tr('Email you paid with on Polar') : tr('Email you paid with on Ko-fi'),
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
  if (ok == true && context.mounted) await _showConfirmation(context, learning, source: source, order: order);
  return ok ?? false;
}

String _sourceName(PurchaseSource source) => switch (source) {
      PurchaseSource.afdian => tr('Afdian'),
      PurchaseSource.polar => 'Polar',
      PurchaseSource.kofi => 'Ko-fi',
    };

/// Opens Polar's checkout, or Ko-fi's shop while there is none.
Future<void> _buyOnPolar() async {
  final checkout = await polarCheckout();
  await openExternal(checkout?.toString() ?? '$kofiPage/shop');
}

String _consentText() => tr(
    'I ask for the learning pack to be supplied now, and I understand that once it is, I lose the 14-day right of withdrawal. This does not affect my rights if the pack does not work as described.');

/// The record of the purchase and the consent, to keep: what EU law asks
/// the seller to give on a durable medium.
Future<void> _showConfirmation(BuildContext context, Learning learning, {required PurchaseSource source, required String order}) async {
  final when = learning.lastConsent ?? DateTime.now();
  final stamp = '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')} ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
  final record = [
    tr('Lumtub learning pack'),
    '${_sourceName(source)}: $order',
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

String _voiceLabel(VoiceService service) => switch (service) {
      VoiceService.system => tr("This computer's voices, offline and free"),
      VoiceService.azure => tr('Azure neural voices, with your own key'),
      VoiceService.google => tr('Google Cloud voices, with your own key'),
    };

Future<void> _pickVoice(BuildContext context, Learning learning) async {
  final picked = await showDialog<VoiceService>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(tr('Voice for reading words')),
      children: [
        for (final v in VoiceService.values)
          ListTile(
            dense: true,
            leading: Icon(v == learning.voiceService ? AppIcons.radioButton : AppIcons.circle),
            title: Text(_voiceLabel(v)),
            onTap: () => Navigator.pop(context, v),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
          child: Text(tr('Azure and Google sound like a person and have a free monthly allowance; you make the key in their consoles. The words go to them to be read.'),
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
        ),
      ],
    ),
  );
  if (picked != null && picked != learning.voiceService) await learning.setVoiceService(picked);
}

String _meaningLabel(MeaningLanguage meanings) => switch (meanings) {
      MeaningLanguage.chineseFirst => tr('Chinese first, a few English ones below'),
      MeaningLanguage.chinese => tr('Chinese only'),
      MeaningLanguage.english => tr('English only'),
    };

Future<void> _pickMeanings(BuildContext context, Learning learning) async {
  final picked = await showDialog<MeaningLanguage>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(tr('Meanings in')),
      children: [
        for (final m in MeaningLanguage.values)
          ListTile(
            dense: true,
            leading: Icon(m == learning.meanings ? AppIcons.radioButton : AppIcons.circle),
            title: Text(_meaningLabel(m)),
            onTap: () => Navigator.pop(context, m),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
          child: Text(tr("A word with no meaning in the chosen language shows the other's."), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
        ),
      ],
    ),
  );
  if (picked != null && picked != learning.meanings) await learning.setMeanings(picked);
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
            title: Text(level < 0 ? tr("Don't mark hard words") : englishLevelName(EnglishLevel.values[level])),
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

  Widget _voiceKeyItem(BuildContext context, String title, String name, {bool secret = true}) {
    final saved = controller.translationKeys[name] ?? '';
    return NormalItem(
      title: title,
      subtitle: saved.isEmpty ? tr('Not set') : (secret ? '${'•' * 8}${saved.length > 4 ? saved.substring(saved.length - 4) : ''}' : saved),
      leading: const Icon(AppIcons.keyFill),
      onTap: () async {
        final typed = await showDialog<String>(context: context, builder: (context) => TextEditDialog(title: title, initialText: saved));
        if (typed == null) return;
        await controller.saveApiKey(name, typed.trim());
        // Shown again with the new key.
        await controller.learning.setVoiceService(controller.learning.voiceService);
      },
    );
  }

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
            SwitchItem(
              title: tr('Romanization above Korean'),
              subtitle: tr('Korean words in Latin letters, such as hangugeo above 한국어'),
              leading: Icon(AppIcons.subtitles),
              value: learning.showRomanization,
              enabled: learning.licensed,
              onChanged: (on) => unawaited(learning.setShowRomanization(on)),
            ),
            NormalItem(
              title: tr('Voice for reading words'),
              subtitle: _voiceLabel(learning.voiceService),
              leading: Icon(AppIcons.speakerHigh),
              enabled: learning.licensed,
              onTap: () => unawaited(_pickVoice(context, learning)),
            ),
            if (learning.voiceService == VoiceService.azure) ...[
              _voiceKeyItem(context, tr('Azure key'), azureVoiceKey),
              _voiceKeyItem(context, tr('Azure region, such as westeurope'), azureVoiceRegion, secret: false),
            ],
            if (learning.voiceService == VoiceService.google) _voiceKeyItem(context, tr('Google Cloud key'), googleVoiceKey),
            NormalItem(
              title: tr('Meanings in'),
              subtitle: _meaningLabel(learning.meanings),
              leading: Icon(AppIcons.translate),
              enabled: learning.licensed,
              onTap: () => unawaited(_pickMeanings(context, learning)),
            ),
            NormalItem(
              title: tr('My English level'),
              subtitle: learning.englishLevel == null
                  ? tr('Hard words are not marked')
                  : tr('{0}. Harder words stand out in color', [englishLevelName(EnglishLevel.values[learning.englishLevel!])]),
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
            NormalItem(
              title: tr('Data sources and licenses'),
              subtitle: tr('The dictionaries are open data: who made them and under which license'),
              leading: Icon(AppIcons.info),
              onTap: () => unawaited(showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(tr('Data sources and licenses')),
                  content: const SizedBox(width: 520, child: SingleChildScrollView(child: SelectableText(learningDataNotice))),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Close')))],
                ),
              )),
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
              onPressed: () => unawaited(zh ? openExternal(afdianPage) : _buyOnPolar()),
              child: Text(zh ? tr('Buy on Afdian (Alipay, WeChat)') : tr('Buy (card, Apple Pay, Google Pay)')),
            ),
            OutlinedButton(
              onPressed: () => unawaited(zh ? _buyOnPolar() : openExternal(afdianPage)),
              child: Text(zh ? tr('Buy (card, Apple Pay, Google Pay)') : tr('Buy on Afdian (Alipay, WeChat)')),
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
        DictionaryPack.japanese => tr('Japanese dictionary (Japanese–Chinese–English, with kana)'),
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

  bool _sending = false;

  /// Sends the book's words straight into Anki through AnkiConnect.
  Future<void> _sendToAnki() async {
    final book = _book;
    if (book == null || book.words.isEmpty || _sending) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _sending = true);
    final anki = AnkiConnect();
    try {
      final added = await anki.send(book.words, book);
      messenger?.showSnackBar(SnackBar(content: Text(added == 0 ? tr('Nothing new: these words are in the Lumtub deck already') : tr('{0} words added to the Lumtub deck in Anki', [added]))));
    } on AnkiException catch (e) {
      logWarn('Could not send the vocabulary to Anki: $e');
      messenger?.showSnackBar(SnackBar(
        duration: const Duration(seconds: 10),
        content: Text(e.notRunning
            ? tr('Anki did not answer. Open Anki with the AnkiConnect add-on (code 2055492159), or use the Anki file instead.')
            : tr('Anki said: {0}', [e.detail])),
      ));
    } finally {
      anki.close();
      if (mounted) setState(() => _sending = false);
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
        TextButton.icon(
          onPressed: _sending ? null : () => unawaited(_sendToAnki()),
          icon: _sending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(AppIcons.paperPlaneRight, size: 18),
          label: Text(tr('Send to Anki')),
        ),
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

/// Who made the learning pack's data and under which license, as their
/// licenses ask to be shown in the app. The dictionaries stay open data:
/// the pack sells the app's features, not the data, which anyone may
/// copy under these licenses.
const learningDataNotice = '''English: the word list, word forms and exam tags of ECDICT by skywind3000 (MIT, github.com/skywind3000/ECDICT). Chinese meanings from the Mandarin translations in the English Wiktionary and from the Chinese Wiktionary (CC BY-SA 4.0, wiktionary.org) as extracted by kaikki.org; where neither has a word, WikDict's translations (CC BY-SA 4.0, wikdict.com), marked as reference translations. Pronunciations (IPA) from the English Wiktionary. Frequency ranks from wordfreq by Robyn Speer (data CC BY-SA 4.0). English meanings from the Simple English and English Wiktionaries (CC BY-SA 4.0, wiktionary.org) as extracted by kaikki.org, and from WordNet 3.0, © Princeton University (WordNet license). CEFR levels: The CEFR-J Wordlist Version 1.5, compiled by Yukio Tono, Tokyo University of Foreign Studies (cefr-j.org), and the Octanove Vocabulary Profile C1/C2 1.0 by Octanove Labs (CC BY-SA 4.0), via github.com/openlanguageprofiles/olp-en-cefrj.

Japanese: JMdict, © Electronic Dictionary Research and Development Group (CC BY-SA 4.0, edrdg.org/edrdg/licence.html), via jmdict-simplified; Chinese meanings from the Chinese Wiktionary (CC BY-SA 4.0) and WikDict (CC BY-SA 4.0, wikdict.com).

Chinese: CC-CEDICT by MDBG (CC BY-SA 4.0, cc-cedict.org).

Korean: 한국어기초사전 (Korean Basic Dictionary), National Institute of Korean Language (CC BY-SA 2.0 KR, krdict.korean.go.kr), via github.com/basickorean/basickorean-vocab; with the Wiktionaries and WikDict.

Spanish, French, German, Italian, Russian: the English and Chinese Wiktionaries (CC BY-SA 4.0) as extracted by kaikki.org, and WikDict (CC BY-SA 4.0).

Word splitting: Lindera (MIT) with IPADIC, mecab-ko-dic (Apache-2.0) and jieba (MIT).

Changes: converted to SQLite word lists, meanings merged, shortened and simplified (Traditional to Simplified Chinese). These adapted dictionaries are shared under the same licenses and can be downloaded freely from github.com/0x696c757a696f/lumtub/releases/tag/learning.''';
