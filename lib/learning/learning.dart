import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_directories.dart';
import '../app_log.dart';
import '../l10n/l10n.dart' show currentLanguage;
import '../zip_archive.dart' show extractZip;
import 'chinese_dictionary.dart';
import 'device_id.dart';
import 'english_dictionary.dart';
import 'japanese_dictionary.dart';
import 'latin_language.dart';
import 'lexicon.dart';
import 'license.dart';
import 'vocabulary.dart';
import 'wiktionary_dictionary.dart';
import 'word_voice.dart';

export 'word_voice.dart' show VoiceService, VoiceException;

/// Where the dictionary packs are published: a release of the app's own
/// repository that holds data only, never an app version.
const learningPackRelease = 'https://github.com/0x696c757a696f/lumtub/releases/download/learning';
/// [downloaded]: on disk, read the first time subtitles in its language
/// show up, so dictionaries for languages not being watched take no memory.
enum PackState { missing, downloading, downloaded, loading, ready, failed }

/// The version of the statement a buyer agrees to before a bought code
/// is sent (the license server keeps it with the time): the pack is
/// supplied at once, which ends the 14-day right of withdrawal.
const learningConsentVersion = 'digital-content-v1';

/// How asking the license server for a bought code went.
enum ClaimResult { ok, notFound, busy, offline, revoked, devices }

/// How entering a code went. [offline]: it is a code, kept, and works
/// while the server is asked again at each start, for [Learning.grace].
enum LicenseResult { ok, invalid, revoked, devices, offline }

/// A device a code is active on, as the license server lists it.
class LicenseDevice {
  const LicenseDevice({required this.id, required this.label, required this.seen});
  final String id;
  final String label;
  final String seen;
}

/// What the license server said about a code on this device.
enum _Activation { ok, revoked, devices, offline }

/// A dictionary the learning pack downloads.
enum DictionaryPack {
  chinese('zh', 'zh-cedict.txt.gz'),
  english('en', 'en-ecdict.sqlite.gz'),
  japanese('ja', 'ja-jmdict.tsv.gz'),
  korean('ko', 'ko-wiktionary.sqlite.gz'),
  spanish('es', 'es-wiktionary.sqlite.gz'),
  french('fr', 'fr-wiktionary.sqlite.gz'),
  german('de', 'de-wiktionary.sqlite.gz'),
  italian('it', 'it-wiktionary.sqlite.gz'),
  russian('ru', 'ru-wiktionary.sqlite.gz');

  const DictionaryPack(this.language, this.file);
  final String language;
  final String file;

  /// Built from Wiktionary, read by [WiktionaryDictionary].
  bool get wiktionary => file.contains('-wiktionary.');

  /// A SQLite file the core looks words up in ([CoreLexicon]), kept
  /// unpacked on disk; the others are word lists read into memory.
  bool get sqlite => file.endsWith('.sqlite.gz');

  /// The name it is kept under.
  String get stored => sqlite ? file.substring(0, file.length - 3) : file;

  /// The Lindera dictionary the core cuts this language's lines into
  /// words with, downloaded beside the dictionary.
  String? get segmenter => switch (this) {
        japanese || korean || chinese => '$language-segmenter.zip',
        _ => null,
      };
}

/// One pack's download and reading.
class _Pack {
  Object? dictionary;
  PackState state = PackState.missing;
  double? progress;
  String? error;
  Future<void>? loading;
}

/// The learning pack: the license, the Chinese dictionary and the
/// vocabulary book. Everything stays on this device; the only request is
/// the one download of the dictionary, from GitHub.
class Learning extends ChangeNotifier {
  Learning();

  AppDirectories? _directories;
  LearningLicense? _license;

  /// The server's signed word that [_license] is active here ([_receipt]),
  /// the day it last said so, when the code was entered without one (the
  /// server out of reach), and whether the server has since refused it
  /// here: revoked, or this device taken off a code on its most devices.
  String _receipt = '';
  DateTime? _receiptDay;
  DateTime? _entered;
  bool _blocked = false;
  String? _deviceId;

  /// How long a code works on a device the server could not be asked for.
  static const grace = Duration(days: 14);

  /// How often the server is asked again whether a code is still good.
  static const recheck = Duration(days: 30);

  /// A code entered while all its device slots were taken, kept until a
  /// device is removed; and the devices the server last listed.
  LearningLicense? pendingLicense;
  List<LicenseDevice> devices = const [];
  int maxDevices = 2;
  bool _showPinyin = true;

  /// Korean in letters above the words; off by default, as Hangul reads
  /// as it sounds.
  bool _showRomanization = false;
  int? _englishLevel = EnglishLevel.cet4.index;
  bool _loaded = false;
  VocabularyBook? _book;

  final _packs = {for (final pack in DictionaryPack.values) pack: _Pack()};

  /// Changes what the video's subtitles show: the license, a dictionary
  /// being ready or gone, pinyin on or off. Download progress does not
  /// count.
  final viewChanges = ValueNotifier<int>(0);

