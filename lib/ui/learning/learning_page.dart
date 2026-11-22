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
import '../../learning/known_words.dart';
import '../../learning/learning.dart';
import '../../learning/review.dart';
import '../../learning/video_words.dart';
import '../../learning/word_token.dart';
import '../../learning/vocabulary.dart';
import '../../learning/word_voice.dart' show azureVoiceKey, azureVoiceRegion, googleVoiceKey;
import '../../save_file.dart';
import '../../widgets/settings_tiles.dart';
import '../app_icons.dart';
import '../motion.dart';
import '../app_shell.dart' show openSettings;
import '../common.dart';
import '../learning_drawer.dart' show LearningDrawerSection, addLearningDrawerSection, studyLockedView;
import '../pages/settings_sections.dart' show SettingsCategory;
import '../skin_paint.dart';
import '../theme.dart';
import 'review_page.dart' show openReview, showSavedWord, watchVocabularyMoment;
import '../../subtitle_cues.dart' show SubtitleCue;
import 'word_card.dart' show englishLevelName, showWordCard;

part 'learning_home.dart';
part 'learning_drawer_parts.dart';

/// 学习: the rail's page; over the watch page while a video is open, so
/// the video keeps playing.
Future<void> openLearningPage(BuildContext context, AppController controller) async {
  if (!controller.onWatchPage) return controller.navigate(PageMode.learning);
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (context) => _LearningPage(controller: controller)));
}

Future<void> openVocabularyBook(BuildContext context, AppController controller) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (context) => _VocabularyPage(controller: controller)));

/// What the settings show for the learning pack in one line.
String learningSummary(Learning learning) => learning.licensed
    ? tr('Licensed to {0}', [learning.license!.name.isEmpty ? '—' : learning.license!.name])
    : tr('Tap words for meanings, pinyin, vocabulary book, Anki export');

