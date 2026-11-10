import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../app_log.dart';
import '../zip_archive.dart' show extractZip;
import 'jsonc.dart';
import 'skin.dart';

/// The skins Lumtub knows: its own, from skins/ in the repository, and the ones in the
/// user's skins folder, one folder per skin with a skin.jsonc in it. The
/// folder is watched, so a skin being edited shows its changes on save.
class SkinLibrary extends ChangeNotifier {
  SkinLibrary._();
  static final instance = SkinLibrary._();

  /// Lumtub's colour schemes as skins: they follow the theme mode and keep
  /// Lumtub's own shapes.
  static const colorSchemeIds = ['rice-paper', 'candlelight', 'ink-bamboo', 'rime', 'pine-soot', 'night-voyage', 'dusk-hills', 'falling-petals', 'sandstone', 'high-contrast'];

  /// The built-in skins, in the order Settings shows them.
  static const builtInIds = [...colorSchemeIds, 'aero', 'ocean', 'meadow', 'city', 'aquarium', 'aurora', 'chrome', 'candy', 'disc', 'messenger', 'player', 'desktop', 'sixteen', 'onebit', 'platinum', 'pinstripe', 'silver', 'metal', 'holo', 'paper', 'linen', 'shelf', 'handheld'];

  List<Skin> _builtIn = const [];
  List<Skin> _user = const [];
  Map<String, String> _errors = const {};
  Directory? _folder;
  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _debounce;
  final _loadedFonts = <String>{};

  /// Changes whenever the skins are read again, so themes built from them
  /// are rebuilt.
  int revision = 0;

  List<Skin> get builtIn => _builtIn;
  List<Skin> get user => _user;
  /// Skin folders that could not be read, with why.
  Map<String, String> get errors => _errors;
  Directory? get folder => _folder;

  /// The skin [id] names; a user's skin wins over a built-in one of the same id.
  Skin? byId(String id) {
    if (id.isEmpty) return null;
    for (final s in _user) {
      if (s.id == id) return s;
    }
    for (final s in _builtIn) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> load({Directory? folder, AssetBundle? bundle}) async {
    _folder = folder;
    final assets = bundle ?? rootBundle;
    final builtIn = <Skin>[];
    for (final id in builtInIds) {
      try {
        builtIn.add(Skin.parse(decodeJsonc(await assets.loadString('skins/$id/skin.jsonc')), folder: 'skins/$id', builtIn: true));
      } catch (e) {
        logError('Built-in skin $id could not be read', e);
      }
    }
    _builtIn = builtIn;
    await _readUser();
    if (folder != null) _startWatching(folder);
  }

  /// Copies a skin into the skins folder, for phones, tablets and TVs,
  /// which have no folder to drop it in: a skin.jsonc on its own, or a zip
  /// of a skin's folder (with or without the folder itself in it). Answers
  /// the skin's id; throws a [FormatException] for a file that is not one.
  Future<String> importFile(String path) async {
    final folder = _folder;
    if (folder == null) throw const FormatException('There is no skins folder');
    await folder.create(recursive: true);
    final staging = await folder.createTemp('.import-');
    try {
      final unpacked = await Directory('${staging.path}${Platform.pathSeparator}skin').create();
      if (path.toLowerCase().endsWith('.zip')) {
        await extractZip(File(path), unpacked);
      } else {
        await File(path).copy('${unpacked.path}${Platform.pathSeparator}skin.jsonc');
      }
      // The skin.jsonc nearest the top is the skin; its folder is copied.
      final found = await unpacked.list(recursive: true).where((e) => e is File && e.uri.pathSegments.last == 'skin.jsonc').cast<File>().toList();
      if (found.isEmpty) throw const FormatException('No skin.jsonc in this file');
      found.sort((a, b) => a.uri.pathSegments.length.compareTo(b.uri.pathSegments.length));
      final source = found.first.parent;
      final skin = Skin.parse(decodeJsonc(await found.first.readAsString()), folder: source.path, builtIn: false);
      if (builtInIds.contains(skin.id)) throw FormatException('"${skin.id}" is the name of a built-in skin');
      final target = Directory('${folder.path}${Platform.pathSeparator}${skin.id}');
      if (await target.exists()) await target.delete(recursive: true);
      await source.rename(target.path);
      await reload();
      return skin.id;
    } finally {
      try {
        await staging.delete(recursive: true);
      } catch (e) {
        logDebug(() => 'Could not remove the skin staging folder: $e');
      }
    }
  }

  Future<void> reload() async {
    await _readUser();
    notifyListeners();
  }

  Future<void> _readUser() async {
    final folder = _folder;
    final skins = <Skin>[];
    final errors = <String, String>{};
    if (folder != null) {
      try {
        if (!await folder.exists()) await folder.create(recursive: true);
        final dirs = await folder.list().where((e) => e is Directory).cast<Directory>().toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        for (final dir in dirs) {
          final file = File('${dir.path}${Platform.pathSeparator}skin.jsonc');
          if (!await file.exists()) continue;
          try {
            final skin = Skin.parse(decodeJsonc(await file.readAsString()), folder: dir.path, builtIn: false);
            await _loadFonts(skin);
            skins.add(skin);
            if (skin.warnings.isNotEmpty) logInfo('Skin ${skin.id}: ${skin.warnings.join('; ')}');
          } catch (e) {
            errors[dir.path] = e is FormatException ? e.message : '$e';
          }
        }
      } catch (e) {
        logError('Could not read the skins folder', e);
      }
    }
    _user = skins;
    _errors = errors;
    revision++;
  }

  Future<void> _loadFonts(Skin skin) async {
    for (final MapEntry(key: family, value: name) in skin.fontFiles.entries) {
      final path = skin.file(name);
      if (path == null) {
        skin.warn('font "$family" ($name) must be a file inside the skin folder');
        continue;
      }
      // Flutter cannot unload a font, so each file is read once a run.
      if (!_loadedFonts.add('$family\n$path')) continue;
      try {
        final bytes = await File(path).readAsBytes();
        await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      } catch (e) {
        skin.warn('font "$family" ($name) could not be read');
      }
    }
  }

  void _startWatching(Directory folder) {
    unawaited(_watch?.cancel());
    try {
      _watch = folder.watch(recursive: true).listen((_) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 400), () => unawaited(reload()));
      }, onError: (Object _) {});
    } catch (_) {
      // Some file systems cannot be watched; Settings has a reload button.
    }
  }
}