  @override
  void notifyListeners() {
    final key = Object.hashAll([_license, licensed, unlocked, _showPinyin, _showRomanization, _englishLevel, for (final p in _packs.values) p.dictionary]);
    if (key != _lastView) {
      _lastView = key;
      viewChanges.value++;
    }
    super.notifyListeners();
  }

  Object? _lastView;

  LearningLicense? get license => _license;

  /// Without the pack: the first [trialTotal] word cards free with
  /// everything on, then this many a day with the pack's features off.
  /// A count rather than days, so a trial never runs past an offer's end.
  static const trialPerDay = 3;
  static const trialTotal = 30;
  String _trialDay = '';

  /// Word cards taken from [trialTotal] so far.
  int _trialTaken = 0;

  /// A word has been looked up here at least once: the getting-started
  /// steps tick it off.
  bool lookedUp = false;
  int _trialUsed = 0;

  /// Words already looked up today: opening one again costs nothing.
  final _trialWords = <String>{};
  static String get _today => DateTime.now().toIso8601String().substring(0, 10);

  /// The latest day the trial has seen, from this computer's clock or a
  /// server's: turning the clock back does not bring today's lookups back.
  String _trialSeen = '';
  String get _trialToday {
    final today = _today;
    return today.compareTo(_trialSeen) >= 0 ? today : _trialSeen;
  }

  /// Notes [day] (yyyy-mm-dd) as seen, when it is later than any before.
  bool _see(String day) {
    if (day.compareTo(_trialSeen) <= 0) return false;
    _trialSeen = day;
    return true;
  }

  /// Free word cards with everything on still left.
  int get trialTotalLeft => (trialTotal - _trialTaken).clamp(0, trialTotal);

  /// Without the pack, but still in the free trial.
  bool get inTrial => !licensed && trialTotalLeft > 0;

  /// The pack's features are on: bought, or in the free trial. Off, only
  /// [trialPerDay] word cards a day are left; dictionaries download and
  /// saved words can be seen and exported as CSV either way.
  bool get unlocked => licensed || trialTotalLeft > 0;

  /// Word cards left today without the pack; unlimited with it.
  int get trialLeft => licensed ? trialPerDay : (_trialDay == _trialToday ? (trialPerDay - _trialUsed).clamp(0, trialPerDay) : trialPerDay);

  /// Counts one word card; false when the free ones are used up. A [word]
  /// already looked up today is free.
  Future<bool> takeLookup(String word) async {
    if (!lookedUp) {
      lookedUp = true;
      if (licensed) {
        await _save();
        notifyListeners();
      }
    }
    if (licensed) return true;
    _see(_today);
    final today = _trialToday;
    if (_trialDay != today) {
      _trialDay = today;
      _trialUsed = 0;
      _trialWords.clear();
    }
    if (_trialWords.contains(word)) return true;
    if (trialTotalLeft > 0) {
      _trialTaken++;
    } else if (_trialUsed >= trialPerDay) {
      return false;
    } else {
      _trialUsed++;
    }
    _trialWords.add(word);
    await _save();
    notifyListeners();
    return true;
  }

  bool get licensed => _license != null && !_blocked && (_receiptDay != null || (_entered != null && DateTime.now().difference(_entered!) < grace));

  /// A code is kept but does not unlock here: revoked, taken off this
  /// device, or never confirmed by the server within [grace].
  bool get licenseStopped => _license != null && !licensed;

  /// Why, for [licenseStopped]: 'revoked', 'refunded', 'devices' or
  /// 'offline'.
  String _stopReason = '';

  /// The last refusal was for a refunded order rather than a code shared
  /// publicly.
  bool lastRefunded = false;
  String get licenseStopReason => _blocked ? _stopReason : 'offline';
  bool get showPinyin => _showPinyin;
  bool get showRomanization => _showRomanization;

  /// Which meanings a word card shows where a dictionary has both.
  /// Until one is chosen: Chinese first with a Chinese interface,
  /// English otherwise.
  MeaningLanguage get meanings => _meanings ?? (currentLanguage.isChinese ? MeaningLanguage.chineseFirst : MeaningLanguage.english);
  MeaningLanguage? _meanings;

  /// Who reads words aloud on a word card.
  VoiceService get voiceService => _voiceService;
  VoiceService _voiceService = VoiceService.system;

  /// Reads words aloud; null until the learning settings are read.
  WordVoice? get voice => _voice;
  WordVoice? _voice;

  /// The learner's English level as an index into [EnglishLevel.values];
  /// words above it stand out. Null marks nothing.
  int? get englishLevel => _englishLevel;

  /// Whether [token] is an English word above the learner's level.
  bool isHard(WordToken token) {
    final level = _englishLevel;
    final en = english;
    if (level == null || en == null || !unlocked || languageOf(token) != 'en') return false;
    final word = en.levelOf(token.key);
    return word != null && word > level;
  }
  PackState stateOf(DictionaryPack pack) => _packs[pack]!.state;
  double? progressOf(DictionaryPack pack) => _packs[pack]!.progress;
  String? errorOf(DictionaryPack pack) => _packs[pack]!.error;
  ChineseDictionary? get chinese => _packs[DictionaryPack.chinese]!.dictionary as ChineseDictionary?;
  EnglishDictionary? get english => _packs[DictionaryPack.english]!.dictionary as EnglishDictionary?;
  JapaneseDictionary? get japanese => _packs[DictionaryPack.japanese]!.dictionary as JapaneseDictionary?;
  /// Whether a dictionary is on disk, read or not: lines in its language
  /// are looked at, which reads it the first time.
  bool get anyDictionary => _packs.values.any((p) => const {PackState.downloaded, PackState.loading, PackState.ready}.contains(p.state));