/// Unlocks a purchase: asks for the order number, and for Ko-fi and Polar
/// the email paid with too, and fetches the code from the license server.
Future<bool> claimPurchase(BuildContext context, Learning learning, {required bool afdianFirst}) async {
  final outer = context;
  final field = TextEditingController();
  final email = TextEditingController();
  var source = afdianFirst ? PurchaseSource.afdian : PurchaseSource.kofi;
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
        if (result == ClaimResult.devices) {
          Navigator.pop(context, false);
          if (context.mounted) unawaited(manageLicenseDevices(context, learning));
          return;
        }
        setState(() {
          busy = false;
          error = switch (result) {
            ClaimResult.notFound => switch (source) {
                PurchaseSource.afdian => tr('No paid order with this number was found. Copy the order number from your Afdian order page.'),
                PurchaseSource.creem => tr('No card order with this ID and email was found yet. Check both against the page shown after paying or the receipt Creem emailed you, or wait a minute and try again.'),
                PurchaseSource.polar => tr('No Polar order with this ID and email was found yet. Check both against the page shown after paying or your Polar receipt, or wait a minute and try again.'),
                PurchaseSource.kofi => tr('No Ko-fi purchase with this transaction ID and email was found yet. Check both against your Ko-fi receipt, or wait a minute and try again.'),
              },
            ClaimResult.busy => tr('Too many tries. Wait a minute and try again.'),
            ClaimResult.revoked => learning.lastRefunded ? tr('This order was refunded, so the learning pack is off. Your vocabulary book stays on this device and can still be exported.') : tr('This code has been revoked because it was shared publicly. If you bought it, write to the author with your order number.'),
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
              // Creem is ready on the server but not selling (its terms
              // exclude video downloaders), so it is not offered.
              for (final s in PurchaseSource.values.where((s) => s != PurchaseSource.creem))
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
                  PurchaseSource.creem => tr('Order ID (starts with ord_)'),
                  PurchaseSource.polar => tr('Polar order ID'),
                  PurchaseSource.kofi => tr('Ko-fi transaction ID'),
                },
                helperText: switch (source) {
                  PurchaseSource.afdian => tr('Afdian › My orders › the order › Order number'),
                  PurchaseSource.creem || PurchaseSource.polar => tr('Shown on the page after paying'),
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
                  labelText: switch (source) {
                    PurchaseSource.polar => tr('Email you paid with on Polar'),
                    PurchaseSource.kofi => tr('Email you paid with on Ko-fi'),
                    _ => tr('Email you paid with'),
                  },
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
            Wrap(spacing: 8, children: [
              TextButton(onPressed: () => unawaited(showLearningPrivacy(context)), child: Text(tr('Activation and privacy'))),
              TextButton(
                onPressed: busy
                    ? null
                    : () {
                        Navigator.pop(context, false);
                        unawaited(enterLicenseCode(outer, learning));
                      },
                child: Text(tr('Have a license code? Enter it')),
              ),
            ]),
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
      PurchaseSource.creem => tr('Card (Creem)'),
      PurchaseSource.polar => 'Polar',
      PurchaseSource.kofi => 'Ko-fi',
    };

/// The card checkout (Creem, else Polar), asked once a run; null while
/// card payments are closed (the published checkout files are empty),
/// and only Afdian is offered.
Future<Uri?> cardCheckout() => _cardCheckout ??= cardCheckoutLink();
Future<Uri?>? _cardCheckout;

/// Opens the card checkout, or Afdian while there is none.
Future<void> _buyByCard() async {
  final checkout = await cardCheckout();
  await openExternal(checkout?.toString() ?? learningAfdianItem);
}

/// The learning pack's price, kept in this one place: [learningPresale]
/// while the pre-sale runs, then null, and [learningPrice] alone shows.
/// The learning pack as a one-off item on Afdian (Alipay, WeChat).
const learningAfdianItem = 'https://afdian.com/item/1257acd0e5cc11f1a9d05254001e7c00';

const learningPrice = (euro: '€16', yuan: '¥129');
({String euro, String yuan})? get learningPresale => (euro: '€12', yuan: '¥99');

/// The last day of the pre-sale price.
/// Through the Christmas and New Year holidays.
final learningPresaleEnds = DateTime(2027, 1, 3);

/// "until 3 January" while the pre-sale runs, else null.
String? learningPresaleDeadline() {
  if (learningPresale == null || DateTime.now().isAfter(learningPresaleEnds.add(const Duration(days: 1)))) return null;
  final day = currentLanguage.isChinese ? '${learningPresaleEnds.month} 月 ${learningPresaleEnds.day} 日' : '${learningPresaleEnds.day} ${const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][learningPresaleEnds.month - 1]}';
  return tr('Pre-sale price until {0}', [day]);
}

/// The price in one line, in yuan too for a Chinese interface.
String learningPriceLine() {
  String shown(({String euro, String yuan}) price) => currentLanguage.isChinese ? '${price.yuan} / ${price.euro}' : price.euro;
  final pre = learningPresale;
  if (pre == null) return tr('{0}, paid once', [shown(learningPrice)]);
  return tr('Pre-sale price {0}, paid once ({1} after launch; nothing more to pay then)', [shown(pre), shown(learningPrice)]);
}

/// The price as a tag: the pre-sale price, the price after launch struck
/// through beside it, and that it is paid once.
class LearningPriceTag extends StatelessWidget {
  const LearningPriceTag({super.key, this.size = 16});
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    String shown(({String euro, String yuan}) price) => currentLanguage.isChinese ? '${price.yuan} / ${price.euro}' : price.euro;
    final pre = learningPresale;
    final small = TextStyle(fontSize: size * 0.8, color: colors.outline);
    return Text.rich(TextSpan(children: [
      if (pre != null) TextSpan(text: '${tr('Pre-sale')} ', style: small.copyWith(color: colors.primary, fontWeight: FontWeight.w600)),
      TextSpan(text: shown(pre ?? learningPrice), style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: colors.primary)),
      if (pre != null) TextSpan(text: '  ${shown(learningPrice)}', style: small.copyWith(decoration: TextDecoration.lineThrough, decorationColor: colors.outline)),
      TextSpan(text: '  ${pre != null ? tr('paid once, nothing more to pay after launch') : tr('paid once')}', style: small),
      if (learningPresaleDeadline() case final until?) TextSpan(text: '\n$until', style: small.copyWith(color: colors.primary)),
    ]));
  }
}

/// Where the free trial stands: the free lookups left, or today's
/// lookups after it.
String learningTrialLine(Learning learning) => learning.inTrial
    ? tr('Free trial: everything on for {0} more word lookups, then {1} a day. Buy once to keep it all.', [learning.trialTotalLeft, Learning.trialPerDay])
    : tr('Trial over. Free today: {0} of {1} word lookups left. Buy once to turn everything back on.', [learning.trialLeft, Learning.trialPerDay]);

/// The trial in one line, before anything was looked up.
String learningTrialOffer() => tr('Free to try: everything on for the first {0} word lookups, then {1} a day, no account', [Learning.trialTotal, Learning.trialPerDay]);

/// What the learning pack unlocks, in one paragraph.
String learningPackFeatures() => tr(
    'The learning pack gives offline dictionaries for nine languages, unlimited word lookups, pinyin and kana above subtitles, harder words highlighted, words read aloud, the vocabulary book with the line and its sound, Anki export and the four-step video study, on up to 5 devices, with one payment and no subscription.');

/// A paid feature was asked for after the free trial: what the pack
/// gives, its price, and the ways to buy or unlock it.
Future<void> showLearningLocked(BuildContext context, Learning learning, {String? title, String? lead}) => showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title ?? tr('A learning pack feature')),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(lead ?? tr('The {0} free trial lookups are used up.', [Learning.trialTotal]), style: Theme.of(dialog).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
            if (_soFar(learning) case final soFar?) Padding(padding: const EdgeInsets.only(top: 4), child: Text(soFar)),
            const SizedBox(height: 8),
            Text(learningPackFeatures()),
            const SizedBox(height: 8),
            Text(tr('Words you saved stay yours: you can still see them and export them as CSV.'),
                style: Theme.of(dialog).textTheme.bodySmall?.copyWith(color: Theme.of(dialog).colorScheme.outline)),
            const SizedBox(height: 16),
            const Entrance(scale: 0.96, child: LearningPriceTag(size: 20)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: Text(tr('Later'))),
          TextButton(
            onPressed: () {
              Navigator.pop(dialog);
              unawaited(claimPurchase(context, learning, afdianFirst: currentLanguage.isChinese));
            },
            child: Text(tr('I bought it: unlock')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialog);
              unawaited(buyLearningPack());
            },
            child: Text(tr('Buy the learning pack')),
          ),
        ],
      ),
    );

