import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'app_log.dart';
import 'app_updater.dart' show updatePackage;
import 'l10n/l10n.dart';
import 'local_db.dart' show callCoreJson;
import 'native_core.dart';
import 'tool_manager.dart';
import 'version_order.dart';

enum PackKind {
  runtime('Runtime'),
  model('AI model'),
  language('Language data'),
  shader('Shaders');

  const PackKind(this._label);
  final String _label;
  String get label => tr(_label);
}

class PackFile {
  const PackFile({required this.path, required this.url, required this.sha256, required this.size});
  final String path;
  final String url;
  final String sha256;
  final int size;

  factory PackFile.fromJson(Map<String, dynamic> json) =>
      PackFile(path: '${json['path']}', url: '${json['url']}', sha256: '${json['sha256']}', size: (json['size'] as num?)?.toInt() ?? 0);

  Map<String, dynamic> toJson() => {'path': path, 'url': url, 'sha256': sha256, 'size': size};
}

/// One entry of the signed catalog (see packs/README.md). The core has
/// checked it: its paths stay inside its folder and its addresses are
/// allowed ones.
class Pack {
  const Pack({
    required this.id,
    required this.version,
    required this.kind,
    required this.titles,
    this.descriptions = const {},
    required this.license,
    this.notice = '',
    this.source = '',
    this.minApp = '',
    this.platforms = const [],
    required this.files,
  });

  final String id;
  final String version;
  final PackKind kind;
  final Map<String, String> titles;
  final Map<String, String> descriptions;
  final String license;
  final String notice;
  final String source;
  final String minApp;
  final List<String> platforms;
  final List<PackFile> files;

  int get size => files.fold(0, (sum, f) => sum + f.size);

  String get title => _inLanguage(titles) ?? id;
  String get description => _inLanguage(descriptions) ?? '';

  static String? _inLanguage(Map<String, String> texts) {
    final tag = currentLanguage.tag;
    return texts[tag] ?? texts[tag.split('-').first] ?? (tag.startsWith('zh') ? texts['zh-Hans'] : null) ?? texts['en'];
  }

  /// Whether this build can use it: made for its package and not newer
  /// than the app. Builds made outside CI take every pack.
  bool get suitsThisBuild {
    final package = updatePackage;
    if (platforms.isNotEmpty && package.isNotEmpty && !platforms.contains(package)) return false;
    if (minApp.isEmpty || !RegExp(r'^\d').hasMatch(appVersion)) return true;
    return compareVersionFolders(appVersion.split('-').first, minApp) <= 0;
  }

  static Pack? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final kind = PackKind.values.where((k) => k.name == json['kind']).firstOrNull;
    final files = json['files'];
    if (kind == null || files is! List) return null;
    Map<String, String> texts(Object? value) => {
          if (value is Map)
            for (final MapEntry(:key, :value) in value.entries) '$key': '$value',
        };
    return Pack(
      id: '${json['id']}',
      version: '${json['version']}',
      kind: kind,
      titles: texts(json['title']),
      descriptions: texts(json['description']),
      license: '${json['license'] ?? ''}',
      notice: '${json['notice'] ?? ''}',
      source: '${json['source'] ?? ''}',
      minApp: '${json['minApp'] ?? ''}',
      platforms: [for (final p in json['platforms'] is List ? json['platforms'] as List : const []) '$p'],
      files: [for (final f in files) if (f is Map<String, dynamic>) PackFile.fromJson(f)],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'version': version,
        'kind': kind.name,
        'title': titles,
        if (descriptions.isNotEmpty) 'description': descriptions,
        'license': license,
        if (notice.isNotEmpty) 'notice': notice,
        if (source.isNotEmpty) 'source': source,
        if (minApp.isNotEmpty) 'minApp': minApp,
        if (platforms.isNotEmpty) 'platforms': platforms,
        'files': [for (final f in files) f.toJson()],
      };
}

/// A pack on this device, in `<root>/<id>/<version>/`.
class InstalledPack {
  const InstalledPack(this.pack, this.folder);
  final Pack pack;
  final Directory folder;

  File file(String path) => File('${folder.path}${Platform.pathSeparator}${path.replaceAll('/', Platform.pathSeparator)}');
}

/// Data packs (models, language data, shaders, runtimes) downloaded only
/// when a feature needs them, next to the components [ToolManager] keeps:
/// the same downloads, retries and SHA-256 checks, with what may be
/// installed listed in a catalog signed like the app's updates.
///
/// One pack downloads at a time; a download stopped halfway goes on from
/// where it stopped. A pack is moved into place only after every file
/// matches its size and SHA-256, so a half-made pack is never used.
class PackManager extends ChangeNotifier {
  PackManager(this.root, this.tools);

  /// `packs` in the data folder.
  final Directory root;
  final ToolManager tools;

