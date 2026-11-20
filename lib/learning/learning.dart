import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_directories.dart';
import '../app_log.dart';
import 'chinese_dictionary.dart';
import 'english_dictionary.dart';
import 'japanese_dictionary.dart';
import 'license.dart';
import 'vocabulary.dart';

/// Where the dictionary packs are published: a release of the app's own
/// repository that holds data only, never an app version.
const learningPackRelease = 'https://github.com/0x696c757a696f/lumtub/releases/download/learning';
enum PackState { missing, downloading, loading, ready, failed }

/// How asking the license server for a bought code went.
enum ClaimResult { ok, notFound, busy, offline }

/// A dictionary the learning pack downloads.
enum DictionaryPack {
  chinese('zh', 'zh-cedict.txt.gz'),
  english('en', 'en-ecdict.tsv.gz'),
  japanese('ja', 'ja-jmdict.tsv.gz');

  const DictionaryPack(this.language, this.file);
  final String language;
  final String file;
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
    final key = Object.hashAll([_license, _showPinyin, _englishLevel, for (final p in _packs.values) p.dictionary]);
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
  bool get anyDictionary => chinese != null || english != null || japanese != null;

  /// [text] as words a tap looks up, when a dictionary for its language
  /// is ready.
  List<WordToken>? wordsOf(String text) {
    final ja = japanese;
    if (ja != null && JapaneseDictionary.looksJapanese(text)) return ja.segment(text);
    final zh = chinese;
    if (zh != null && ChineseDictionary.looksChinese(text)) return zh.segment(text);
    final en = english;
    if (en != null && EnglishDictionary.looksLatin(text)) return en.segment(text);
    return null;
  }

  /// The language of the dictionary [token] is looked up in.
  static String languageOf(WordToken token) => token.language ?? (ChineseDictionary.isHan(token.text) ? 'zh' : 'en');
  VocabularyBook? get book => _book;

  File? get _settingsFile => _directories == null ? null : File('${_directories!.config.path}${Platform.pathSeparator}learning.json');
  Directory? _folderOf(DictionaryPack pack) => _directories == null ? null : Directory('${_directories!.data.path}${Platform.pathSeparator}learn${Platform.pathSeparator}${pack.language}');
  File? _fileOf(DictionaryPack pack) {
    final folder = _folderOf(pack);
    return folder == null ? null : File('${folder.path}${Platform.pathSeparator}${pack.file}');
  }

  /// Reads the saved license and settings; with a license, the
  /// dictionary is read in the background when it is there.
  Future<void> start(AppDirectories directories) async {
    if (_loaded) return;
    _loaded = true;
    _directories = directories;
    _book = VocabularyBook(File('${directories.data.path}${Platform.pathSeparator}vocabulary.json'));
    try {
      final file = _settingsFile!;
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        if (json is Map) {
          _showPinyin = json['pinyin'] != false;
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
      if (await _fileOf(pack)!.exists()) _packs[pack]!.state = PackState.loading;
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

  /// Asks the license server for the code of a purchase: a Ko-fi buyer
  /// gives the email they paid with, an 爱发电 buyer the order number.
  /// The server's address is published on the `learning` release, so it
  /// can move without an app update.
  Future<ClaimResult> claimLicense({required bool afdian, required String value}) async {
    final client = http.Client();
    try {
      final where = await client.get(Uri.parse('$learningPackRelease/license-server.txt')).timeout(const Duration(seconds: 20));
      final server = where.statusCode == 200 ? Uri.tryParse(where.body.trim()) : null;
      if (server == null || server.scheme != 'https') return ClaimResult.offline;
      final response = await client
          .post(
            server.resolve('/claim'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'source': afdian ? 'afdian' : 'kofi', if (afdian) 'order': value.trim() else 'email': value.trim()}),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 429) return ClaimResult.busy;
      final code = response.statusCode == 200 ? (jsonDecode(response.body) as Map)['code'] : null;
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

  Future<void> setEnglishLevel(int? level) async {
    _englishLevel = level;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    final file = _settingsFile;
    if (file == null) return;
    try {
      await writeFileAtomic(file, jsonEncode({'license': _license?.code ?? '', 'pinyin': _showPinyin, 'englishLevel': _englishLevel ?? -1}));
    } catch (e) {
      logError('Could not save the learning settings', e);
    }
  }

  void _loadAll() {
    for (final pack in DictionaryPack.values) {
      unawaited(load(pack));
    }
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
      state.dictionary = await Isolate.run<Object>(() {
        final text = utf8.decode(gzip.decode(File(path).readAsBytesSync()));
        return switch (pack) {
          DictionaryPack.chinese => ChineseDictionary.parse(text),
          DictionaryPack.english => EnglishDictionary.parse(text),
          DictionaryPack.japanese => JapaneseDictionary.parse(text),
        };
      });
      logInfo('${pack.name} dictionary read in ${watch.elapsedMilliseconds} ms');
      state.state = PackState.ready;
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
      await part.rename(file.path);
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
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {}
      notifyListeners();
    } finally {
      client.close();
    }
  }

  Future<void> delete(DictionaryPack pack) async {
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