/// What the learner did in the trial, so buying reads as carrying on.
String? _soFar(Learning learning) {
  final looked = Learning.trialTotal - learning.trialTotalLeft;
  final saved = learning.book?.words.length ?? 0;
  if (looked == 0 && saved == 0) return null;
  return saved > 0
      ? tr('So far you looked up {0} words and saved {1}. Buy once and carry on where you are.', [looked, saved])
      : tr('So far you looked up {0} words. Buy once and carry on where you are.', [looked]);
}

/// Opens the checkout the interface's language suggests: Afdian (Alipay,
/// WeChat) for Chinese, Polar (cards) otherwise.
Future<void> buyLearningPack() => currentLanguage.isChinese ? openExternal(learningAfdianItem) : _buyByCard();

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
    tr('What it includes: unlimited word lookup in subtitles with offline dictionaries, readings above words, harder words highlighted, reading aloud, the vocabulary book with Anki export, the four-step video study, on up to 5 devices, with updates.'),
    tr('Lost the code? Unlock again with the same order. Orders, refunds and questions: {0}', [learningContact]),
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
      VoiceService.edge => tr("Edge's online voices: natural, free, nothing to set up; the computer's voice when they can't be reached"),
      VoiceService.lumtub => tr("Natural voices through Lumtub's server"),
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
        for (final v in VoiceService.values.where((v) => v != VoiceService.lumtub))
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
              final result = await learning.enterLicense(field.text);
              if (!context.mounted) return;
              switch (result) {
                case LicenseResult.ok || LicenseResult.offline:
                  Navigator.pop(context, true);
                case LicenseResult.devices:
                  Navigator.pop(context, false);
                  unawaited(manageLicenseDevices(context, learning));
                case LicenseResult.revoked:
                  setState(() => error = learning.lastRefunded ? tr('This order was refunded, so the learning pack is off. Your vocabulary book stays on this device and can still be exported.') : tr('This code has been revoked because it was shared publicly. If you bought it, write to the author with your order number.'));
                case LicenseResult.invalid:
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
  Widget build(BuildContext context) => Scaffold(
        appBar: SkinAppBar(AppBar(title: Text(tr('Learning')))),
        body: LearningHome(controller: controller),
      );
}