  /// The Wiktionary dictionary for [language], when it is ready.
  WiktionaryDictionary? wiktionary(String language) {
    for (final pack in DictionaryPack.values) {
      if (pack.wiktionary && pack.language == language) return _packs[pack]!.dictionary as WiktionaryDictionary?;
    }
    return null;
  }

  final _latin = LatinLanguageGuess();

  /// [text] as words a tap looks up, when a dictionary for its language
  /// is ready; readings above them only while [unlocked].
  List<WordToken>? wordsOf(String text) {
    final words = _wordsOf(text);
    if (words == null || unlocked) return words;
    return [for (final w in words) w.reading == null ? w : WordToken(w.text, null, isWord: w.isWord, lookup: w.lookup, language: w.language)];
  }

  List<WordToken>? _wordsOf(String text) {
    if (JapaneseDictionary.looksJapanese(text) && _onDisk('ja')) {
      final ja = japanese;
      return ja == null ? null : _cut('ja', text) ?? ja.segment(text);
    }
    if (ChineseDictionary.looksChinese(text) && _onDisk('zh')) {
      final zh = chinese;
      return zh == null ? null : _cut('zh', text) ?? zh.segment(text);
    }
    if (WiktionaryDictionary.looksKorean(text)) {
      final words = _onDisk('ko') ? _wiktionaryWords('ko', text) : null;
      if (words == null || _showRomanization) return words;
      return [for (final w in words) w.reading == null ? w : WordToken(w.text, null, isWord: w.isWord, lookup: w.lookup, language: w.language)];
    }
    if (WiktionaryDictionary.looksCyrillic(text)) return _onDisk('ru') ? _wiktionaryWords('ru', text) : null;
    if (!EnglishDictionary.looksLatin(text)) return null;
    final latin = [for (final code in const ['en', 'es', 'fr', 'de', 'it']) if (_packs[DictionaryPack.values.firstWhere((p) => p.language == code)]!.state case PackState.downloaded || PackState.loading || PackState.ready) code];
    final language = _latin.guess(text, latin);
    // Read on first use; until then the line stays plain.
    if (language == null || !_onDisk(language)) return null;
    if (language == 'en') return english?.segment(text);
    return _wiktionaryWords(language, text);
  }

  List<WordToken>? _wiktionaryWords(String language, String text) {
    final dictionary = wiktionary(language);
    if (dictionary == null) return null;
    return _cut(language, text) ?? dictionary.segment(text);
  }

  /// [text] cut into words by the core: elision and joined pronouns
  /// handled, Japanese, Korean and Chinese by their segmenter. Null when
  /// the core cannot, and the dictionary's own cutting is used.
  List<WordToken>? _cut(String language, String text) {
    if (const {'ja', 'ko', 'zh'}.contains(language) && !CoreWords.isOpen(language)) return null;
    final words = CoreWords.cut(language, text);
    if (words == null) return null;
    final tokens = <WordToken>[];
    var at = 0;
    for (final w in words) {
      if (w.start < at || w.end > text.length || w.keys.isEmpty) continue;
      if (w.start > at) tokens.add(WordToken(text.substring(at, w.start), null, isWord: false, language: language));
      final surface = text.substring(w.start, w.end);
      final reading = switch (language) {
        'ja' => w.reading,
        'ko' => WiktionaryDictionary.romanizeKorean(surface),
        'zh' => chinese?.readingWithChars(surface),
        _ => null,
      };
      tokens.add(WordToken(surface, reading, isWord: true, lookup: _bestKey(language, w.keys), language: language));
      at = w.end;
    }
    if (at < text.length) tokens.add(WordToken(text.substring(at), null, isWord: false, language: language));
    return tokens;
  }

  /// The first of [keys] the dictionary knows; the core puts the ones its
  /// own dictionaries know first already.
  String _bestKey(String language, List<String> keys) {
    final ja = japanese;
    if (language == 'ja' && ja != null) {
      for (final key in keys) {
        if (ja.lookUpInflected(key).isNotEmpty) return key;
      }
    }
    return keys.first;
  }

  /// The language of the dictionary [token] is looked up in.
  static String languageOf(WordToken token) => token.language ?? (ChineseDictionary.isHan(token.text) ? 'zh' : 'en');
  VocabularyBook? get book => _book;

  File? get _settingsFile => _directories == null ? null : File('${_directories!.config.path}${Platform.pathSeparator}learning.json');
  Directory? _folderOf(DictionaryPack pack) => _directories == null ? null : Directory('${_directories!.data.path}${Platform.pathSeparator}learn${Platform.pathSeparator}${pack.language}');
  File? _fileOf(DictionaryPack pack) {
    final folder = _folderOf(pack);
    return folder == null ? null : File('${folder.path}${Platform.pathSeparator}${pack.stored}');
  }

