import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_directories.dart';
import '../app_log.dart';
import '../zip_archive.dart' show extractZip;
import 'chinese_dictionary.dart';
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
enum ClaimResult { ok, notFound, busy, offline }

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
    final key = Object.hashAll([_license, _showPinyin, _showRomanization, _englishLevel, for (final p in _packs.values) p.dictionary]);
    if (key != _lastView) {
      _lastView = key;
      viewChanges.value++;
    }
    super.notifyListeners();
  }

  Object? _lastView;

  LearningLicense? get license => _license;
  bool get licensed => _license != null;
  bool get showPinyin => _showPinyin;
  bool get showRomanization => _showRomanization;

  /// Which meanings a word card shows where a dictionary has both.
  MeaningLanguage get meanings => _meanings;
  MeaningLanguage _meanings = MeaningLanguage.chineseFirst;

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
    if (level == null || en == null || languageOf(token) != 'en') return false;
    final word = en.levelOf(token.key);
    return word != null && word > level;
  }
  PackState stateOf(DictionaryPack pack) => _packs[pack]!.state;
  double? progressOf(DictionaryPack pack) => _packs[pack]!.progress;
  String? errorOf(DictionaryPack pack) => _packs[pack]!.error;
  ChineseDictionary? get chinese => licensed ? _packs[DictionaryPack.chinese]!.dictionary as ChineseDictionary? : null;
  EnglishDictionary? get english => licensed ? _packs[DictionaryPack.english]!.dictionary as EnglishDictionary? : null;
  JapaneseDictionary? get japanese => licensed ? _packs[DictionaryPack.japanese]!.dictionary as JapaneseDictionary? : null;
  bool get anyDictionary => _packs.values.any((p) => p.dictionary != null) && licensed;

  /// The Wiktionary dictionary for [language], when it is ready.
  WiktionaryDictionary? wiktionary(String language) {
    if (!licensed) return null;
    for (final pack in DictionaryPack.values) {
      if (pack.wiktionary && pack.language == language) return _packs[pack]!.dictionary as WiktionaryDictionary?;
    }
    return null;
  }

  final _latin = LatinLanguageGuess();

  /// [text] as words a tap looks up, when a dictionary for its language
  /// is ready.
  List<WordToken>? wordsOf(String text) {
    final ja = japanese;
    if (ja != null && JapaneseDictionary.looksJapanese(text)) return _cut('ja', text) ?? ja.segment(text);
    final zh = chinese;
    if (zh != null && ChineseDictionary.looksChinese(text)) return _cut('zh', text) ?? zh.segment(text);
    if (WiktionaryDictionary.looksKorean(text)) {
      final words = _onDisk('ko') ? _wiktionaryWords('ko', text) : null;
      if (words == null || _showRomanization) return words;
      return [for (final w in words) w.reading == null ? w : WordToken(w.text, null, isWord: w.isWord, lookup: w.lookup, language: w.language)];
    }
    if (WiktionaryDictionary.looksCyrillic(text)) return _onDisk('ru') ? _wiktionaryWords('ru', text) : null;
    if (!EnglishDictionary.looksLatin(text)) return null;
    final en = english;
    final latin = [if (en != null) 'en', for (final code in const ['es', 'fr', 'de', 'it']) if (_packs[DictionaryPack.values.firstWhere((p) => p.language == code)]!.state case PackState.downloaded || PackState.loading || PackState.ready) code];
    if (!licensed) return null;
    final language = _latin.guess(text, latin);
    if (language == null) return null;
    if (language == 'en') return en!.segment(text);
    // Read on first use; until then the line stays plain.
    return _onDisk(language) ? _wiktionaryWords(language, text) : null;
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

  /// Reads the saved license and settings; with a license, the
  /// dictionary is read in the background when it is there.
  Future<void> start(AppDirectories directories) async {
    if (_loaded) return;
    _loaded = true;
    _directories = directories;
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
          _meanings = MeaningLanguage.values.firstWhere((m) => m.name == json['meanings'], orElse: () => MeaningLanguage.chineseFirst);
          _voiceService = VoiceService.values.firstWhere((v) => v.name == json['voice'], orElse: () => VoiceService.system);
          final level = json['englishLevel'];
          if (level is int) _englishLevel = level >= 0 && level < EnglishLevel.beyond.index ? level : null;
          final code = json['license'];
          if (code is String && code.isNotEmpty) _license = await Isolate.run(() => LearningLicense.parse(code));
        }
      }
    } catch (e) {
      logWarn('Could not read the learning settings: $e');
    }
    for (final pack in DictionaryPack.values) {
      if (await _fileOf(pack)!.exists()) _packs[pack]!.state = pack.wiktionary ? PackState.downloaded : PackState.loading;
    }
    notifyListeners();
    if (licensed) {
      unawaited(_book!.load());
      _loadAll();
    }
  }

  /// Checks [code] and keeps it when it is a license. Returns whether it is.
  Future<bool> enterLicense(String code) async {
    final license = await Isolate.run(() => LearningLicense.parse(code));
    if (license == null) return false;
    _license = license;
    await _save();
    notifyListeners();
    unawaited(_book?.load());
    _loadAll();
    return true;
  }

  /// When the server recorded the buyer's consent for the last code it
  /// sent, for the confirmation shown after unlocking.
  DateTime? lastConsent;

  /// Asks the license server for the code of a purchase: the order
  /// number, and for Ko-fi also the email paid with. The buyer has agreed
  /// to [learningConsentVersion].
  /// The server's address is published on the `learning` release, so it
  /// can move without an app update.
  Future<ClaimResult> claimLicense({required bool afdian, required String order, String email = ''}) async {
    final client = http.Client();
    try {
      final where = await client.get(Uri.parse('$learningPackRelease/license-server.txt')).timeout(const Duration(seconds: 20));
      final server = where.statusCode == 200 ? Uri.tryParse(where.body.trim()) : null;
      if (server == null || server.scheme != 'https') return ClaimResult.offline;
      final response = await client
          .post(
            server.resolve('/claim'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'source': afdian ? 'afdian' : 'kofi', 'order': order.trim(), if (!afdian) 'email': email.trim(), 'consent': learningConsentVersion}),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 429) return ClaimResult.busy;
      final answer = response.statusCode == 200 ? jsonDecode(response.body) : null;
      final code = answer is Map ? answer['code'] : null;
      lastConsent = answer is Map ? DateTime.tryParse('${answer['consented']}')?.toLocal() : null;
      if (code is! String) return response.statusCode >= 500 ? ClaimResult.offline : ClaimResult.notFound;
      return await enterLicense(code) ? ClaimResult.ok : ClaimResult.notFound;
    } catch (e) {
      logWarn('Could not ask the license server: $e');
      return ClaimResult.offline;
    } finally {
      client.close();
    }
  }

  Future<void> removeLicense() async {
    _license = null;
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
      await writeFileAtomic(file, jsonEncode({'license': _license?.code ?? '', 'pinyin': _showPinyin, 'romanization': _showRomanization, 'meanings': _meanings.name, 'voice': _voiceService.name, 'englishLevel': _englishLevel ?? -1}));
    } catch (e) {
      logError('Could not save the learning settings', e);
    }
  }

  void _loadAll() {
    for (final pack in DictionaryPack.values) {
      if (_packs[pack]!.state != PackState.downloaded) unawaited(load(pack));
    }
  }

  /// Whether [language]'s Wiktionary dictionary is on disk; reading it
  /// starts now when it has not been read.
  bool _onDisk(String language) {
    if (!licensed) return false;
    for (final pack in DictionaryPack.values) {
      if (!pack.wiktionary || pack.language != language) continue;
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
      state.dictionary = pack.sqlite
          ? switch (pack) {
              DictionaryPack.english => EnglishDictionary(CoreLexicon.open(pack.language, path)),
              _ => WiktionaryDictionary(pack.language, CoreLexicon.open(pack.language, path)),
            }
          : await Isolate.run<Object>(() {
              final text = utf8.decode(gzip.decode(File(path).readAsBytesSync()));
              return switch (pack) {
                DictionaryPack.chinese => ChineseDictionary.parse(text),
                DictionaryPack.japanese => JapaneseDictionary.parse(text),
                _ => throw StateError('${pack.name} is a SQLite dictionary'),
              };
            });
      logInfo('${pack.name} dictionary opened in ${watch.elapsedMilliseconds} ms');
      state.state = PackState.ready;
      _openSegmenter(pack);
    } catch (e) {
      logError('Could not read the ${pack.name} dictionary', e);
      state.error = '$e';
      state.state = PackState.failed;
    }
    notifyListeners();
  }

  /// Downloads [pack]'s dictionary and checks it against the SHA-256 sum
  /// published beside it.
  Future<void> download(DictionaryPack pack) async {
    final state = _packs[pack]!;
    final file = _fileOf(pack);
    if (file == null || state.state == PackState.downloading) return;
    state
      ..state = PackState.downloading
      ..progress = null
      ..error = null;
    notifyListeners();
    final client = http.Client();
    final part = File('${file.path}.part');
    final unpacked = File('${file.path}.new');
    try {
      final sums = await client.get(Uri.parse('$learningPackRelease/SHA256SUMS')).timeout(const Duration(seconds: 30));
      if (sums.statusCode != 200) throw HttpException('SHA256SUMS HTTP ${sums.statusCode}');
      final expected = RegExp('^([0-9a-f]{64}) [ *]?${RegExp.escape(pack.file)}\\s*\$', multiLine: true).firstMatch(sums.body)?.group(1);
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
          if (total != null && total > 0) {
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
        await unpacked.rename(file.path);
      } else {
        await part.rename(file.path);
      }
      logInfo('${pack.name} dictionary downloaded: $received bytes');
      state
        ..state = PackState.loading
        ..progress = null;
      notifyListeners();
      await load(pack);
    } catch (e) {
      logError('Could not download the ${pack.name} dictionary', e);
      state
        ..error = '$e'
        ..state = PackState.failed;
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
  void _openSegmenter(DictionaryPack pack) {
    final folder = _segmenterOf(pack);
    if (pack.segmenter == null || folder == null || !CoreWords.available || CoreWords.isOpen(pack.language)) return;
    if (File('${folder.path}${Platform.pathSeparator}metadata.json').existsSync()) {
      try {
        CoreWords.open(pack.language, folder.path);
        logInfo('${pack.name} segmenter opened');
        viewChanges.value++;
      } catch (e) {
        logWarn('Could not open the ${pack.name} segmenter: $e');
      }
      return;
    }
    if (licensed) unawaited(_downloadSegmenter(pack));
  }

  Future<void> _downloadSegmenter(DictionaryPack pack) async {
    final name = pack.segmenter;
    final folder = _segmenterOf(pack);
    if (name == null || folder == null || !_fetchingSegmenters.add(pack)) return;
    final client = http.Client();
    final archive = File('${folder.path}.zip');
    final unpacked = Directory('${folder.path}.new');
    try {
      final sums = await client.get(Uri.parse('$learningPackRelease/SHA256SUMS')).timeout(const Duration(seconds: 30));
      final expected = sums.statusCode == 200 ? RegExp('^([0-9a-f]{64}) [ *]?${RegExp.escape(name)}\\s*\$', multiLine: true).firstMatch(sums.body)?.group(1) : null;
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
      _openSegmenter(pack);
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