Widget _voiceKeyItem(BuildContext context, AppController controller, String title, String name, {bool secret = true}) {
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

/// The learning pack's own settings, for 设置 › 学习, each wrapped so it
/// follows the pack's state.
List<(String, String, WidgetBuilder)> learningSettingRows(AppController controller) {
  final learning = controller.learning;
  Widget live(Widget Function(BuildContext context) build) => ListenableBuilder(listenable: learning, builder: (context, _) => build(context));
  return [
    (tr('Learning pack'), '学习包 learning dictionary license 词典 授权码 设备', (context) => live((context) => NormalItem(
          title: tr('Learning pack'),
          subtitle: learningSummary(learning),
          leading: Icon(AppIcons.graduationCap),
          onTap: () => unawaited(openLearningPage(context, controller)),
        ))),
    (tr('Pause while the mouse is on a subtitle line'), '悬停暂停 鼠标 字幕 hover pause', (context) => live((context) => SwitchItem(
          title: tr('Pause while the mouse is on a subtitle line'),
          subtitle: tr('Read and tap the words at ease; it plays on when the mouse leaves'),
          leading: Icon(AppIcons.pauseCircle),
          value: learning.hoverPause,
          onChanged: (on) => unawaited(learning.setHoverPause(on)),
        ))),
    (tr('Show pinyin and kana above subtitles'), '拼音 假名 pinyin kana', (context) => live((context) => SwitchItem(
          title: tr('Show pinyin and kana above subtitles'),
          subtitle: tr('Above each word, on the video and in the subtitle list'),
          leading: Icon(AppIcons.subtitles),
          value: learning.showPinyin,
          onChanged: (on) => unawaited(learning.setShowPinyin(on)),
        ))),
    (tr('Romanization above Korean'), '韩语 罗马字 romanization', (context) => live((context) => SwitchItem(
          title: tr('Romanization above Korean'),
          subtitle: tr('Korean words in Latin letters, such as hangugeo above 한국어'),
          leading: Icon(AppIcons.subtitles),
          value: learning.showRomanization,
          onChanged: (on) => unawaited(learning.setShowRomanization(on)),
        ))),
    (tr('Voice for reading words'), '朗读 发音 语音 TTS Azure Google voice', (context) => live((context) => Column(mainAxisSize: MainAxisSize.min, children: [
          NormalItem(
            title: tr('Voice for reading words'),
            subtitle: _voiceLabel(learning.voiceService),
            leading: Icon(AppIcons.speakerHigh),
              onTap: () => unawaited(_pickVoice(context, learning)),
          ),
          if (learning.voiceService == VoiceService.azure) ...[
            _voiceKeyItem(context, controller, tr('Azure key'), azureVoiceKey),
            _voiceKeyItem(context, controller, tr('Azure region, such as westeurope'), azureVoiceRegion, secret: false),
          ],
          if (learning.voiceService == VoiceService.google) _voiceKeyItem(context, controller, tr('Google Cloud key'), googleVoiceKey),
        ]))),
    (tr('Meanings in'), '释义 语言 meanings', (context) => live((context) => NormalItem(
          title: tr('Meanings in'),
          subtitle: _meaningLabel(learning.meanings),
          leading: Icon(AppIcons.translate),
          onTap: () => unawaited(_pickMeanings(context, learning)),
        ))),
    (tr('My English level'), '英语水平 难词 CEFR level', (context) => live((context) => NormalItem(
          title: tr('My English level'),
          subtitle: learning.englishLevel == null
              ? tr('Hard words are not marked')
              : tr('{0}. Harder words stand out in color', [englishLevelName(EnglishLevel.values[learning.englishLevel!])]),
          leading: Icon(AppIcons.graduationCap),
          onTap: () => unawaited(_pickEnglishLevel(context, learning)),
        ))),
  ];
}

/// Who made the dictionaries, as their licenses ask to be shown.
Future<void> showLearningSources(BuildContext context) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Data sources and licenses')),
        content: const SizedBox(width: 520, child: SingleChildScrollView(child: SelectableText(learningDataNotice))),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Close')))],
      ),
    );

