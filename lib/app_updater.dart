import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'friendly_error.dart';
import 'l10n/l10n.dart';
import 'native_core.dart';

/// The package this build is, such as `windows-x64-v3`; empty for builds
/// made outside CI, which never update themselves.
const appPackage = String.fromEnvironment('LUMTUB_PACKAGE');

/// The release file this build updates from. The Mac app is built once for
/// both CPUs and shipped thinned to each, so it asks for the one it runs on.
String get updatePackage => switch (appPackage) {
      'macos' => 'macos-${Abi.current() == Abi.macosArm64 ? 'arm64' : 'x64'}',
      // One APK per processor type, like the ones CI builds.
      'android' => 'android-${switch (Abi.current()) { Abi.androidArm64 => 'arm64-v8a', Abi.androidArm => 'armeabi-v7a', _ => 'x86_64' }}',
      _ => appPackage,
    };

/// When this build's commit was made, from CI.
final appBuilt = DateTime.tryParse(const String.fromEnvironment('LUMTUB_BUILT'));

/// A release newer than the running build.
class AppRelease {
  const AppRelease({required this.version, required this.page, this.asset, this.signature});
  /// Such as `0.2.1-72ec49d`.
  final String version;
  /// The release's GitHub page.
  final String page;
  /// The installer or portable ZIP for this package, as GitHub lists it.
  final Map<String, dynamic>? asset;
  /// The asset's `.sig`: Ed25519 and ML-DSA-65 signatures, both required.
  final Map<String, dynamic>? signature;
}

/// Keeps Lumtub up to date without getting in the way: it checks GitHub,
/// downloads the new installer (or the portable ZIP) in the background and
/// verifies its SHA-256 and both of its signatures, then installs it once Lumtub closes, so the next start is
/// the new version. [restartNow] does the same at once.
class AppUpdater extends ChangeNotifier {
  AppUpdater({required http.Client client, required Directory directory, required Future<File> Function(Map<String, dynamic> asset, Directory into, void Function(int received, int? total) onProgress) download})
      : _client = client,
        _directory = directory,
        _download = download;

  final http.Client _client;
  /// Where packages are downloaded to.
  final Directory _directory;
  final Future<File> Function(Map<String, dynamic> asset, Directory into, void Function(int received, int? total) onProgress) _download;

  bool checking = false;
  /// The newer release, while there is one.
  AppRelease? available;
  /// 0 to 1 while downloading.
  double? progress;
  /// The verified package, installed when Lumtub closes.
  File? ready;
  String? error;
  /// Why the installer did not start, as when its administrator prompt
  /// was declined; the package stays ready for another try.
  String? installError;
  /// A version whose package failed its signature check; it is not
  /// downloaded again, and the settings page sends to GitHub instead.
  String? rejected;
  Timer? _timer;
  bool _disposed = false;
  /// GitHub's ETag for the last answer and that answer, so a check can ask
  /// "has it changed?" and an unchanged one (HTTP 304) costs no rate limit.
  String? _etag;
  Map<String, dynamic>? _latest;

  /// The portable package keeps a portable.txt next to lumtub.exe.
  static bool get portable => File('${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}portable.txt').existsSync();

  /// Whether this build can install updates itself.
  static bool get canInstall => (Platform.isWindows || Platform.isAndroid || appImage != null || macApp != null) && appPackage.isNotEmpty && appBuilt != null;

  /// The app bundle this macOS build runs from, which an update replaces,
  /// when Lumtub may write the folder it is in.
  static String? get macApp {
    if (!Platform.isMacOS) return null;
    final app = File(Platform.resolvedExecutable).parent.parent.parent.path;
    if (!app.endsWith('.app') || app.startsWith('/Volumes/')) return null;
    return canReplace(app) ? app : null;
  }

  /// The AppImage file this Linux build runs from, which an update replaces,
  /// when Lumtub may write the folder it is in: one a package manager put
  /// in a system folder is updated by that package manager.
  static String? get appImage {
    if (!Platform.isLinux) return null;
    final path = Platform.environment['APPIMAGE'] ?? '';
    return path.isEmpty || !canReplace(path) ? null : path;
  }

