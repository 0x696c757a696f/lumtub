import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show debugPrint;

import 'android_python.dart';
import 'app_directories.dart';
import 'app_log.dart';
import 'zip_archive.dart';
import 'libmpv_updates.dart';
import 'native_core.dart';
import 'native_http.dart';
import 'process_runner.dart';
import 'version_order.dart';
import 'l10n/l10n.dart';

class ToolPaths {
  final String mpv;
  final String ytDlp;
  final String? deno;
  const ToolPaths({required this.mpv, required this.ytDlp, this.deno});
  List<String> get executableDirectories => [
        if (mpv.isNotEmpty && Platform.isWindows) File(mpv).parent.path,
        if (ytDlp.isNotEmpty) File(ytDlp).parent.path,
        if (deno != null) File(deno!).parent.path,
      ];
}

/// Downloads GitHub release assets to versioned directories and checks SHA-256.
class ToolManager {
  final AppDirectories directories;
  /// Shows a message, and writes it to the log in English.
  final void Function(String shown, String logged) report;
  ToolManager(this.directories, this.report, {http.Client? client}) : _client = client ?? appHttpClient();

  void status(String text, [List<Object?> args = const []]) => report(tr(text, args), trLog(text, args));

  late final Directory root;
  late final LibmpvState libmpv;
  final http.Client _client;

  static final _separator = Platform.pathSeparator;

  /// [name] as an executable's file name on this system.
  /// Lets [path] run off Windows, whatever mode the archive gave it.
  static Future<void> _makeExecutable(String path) async {
    if (Platform.isWindows) return;
    final chmod = await Process.run('chmod', ['755', path]);
    if (chmod.exitCode != 0) throw StateError('chmod $path failed: ${chmod.stderr}');
  }

  static String _exe(String name) => Platform.isWindows ? '$name.exe' : name;

  static bool get _linuxArm64 => Abi.current() == Abi.linuxArm64;
  static bool get _macArm64 => Abi.current() == Abi.macosArm64;

  /// Off Windows libmpv is not downloaded: the AppImage carries its own in
  /// lib/, the macOS app its Mpv.framework, else the system's is found by
  /// its library name.
  static bool get _systemMpv => !Platform.isWindows;

  /// The libmpv packaged with a Linux build (the AppImage), or '' for the
  /// system's. Named exactly, so media_kit cannot open a second libmpv
  /// beside the one the video plugin linked.
  static String get _linuxMpv {
    final packaged = '${File(Platform.resolvedExecutable).parent.path}/lib/libmpv.so.2';
    return File(packaged).existsSync() ? packaged : '';
  }

  /// libmpv's own version (mpv's `mpv-version`), once the player is made.
  String? mpvVersion;

  /// The libmpv in use, for the status bar and settings.
  String get libmpvLabel => _systemMpv ? mpvVersion ?? 'libmpv' : 'libmpv ${libmpv.current?.label ?? tr('Built-in')}';

  Future<void> initialize() async {
    root = directories.components;
    await root.create(recursive: true);
    libmpv = LibmpvState(Directory('${root.path}${_separator}mpv'), bundled: _readBundledLibmpv());
    // A newer app release may ship a newer libmpv than an earlier download.
    await libmpv.dropIfOutdated();
  }

  LibmpvBuild? _readBundledLibmpv() {
    final file = File('${File(Platform.resolvedExecutable).parent.path}${_separator}libmpv-version.txt');
    try {
      return file.existsSync() ? LibmpvBuild.fromVersionFile(file.readAsStringSync()) : null;
    } on FileSystemException {
      return null;
    }
  }