class _Pitch extends StatelessWidget {
  const _Pitch({required this.learning});
  final Learning learning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final zh = currentLanguage.isChinese;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _Badge(icon: AppIcons.graduationCap, size: 48),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Learning pack'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const LearningPriceTag(),
              ]),
            ),
          ]),
          const SizedBox(height: Space.l),
          _FeatureGrid(features: [
            (AppIcons.handTap, tr('Tap any word in a subtitle'), tr('Offline dictionaries for nine languages, Chinese meanings first; conjugated and inflected forms lead to their word.')),
            (AppIcons.textAa, tr('Readings above the words'), tr('Pinyin above Chinese, kana above Japanese, romanization above Korean.')),
            (AppIcons.sparkle, tr('Harder words stand out'), tr('English words above your level are highlighted, from middle school and CET-4 up to TOEFL, IELTS and GRE; Korean words show their level.')),
            (AppIcons.speakerHigh, tr('Hear it'), tr('The word read aloud, or the line once more in the speaker\'s own voice.')),
            (AppIcons.bookOpenText, tr('A vocabulary book that remembers where'), tr('Each word keeps its line, translation, video and moment: tap it to watch that moment again.')),
            (AppIcons.brain, tr('Review at the right time'), tr('Words come back just before you would forget them, in the line they were said in, with its own sound.')),
            (AppIcons.cards, tr('Anki with the real sound'), tr('Send words to Anki in one tap with the audio of the line, or save an Anki import file or CSV.')),
            (AppIcons.graduationCap, tr('Study a video in four steps'), tr('Listen without subtitles, read along, shadow the hard lines, listen again.')),
            (AppIcons.cloudSlash, tr('Works offline'), tr('Dictionaries live on your computer: lookups need no internet and send nothing anywhere.')),
          ]),
          const SizedBox(height: Space.m),
          _FreeExtras(),
          const SizedBox(height: 8),
          Text(
            tr('Chinese, English, Japanese, Korean, Spanish, French, German, Italian and Russian. One payment, up to 5 devices, no account, no subscription. Buying it keeps Lumtub alive.'),
            style: TextStyle(color: theme.colorScheme.outline, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: Space.s),
          Text(learningTrialLine(learning), style: theme.textTheme.bodyMedium),
          if (learning.inTrial && learning.trialTotalLeft < Learning.trialTotal) ...[
            const SizedBox(height: 6),
            _TrialBar(used: (Learning.trialTotal - learning.trialTotalLeft) / Learning.trialTotal),
          ],
          const SizedBox(height: 12),
          FutureBuilder<Uri?>(
            future: cardCheckout(),
            builder: (context, snapshot) {
              final card = snapshot.data != null;
              final afdianFirst = zh || !card;
              return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                FilledButton(
                  onPressed: () => unawaited(afdianFirst ? openExternal(learningAfdianItem) : _buyByCard()),
                  child: Text(afdianFirst ? tr('Buy on Afdian (Alipay, WeChat)') : tr('Buy on Ko-fi (card, PayPal)')),
                ),
                if (card)
                  OutlinedButton(
                    onPressed: () => unawaited(zh ? _buyByCard() : openExternal(learningAfdianItem)),
                    child: Text(zh ? tr('Buy on Ko-fi (card, PayPal)') : tr('Buy on Afdian (Alipay, WeChat)')),
                  ),
                TextButton(onPressed: () => unawaited(claimPurchase(context, learning, afdianFirst: zh)), child: Text(tr('I bought it: unlock'))),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}

/// How much of the free trial is used, filling up to where it stands.
class _TrialBar extends StatelessWidget {
  const _TrialBar({required this.used});
  final double used;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 320,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: used),
        duration: Motion.of(const Duration(milliseconds: 700)),
        curve: Ease.curve,
        builder: (context, value, _) => ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(value: value, minHeight: 6, color: colors.primary, backgroundColor: colors.primaryContainer),
        ),
      ),
    );
  }
}

/// The pack's features as tiles, three across on a wide page.
class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid({required this.features});
  final List<(IconData, String, String)> features;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
      final across = constraints.maxWidth > 760 ? 3 : (constraints.maxWidth > 480 ? 2 : 1);
      final width = (constraints.maxWidth - (across - 1) * Space.s) / across;
      return Wrap(spacing: Space.s, runSpacing: Space.s, children: [
        for (final (i, (icon, title, detail)) in features.indexed)
          Entrance(
            duration: Motion.of(Duration(milliseconds: 260 + 50 * i)),
            scale: 0.95,
            child: Container(
              width: width,
              constraints: const BoxConstraints(minHeight: 128),
              padding: const EdgeInsets.all(Space.m),
              decoration: BoxDecoration(border: Border.all(color: colors.outlineVariant), borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: colors.primaryContainer, shape: BoxShape.circle),
                  child: Icon(icon, size: 18, color: colors.primary),
                ),
                const SizedBox(height: Space.s),
                Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(detail, style: theme.textTheme.bodySmall?.copyWith(color: colors.outline, height: 1.45)),
              ]),
            ),
          ),
      ]);
    });
  }
}