  static final catalogUri = Uri.parse('https://github.com/0x696c757a696f/lumtub/releases/download/packs/packs.json');
  static final signatureUri = Uri.parse('$catalogUri.sig');

  static String get _sep => Platform.pathSeparator;

  List<Pack> _catalog = const [];
  int _catalogVersion = 0;
  List<InstalledPack> _installed = const [];

  /// Every pack in the catalog kept, whether this build can use it or not.
  List<Pack> get catalog => _catalog;

  /// When the catalog kept was published (0 when there is none).
  int get catalogVersion => _catalogVersion;

  List<InstalledPack> get installed => _installed;

  /// The packs this build can install that are not installed in that
  /// version.
  List<Pack> get offered => [
        for (final pack in _catalog)
          if (pack.suitsThisBuild && installedOf(pack.id)?.pack.version != pack.version) pack,
      ];

  /// Download progress by pack id, 0 to 1.
  final progress = <String, double>{};

  bool refreshing = false;

  /// The last failure, for the settings page.
  String? error;

  Future<void>? _busy;
  var _disposed = false;

  /// Uses [packs] as the catalog, as if a signed one listed them.
  @visibleForTesting
  set catalogForTesting(List<Pack> packs) => _catalog = packs;

  InstalledPack? installedOf(String id) => _installed.where((p) => p.pack.id == id).firstOrNull;

  /// Reads the catalog kept and the packs on this device.
  Future<void> load() async {
    final folder = root.path;
    final answer = NativeCore.instance == null ? const <String, dynamic>{} : await Isolate.run(() => callCoreJson('lumtub_packs_in', jsonEncode({'folder': folder})));
    _catalogVersion = (answer['version'] as num?)?.toInt() ?? 0;
    _catalog = [
      for (final p in answer['packs'] is List ? answer['packs'] as List : const [])
        if (Pack.fromJson(p) case final pack?) pack,
    ];
    _installed = await _scan();
    _changed();
  }

  Future<List<InstalledPack>> _scan() async {
    final found = <InstalledPack>[];
    if (!await root.exists()) return found;
    await for (final idFolder in root.list()) {
      if (idFolder is! Directory) continue;
      final versions = <Directory>[];
      await for (final v in idFolder.list()) {
        if (v is Directory && !v.path.endsWith('.new') && await File('${v.path}$_sep$_entry').exists()) versions.add(v);
      }
      versions.sort((a, b) => compareVersionFolders(a.path, b.path));
      for (final version in versions) {
        final pack = await _readEntry(File('${version.path}$_sep$_entry'));
        if (pack != null && '${root.path}$_sep${pack.id}$_sep${pack.version}' == version.path) {
          found.add(InstalledPack(pack, version));
          break;
        }
      }
    }
    found.sort((a, b) => a.pack.id.compareTo(b.pack.id));
    return found;
  }

  static const _entry = 'pack.json';

  /// An installed pack's entry, checked again by the core so a changed file
  /// cannot point outside its folder.
  Future<Pack?> _readEntry(File file) async {
    try {
      final text = await file.readAsString();
      if (NativeCore.instance == null) return Pack.fromJson(jsonDecode(text));
      final answer = await Isolate.run(() => callCoreJson('lumtub_pack_check', text));
      return answer['error'] == null ? Pack.fromJson(answer) : null;
    } catch (e) {
      logDebug(() => 'Could not read ${file.path}: $e');
      return null;
    }
  }

  /// Downloads the catalog and keeps it when its signatures hold and it is
  /// not older than the one kept.
  Future<void> refresh() => _serial(() async {
        refreshing = true;
        error = null;
        _changed();
        final temp = Directory('${root.path}$_sep.download');
        try {
          await temp.create(recursive: true);
          final json = File('${temp.path}${_sep}packs.json');
          final signature = File('${temp.path}${_sep}packs.json.sig');
          await _get(catalogUri, json, most: 4 << 20);
          await _get(signatureUri, signature, most: 64 << 10);
          final ask = jsonEncode({'file': json.path, 'signature': signature.path, 'folder': root.path});
          final answer = await Isolate.run(() => callCoreJson('lumtub_packs_take', ask));
          if (answer['error'] case final String problem) throw FormatException(problem);
          logInfo('Pack catalog ${answer['version']} with ${answer['packs']} pack(s)${answer['newer'] == true ? '' : ' (already kept)'}');
          await load();
        } catch (e) {
          error = '$e';
          logWarn('Could not refresh the pack catalog: $e');
        } finally {
          refreshing = false;
          _changed();
          unawaited(_removeQuietly(temp));
        }
      });