  Future<ToolPaths> ensureReady() async {
    // Android: libmpv comes inside the APK; yt-dlp runs with the APK's
    // Python, and without it streams come from the core (quick.rs) alone.
    if (Platform.isAndroid) return ToolPaths(mpv: '', ytDlp: await _androidYtDlp(), deno: null);
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) throw UnsupportedError('Lumtub runs on Windows, Linux, macOS and Android.');
    // The runner already loaded a downloaded libmpv when one was selected;
    // Dart has to open that same copy.
    final mpv = _systemMpv ? _linuxMpv : libmpv.loadedPath ?? _bundledMpv;
    if (!_systemMpv && !File(mpv).existsSync()) throw StateError('Bundled libmpv-2.dll is missing. Re-download the Lumtub package.');
    if (discover()?.ytDlp.isNotEmpty != true) {
      status('First launch: installing yt-dlp…');
      await _installYtDlp();
    }
    // Deno is needed by some YouTube JavaScript challenge paths. Optional at startup.
    // After a failed try, launches within six hours start without waiting
    // on it again (offline, it is a 25-second wait every time).
    final denoFailed = File('${root.path}${_separator}deno-failed');
    final failedAt = denoFailed.existsSync() ? denoFailed.lastModifiedSync() : null;
    if (discover()?.deno == null && (failedAt == null || DateTime.now().difference(failedAt) > const Duration(hours: 6))) {
      try {
        status('Installing Deno, needed for YouTube extraction…');
        await _installDeno();
        if (denoFailed.existsSync()) denoFailed.deleteSync();
      } catch (e) {
        try {
          denoFailed.writeAsStringSync('$e');
        } catch (e) {
          logDebug(() => 'Could not write the Deno failure note: $e');
        }
        status('Deno is unavailable for now. You can retry later from tool updates: {0}', [e]);
      }
    }
    final ready = discover();
    if (ready == null || ready.ytDlp.isEmpty) {
      throw StateError('Required components could not be installed.');
    }
    return ToolPaths(mpv: mpv, ytDlp: ready.ytDlp, deno: ready.deno);
  }

  /// The newest yt-dlp, the one inside the APK installed the first time;
  /// '' when Python cannot run.
  Future<String> _androidYtDlp() async {
    final AndroidPython? python;
    try {
      python = await AndroidPython.prepare();
    } catch (e) {
      logWarn('Python for yt-dlp could not be prepared: $e');
      return '';
    }
    if (python == null) return '';
    final found = discover()?.ytDlp;
    if (found != null && found.isNotEmpty) return found;
    final bundled = python.bundledYtDlp;
    if (bundled == null) return '';
    try {
      status('Preparing yt-dlp…');
      final check = await runWithTimeout(bundled, ['--version'], timeout: const Duration(seconds: 60));
      if (check.exitCode != 0) throw StateError('${check.stderr}'.trim());
      final tag = _safeTag('${check.stdout}'.trim());
      final dest = Directory('${root.path}${_separator}yt-dlp$_separator$tag');
      await dest.create(recursive: true);
      final file = await File(bundled).copy('${dest.path}${_separator}yt-dlp');
      // In the system log, where the emulator test looks for it.
      debugPrint('Lumtub: yt-dlp $tag runs with Python');
      return file.path;
    } catch (e) {
      debugPrint('Lumtub: yt-dlp does not run: $e');
      logWarn('The bundled yt-dlp does not run: $e');
      return '';
    }
  }

  String get _bundledMpv => '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}libmpv-2.dll';

  ToolPaths? discover() {
    if (!root.existsSync()) return null;
    final bundledMpv = _systemMpv ? _linuxMpv : libmpv.loadedPath ?? _bundledMpv;
    final mpv = _systemMpv || File(bundledMpv).existsSync() ? bundledMpv : null;
    final yt = _findNewest('yt-dlp', _exe('yt-dlp'));
    final deno = _findNewest('deno', _exe('deno'));
    if (mpv == null && yt == null) return null;
    return ToolPaths(mpv: mpv ?? '', ytDlp: yt ?? '', deno: deno);
  }

  String? _findNewest(String group, String fileName) {
    final parent = Directory('${root.path}${Platform.pathSeparator}$group');
    if (!parent.existsSync()) return null;
    final dirs = _versions(parent);
    // Settings pages ask on every rebuild, and a yt-dlp folder holds a
    // thousand files: the answer is kept while the version folders stay.
    final key = '$group/$fileName';
    final folders = dirs.map((d) => d.path).join('|');
    if (_found[key] case (final known, final path) when known == folders && (path == null || File(path).existsSync())) return path;
    String? found;
    search:
    for (final folder in dirs) {
      try {
        for (final item in folder.listSync(recursive: true, followLinks: false)) {
          if (item is File && item.uri.pathSegments.last.toLowerCase() == fileName.toLowerCase()) {
            found = item.path;
            break search;
          }
        }
      } catch (e) {
        logDebug(() => 'Could not search a tool version folder: $e');
      }
    }
    _found[key] = (folders, found);
    return found;
  }

  final _found = <String, (String, String?)>{};

  /// Usable version folders in [parent], newest first.
  List<Directory> _versions(Directory parent) {
    if (!parent.existsSync()) return const [];
    return parent
        .listSync()
        .whereType<Directory>()
        .where((d) => !d.path.endsWith('.partial') && !File('${d.path}$_separator$_failedMarker').existsSync())
        .toList()
      ..sort((a, b) => compareVersionFolders(a.path, b.path));
  }

  static const _failedMarker = 'failed';
  static const _no7zMarker = 'cannot-extract-7z';

  /// The yt-dlp release tag in use, if any.
  String? get ytDlpVersion => _versionOf(discover()?.ytDlp);

  String? get denoVersion => _versionOf(discover()?.deno);

  String? _versionOf(String? executable) {
    if (executable == null || executable.isEmpty) return null;
    final parts = executable.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty).toList();
    return parts.length < 2 ? null : parts[parts.length - 2].replaceFirst(RegExp(r'-dir$'), '');
  }

  /// Whether the yt-dlp in use is the single-file build, which the
  /// unpacked one replaces as soon as possible rather than at the next
  /// release.
  bool get _ytDlpIsSingleFile {
    final yt = discover()?.ytDlp;
    if (Platform.isAndroid || yt == null || yt.isEmpty) return false;
    return !Directory('${File(yt).parent.path}${_separator}_internal').existsSync();
  }

  /// Whether an older working yt-dlp is installed to go back to.
  bool get canRollBackYtDlp => _versions(Directory('${root.path}${_separator}yt-dlp')).length > 1;

  /// Stops using the newest yt-dlp, for example after a nightly build broke
  /// playback. Takes effect at the next launch, like an update.
  Future<void> rollBackYtDlp() async {
    final versions = _versions(Directory('${root.path}${_separator}yt-dlp'));
    if (versions.length < 2) return;
    await File('${versions.first.path}$_separator$_failedMarker').writeAsString(DateTime.now().toIso8601String());
  }

  Future<void> checkUpdates({bool force = false}) async {
    // Android has no Deno to keep current, and yt-dlp only with its Python.
    if (Platform.isIOS || Platform.isAndroid && AndroidPython.current == null) return;
    final stamp = File('${root.path}${Platform.pathSeparator}last_update_check.txt');
    // The single-file yt-dlp is replaced as soon as possible, but a failed
    // try waits an hour, as does any check that failed, rather than costing
    // every launch GitHub requests against its hourly limit.
    if (!force && await stamp.exists()) {
      final [time, ...rest] = (await stamp.readAsString()).trim().split(' ');
      final last = DateTime.tryParse(time);
      final wait = _ytDlpIsSingleFile || rest.contains('failed') ? const Duration(hours: 1) : const Duration(hours: 24);
      if (last != null && DateTime.now().difference(last) < wait) return;
    }
    // The ffmpeg earlier versions installed for downloads; the core joins
    // and cuts streams now.
    try {
      final ffmpeg = Directory('${root.path}${_separator}ffmpeg');
      if (await ffmpeg.exists()) await ffmpeg.delete(recursive: true);
    } on FileSystemException catch (e) {
      logWarn('Could not remove the old ffmpeg: ${e.message}');
    }
    final errors = <String>[];
    for (final task in <(String, Future<void> Function())>[
      ('yt-dlp', _installYtDlp),
      if (!Platform.isAndroid) ('Deno', _installDeno),
      if (!_systemMpv) ('libmpv', _installLibmpv),
    ]) {
      try {
        status('Check for {0} updates…', [task.$1]);
        await task.$2();
      } catch (e) {
        errors.add('${task.$1}: $e');
      }
    }
    if (errors.isEmpty) {
      await stamp.writeAsString(DateTime.now().toIso8601String());
      status('Update check complete. New versions take effect after restarting the app.');
    } else {
      await stamp.writeAsString('${DateTime.now().toIso8601String()} failed');
      status('Some components failed to update; current versions are unaffected: {0}', [errors.join(' / ')]);
    }
  }

  Future<Map<String, dynamic>> _release(String repository, {String? tag}) async {
    final response = await _client.get(
      Uri.parse('https://api.github.com/repos/$repository/releases/${tag == null ? 'latest' : 'tags/$tag'}'),
      headers: {'Accept': 'application/vnd.github+json', 'User-Agent': _userAgent},
    ).timeout(const Duration(seconds: 25));
    if (response.statusCode == 200) return jsonDecode(response.body) as Map<String, dynamic>;
    // The API allows 60 unsigned requests an hour per address, which a
    // shared address can use up; releases that list their SHA-256 sums in
    // a file are still read from github.com itself.
    final sums = _sumsFileOf(repository);
    if (sums != null && (response.statusCode == 403 || response.statusCode == 429)) {
      try {
        return await _releaseFromSums(repository, sums, tag: tag);
      } catch (e) {
        logDebug(() => 'Could not read the release checksums: $e');
      }
    }
    throw HttpException('GitHub API HTTP ${response.statusCode} for $repository');
  }

  /// The file in [repository]'s releases with the SHA-256 sums of the
  /// packages wanted; Deno has one beside each package.
  String? _sumsFileOf(String repository) => switch (repository) {
        'yt-dlp/yt-dlp-nightly-builds' => 'SHA2-256SUMS',
        'denoland/deno' => '$_denoPackage.sha256sum',
        _ => null,
      };

  /// Deno's package for this computer.
  String get _denoPackage => 'deno-${Platform.isWindows ? 'x86_64-pc-windows-msvc' : Platform.isMacOS ? (_macArm64 ? 'aarch64-apple-darwin' : 'x86_64-apple-darwin') : _linuxArm64 ? 'aarch64-unknown-linux-gnu' : 'x86_64-unknown-linux-gnu'}.zip';

  Future<Map<String, dynamic>> _releaseFromSums(String repository, String sumsFile, {String? tag}) async {
    var name = tag;
    if (name == null) {
      final request = http.Request('GET', Uri.parse('https://github.com/$repository/releases/latest'))
        ..followRedirects = false
        ..headers['User-Agent'] = _userAgent;
      // The Rust client always follows redirects, so the redirect itself is
      // read with Dart's own client, which uses the app's proxy overrides.
      final plain = http.Client();
      try {
        final answer = await plain.send(request).timeout(const Duration(seconds: 25));
        await answer.stream.drain<void>();
        name = releaseTagOfRedirect(repository, answer.headers['location']);
      } finally {
        plain.close();
      }
      if (name == null) throw HttpException('No latest release redirect for $repository');
    }
    final base = 'https://github.com/$repository/releases/download/${Uri.encodeComponent(name)}';
    final response = await _client.get(Uri.parse('$base/$sumsFile'), headers: {'User-Agent': _userAgent}).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) throw HttpException('$sumsFile HTTP ${response.statusCode} for $repository');
    return {
      'tag_name': name,
      'assets': [
        for (final (hash, file) in parseSha256Sums(response.body))
          {'name': file, 'browser_download_url': '$base/${Uri.encodeComponent(file)}', 'digest': 'sha256:$hash'},
      ],
    };
  }

  /// The tag a github.com `releases/latest` redirect points at.
  static String? releaseTagOfRedirect(String repository, String? location) {
    if (location == null) return null;
    final uri = Uri.tryParse(location);
    if (uri == null || uri.host != 'github.com') return null;
    final prefix = '$repository/releases/tag'.split('/');
    final parts = uri.pathSegments;
    if (parts.length != prefix.length + 1) return null;
    for (var i = 0; i < prefix.length; i++) {
      if (parts[i].toLowerCase() != prefix[i].toLowerCase()) return null;
    }
    final tag = parts.last;
    return tag.isEmpty ? null : tag;
  }

  /// `hash  name` lines of a SHA-256 sums file.
  static List<(String, String)> parseSha256Sums(String body) => [
        for (final line in body.split('\n'))
          if (RegExp(r'^([a-fA-F0-9]{64}) [ *]?(\S.*?)\s*$').firstMatch(line) case final m?) (m[1]!.toLowerCase(), m[2]!),
      ];

  Map<String, dynamic> _asset(Map<String, dynamic> release, bool Function(String) accept) {
    final raw = release['assets'];
    if (raw is! List) throw const FormatException('GitHub release contains no assets');
    for (final obj in raw) {
      if (obj is Map<String, dynamic> && accept(obj['name']?.toString() ?? '')) return obj;
    }
    throw StateError('Matching release asset not found: ${release['tag_name']}');
  }

  Uri _assetUri(Map<String, dynamic> asset) {
    final uri = Uri.parse(asset['browser_download_url']?.toString() ?? '');
    if (uri.scheme != 'https' || uri.host != 'github.com' || (asset['name']?.toString() ?? '').isEmpty) {
      throw const FormatException('Untrusted GitHub asset URL');
    }
    return uri;
  }

  /// Downloads a GitHub release [asset] into [into], checked against the
  /// SHA-256 digest GitHub lists for it.
  Future<File> downloadVerified(Map<String, dynamic> asset, Directory into, void Function(int received, int? total) onProgress) => _downloadVerified(asset, into, onProgress: onProgress);

  /// Downloads [asset] into [into] and checks its SHA-256: [sha256Hex] when
  /// given (from the release's checksum file), else the digest GitHub lists.
  Future<File> _downloadVerified(Map<String, dynamic> asset, Directory into, {String? sha256Hex, void Function(int received, int? total)? onProgress}) async {
    final assetName = asset['name']?.toString() ?? '';
    final uri = _assetUri(asset);
    final digest = sha256Hex == null ? asset['digest']?.toString() ?? '' : 'sha256:$sha256Hex';
    if (!RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest)) {
      throw StateError('No trusted SHA-256 digest for $assetName');
    }
    await into.create(recursive: true);
    final file = File('${into.path}${Platform.pathSeparator}$assetName');
    if (await file.exists() && (await _sha256(file)) == digest.substring(7).toLowerCase()) return file;
    final temp = File('${file.path}.download');
    if (await temp.exists()) await temp.delete();
    try {
      final result = await _sendRetrying(uri);
      if (result.statusCode != 200) throw HttpException('Download failed: HTTP ${result.statusCode}');
      final sink = temp.openWrite();
      try {
        var received = 0;
        await sink.addStream(result.stream.timeout(const Duration(seconds: 90)).map((chunk) {
          received += chunk.length;
          onProgress?.call(received, result.contentLength);
          return chunk;
        }));
      } finally {
        await sink.close();
      }
      if ((await _sha256(temp)) != digest.substring(7).toLowerCase()) {
        throw const FormatException('SHA-256 verification failed');
      }
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
      return file;
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  /// GitHub's downloads answer 502 to 504 now and then; such answers, and
  /// 429, are asked again a few times before the last one is returned.
  Future<http.StreamedResponse> _sendRetrying(Uri uri) async {
    const waits = [Duration(seconds: 2), Duration(seconds: 5), Duration(seconds: 10)];
    for (var attempt = 0; ; attempt++) {
      final request = http.Request('GET', uri);
      request.headers['User-Agent'] = _userAgent;
      final result = await _client.send(request).timeout(const Duration(seconds: 30));
      final busy = result.statusCode == 429 || (result.statusCode >= 502 && result.statusCode <= 504);
      if (!busy || attempt >= waits.length) return result;
      await result.stream.drain<void>();
      await Future<void>.delayed(waits[attempt]);
    }
  }

  /// The file's SHA-256, hashed by the native core on another isolate so the
  /// window keeps drawing; Dart hashes it when the core is missing.
  Future<String> _sha256(File file) async {
    final path = file.path;
    final native = NativeCore.instance == null ? null : await Isolate.run(() => NativeCore.fileSha256Of(path));
    return native ?? (await sha256.bind(file.openRead()).first).toString();
  }

  Future<void> _installYtDlp() async {
    final release = await _release('yt-dlp/yt-dlp-nightly-builds');
    final tag = _safeTag(release['tag_name']);
    final group = Directory('${root.path}${_separator}yt-dlp');
    if (!Platform.isAndroid) await _removeSingleFileYtDlp(group);
    var dest = Directory('${group.path}$_separator$tag');
    // A version rolled back by the user is not installed again.
    if (await File('${dest.path}$_separator$_failedMarker').exists()) return;
    if (await File('${dest.path}$_separator${_exe('yt-dlp')}').exists()) {
      // Android's is the zip app, which Python runs as it is.
      if (Platform.isAndroid) return;
      if (await Directory('${dest.path}${_separator}_internal').exists()) return;
      // The same release as the single-file build in use, unpacked, beside
      // it: the running one cannot be replaced, and the newer name wins.
      dest = Directory('${dest.path}-dir');
      if (await File('${dest.path}$_separator$_failedMarker').exists()) return;
      if (await File('${dest.path}$_separator${_exe('yt-dlp')}').exists()) return;
    }
    status('Downloading yt-dlp {0}…', [tag]);
    final partial = Directory('${dest.path}.partial');
    if (await partial.exists()) await partial.delete(recursive: true);
    try {
      final file = await _downloadYtDlp(release, partial);
      // A build that cannot even report its version is never used.
      final check = await runWithTimeout(file.path, ['--version'], timeout: const Duration(seconds: 30));
      if (check.exitCode != 0) throw StateError('yt-dlp $tag failed its self-check');
      await partial.rename(dest.path);
    } catch (_) {
      if (await partial.exists()) await partial.delete(recursive: true);
      rethrow;
    }
    await _prune(group, keep: 3);
  }

  /// The unpacked build (yt-dlp_win.zip). The single-file yt-dlp.exe
  /// unpacks itself to a temp folder on every start, which costs a second
  /// of CPU and a second process for each search or channel page.
  Future<File> _downloadYtDlp(Map<String, dynamic> release, Directory into) async {
    if (Platform.isAndroid) {
      final app = await _downloadVerified(_asset(release, (name) => name == ytDlpFolderAsset), Directory('${root.path}${_separator}downloads'));
      await into.create(recursive: true);
      return app.rename('${into.path}${_separator}yt-dlp');
    }
    final archive = await _downloadVerified(_asset(release, (name) => name == ytDlpFolderAsset), Directory('${root.path}${_separator}downloads'));
    await into.create(recursive: true);
    await _extractZip(archive, into);
    await archive.delete();
    if (!Platform.isWindows) {
      // mpv's ytdl_hook, used for live videos, looks for it as yt-dlp.
      final named = File('${into.path}$_separator$_ytDlpInArchive');
      if (await named.exists()) await named.rename('${into.path}${_separator}yt-dlp');
    }
    final exe = File('${into.path}$_separator${_exe('yt-dlp')}');
    if (!await exe.exists()) throw StateError('$ytDlpFolderAsset has no ${_exe('yt-dlp')}');
    await _makeExecutable(exe.path);
    return exe;
  }

  /// Deletes single-file yt-dlp builds once an unpacked one is installed.
  /// One still running stays until the next launch.
  Future<void> _removeSingleFileYtDlp(Directory group) async {
    final versions = _versions(group);
    bool unpacked(Directory d) => Directory('${d.path}${_separator}_internal').existsSync();
    if (!versions.any(unpacked)) return;
    for (final old in versions.where((d) => !unpacked(d))) {
      try {
        await old.delete(recursive: true);
      } on FileSystemException {
        // In use; tried again next time.
      }
    }
  }

  static String get ytDlpFolderAsset => Platform.isAndroid
      ? 'yt-dlp'
      : Platform.isWindows
      ? 'yt-dlp_win.zip'
      : Platform.isMacOS
          ? 'yt-dlp_macos.zip'
          : _linuxArm64
              ? 'yt-dlp_linux_aarch64.zip'
              : 'yt-dlp_linux.zip';

  /// The executable's name in the Linux or macOS archive.
  static String get _ytDlpInArchive => Platform.isMacOS ? 'yt-dlp_macos' : _linuxArm64 ? 'yt-dlp_linux_aarch64' : 'yt-dlp_linux';

  /// Deletes all but the newest [keep] usable versions in [group]; rolled
  /// back versions stay as markers so they are not downloaded again.
  Future<void> _prune(Directory group, {required int keep}) async {
    for (final old in _versions(group).skip(keep)) {
      try {
        await old.delete(recursive: true);
      } on FileSystemException {
        // Still in use by a running process; tried again next time.
      }
    }
  }

  Future<void> _installLibmpv() async {
    if (_systemMpv) return;
    final release = await _release('zhongfly/mpv-winbuild');
    final tag = _safeTag(release['tag_name']);
    final build = LibmpvBuild(tag, libmpvVariantForThisProcess());
    final running = libmpv.selected ?? libmpv.current;
    if (running != null && !running.isReplacedBy(build)) return;
    final group = libmpv.directory;
    final no7z = File('${group.path}$_separator$_no7zMarker');
    if (await no7z.exists()) return;
    final dest = Directory('${group.path}$_separator${build.folderName}');
    final dll = File('${dest.path}${_separator}libmpv-2.dll');
    if (libmpv.hasFailed(dll.path)) return;
    if (!await dll.exists()) {
      final names = (release['assets'] as List? ?? const []).whereType<Map>().map((asset) => asset['name']?.toString() ?? '');
      final assetName = libmpvAssetName(names, build.variant);
      if (assetName == null) throw StateError('No libmpv archive for this CPU in $tag');
      status('Downloading libmpv {0}…', [build.label]);
      final archive = await _downloadVerified(_asset(release, (name) => name == assetName), Directory('${root.path}${_separator}downloads'));
      final partial = Directory('${dest.path}.partial');
      if (await partial.exists()) await partial.delete(recursive: true);
      await partial.create(recursive: true);
      try {
        try {
          await _extractZip(archive, partial);
        } on ProcessException {
          // Windows before 11 23H2 has no 7z support in tar.exe; do not
          // download every new release only to fail again.
          await no7z.writeAsString(DateTime.now().toIso8601String());
          throw StateError(tr("This version of Windows can't extract 7z files. Still using the built-in libmpv"));
        }
        final found = partial.listSync(recursive: true).whereType<File>().where((f) => f.path.toLowerCase().endsWith('${_separator}libmpv-2.dll'));
        if (found.isEmpty) throw StateError('libmpv archive $tag has no libmpv-2.dll');
        await dest.create(recursive: true);
        await found.first.copy(dll.path);
      } finally {
        await partial.delete(recursive: true);
        if (await archive.exists()) await archive.delete();
      }
    }
    await libmpv.select(dll.path);
    // Keep the running copy and the new one; the loaded DLL cannot be deleted.
    for (final old in group.listSync().whereType<Directory>()) {
      if (old.path == dest.path || (libmpv.loadedPath?.startsWith('${old.path}$_separator') ?? false)) continue;
      try {
        await old.delete(recursive: true);
      } on FileSystemException {
        // Locked; tried again next time.
      }
    }
  }

  Future<void> _installDeno() async {
    final release = await _release('denoland/deno');
    final tag = _safeTag(release['tag_name']);
    final dest = Directory('${root.path}${Platform.pathSeparator}deno${Platform.pathSeparator}$tag');
    if (await File('${dest.path}$_separator${_exe('deno')}').exists()) return;
    status('Downloading Deno {0}…', [tag]);
    final asset = _asset(release, (name) => name == _denoPackage);
    final archive = await _downloadVerified(asset, Directory('${root.path}${Platform.pathSeparator}downloads'));
    final partial = Directory('${dest.path}.partial');
    if (await partial.exists()) await partial.delete(recursive: true);
    await partial.create(recursive: true);
    try {
      await _extractZip(archive, partial);
      if (!await File('${partial.path}$_separator${_exe('deno')}').exists()) {
        throw StateError('Deno release did not contain ${_exe('deno')}');
      }
      await _makeExecutable('${partial.path}$_separator${_exe('deno')}');
      await dest.parent.create(recursive: true);
      await partial.rename(dest.path);
    } catch (_) {
      if (await partial.exists()) await partial.delete(recursive: true);
      rethrow;
    }
  }

  String _safeTag(Object? value) {
    final tag = value?.toString() ?? '';
    if (!RegExp(r'^[a-zA-Z0-9._-]{1,100}$').hasMatch(tag)) throw const FormatException('Invalid release tag');
    return tag;
  }

  Future<void> _extractZip(File archive, Directory into) async {
    if (!Platform.isWindows) {
      await extractZip(archive, into);
      return;
    }
    final result = await Process.run('tar.exe', ['-xf', archive.path, '-C', into.path]);
    if (result.exitCode != 0) {
      throw ProcessException('tar.exe', ['-xf', archive.path, '-C', into.path], result.stderr.toString(), result.exitCode);
    }
  }

  static String get _userAgent => Platform.isWindows ? 'Lumtub-Windows/0.1' : 'Lumtub-${Platform.operatingSystem}/0.1';

  void dispose() => _client.close();
}