/// What stays free with or without the pack, as a row of small chips.
class _FreeExtras extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text(tr('Free for everyone as well:'), style: TextStyle(fontSize: 12, color: colors.outline)),
      for (final name in [tr('Pause after each line'), tr('Blur the translation'), tr('Loop this line'), tr('Record yourself'), tr('AI video overview')])
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
          child: Text(name, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
        ),
    ]);
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
    if (anki && !widget.controller.learning.unlocked) return showLearningLocked(context, widget.controller.learning);
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
    if (!widget.controller.learning.unlocked) return showLearningLocked(context, widget.controller.learning);
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

  @override
  Widget build(BuildContext context) {
    final book = _book;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: SkinAppBar(AppBar(title: Text(tr('Vocabulary book')), actions: [
        TextButton.icon(
          onPressed: _sending ? null : () => unawaited(_sendToAnki()),
          icon: _sending
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(widget.controller.learning.unlocked ? AppIcons.paperPlaneRight : AppIcons.lock, size: 18),
          label: Text(tr('Send to Anki')),
        ),
        TextButton.icon(
            onPressed: () => unawaited(_export(anki: true)),
            icon: Icon(widget.controller.learning.unlocked ? AppIcons.downloadSimple : AppIcons.lock, size: 18),
            label: const Text('Anki')),
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
                      onTap: () => unawaited(showSavedWord(context, widget.controller, w)),
                      title: Text.rich(TextSpan(children: [
                        TextSpan(text: w.word, style: const TextStyle(fontSize: 18)),
                        if (w.reading.isNotEmpty) TextSpan(text: '  ${w.reading}', style: TextStyle(color: colors.primary)),
                      ])),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (w.meaning.isNotEmpty) Text(w.meaning, maxLines: 2, overflow: TextOverflow.ellipsis),
                        if (w.sentence.isNotEmpty) Text(w.sentence, style: TextStyle(color: colors.outline)),
                        if (w.videoTitle.isNotEmpty) Text('${w.videoTitle} · ${clockOf(w.at)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: colors.outline)),
                      ]),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (w.videoId.isNotEmpty)
                          IconButton(tooltip: tr('Watch this moment'), icon: Icon(AppIcons.playCircle, size: 18), onPressed: () => watchVocabularyMoment(context, widget.controller, w)),
                        IconButton(tooltip: tr('Delete'), icon: Icon(AppIcons.trash, size: 18), onPressed: () => unawaited(book.remove(w))),
                      ]),
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
/// The devices a code is active on, with a way to remove each; for a code
/// that could not be activated here ([Learning.pendingLicense]), removing
/// one lets it activate here.
Future<void> manageLicenseDevices(BuildContext context, Learning learning) async {
  final pending = learning.pendingLicense;
  final license = pending ?? learning.license;
  if (license == null) return;
  final here = await learning.thisDevice();
  var list = await learning.loadDevices(license: license);
  var busy = false;
  String? error;
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(builder: (context, setState) {
      final colors = Theme.of(context).colorScheme;
      Future<void> remove(String id) async {
        setState(() => busy = true);
        final ok = await learning.removeDevice(id, license: license);
        list = learning.devices;
        if (!context.mounted) return;
        setState(() {
          busy = false;
          error = ok ? null : tr('Could not reach the license server. Check your connection, or ask for your code by message.');
        });
      }

      Future<void> activateHere() async {
        setState(() => busy = true);
        final result = await learning.enterLicense(license.code);
        if (!context.mounted) return;
        if (result == LicenseResult.ok || result == LicenseResult.offline) {
          Navigator.pop(context);
          return;
        }
        list = learning.devices;
        setState(() {
          busy = false;
          error = result == LicenseResult.devices ? tr('Still on as many devices as it allows. Remove one first.') : tr('This code has been revoked because it was shared publicly. If you bought it, write to the author with your order number.');
        });
      }

      final waiting = pending != null && (list?.length ?? learning.maxDevices) >= learning.maxDevices;
      return AlertDialog(
        title: Text(tr('Devices')),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              pending != null
                  ? tr('This code is on {0} devices, the most it allows. Remove one you no longer use, then activate it here.', ['${learning.maxDevices}'])
                  : tr('A code works on up to {0} devices. Only the kind of system is kept, never the computer\'s name.', ['${learning.maxDevices}']),
            ),
            const SizedBox(height: 8),
            if (list == null)
              Text(tr('Could not reach the license server. Check your connection, or ask for your code by message.'), style: TextStyle(color: colors.error))
            else
              for (final d in list!)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(d.id == here ? '${d.label} · ${tr('This device')}' : d.label),
                  subtitle: Text(tr('Last seen {0}', [d.seen])),
                  trailing: d.id == here ? null : TextButton(onPressed: busy ? null : () => unawaited(remove(d.id)), child: Text(tr('Remove'))),
                ),
            if (error != null) Text(error!, style: TextStyle(color: colors.error)),
            const SizedBox(height: 8),
            SelectableText(tr('Code ID: {0}', [license.id]), style: TextStyle(fontSize: 11, color: colors.outline)),
            TextButton(onPressed: () => unawaited(showLearningPrivacy(context)), child: Text(tr('Activation and privacy'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Close'))),
          if (pending != null) FilledButton(onPressed: busy || waiting ? null : () => unawaited(activateHere()), child: Text(tr('Activate here'))),
        ],
      );
    }),
  );
}