  /// The SHA-256 sum of the download [pack]'s file came from, to tell
  /// when a newer one is published.
  File? _sumOf(DictionaryPack pack) {
    final file = _fileOf(pack);
    return file == null ? null : File('${file.path}.sha256');
  }

  /// Reads the saved license and settings; with a license, the
  /// dictionary is read in the background when it is there.
  Future<void> start(AppDirectories directories) async {
    if (_loaded) return;
    _loaded = true;
    _directories = directories;
    // Learners outside China know CEFR levels, not Chinese exam lists.
    EnglishEntry.preferCefr = !currentLanguage.isChinese;
    _voice = WordVoice(Directory('${directories.cache.path}${Platform.pathSeparator}word-sounds'));
    unawaited(_voice!.tidy());
    _book = VocabularyBook(File('${directories.data.path}${Platform.pathSeparator}vocabulary.json'));
    try {
      final file = _settingsFile!;
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        if (json is Map) {
          _showPinyin = json['pinyin'] != false;
          _showRomanization = json['romanization'] == true;
          _meanings = MeaningLanguage.values.where((m) => m.name == json['meanings']).firstOrNull;
          _voiceService = VoiceService.values.firstWhere((v) => v.name == json['voice'], orElse: () => VoiceService.system);
          final level = json['englishLevel'];
          if (level is int) _englishLevel = level >= 0 && level < EnglishLevel.beyond.index ? level : null;
          final code = json['license'];
          if (code is String && code.isNotEmpty) _license = await Isolate.run(() => LearningLicense.parse(code));
          _receipt = '${json['activation'] ?? ''}';
          _entered = DateTime.tryParse('${json['entered'] ?? ''}');
          _blocked = json['blocked'] == true;
          _stopReason = '${json['stopped'] ?? ''}';
          lookedUp = json['lookedUp'] == true;
          final trial = json['trial'];
          if (trial is Map) {
            _trialDay = '${trial['day'] ?? ''}';
            _trialTaken = trial['taken'] is int ? trial['taken'] as int : 0;
            _trialSeen = '${trial['seen'] ?? trial['day'] ?? ''}';
            _trialUsed = trial['used'] is int ? trial['used'] as int : 0;
            final words = trial['words'];
            if (words is List) _trialWords.addAll(words.whereType<String>());
          }
        }
      }
    } catch (e) {
      logWarn('Could not read the learning settings: $e');
    }
    // Read when a line in its language first needs it: reading a
    // dictionary at start held up the window's first frames.
    for (final pack in DictionaryPack.values) {
      if (await _fileOf(pack)!.exists()) _packs[pack]!.state = PackState.downloaded;
    }
    if (_license != null) {
      final license = _license!;
      final device = await _device();
      final receipt = _receipt;
      _receiptDay = await Isolate.run(() => ActivationReceipt.verify(receipt, codeId: license.id, device: device)?.day);
      // A code kept before devices were counted gets the same grace as
      // one entered offline.
      if (_receiptDay == null && _entered == null) {
        _entered = DateTime.now();
        await _save();
      }
      // Asked again now and then, and at once when never confirmed here.
      if (_receiptDay == null || DateTime.now().difference(_receiptDay!) > recheck) unawaited(_checkIn());
    }
    notifyListeners();
    // Everyone can try the pack, so dictionaries on disk stay current.
    unawaited(_book!.load());
    unawaited(_updateAll());
  }

  bool _updating = false;

  /// Downloads again, in the background, each dictionary on disk whose
  /// published file has changed since (one at a time, a little after
  /// start). The one in use stays until the new one is in place.
  Future<void> _updateAll() async {
    if (_updating) return;
    _updating = true;
    try {
      await Future<void>.delayed(const Duration(seconds: 20));
      final client = http.Client();
      final SignedSums sums;
      try {
        sums = await _signedSums(client);
      } finally {
        client.close();
      }
      if (_serverDay case final day? when !licensed && _see(day)) {
        await _save();
        notifyListeners();
      }
      for (final pack in DictionaryPack.values) {
        final file = _fileOf(pack);
        final sum = _sumOf(pack);
        if (file == null || sum == null || !await file.exists()) continue;
        final expected = sums.of(pack.file);
        if (expected == null) continue;
        final have = await sum.exists() ? (await sum.readAsString()).trim() : '';
        if (have == expected) continue;
        if (_packs[pack]!.state == PackState.downloading) continue;
        logInfo('A newer ${pack.name} dictionary is out; updating it');
        await download(pack, quiet: true);
      }
    } catch (e) {
      logWarn('Could not check for dictionary updates: $e');
    } finally {
      _updating = false;
    }
  }

  /// Today as the server's clock has it, in local time, when it said.
  static String? _serverDay;
  static String? _dayOf(String? date) {
    if (date == null) return null;
    try {
      return HttpDate.parse(date).toLocal().toIso8601String().substring(0, 10);
    } catch (_) {
      return null;
    }
  }

  /// The published SHA256SUMS, checked against its signature.
  static Future<SignedSums> _signedSums(http.Client client) async {
    final sums = await client.get(Uri.parse('$learningPackRelease/SHA256SUMS')).timeout(const Duration(seconds: 30));
    if (sums.statusCode != 200) throw HttpException('SHA256SUMS HTTP ${sums.statusCode}');
    _serverDay = _dayOf(sums.headers['date']);
    final signature = await client.get(Uri.parse('$learningPackRelease/SHA256SUMS.sig')).timeout(const Duration(seconds: 30));
    if (signature.statusCode != 200) throw HttpException('SHA256SUMS.sig HTTP ${signature.statusCode}');
    final signed = SignedSums.verify(sums.bodyBytes, signature.body);
    if (signed == null) throw const FormatException('The dictionary list is not signed by Lumtub');
    return signed;
  }

  /// Checks [code], activates it on this device and keeps it when it is a
  /// license.
  Future<LicenseResult> enterLicense(String code) async {
    final license = await Isolate.run(() => LearningLicense.parse(code));
    if (license == null) return LicenseResult.invalid;
    final (answer, receipt) = await _activate(license);
    switch (answer) {
      case _Activation.revoked:
        return LicenseResult.revoked;
      case _Activation.devices:
        pendingLicense = license;
        notifyListeners();
        return LicenseResult.devices;
      case _Activation.ok:
      case _Activation.offline:
        break;
    }
    final wasLicensed = licensed;
    pendingLicense = null;
    _license = license;
    _blocked = false;
    _stopReason = '';
    _receipt = receipt ?? '';
    _receiptDay = receipt == null ? null : DateTime.now();
    _entered = receipt == null ? DateTime.now() : null;
    await _save();
    notifyListeners();
    if (!wasLicensed) {
      unawaited(_book?.load());
      unawaited(_updateAll());
    }
    return answer == _Activation.ok ? LicenseResult.ok : LicenseResult.offline;
  }

  Future<String> _device() async => _deviceId ??= await learningDeviceId(_directories!.data);

  /// The license server's address, published on the `learning` release so
  /// it can move without an app update.
  static Future<Uri?> _server(http.Client client) async {
    final where = await client.get(Uri.parse('$learningPackRelease/license-server.txt')).timeout(const Duration(seconds: 20));
    final server = where.statusCode == 200 ? Uri.tryParse(where.body.trim()) : null;
    return server == null || server.scheme != 'https' ? null : server;
  }

  void _takeDevices(Object? answer) {
    if (answer is! Map) return;
    final list = answer['devices'];
    if (list is List) {
      devices = [
        for (final d in list)
          if (d is Map) LicenseDevice(id: '${d['id']}', label: '${d['label'] ?? ''}', seen: '${d['seen'] ?? ''}'),
      ];
    }
    if (answer['max'] is int) maxDevices = answer['max'] as int;
  }

  /// Asks the server to count this device for [license]; the receipt
  /// when it does.
  Future<(_Activation, String?)> _activate(LearningLicense license) async {
    final client = http.Client();
    try {
      final server = await _server(client);
      if (server == null) return (_Activation.offline, null);
      final response = await client
          .post(server.resolve('/activate'), headers: {'content-type': 'application/json'}, body: jsonEncode({'code': license.code, 'device': await _device(), 'label': learningDeviceLabel()}))
          .timeout(const Duration(seconds: 20));
      final answer = jsonDecode(response.body);
      _takeDevices(answer);
      if (response.statusCode == 403 && answer is Map && answer['error'] == 'revoked') {
        lastRefunded = answer['reason'] == 'refunded';
        return (_Activation.revoked, null);
      }
      if (response.statusCode == 409) return (_Activation.devices, null);
      final receipt = answer is Map ? answer['receipt'] : null;
      if (response.statusCode != 200 || receipt is! String) return (_Activation.offline, null);
      final device = await _device();
      final id = license.id;
      final valid = await Isolate.run(() => ActivationReceipt.verify(receipt, codeId: id, device: device) != null);
      return valid ? (_Activation.ok, receipt) : (_Activation.offline, null);
    } catch (e) {
      logWarn('Could not ask the license server about this device: $e');
      return (_Activation.offline, null);
    } finally {
      client.close();
    }
  }

  /// Asks the server again whether the kept code is still good here. Out
  /// of reach changes nothing; revoked, or this device taken off a full
  /// code, stops it here.
  Future<void> _checkIn() async {
    final license = _license;
    if (license == null) return;
    final (answer, receipt) = await _activate(license);
    if (_license != license) return;
    final was = licensed;
    switch (answer) {
      case _Activation.ok:
        _receipt = receipt!;
        _receiptDay = DateTime.now();
        _entered = null;
        _blocked = false;
      case _Activation.revoked:
        _blocked = true;
        _stopReason = lastRefunded ? 'refunded' : 'revoked';
        logWarn('The learning pack code was revoked');
      case _Activation.devices:
        _blocked = true;
        _stopReason = 'devices';
        pendingLicense = license;
        logWarn('This device is no longer among the learning pack code\'s devices');
      case _Activation.offline:
        return;
    }
    await _save();
    notifyListeners();
    if (!was && licensed) {
      unawaited(_book?.load());
      unawaited(_updateAll());
    }
  }

  /// The devices [license] (or the kept code) is active on, fresh from
  /// the server; null when it is out of reach.
  Future<List<LicenseDevice>?> loadDevices({LearningLicense? license}) async {
    final code = license ?? pendingLicense ?? _license;
    if (code == null) return null;
    if (code == _license && pendingLicense == null) {
      await _checkIn();
      return devices;
    }
    final (answer, _) = await _activate(code);
    if (answer == _Activation.offline) return null;
    if (answer == _Activation.ok) await enterLicense(code.code);
    return devices;
  }

  /// Takes [device] off the code's list, freeing its slot.
  Future<bool> removeDevice(String device, {LearningLicense? license}) async {
    final code = license ?? pendingLicense ?? _license;
    if (code == null) return false;
    final client = http.Client();
    try {
      final server = await _server(client);
      if (server == null) return false;
      final response = await client
          .post(server.resolve('/deactivate'), headers: {'content-type': 'application/json'}, body: jsonEncode({'code': code.code, 'device': device}))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return false;
      _takeDevices(jsonDecode(response.body));
      notifyListeners();
      return true;
    } catch (e) {
      logWarn('Could not remove a device from the learning pack code: $e');
      return false;
    } finally {
      client.close();
    }
  }

  /// This device's id as the server counts it, to mark it in the list.
  Future<String?> thisDevice() async => _directories == null ? null : _device();

  /// When the server recorded the buyer's consent for the last code it
  /// sent, for the confirmation shown after unlocking.
  DateTime? lastConsent;

  /// Asks the license server for the code of a purchase: the order
  /// number, and for Ko-fi also the email paid with. The buyer has agreed
  /// to [learningConsentVersion].
  /// The server's address is published on the `learning` release, so it
  /// can move without an app update.
  Future<ClaimResult> claimLicense({required PurchaseSource source, required String order, String email = ''}) async {
    final client = http.Client();
    try {
      final server = await _server(client);
      if (server == null) return ClaimResult.offline;
      final response = await client
          .post(
            server.resolve('/claim'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'source': source.name, 'order': order.trim(), if (source.needsEmail) 'email': email.trim(), 'consent': learningConsentVersion}),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 429) return ClaimResult.busy;
      if (response.statusCode == 403) {
        lastRefunded = response.body.contains('refunded');
        return ClaimResult.revoked;
      }
      final answer = response.statusCode == 200 ? jsonDecode(response.body) : null;
      final code = answer is Map ? answer['code'] : null;
      lastConsent = answer is Map ? DateTime.tryParse('${answer['consented']}')?.toLocal() : null;
      if (code is! String) return response.statusCode >= 500 ? ClaimResult.offline : ClaimResult.notFound;
      return switch (await enterLicense(code)) {
        LicenseResult.ok || LicenseResult.offline => ClaimResult.ok,
        LicenseResult.revoked => ClaimResult.revoked,
        LicenseResult.devices => ClaimResult.devices,
        LicenseResult.invalid => ClaimResult.notFound,
      };
    } catch (e) {
      logWarn('Could not ask the license server: $e');
      return ClaimResult.offline;
    } finally {
      client.close();
    }
  }

  /// Forgets the code here, and frees this device's slot when the server
  /// can be reached.
  Future<void> removeLicense() async {
    final license = _license;
    if (license != null && _directories != null) await removeDevice(await _device(), license: license);
    _license = null;
    pendingLicense = null;
    _receipt = '';
    _receiptDay = null;
    _entered = null;
    _blocked = false;
    _stopReason = '';
    await _save();
    notifyListeners();
  }

  Future<void> setShowPinyin(bool on) async {
    _showPinyin = on;
    notifyListeners();
    await _save();
  }

  Future<void> setVoiceService(VoiceService service) async {
    _voiceService = service;
    notifyListeners();
    await _save();
  }

  Future<void> setMeanings(MeaningLanguage meanings) async {
    _meanings = meanings;
    notifyListeners();
    await _save();
  }

  Future<void> setShowRomanization(bool on) async {
    _showRomanization = on;
    notifyListeners();
    await _save();
  }

  Future<void> setEnglishLevel(int? level) async {
    _englishLevel = level;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    final file = _settingsFile;
    if (file == null) return;
    try {
      await writeFileAtomic(file, jsonEncode({'license': _license?.code ?? '', 'activation': _receipt, 'entered': _entered?.toIso8601String() ?? '', 'blocked': _blocked, 'stopped': _stopReason, 'pinyin': _showPinyin, 'romanization': _showRomanization, 'meanings': _meanings?.name ?? '', 'voice': _voiceService.name, 'englishLevel': _englishLevel ?? -1, 'trial': {'taken': _trialTaken, 'seen': _trialSeen, 'day': _trialDay, 'used': _trialUsed, 'words': _trialWords.toList()}, 'lookedUp': lookedUp}));
    } catch (e) {
      logError('Could not save the learning settings', e);
    }
  }

  /// Whether [language]'s dictionary is on disk; reading it starts now
  /// when it has not been read.
  bool _onDisk(String language) {
    for (final pack in DictionaryPack.values) {
      if (pack.language != language) continue;
      final state = _packs[pack]!.state;
      if (state == PackState.downloaded) unawaited(load(pack));
      return state == PackState.downloaded || state == PackState.loading || state == PackState.ready;
    }
    return false;
  }

  /// Reads [pack]'s dictionary when it has been downloaded.
  Future<void> load(DictionaryPack pack) {
    final state = _packs[pack]!;
    return state.loading ??= _load(pack).whenComplete(() => state.loading = null);
  }

  Future<void> _load(DictionaryPack pack) async {
    final state = _packs[pack]!;
    final file = _fileOf(pack);
    if (state.dictionary != null || file == null || !await file.exists()) return;
    state.state = PackState.loading;
    notifyListeners();
    try {
      final path = file.path;
      final watch = Stopwatch()..start();
      // Both on another thread: opening a SQLite file counts its words.
      state.dictionary = pack.sqlite
          ? switch (pack) {
              DictionaryPack.english => EnglishDictionary(await CoreLexicon.openInBackground(pack.language, path)),
              _ => WiktionaryDictionary(pack.language, await CoreLexicon.openInBackground(pack.language, path)),
            }
          : await Isolate.run<Object>(() {
              final unpacked = gzip.decode(File(path).readAsBytesSync());
              final bytes = unpacked is Uint8List ? unpacked : Uint8List.fromList(unpacked);
              return switch (pack) {
                DictionaryPack.chinese => ChineseDictionary.fromBytes(bytes),
                DictionaryPack.japanese => JapaneseDictionary.fromBytes(bytes),
                _ => throw StateError('${pack.name} is a SQLite dictionary'),
              };
            });
      logInfo('${pack.name} dictionary opened in ${watch.elapsedMilliseconds} ms');
      state.state = PackState.ready;
      unawaited(_openSegmenter(pack));
    } catch (e) {
      logError('Could not read the ${pack.name} dictionary', e);
      // An update that does not open: back to the version before it.
      final previous = File('${file.path}.prev');
      if (await previous.exists()) {
        try {
          _close(pack);
          await previous.rename(file.path);
          await _sumOf(pack)?.delete();
          logWarn('Went back to the previous ${pack.name} dictionary');
          return await _load(pack);
        } catch (e) {
          logWarn('Could not go back to the previous ${pack.name} dictionary: $e');
        }
      }
      state.error = '$e';
      state.state = PackState.failed;
    }
    notifyListeners();
  }

  /// Keeps the version [file] replaces, one only, to go back to when the
  /// new one does not open.
  Future<void> _keepPrevious(File file) async {
    try {
      if (await file.exists()) await file.rename('${file.path}.prev');
    } catch (e) {
      logWarn('Could not keep the previous ${file.path}: $e');
    }
  }

  /// Downloads [pack]'s dictionary and checks it against the SHA-256 sum
  /// published beside it. [quiet], for an update of one on disk, keeps
  /// the old one in use until the new one is in place and only logs a
  /// failure.
  Future<void> download(DictionaryPack pack, {bool quiet = false}) async {
    final state = _packs[pack]!;
    final file = _fileOf(pack);
    if (file == null || state.state == PackState.downloading) return;
    if (!quiet) {
      state
        ..state = PackState.downloading
        ..progress = null
        ..error = null;
      notifyListeners();
    }
    // A quiet update reads the new file only where the old one was read.
    final wasRead = state.dictionary != null;
    final client = http.Client();
    final part = File('${file.path}.part');
    final unpacked = File('${file.path}.new');
    try {
      final expected = (await _signedSums(client)).of(pack.file);
      if (expected == null) throw const FormatException('The dictionary is not listed in SHA256SUMS');
      final response = await client.send(http.Request('GET', Uri.parse('$learningPackRelease/${pack.file}'))).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw HttpException('Dictionary HTTP ${response.statusCode}');
      await file.parent.create(recursive: true);
      final sink = part.openWrite();
      final total = response.contentLength;
      var received = 0;
      final hashSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(hashSink);
      try {
        await for (final chunk in response.stream.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          hasher.add(chunk);
          received += chunk.length;
          if (!quiet && total != null && total > 0) {
            state.progress = received / total;
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
      hasher.close();
      if (hashSink.value.toString() != expected) throw const FormatException('The dictionary download is damaged; try again');
      if (pack.sqlite) {
        // Unpacked once, then looked up in place; the open copy is let go
        // first so it can be replaced.
        await part.openRead().transform(gzip.decoder).pipe(unpacked.openWrite());
        await part.delete();
        _close(pack);
        await _keepPrevious(file);
        await unpacked.rename(file.path);
      } else {
        _close(pack);
        await _keepPrevious(file);
        await part.rename(file.path);
      }
      try {
        await _sumOf(pack)!.writeAsString(expected);
      } catch (_) {}
      logInfo('${pack.name} dictionary downloaded: $received bytes');
      if (quiet && !wasRead) {
        state.state = PackState.downloaded;
        notifyListeners();
        return;
      }
      state
        ..state = PackState.loading
        ..progress = null;
      notifyListeners();
      await load(pack);
    } catch (e) {
      logError('Could not download the ${pack.name} dictionary', e);
      if (!quiet) {
        state
          ..error = '$e'
          ..state = PackState.failed;
      }
      for (final leftover in [part, unpacked]) {
        try {
          if (await leftover.exists()) await leftover.delete();
        } catch (_) {}
      }
      notifyListeners();
    } finally {
      client.close();
    }
  }

  void _close(DictionaryPack pack) {
    _packs[pack]!.dictionary = null;
    if (pack.sqlite) CoreLexicon.close(pack.language);
    if (pack.segmenter != null) CoreWords.close(pack.language);
  }

  Directory? _segmenterOf(DictionaryPack pack) {
    final folder = _folderOf(pack);
    return folder == null ? null : Directory('${folder.path}${Platform.pathSeparator}segmenter');
  }

  final _fetchingSegmenters = <DictionaryPack>{};

  /// Opens [pack]'s segmenter, fetching it first when it is not there,
  /// such as for a dictionary downloaded before segmenters were. Lines
  /// are cut the old way until it is open.
  Future<void> _openSegmenter(DictionaryPack pack) async {
    final folder = _segmenterOf(pack);
    if (pack.segmenter == null || folder == null || !CoreWords.available || CoreWords.isOpen(pack.language)) return;
    if (await File('${folder.path}${Platform.pathSeparator}metadata.json').exists()) {
      try {
        // Reading Lindera's dictionary takes a while; not on the window's thread.
        await CoreWords.openInBackground(pack.language, folder.path);
        // Deleted or replaced meanwhile.
        if (_packs[pack]!.dictionary == null) {
          CoreWords.close(pack.language);
          return;
        }
        logInfo('${pack.name} segmenter opened');
        viewChanges.value++;
      } catch (e) {
        logWarn('Could not open the ${pack.name} segmenter: $e');
      }
      return;
    }
    unawaited(_downloadSegmenter(pack));
  }

  Future<void> _downloadSegmenter(DictionaryPack pack) async {
    final name = pack.segmenter;
    final folder = _segmenterOf(pack);
    if (name == null || folder == null || !_fetchingSegmenters.add(pack)) return;
    final client = http.Client();
    final archive = File('${folder.path}.zip');
    final unpacked = Directory('${folder.path}.new');
    try {
      final expected = (await _signedSums(client)).of(name);
      // Not published yet: the dictionary cuts lines itself meanwhile.
      if (expected == null) return;
      final response = await client.send(http.Request('GET', Uri.parse('$learningPackRelease/$name'))).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw HttpException('Segmenter HTTP ${response.statusCode}');
      await folder.parent.create(recursive: true);
      final sink = archive.openWrite();
      final hashSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(hashSink);
      try {
        await for (final chunk in response.stream.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          hasher.add(chunk);
        }
      } finally {
        await sink.close();
      }
      hasher.close();
      if (hashSink.value.toString() != expected) throw const FormatException('The segmenter download is damaged');
      if (await unpacked.exists()) await unpacked.delete(recursive: true);
      await extractZip(archive, unpacked);
      if (_packs[pack]!.dictionary == null) return;
      CoreWords.close(pack.language);
      if (await folder.exists()) await folder.delete(recursive: true);
      await unpacked.rename(folder.path);
      await _openSegmenter(pack);
    } catch (e) {
      logWarn('Could not download the ${pack.name} segmenter: $e');
    } finally {
      client.close();
      _fetchingSegmenters.remove(pack);
      for (final leftover in [archive, unpacked]) {
        try {
          if (await leftover.exists()) await leftover.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<void> delete(DictionaryPack pack) async {
    _close(pack);
    _packs[pack]!
      ..dictionary = null
      ..state = PackState.missing;
    notifyListeners();
    try {
      final folder = _folderOf(pack);
      if (folder != null && await folder.exists()) await folder.delete(recursive: true);
    } catch (e) {
      logWarn('Could not delete the ${pack.name} dictionary: $e');
    }
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// The meanings a word card shows: Chinese first with a few English ones
/// below, Chinese only, or English only. Where a word has none in the
/// chosen language, the other's are shown.
enum MeaningLanguage { chineseFirst, chinese, english }

/// Where the learning pack was bought.
enum PurchaseSource {
  afdian,
  creem,
  polar,
  kofi;

  /// Card orders are claimed with the email paid with too.
  bool get needsEmail => this != afdian;
}

/// The card checkout for the learning pack, published on the `learning`
/// release so it can change without an app update: Creem's, else
/// Polar's; null while card payments are closed (both files empty).
Future<Uri?> cardCheckoutLink() async {
  final client = http.Client();
  try {
    for (final (file, host) in const [('creem-checkout.txt', 'creem.io'), ('polar-checkout.txt', 'polar.sh')]) {
      final answer = await client.get(Uri.parse('$learningPackRelease/$file')).timeout(const Duration(seconds: 15));
      final uri = answer.statusCode == 200 ? Uri.tryParse(answer.body.trim()) : null;
      if (uri != null && uri.scheme == 'https' && (uri.host == host || uri.host.endsWith('.$host'))) return uri;
    }
    return null;
  } catch (e) {
    logWarn('Could not look up the card checkout: $e');
    return null;
  } finally {
    client.close();
  }
}