  /// Checks now and then every six hours, downloading what it finds when
  /// [download] says so.
  void start({required bool Function() download}) {
    // Cleaning first: it deletes what is in the folder, and the first
    // download writes there.
    unawaited(_cleanUp().then((_) => check(download: download(), automatic: true)));
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(hours: 6), (_) => check(download: download(), automatic: true));
  }

  /// Asks GitHub for the latest release and, with [download], fetches its
  /// package in the background; an [automatic] one not over a metered
  /// (mobile) connection on Android.
  Future<void> check({bool download = false, bool automatic = false}) async {
    if (checking) return;
    checking = true;
    error = null;
    _notify();
    try {
      final response = await _client.get(
        Uri.https('api.github.com', '/repos/0x696c757a696f/lumtub/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'Lumtub/$appVersion', if (_etag != null && _latest != null) 'If-None-Match': _etag!},
      ).timeout(const Duration(seconds: 15));
      final Object? json;
      if (response.statusCode == 304 && _latest != null) {
        json = _latest;
      } else {
        if (response.statusCode != 200) throw HttpException('GitHub returned HTTP ${response.statusCode}');
        json = jsonDecode(response.body);
        if (json is Map<String, dynamic>) {
          _latest = json;
          _etag = response.headers['etag'];
        }
      }
      if (json is! Map<String, dynamic>) throw const FormatException('Invalid GitHub release response');
      final offer = offerOf(json, current: appVersion, built: appBuilt, package: updatePackage, portable: portable);
      available = offer;
      if (offer == null) ready = null;
      logInfo(offer != null ? 'Lumtub update available: ${offer.version}' : 'Lumtub is up to date ($appVersion)');
    } catch (e) {
      error = friendlyError(e);
      logWarn('Could not check Lumtub updates: $e');
    } finally {
      checking = false;
      _notify();
    }
    if (download && !(automatic && await _metered())) await this.download();
  }

  /// Whether Android says the connection is metered, as mobile data is.
  static Future<bool> _metered() async {
    if (!Platform.isAndroid) return false;
    try {
      return await const MethodChannel('lumtub/windows_shell').invokeMethod<bool>('isMetered') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Downloads and verifies the available package, in the background.
  Future<void> download() async {
    final asset = available?.asset;
    if (!canInstall || asset == null || progress != null || rejected == available!.version || ready?.path.endsWith(asset['name'].toString()) == true) return;
    progress = 0;
    error = null;
    _notify();
    try {
      final file = await _download(asset, _directory, (received, total) {
        if (total == null || total <= 0) return;
        // Whole percents only: each notice rebuilds the app.
        final next = (received * 100 ~/ total) / 100;
        if (next == progress) return;
        progress = next;
        _notify();
      });
      try {
        await _verifySignature(file, asset, available!.signature);
      } on FormatException {
        rejected = available!.version;
        rethrow;
      }
      ready = file;
      logInfo('Lumtub ${available!.version} downloaded; it installs when Lumtub closes');
    } catch (e) {
      error = friendlyError(e);
      logWarn('Could not download the Lumtub update: $e');
    } finally {
      progress = null;
      _notify();
    }
  }

  /// Fetches the package's `.sig` and checks it in the native core; deletes
  /// [file] and throws when the signatures do not hold.
  Future<void> _verifySignature(File file, Map<String, dynamic> asset, Map<String, dynamic>? signature) async {
    final name = asset['name'].toString();
    try {
      final uri = Uri.parse(signature?['browser_download_url']?.toString() ?? '');
      if (signature == null || uri.scheme != 'https' || uri.host != 'github.com') throw const FormatException('The update has no signature');
      final response = await _client.get(uri, headers: {'User-Agent': 'Lumtub/$appVersion'}).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw HttpException('Signature download failed: HTTP ${response.statusCode}');
      final sig = File('${file.path}.sig');
      await sig.writeAsBytes(response.bodyBytes);
      final path = file.path, sigPath = sig.path, version = available?.version;
      final error = await Isolate.run(() => verifyUpdate(file: path, name: name, signature: sigPath, version: version, current: appVersion));
      if (error != null) throw FormatException(error);
    } catch (_) {
      await _discard(file);
      rethrow;
    }
  }

  static Future<void> _discard(File file) async {
    for (final f in [file, File('${file.path}.sig')]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// Checks the package against the `.sig` saved at download once more,
  /// right before it is installed, in case the file changed on disk since.
  /// Deletes it and returns false when it no longer holds.
  Future<bool> _recheck(File file) async {
    final name = available?.asset?['name']?.toString() ?? file.path.split(Platform.pathSeparator).last;
    final sigPath = '${file.path}.sig', path = file.path, version = available?.version;
    String? error;
    try {
      error = await File(sigPath).exists() ? await Isolate.run(() => verifyUpdate(file: path, name: name, signature: sigPath, version: version, current: appVersion)) : 'The update signature is missing';
    } catch (e) {
      error = '$e';
    }
    if (error == null) return true;
    logWarn('The downloaded Lumtub update failed its check before installing: $error');
    await _discard(file);
    rejected = available?.version;
    ready = null;
    installError = tr('see the logs for details');
    _notify();
    return false;
  }

  /// Installs the downloaded package once this process has ended, and
  /// starts Lumtub again when [relaunch]. Returns whether it was handed
  /// over; false when it could not start, as when the administrator prompt
  /// was declined, and Lumtub should keep running.
  ///
  /// The installer is started directly and waits for Lumtub itself: a
  /// hidden PowerShell script, as before, is what security software stops.
  /// The portable ZIP still needs the script to unpack it.
  Future<bool> install({bool relaunch = false}) async {
    final file = ready;
    if (file == null || !await file.exists()) return false;
    if (!await _recheck(file)) return false;
    if (Platform.isAndroid) return _installApk(file);
    final executable = Platform.resolvedExecutable;
    final portable = file.path.endsWith('.zip');
    try {
      final image = appImage;
      final app = macApp;
      if (app != null) {
        await replaceMacApp(file, app);
        logInfo('Installed Lumtub ${available?.version ?? ''} to $app');
        await AppLog.current?.flush();
        if (relaunch) await relaunchAfterExit(app, pid, open: true);
      } else if (image != null) {
        await replaceAppImage(file, image);
        logInfo('Installed Lumtub ${available?.version ?? ''} to $image');
        await AppLog.current?.flush();
        if (relaunch) await relaunchAfterExit(image, pid);
      } else if (!portable) {
        final folder = File(executable).parent.path;
        final result = launchInstaller(package: file.path, folder: folder, processId: pid, relaunch: relaunch);
        if (result == null) throw StateError('No native core');
        if (result['ok'] != true) {
          logWarn('Could not start the Lumtub installer${result['elevated'] == true ? ' as administrator' : ''}: ${result['error']}');
          installError = result['elevated'] == true ? tr('Administrator rights are needed to install into this folder') : tr('see the logs for details');
          _notify();
          return false;
        }
        installError = null;
        logInfo('Installing Lumtub ${available?.version ?? ''} after exit${result['elevated'] == true ? ' as administrator' : ''}');
        await AppLog.current?.flush();
      } else {
        final script = File('${_directory.path}${Platform.pathSeparator}install-update.ps1');
        final text = updateScript(package: file.path, processId: pid, executable: executable, portable: true, relaunch: relaunch);
        if (text == null) return false;
        // Windows PowerShell reads a script without a byte order mark in the
        // ANSI code page, which garbles a path outside it.
        await script.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(text)]);
        await Process.start('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', script.path], mode: ProcessStartMode.detached);
        logInfo('Installing Lumtub ${available?.version ?? ''} after exit');
        await AppLog.current?.flush();
      }
      ready = null;
      return true;
    } catch (e) {
      logWarn('Could not start the Lumtub update: $e');
      if (appImage != null || macApp != null) {
        installError = friendlyFileError(e);
        _notify();
      }
      return false;
    }
  }

  /// Hands the APK to Android's installer, which asks the user and then
  /// replaces the running app. The file stays ready in case they say no.
  Future<bool> _installApk(File file) async {
    try {
      await const MethodChannel('lumtub/windows_shell').invokeMethod<void>('installApk', file.path);
      installError = null;
      logInfo('Handed Lumtub ${available?.version ?? ''} to the Android installer');
      return true;
    } on PlatformException catch (e) {
      logWarn('Could not start the Android installer: ${e.message ?? e.code}');
      installError = tr('see the logs for details');
      _notify();
      return false;
    }
  }

  /// Removes the packages of updates already installed, after logging how
  /// the last install went (update.log, and the installer's own log when
  /// it failed).
  Future<void> _cleanUp() async {
    try {
      if (!await _directory.exists()) return;
      final sep = Platform.pathSeparator;
      final outcome = File('${_directory.path}${sep}update.log');
      final setupLog = File('${_directory.path}${sep}setup.log');
      if (!await outcome.exists() && await setupLog.exists()) {
        final tail = (await setupLog.readAsLines(encoding: const Utf8Codec(allowMalformed: true))).reversed.take(8).toList().reversed;
        logWarn('Lumtub update did not finish; installer log ends with:\n${tail.join('\n')}');
      }
      if (await outcome.exists()) {
        final lines = (await outcome.readAsLines(encoding: const Utf8Codec(allowMalformed: true))).where((line) => line.trim().isNotEmpty).toList();
        final last = lines.isEmpty ? '' : lines.last.trim();
        logInfo('Last Lumtub update: $last');
        if (!last.endsWith(' updated')) {
          final setup = File('${_directory.path}${sep}setup.log');
          if (await setup.exists()) {
            final tail = (await setup.readAsLines(encoding: const Utf8Codec(allowMalformed: true))).reversed.take(8).toList().reversed;
            logInfo('Installer log ends with:\n${tail.join('\n')}');
          }
        }
      }
      await for (final entity in _directory.list()) {
        if (entity is File) await entity.delete();
      }
    } catch (e) {
      logWarn('Could not clean the update folder: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

/// Puts the verified AppImage [update] in place of [image]. The running
/// program keeps the old file open, so it is replaced by a rename on the
/// same file system, never written over.
Future<void> replaceAppImage(File update, String image) async {
  final next = File('$image.update');
  await update.copy(next.path);
  final chmod = await Process.run('chmod', ['755', next.path]);
  if (chmod.exitCode != 0) {
    await next.delete();
    throw StateError('chmod failed: ${chmod.stderr}');
  }
  await next.rename(image);
  await update.delete();
}

/// Starts [image] once process [processId] has ended; a second Lumtub
/// started earlier would only bring the closing one to the front. An app
/// bundle is started with [open].
Future<void> relaunchAfterExit(String image, int processId, {bool open = false}) async {
  final start = open ? r'exec /usr/bin/open -n "$2"' : r'exec "$2"';
  await Process.start('/bin/sh', ['-c', r'while kill -0 "$1" 2>/dev/null; do sleep 0.2; done; ' + start, 'lumtub-relaunch', '$processId', image], mode: ProcessStartMode.detached);
}

/// Whether the folder holding [app] (a macOS bundle or an AppImage) can be
/// written, so that [app] can be replaced.
bool canReplace(String app) {
  try {
    final probe = File('${File(app).parent.path}/.lumtub-write-test-$pid');
    probe.writeAsStringSync('');
    probe.deleteSync();
    return true;
  } catch (_) {
    return false;
  }
}

/// Puts the app from the verified disk image [update] in place of the
/// bundle [app]. The new bundle is copied next to the old one first and
/// swapped in by renames; the running program keeps its open files.
/// Lumtub downloads the image itself, so it carries no quarantine mark and
/// opens without Gatekeeper's first-launch check.
Future<void> replaceMacApp(File update, String app) async {
  final mount = await Directory.systemTemp.createTemp('lumtub-update-');
  final next = '$app.update';
  final old = '$app.old';
  Future<void> run(String program, List<String> arguments) async {
    final result = await Process.run(program, arguments);
    if (result.exitCode != 0) throw StateError('$program failed: ${result.stderr}'.trim());
  }

  try {
    await run('/usr/bin/hdiutil', ['attach', '-nobrowse', '-readonly', '-noautoopen', '-mountpoint', mount.path, update.path]);
    try {
      final bundles = mount.listSync().where((e) => e.path.endsWith('.app')).toList();
      if (bundles.length != 1) throw StateError('The disk image holds ${bundles.length} apps');
      await Process.run('/bin/rm', ['-rf', next]);
      await run('/usr/bin/ditto', [bundles.single.path, next]);
    } finally {
      await Process.run('/usr/bin/hdiutil', ['detach', '-force', mount.path]);
    }
    await Process.run('/usr/bin/xattr', ['-dr', 'com.apple.quarantine', next]);
    await Process.run('/bin/rm', ['-rf', old]);
    await Directory(app).rename(old);
    try {
      await Directory(next).rename(app);
    } catch (_) {
      await Directory(old).rename(app);
      rethrow;
    }
    await Process.run('/bin/rm', ['-rf', old]);
    await update.delete();
  } finally {
    try {
      await mount.delete();
    } catch (e) {
      logDebug(() => 'Could not remove the update mount folder: $e');
    }
  }
}

/// The update [release] (GitHub's JSON) offers a build of [current] made at
/// [built]: newer, with the file for [package]. Null when it is not newer or
/// the native core is missing.
AppRelease? offerOf(Map<String, dynamic> release, {required String current, DateTime? built, String package = '', bool portable = false}) {
  final core = NativeCore.instance;
  if (core == null) return null;
  final ask = jsonEncode({'release': release, 'current': current, 'built': built == null ? null : built.millisecondsSinceEpoch ~/ 1000, 'package': package, 'portable': portable});
  final answer = jsonDecode(core.take(core.withText(ask, core.updateOffer)) ?? 'null');
  if (answer is! Map<String, dynamic>) return null;
  return AppRelease(version: answer['version'] as String, page: answer['page'] as String, asset: answer['asset'] as Map<String, dynamic>?, signature: answer['signature'] as Map<String, dynamic>?);
}

/// Why the package [file] (listed as [name]) fails its `.sig` file
/// [signature], or null when both signatures hold. It reads the whole
/// package, so run it on another isolate.
/// With [version] (the release offered) the package's name must carry that
/// version, newer than [current], so a signed older package can't be passed
/// off as an update.
String? verifyUpdate({required String file, required String name, required String signature, String? version, String? current}) {
  final core = NativeCore.instance;
  if (core == null) return 'The native core is missing';
  final ask = {'file': file, 'name': name, 'signature': signature, if (version != null) 'version': version, if (version != null && current != null && RegExp(r'^v?\d+\.\d+\.\d+').hasMatch(current)) 'current': current};
  final answer = jsonDecode(core.take(core.withText(jsonEncode(ask), core.updateVerify)) ?? 'null');
  if (answer is Map && answer['ok'] == true) return null;
  return answer is Map ? '${answer['error']}' : 'Could not check the signature';
}

/// Starts the installer [package] into [folder]; see `lumtub_update_launch`.
/// Null without the native core.
Map<String, dynamic>? launchInstaller({required String package, required String folder, required int processId, required bool relaunch}) {
  final core = NativeCore.instance;
  if (core == null) return null;
  final ask = jsonEncode({'package': package, 'folder': folder, 'processId': processId, 'relaunch': relaunch});
  return jsonDecode(core.take(core.withText(ask, core.updateLaunch)) ?? 'null') as Map<String, dynamic>?;
}

/// A PowerShell script that waits for Lumtub ([processId]) to end, then runs
/// the installer silently or unpacks the portable ZIP over the folder of
/// [executable], removes [package] and starts Lumtub again if [relaunch].
@visibleForTesting
String? updateScript({required String package, required int processId, required String executable, required bool portable, required bool relaunch}) {
  final core = NativeCore.instance;
  if (core == null) return null;
  final ask = jsonEncode({'package': package, 'processId': processId, 'executable': executable, 'portable': portable, 'relaunch': relaunch});
  return jsonDecode(core.take(core.withText(ask, core.updateScript)) ?? 'null') as String?;
}