/// The privacy notice for buying and activating the learning pack.
Future<void> showLearningPrivacy(BuildContext context) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Activation and privacy')),
        content: SizedBox(width: 560, child: SingleChildScrollView(child: SelectableText(currentLanguage.isChinese ? learningPrivacyZh : learningPrivacyEn))),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Close')))],
      ),
    );

/// Where buyers write about orders, refunds and their data.
const learningContact = '7poad30n5@mozmail.com';

/// 订单与退款: how a code is recovered, what happens on a refund, and
/// whom to write to.
Future<void> showLearningOrders(BuildContext context) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Orders and refunds')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: SelectableText([
              tr('Lost your code, or a new computer: choose I bought it: unlock and enter the same order again. You get the same code; nothing is bought twice.'),
              tr('A code works on up to 5 devices. Remove one you no longer use under Learning › Devices; a reinstalled Lumtub counts as a new device.'),
              tr('Once the code is activated it keeps working without internet; Lumtub only checks now and then, when it can.'),
              tr('The learning pack is digital content: once it is activated, it is not refunded for a change of mind. If a problem in Lumtub keeps it from working and cannot be fixed, or you were charged by mistake, write to us with your order number and we will refund you. A refunded order stops its code; your vocabulary book stays on your computer and can still be exported.'),
              tr('Orders, refunds and questions: {0}', [learningContact]),
            ].join('\n\n')),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Close')))],
      ),
    );

const learningPrivacyEn = '''Activation and privacy (learning pack)

Controller: Lumtub (Italy). Privacy contact: 7poad30n5@mozmail.com

What is kept, and why
• Unlocking a purchase: the order number, a SHA-256 hash of the email you paid with (Ko-fi and Polar; never the email itself), the order date, and when you agreed that the pack is supplied at once (proof of the end of the 14-day withdrawal right). Basis: performing the licence (GDPR art. 6(1)(b)) and legal obligations (6(1)(c)). Kept while the licence is valid.
• Activating a device: a hashed installation identifier (a random number Lumtub makes once when it is installed; nothing is read from your hardware or system), the kind of system (Windows, macOS…), and the dates the device was added and last confirmed. Used to activate the pack and keep a code to at most 5 devices. Basis: performing the licence (6(1)(b)) and our legitimate interest in preventing a code being shared (6(1)(f)). Removed at once when you remove the device in the app, and automatically 24 months after the device last confirmed the code.
• Refunds: when an order is refunded in full, the date of the refund, so its code stops. Basis: performing the licence (6(1)(b)).
How long: order and code records are kept as long as the licence is valid, so you can always get your code again on a new computer; device entries as above; payment and tax records are kept by the payment platform under the law that applies to it.
• IP address: seen by the server to limit how often it can be asked; our own record of it is deleted within 2 minutes. Basis: legitimate interest in keeping the service safe (6(1)(f)).
Words you look up, your vocabulary book and what you watch stay on your device and are never sent.

Who processes it
The server runs on Cloudflare (Cloudflare, Inc.) as our processor, which may involve transfer to the United States under the EU–US Data Privacy Framework or Standard Contractual Clauses. Workers Logs and request logging are turned off for this service; Cloudflare's own operational and security logs follow its policies. Payments are handled by Polar, Ko-fi or Afdian under their own privacy policies.

Your rights
You may ask for access, correction, deletion, restriction, objection and a copy of your data, and complain to a supervisory authority (in Italy the Garante per la protezione dei dati personali). Write to the email above; we answer within one month. Without the device identifier the pack cannot be activated online. The 5-device limit is checked automatically; write to us if you need it looked at by a person.

Last updated: 21 November 2026''';