  /// Downloads [uri] whole into [file], refusing more than [most] bytes.
  Future<void> _get(Uri uri, File file, {required int most}) async {
    final reply = await tools.sendRetrying(uri);
    if (reply.statusCode == 404) {
      unawaited(reply.stream.drain<void>().catchError((Object _) {}));
      throw HttpException(tr('No data packs are published yet'));
    }
    if (reply.statusCode != 200) {
      unawaited(reply.stream.drain<void>().catchError((Object _) {}));
      throw HttpException('HTTP ${reply.statusCode}');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in reply.stream.timeout(const Duration(seconds: 60))) {
      bytes.add(chunk);
      if (bytes.length > most) throw const FormatException('The reply is too large');
    }
    await file.writeAsBytes(bytes.takeBytes(), flush: true);
  }

  /// Downloads [id] from the catalog, checks every file and puts it in
  /// place, then removes its older versions.
  Future<InstalledPack> install(String id) => _serial(() async {
        final pack = _catalog.where((p) => p.id == id).firstOrNull;
        if (pack == null) throw StateError('No pack $id in the catalog');
        if (!pack.suitsThisBuild) throw StateError('$id is not for this build');
        error = null;
        progress[id] = 0;
        _changed();
        final folder = Directory('${root.path}$_sep$id');
        final staging = Directory('${folder.path}$_sep${pack.version}.new');
        final target = Directory('${folder.path}$_sep${pack.version}');
        try {
          await staging.create(recursive: true);
          final total = pack.size;
          var before = 0;
          for (final file in pack.files) {
            final into = File('${staging.path}$_sep${file.path.replaceAll('/', _sep)}');
            await into.parent.create(recursive: true);
            await _download(file, into, (received) {
              final now = total == 0 ? 1.0 : (before + received) / total;
              // A repaint per percent, not per chunk.
              if ((now * 100).floor() == ((progress[id] ?? 0) * 100).floor()) return;
              progress[id] = now;
              _changed();
            });
            before += file.size;
          }
          await File('${staging.path}$_sep$_entry').writeAsString(jsonEncode(pack.toJson()));
          if (await target.exists()) await target.delete(recursive: true);
          await staging.rename(target.path);
          await for (final other in folder.list()) {
            if (other is Directory && other.path != target.path && !other.path.endsWith('.new')) await _removeQuietly(other);
          }
          logInfo('Installed pack $id ${pack.version}');
          await load();
          return installedOf(id)!;
        } catch (e) {
          error = '$e';
          logWarn('Could not install pack $id: $e');
          rethrow;
        } finally {
          progress.remove(id);
          _changed();
        }
      });

  /// Downloads [file] into [into], going on from a part left by an earlier
  /// try, and checks its size and SHA-256.
  Future<void> _download(PackFile file, File into, void Function(int received) onProgress) async {
    if (await into.exists() && await into.length() == file.size && await tools.sha256Of(into) == file.sha256) {
      onProgress(file.size);
      return;
    }
    final part = File('${into.path}.part');
    var have = await part.exists() ? await part.length() : 0;
    if (have > file.size) {
      await part.delete();
      have = 0;
    }
    final reply = await tools.sendRetrying(Uri.parse(file.url), headers: {if (have > 0) 'Range': 'bytes=$have-'});
    if (reply.statusCode == 200) {
      have = 0;
    } else if (reply.statusCode != 206) {
      unawaited(reply.stream.drain<void>().catchError((Object _) {}));
      throw HttpException('Download failed: HTTP ${reply.statusCode}');
    }
    final sink = part.openWrite(mode: have == 0 ? FileMode.write : FileMode.append);
    var received = have;
    try {
      await for (final chunk in reply.stream.timeout(const Duration(seconds: 90))) {
        received += chunk.length;
        if (received > file.size) throw const FormatException('The file is larger than the catalog says');
        sink.add(chunk);
        onProgress(received);
      }
    } finally {
      await sink.close();
    }
    if (received != file.size) throw const FormatException('The download stopped early');
    if (await tools.sha256Of(part) != file.sha256) {
      await part.delete();
      throw const FormatException('SHA-256 verification failed');
    }
    if (await into.exists()) await into.delete();
    await part.rename(into.path);
  }

  /// Deletes [id] from this device.
  Future<void> remove(String id) => _serial(() async {
        await _removeQuietly(Directory('${root.path}$_sep$id'));
        logInfo('Removed pack $id');
        await load();
      });

  /// What the installed packs take on disk.
  int get installedSize => _installed.fold(0, (sum, p) => sum + p.pack.size);

  static Future<void> _removeQuietly(Directory folder) async {
    try {
      if (await folder.exists()) await folder.delete(recursive: true);
    } catch (e) {
      logDebug(() => 'Could not remove ${folder.path}: $e');
    }
  }

  /// Runs [work] after the download or change before it, one at a time.
  Future<T> _serial<T>(Future<T> Function() work) {
    final before = _busy ?? Future<void>.value();
    final next = before.catchError((Object _) {}).then((_) => work());
    _busy = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