const learningPrivacyZh = '''激活与隐私说明（学习包）

数据控制者：Lumtub（意大利）。隐私联系邮箱：7poad30n5@mozmail.com

保存什么，为什么
• 领取购买的激活码：订单号、付款邮箱的 SHA-256 哈希值（Ko-fi 和 Polar；不保存邮箱本身）、订单日期，以及你同意「立即提供、14 天撤回权随之结束」的时间。法律依据：履行许可合同（GDPR 第 6(1)(b) 条）及法定义务（第 6(1)(c) 条）。在授权有效期间保存。
• 激活设备：经过哈希的安装标识（Lumtub 安装后生成一次的随机数，不读取任何硬件或系统信息）、系统类型（Windows、macOS 等）、设备加入和最近确认的日期。用于激活学习包，并把一个激活码限制在最多 5 台设备（2026 年 11 月 21 日前发出的激活码为 5 台）。法律依据：履行许可合同（第 6(1)(b) 条）及防止激活码被分享的正当利益（第 6(1)(f) 条）。你在 App 里移除设备时立即删除；从该设备最后一次确认起满 24 个月自动删除。
• 退款：订单全额退款时记录退款日期，相应激活码随之停用。法律依据：履行许可合同（第 6(1)(b) 条）。
保存期限：订单和激活码记录在授权有效期间一直保存，方便你在新电脑上随时重新领取；设备记录如上；付款和税务记录由付款平台按其适用法律保存。
• IP 地址：服务器用来限制请求频率，我们自己的记录在 2 分钟内删除。法律依据：保障服务安全的正当利益（第 6(1)(f) 条）。
你查的词、生词本和观看内容都只保存在你的设备上，不会发送。

谁来处理
服务器运行在 Cloudflare（Cloudflare, Inc.）上，作为我们的数据处理者，可能涉及向美国传输，依据欧美数据隐私框架（DPF）或欧盟标准合同条款。本服务关闭了 Workers 日志和请求日志；Cloudflare 自身的运行和安全日志遵循其政策。付款由 Polar、Ko-fi 或爱发电处理，适用它们各自的隐私政策。

你的权利
你可以要求访问、更正、删除、限制处理、反对处理，以及获取数据副本，也可以向监管机构投诉（意大利为 Garante per la protezione dei dati personali）。请写信到上面的邮箱，我们会在一个月内答复。不提供设备标识就无法在线激活。设备数上限由系统自动检查；如需人工处理，请来信。

更新日期：2026 年 11 月 21 日''';

const learningDataNotice = '''English: the word list, word forms and exam tags of ECDICT by skywind3000 (MIT, github.com/skywind3000/ECDICT). Chinese meanings from the Mandarin translations in the English Wiktionary and from the Chinese Wiktionary (CC BY-SA 4.0, wiktionary.org) as extracted by kaikki.org; the Chinese Open Wordnet, © 2013–2026 Francis Bond, Shan Wang and Luís Morgado da Costa (bond-lab.github.io/cow/LICENSE), through WordNet 3.0; where none has a word, WikDict's translations (CC BY-SA 4.0, wikdict.com), marked as reference translations. Pronunciations (IPA) from the English Wiktionary. Frequency ranks from wordfreq by Robyn Speer (data CC BY-SA 4.0). English meanings from the Simple English and English Wiktionaries (CC BY-SA 4.0, wiktionary.org) as extracted by kaikki.org, and from WordNet 3.0, © Princeton University (WordNet license). CEFR levels: The CEFR-J Wordlist Version 1.5, compiled by Yukio Tono, Tokyo University of Foreign Studies (cefr-j.org), and the Octanove Vocabulary Profile C1/C2 1.0 by Octanove Labs (CC BY-SA 4.0), via github.com/openlanguageprofiles/olp-en-cefrj.

Japanese: JMdict, © Electronic Dictionary Research and Development Group (CC BY-SA 4.0, edrdg.org/edrdg/licence.html), via jmdict-simplified; Chinese meanings from the Chinese Wiktionary (CC BY-SA 4.0) and WikDict (CC BY-SA 4.0, wikdict.com).

Chinese: CC-CEDICT by MDBG (CC BY-SA 4.0, cc-cedict.org).

Korean: 한국어기초사전 (Korean Basic Dictionary), National Institute of Korean Language (CC BY-SA 2.0 KR, krdict.korean.go.kr), via github.com/basickorean/basickorean-vocab; with the Wiktionaries and WikDict.

Spanish, French, German, Italian, Russian: the English and Chinese Wiktionaries (CC BY-SA 4.0) as extracted by kaikki.org, and WikDict (CC BY-SA 4.0).

Word splitting: Lindera (MIT) with IPADIC, mecab-ko-dic (Apache-2.0) and jieba (MIT).

Changes: converted to SQLite word lists, meanings merged, shortened and simplified (Traditional to Simplified Chinese). These adapted dictionaries are shared under the same licenses and can be downloaded freely from github.com/0x696c757a696f/lumtub/releases/tag/learning.

The learning pack's price pays for Lumtub's learning features and the service around them, not for this data: the dictionaries stay under their own licenses, and nothing in the purchase limits what those licenses let you do with them, such as copying, changing and sharing them.''';
