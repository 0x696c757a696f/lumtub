import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'file_mode.dart';
import 'friendly_error.dart';
import 'l10n/l10n.dart';
import 'native_core.dart';
import 'system_env.dart';

/// The package this build is, such as `windows-x64-v3`; empty for builds
/// made outside CI, which never update themselves.
const appPackage = String.fromEnvironment('LUMTUB_PACKAGE');

/// The release file this build updates from. The Mac app is built once for
/// both CPUs and shipped thinned to each, so it asks for the one it runs on.
String get updatePackage => switch (appPackage) {
      'macos' => 'macos-${Abi.current() == Abi.macosArm64 ? 'arm64' : 'x64'}',
      // One APK per processor type, like the ones CI builds.
      'android' => 'android-${switch (Abi.current()) {
          Abi.androidArm64 => 'arm64-v8a',
          Abi.androidArm => 'armeabi-v7a',
          _ => 'x86_64'
        }}',
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

/// Checks a package against its `.sig`, as [verifyUpdate] does.
typedef UpdateVerifier = String? Function(
    {required String file,
    required String name,
    required String signature,
    String? version,
    String? current});

/// Keeps Lumtub up to date without getting in the way: it checks GitHub,
/// downloads the new installer (or the portable ZIP) in the background and
/// verifies its SHA-256 and both of its signatures, then installs it once Lumtub closes, so the next start is
/// the new version. [restartNow] does the same at once.
///
/// When a newer release comes out before a downloaded one is installed,
/// the newer one is downloaded and the older package deleted once the
/// newer one has passed its checks; until then the older one still
/// installs. A downloaded package that is not installed yet stays across
/// starts.
class AppUpdater extends ChangeNotifier {
  AppUpdater({
    required http.Client client,
    required Directory directory,
    required Future<File> Function(Map<String, dynamic> asset, Directory into,
            void Function(int received, int? total) onProgress)
        download,
    @visibleForTesting UpdateVerifier verifier = verifyUpdate,
    @visibleForTesting String? current,
    @visibleForTesting String? package,
    @visibleForTesting http.Client Function()? plainClient,
  })  : _client = client,
        _plainClient = plainClient ?? http.Client.new,
        _package = package ?? updatePackage,
        _directory = directory,
        _download = download,
        _verifier = verifier,
        _current = current ?? appVersion,
        _noticeFile = File('${directory.parent.path}${Platform.pathSeparator}update-notice.txt');

  final http.Client _client;

  /// A dart:io client, for the one request whose redirect is read rather
  /// than followed.
  final http.Client Function() _plainClient;

  /// Where packages are downloaded to.
  final Directory _directory;
  final Future<File> Function(Map<String, dynamic> asset, Directory into,
      void Function(int received, int? total) onProgress) _download;
  final UpdateVerifier _verifier;

  /// The running version.
  final String _current;

  /// The release file this build updates from.
  final String _package;

  /// Holds the notice last closed on the home page, so it stays closed
  /// after a restart.
  final File _noticeFile;

  bool checking = false;

  /// The newer release, while there is one.
  AppRelease? available;

  /// 0 to 1 while downloading.
  double? progress;

  /// The verified package, installed when Lumtub closes.
  File? ready;

  /// The version [ready] is, which can be older than [available] while a
  /// newer release downloads.
  String? readyVersion;

  /// The version being downloaded.
  String? downloading;

  /// The home page's update notice the user closed, as [noticeKey] was.
  String? dismissed;
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

  /// Set when a download was asked for while another one ran, so a newer
  /// release found meanwhile is downloaded right after.
  bool _again = false;

  /// The portable package keeps a portable.txt next to lumtub.exe.
  static bool get portable =>
      File('${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}portable.txt')
          .existsSync();

  /// Stands in for [canInstall] in tests.
  @visibleForTesting
  static bool? debugCanInstall;

  /// Whether this build can install updates itself.
  static bool get canInstall =>
      debugCanInstall ??
      ((Platform.isWindows || Platform.isAndroid || appImage != null || macApp != null) &&
          appPackage.isNotEmpty &&
          appBuilt != null);

  /// The app bundle this macOS build runs from, which an update replaces,
  /// when Lumtub may write the folder it is in.
  static String? get macApp {
    if (!Platform.isMacOS) return null;
    final app = File(Platform.resolvedExecutable).parent.parent.parent.path;
    if (!app.endsWith('.app') || app.startsWith('/Volumes/')) return null;
    return _canReplace(app) ? app : null;
  }

  /// [canReplace], asked once a run: it writes a file, and the update bar
  /// asks on every rebuild.
  static final _replaceable = <String, bool>{};
  static bool _canReplace(String app) => _replaceable.putIfAbsent(app, () => canReplace(app));

  /// The AppImage file this Linux build runs from, which an update replaces,
  /// when Lumtub may write the folder it is in: one a package manager put
  /// in a system folder is updated by that package manager.
  static String? get appImage {
    if (!Platform.isLinux) return null;
    final path = Platform.environment['APPIMAGE'] ?? '';
    return path.isEmpty || !_canReplace(path) ? null : path;
  }

  /// Checks now and then every six hours, downloading what it finds when
  /// [download] says so.
  void start({required bool Function() download}) {
    // Cleaning first: it deletes what is in the folder, and the first
    // download writes there.
    unawaited(_readNotice());
    unawaited(_cleanUp().then((_) => check(download: download(), automatic: true)));
    _timer?.cancel();
    _timer = Timer.periodic(
        const Duration(hours: 6), (_) => check(download: download(), automatic: true));
  }

  static const _repository = '0x696c757a696f/lumtub';

  /// The latest release as the API would describe it, from github.com: its
  /// tag from where `releases/latest` points, its time from the releases
  /// feed, and the package for this build with its `.sig` file by name.
  Future<Map<String, dynamic>> _releaseFromPages() async {
    final request = http.Request('GET', Uri.https('github.com', '/$_repository/releases/latest'))
      ..followRedirects = false
      ..headers['User-Agent'] = 'Lumtub/$appVersion';
    final String tag;
    final plain = _plainClient();
    try {
      final answer = await plain.send(request).timeout(const Duration(seconds: 15));
      await answer.stream.drain<void>();
      tag = releaseTagOfRedirect(_repository, answer.headers['location']) ??
          (throw const HttpException('No latest release redirect'));
    } finally {
      plain.close();
    }
    String? published;
    try {
      final feed = await _client.get(Uri.https('github.com', '/$_repository/releases.atom'),
          headers: {'User-Agent': 'Lumtub/$appVersion'}).timeout(const Duration(seconds: 15));
      if (feed.statusCode == 200) published = publishedInFeed(feed.body, tag);
    } catch (e) {
      logDebug(() => 'Could not read the releases feed: $e');
    }
    return releaseOfTag(tag, package: _package, portable: portable, published: published);
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
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'Lumtub/$appVersion',
          if (_etag != null && _latest != null) 'If-None-Match': _etag!
        },
      ).timeout(const Duration(seconds: 15));
      Object? json;
      if (response.statusCode == 304 && _latest != null) {
        json = _latest;
      } else if (response.statusCode == 403 || response.statusCode == 429) {
        // The API allows 60 unsigned requests an hour per address, which an
        // address shared through a VPN or proxy soon uses up: the release
        // is then read from github.com's pages, which have no such limit.
        // A package found this way is still checked against its signature.
        logInfo(
            'GitHub API answered ${response.statusCode}; reading the latest release from github.com');
        try {
          json = await _releaseFromPages();
        } catch (e) {
          logDebug(() => 'Could not read the release from github.com: $e');
          throw UpdateCheckException(tr(
              'GitHub is limiting update checks from this network for now (HTTP {0}); try again later or use another proxy',
              [response.statusCode]));
        }
      } else {
        if (response.statusCode != 200) {
          throw UpdateCheckException(tr(
              'GitHub could not be asked for updates (HTTP {0}); try again later',
              [response.statusCode]));
        }
        json = jsonDecode(response.body);
        if (json is Map<String, dynamic>) {
          _latest = json;
          _etag = response.headers['etag'];
        }
      }
      if (json is! Map<String, dynamic>) {
        throw const FormatException('Invalid GitHub release response');
      }
      final offer =
          offerOf(json, current: _current, built: appBuilt, package: _package, portable: portable);
      available = offer;
      if (offer == null && ready != null) {
        await _discard(ready!);
        ready = null;
        readyVersion = null;
      }
      if (offer != null) await _adopt(offer);
      if (progress == null) await _prune();
      logInfo(offer != null
          ? 'Lumtub update available: ${offer.version}'
          : 'Lumtub is up to date ($_current)');
    } catch (e) {
      error = e is UpdateCheckException ? e.message : friendlyError(e);
      logWarn('Could not check Lumtub updates: $e');
    } finally {
      checking = false;
    }
    // Told once the download has started, so the home page does not show
    // a release as waiting for a click for a moment first.
    if (download && available != null && !(automatic && await metered())) await this.download();
    _notify();
  }

  /// Whether Android says the connection is metered, as mobile data is.
  static Future<bool> metered() async {
    if (!Platform.isAndroid) return false;
    try {
      return await const MethodChannel('lumtub/windows_shell').invokeMethod<bool>('isMetered') ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// The package for [offer] left in the update folder by an earlier run,
  /// when it still passes its checks: it becomes [ready] without being
  /// downloaded again.
  Future<void> _adopt(AppRelease offer) async {
    final name = offer.asset?['name']?.toString();
    if (!safeName(name) ||
        readyVersion == offer.version ||
        rejected == offer.version ||
        progress != null) {
      return;
    }
    final file = File('${_directory.path}${Platform.pathSeparator}$name');
    final sig = '${file.path}.sig';
    // Only plain files: a link could point the check at one file and the
    // installer at another.
    if (await FileSystemEntity.type(file.path, followLinks: false) != FileSystemEntityType.file ||
        await FileSystemEntity.type(sig, followLinks: false) != FileSystemEntityType.file) {
      return;
    }
    final verify = _verifier,
        version = offer.version,
        current = _current,
        path = file.path,
        named = name!;
    String? error;
    try {
      error = await Isolate.run(() =>
          verify(file: path, name: named, signature: sig, version: version, current: current));
    } catch (e) {
      error = '$e';
    }
    if (error != null) {
      logWarn('The Lumtub $version package kept from before failed its check: $error');
      await _discard(file);
      return;
    }
    final old = ready;
    ready = file;
    readyVersion = version;
    if (old != null && old.path != file.path) await _discard(old);
    logInfo('Lumtub $version was downloaded before; it installs when Lumtub closes');
  }

  /// Deletes what the update folder holds besides [ready] and the package
  /// of the release [available], with their signatures.
  Future<void> _prune() async {
    final keep = <String>{
      if (ready != null) _nameOf(ready!),
      if (available?.asset?['name'] case final String name) name,
    };
    try {
      if (!await _directory.exists()) return;
      await for (final entity in _directory.list()) {
        if (entity is! File) continue;
        final name = _nameOf(entity);
        if (keep.contains(name) ||
            keep.contains(name.endsWith('.sig') ? name.substring(0, name.length - 4) : '')) {
          continue;
        }
        try {
          await entity.delete();
          logDebug(() => 'Removed the old update file $name');
        } catch (e) {
          logDebug(() => 'Could not remove the old update file $name: $e');
        }
      }
    } catch (e) {
      logWarn('Could not clean the update folder: $e');
    }
  }

  static String _nameOf(File file) => file.path.split(Platform.pathSeparator).last;

  /// Whether [name], from GitHub's answer, is a plain package file name
  /// that stays inside the update folder.
  @visibleForTesting
  static bool safeName(String? name) =>
      name != null && RegExp(r'^Lumtub_[A-Za-z0-9._-]+$').hasMatch(name) && !name.contains('..');

  /// [page] when it is this project's page on GitHub, else its releases.
  static String releasePage(String? page) {
    const releases = 'https://github.com/0x696c757a696f/lumtub/releases';
    final uri = Uri.tryParse(page ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        !uri.path.startsWith('/0x696c757a696f/lumtub/releases')) {
      return releases;
    }
    return uri.toString();
  }

  /// Downloads and verifies the available package, in the background.
  /// While another download runs, the newest release is downloaded once
  /// that one ends.
  Future<void> download() async {
    final release = available;
    final asset = release?.asset;
    if (!canInstall || release == null || asset == null) return;
    if (!safeName(asset['name']?.toString())) {
      logWarn('Lumtub ${release.version} has a package name that is not allowed: ${asset['name']}');
      return;
    }
    if (progress != null) {
      if (downloading != release.version) _again = true;
      return;
    }
    if (rejected == release.version || readyVersion == release.version) return;
    final version = release.version;
    _again = false;
    downloading = version;
    progress = 0;
    error = null;
    _notify();
    try {
      final shown = Stopwatch()..start();
      final file = await _download(asset, _directory, (received, total) {
        if (total == null || total <= 0) return;
        // Whole percents, at most four a second: each notice rebuilds the
        // app (a fast line gave 104 in a minute, user log 2026-11-27).
        final next = (received * 100 ~/ total) / 100;
        if (next == progress || next < 1 && shown.elapsedMilliseconds < 250) return;
        shown.reset();
        progress = next;
        _notify();
      });
      try {
        await _verifySignature(file, asset, release.signature, version);
      } on FormatException {
        rejected = version;
        rethrow;
      }
      final old = ready;
      ready = file;
      readyVersion = version;
      if (old != null && old.path != file.path) {
        await _discard(old);
        logInfo(
            'Lumtub $version downloaded and replaces the ${_versionOf(old) ?? 'older'} package; it installs when Lumtub closes');
      } else {
        logInfo('Lumtub $version downloaded; it installs when Lumtub closes');
      }
    } catch (e) {
      error = friendlyError(e);
      logWarn('Could not download the Lumtub update: $e');
    } finally {
      progress = null;
      downloading = null;
      _notify();
    }
    if (_again && available != null && available!.version != version) {
      _again = false;
      await download();
    } else {
      _again = false;
      await _prune();
    }
  }

  /// The version in a package's file name, `Lumtub_<version>_<package>`.
  static String? _versionOf(File file) {
    final parts = _nameOf(file).split('_');
    return parts.length >= 3 && parts.first == 'Lumtub' ? parts[1] : null;
  }

  /// What the home page's update notice is about, or null when there is
  /// nothing to tell: a package ready to install, or a release this build
  /// does not download itself or the user has to start. Nothing while a
  /// download runs in the background.
  String? get noticeKey {
    final release = available;
    if (ready != null && readyVersion != null) return '$readyVersion ready';
    if (release == null || progress != null) return null;
    return '${release.version} available';
  }

  /// Whether the home page shows its update notice.
  bool get showsNotice => noticeKey != null && noticeKey != dismissed;

  /// Closes the home page's notice until there is news: a newer release,
  /// or a package ready to install.
  Future<void> dismissNotice() async {
    final key = noticeKey;
    if (key == null) return;
    dismissed = key;
    _notify();
    try {
      await _noticeFile.parent.create(recursive: true);
      await _noticeFile.writeAsString(key);
    } catch (e) {
      logDebug(() => 'Could not save the closed update notice: $e');
    }
  }

  Future<void> _readNotice() async {
    try {
      if (await _noticeFile.exists()) {
        dismissed = (await _noticeFile.readAsString()).trim();
        _notify();
      }
    } catch (_) {}
  }

  /// Fetches the package's `.sig` and checks it in the native core; deletes
  /// [file] and throws when the signatures do not hold.
  Future<void> _verifySignature(File file, Map<String, dynamic> asset,
      Map<String, dynamic>? signature, String version) async {
    final name = asset['name'].toString();
    try {
      final uri = Uri.parse(signature?['browser_download_url']?.toString() ?? '');
      if (signature == null || uri.scheme != 'https' || uri.host != 'github.com') {
        throw const FormatException('The update has no signature');
      }
      final response = await _client.get(uri,
          headers: {'User-Agent': 'Lumtub/$appVersion'}).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw HttpException('Signature download failed: HTTP ${response.statusCode}');
      }
      final sig = File('${file.path}.sig');
      await sig.writeAsBytes(response.bodyBytes);
      final path = file.path, sigPath = sig.path, current = _current, verify = _verifier;
      final error = await Isolate.run(() =>
          verify(file: path, name: name, signature: sigPath, version: version, current: current));
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
  Future<bool> _recheck(File file, {File? copy}) async {
    final name = _nameOf(file);
    final sigPath = '${file.path}.sig',
        path = (copy ?? file).path,
        version = readyVersion ?? available?.version,
        current = _current,
        verify = _verifier;
    String? error;
    try {
      error = await File(sigPath).exists()
          ? await Isolate.run(() => verify(
              file: path, name: name, signature: sigPath, version: version, current: current))
          : 'The update signature is missing';
    } catch (e) {
      error = '$e';
    }
    if (error == null) return true;
    logWarn('The downloaded Lumtub update failed its check before installing: $error');
    await _discard(file);
    rejected = version;
    ready = null;
    readyVersion = null;
    installError = tr('see the logs for details');
    _notify();
    return false;
  }

  /// Runs [launchInstaller] on another isolate. Static, so that the closure
  /// sent there carries only these plain values and never the updater.
  static Future<Map<String, dynamic>?> _launchOffThread(
          {required String package,
          required String folder,
          required int processId,
          required bool relaunch,
          required String name}) =>
      Isolate.run(() => launchInstaller(
          package: package,
          folder: folder,
          processId: processId,
          relaunch: relaunch,
          name: name,
          signature: '$package.sig'));

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
        await replaceMacApp(file, app, check: (copy) => _recheck(file, copy: copy));
        logInfo('Installed Lumtub ${readyVersion ?? available?.version ?? ''} to $app');
        await AppLog.current?.flush();
        if (relaunch) await relaunchAfterExit(app, pid, open: true);
      } else if (image != null) {
        await replaceAppImage(file, image, check: (copy) => _recheck(file, copy: copy));
        logInfo('Installed Lumtub ${readyVersion ?? available?.version ?? ''} to $image');
        await AppLog.current?.flush();
        if (relaunch) await relaunchAfterExit(image, pid);
      } else if (!portable) {
        final folder = File(executable).parent.path;
        final name = _nameOf(file);
        final package = file.path, processId = pid;
        // Hashing the package and waiting on the administrator prompt take
        // seconds: never on the window's isolate.
        final result = await _launchOffThread(
            package: package, folder: folder, processId: processId, relaunch: relaunch, name: name);
        if (result == null) throw StateError('No native core');
        if (result['rejected'] == true) {
          logWarn(
              'The downloaded Lumtub update failed its check before installing: ${result['error']}');
          await _discard(file);
          rejected = readyVersion ?? available?.version;
          ready = null;
          readyVersion = null;
          installError = tr('see the logs for details');
          _notify();
          return false;
        }
        if (result['ok'] != true) {
          logWarn(
              'Could not start the Lumtub installer${result['elevated'] == true ? ' as administrator' : ''}: ${result['error']}');
          installError = result['elevated'] == true
              ? tr('Administrator rights are needed to install into this folder')
              : tr('see the logs for details');
          _notify();
          return false;
        }
        installError = null;
        logInfo(
            'Installing Lumtub ${readyVersion ?? available?.version ?? ''} after exit${result['elevated'] == true ? ' as administrator' : ''}');
        await AppLog.current?.flush();
      } else {
        // The portable ZIP is unpacked by the script after Lumtub has
        // exited, so no handle can be held until then; the folder it is in
        // is the user's own, as is the folder it unpacks into.
        final script = File('${_directory.path}${Platform.pathSeparator}install-update.ps1');
        final text = updateScript(
            package: file.path,
            processId: pid,
            executable: executable,
            portable: true,
            relaunch: relaunch);
        if (text == null) return false;
        // Windows PowerShell reads a script without a byte order mark in the
        // ANSI code page, which garbles a path outside it.
        await script.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(text)]);
        await Process.start(
            windowsProgram(r'System32\WindowsPowerShell\v1.0\powershell.exe'),
            [
              '-NoProfile',
              '-ExecutionPolicy',
              'Bypass',
              '-WindowStyle',
              'Hidden',
              '-File',
              script.path
            ],
            mode: ProcessStartMode.detached);
        logInfo('Installing Lumtub ${readyVersion ?? available?.version ?? ''} after exit');
        await AppLog.current?.flush();
      }
      ready = null;
      readyVersion = null;
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
  /// replaces the running app; the installer checks the APK's own
  /// signature against the installed app's as it reads it. The file stays ready in case they say no.
  Future<bool> _installApk(File file) async {
    try {
      await const MethodChannel('lumtub/windows_shell').invokeMethod<void>('installApk', file.path);
      installError = null;
      logInfo('Handed Lumtub ${readyVersion ?? available?.version ?? ''} to the Android installer');
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
  /// it failed). A package of another version than this one, not
  /// installed yet, stays with its signature until the first check says
  /// whether it is still the one to install.
  Future<void> _cleanUp() async {
    try {
      if (!await _directory.exists()) return;
      final sep = Platform.pathSeparator;
      final outcome = File('${_directory.path}${sep}update.log');
      final setupLog = File('${_directory.path}${sep}setup.log');
      if (!await outcome.exists() && await setupLog.exists()) {
        final tail = (await setupLog.readAsLines(encoding: const Utf8Codec(allowMalformed: true)))
            .reversed
            .take(8)
            .toList()
            .reversed;
        logWarn('Lumtub update did not finish; installer log ends with:\n${tail.join('\n')}');
      }
      if (await outcome.exists()) {
        final lines = (await outcome.readAsLines(encoding: const Utf8Codec(allowMalformed: true)))
            .where((line) => line.trim().isNotEmpty)
            .toList();
        final last = lines.isEmpty ? '' : lines.last.trim();
        logInfo('Last Lumtub update: $last');
        if (!last.endsWith(' updated')) {
          final setup = File('${_directory.path}${sep}setup.log');
          if (await setup.exists()) {
            final tail = (await setup.readAsLines(encoding: const Utf8Codec(allowMalformed: true)))
                .reversed
                .take(8)
                .toList()
                .reversed;
            logInfo('Installer log ends with:\n${tail.join('\n')}');
          }
        }
      }
      await for (final entity in _directory.list()) {
        if (entity is File && !_waiting(_nameOf(entity))) await entity.delete();
      }
    } catch (e) {
      logWarn('Could not clean the update folder: $e');
    }
  }

  /// Whether [name] is a package (or its `.sig`) of another version than
  /// the running one, which may still be installed.
  bool _waiting(String name) {
    final package = name.endsWith('.sig') ? name.substring(0, name.length - 4) : name;
    final version = _versionOf(File(package));
    return version != null &&
        version != _current &&
        !package.endsWith('.download') &&
        !package.endsWith('.ps1');
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
/// same file system, never written over. The copy is what [check]
/// verifies, the file that is then put in place.
Future<void> replaceAppImage(File update, String image,
    {Future<bool> Function(File copy)? check}) async {
  final next = File('$image.update');
  await update.copy(next.path);
  try {
    setFileMode(next.path, executableMode);
    if (check != null && !await check(next)) throw StateError('The update failed its check');
  } catch (_) {
    if (await next.exists()) await next.delete();
    rethrow;
  }
  await next.rename(image);
  await update.delete();
}

/// Starts [image] once process [processId] has ended; a second Lumtub
/// started earlier would only bring the closing one to the front. An app
/// bundle is started with [open].
Future<void> relaunchAfterExit(String image, int processId, {bool open = false}) async {
  final start = open ? r'exec /usr/bin/open -n "$2"' : r'exec "$2"';
  await Process.start(
      '/bin/sh',
      [
        '-c',
        r'while kill -0 "$1" 2>/dev/null; do sleep 0.2; done; ' + start,
        'lumtub-relaunch',
        '$processId',
        image
      ],
      mode: ProcessStartMode.detached);
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
/// opens without Gatekeeper's first-launch check. The image is copied into
/// a private folder first, and that copy is what [check] verifies and
/// what is opened.
Future<void> replaceMacApp(File update, String app,
    {Future<bool> Function(File copy)? check}) async {
  final mount = await Directory.systemTemp.createTemp('lumtub-update-');
  final held = await Directory.systemTemp.createTemp('lumtub-update-image-');
  final next = '$app.update';
  final old = '$app.old';
  Future<void> run(String program, List<String> arguments) async {
    final result = await Process.run(program, arguments);
    if (result.exitCode != 0) throw StateError('$program failed: ${result.stderr}'.trim());
  }

  try {
    final image = await update.copy('${held.path}/update.dmg');
    if (check != null && !await check(image)) throw StateError('The update failed its check');
    await run('/usr/bin/hdiutil',
        ['attach', '-nobrowse', '-readonly', '-noautoopen', '-mountpoint', mount.path, image.path]);
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
    try {
      await held.delete(recursive: true);
    } catch (e) {
      logDebug(() => 'Could not remove the copied update image: $e');
    }
  }
}

/// Why an update check failed, already in words for the person.
class UpdateCheckException implements Exception {
  const UpdateCheckException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The tag a github.com `releases/latest` redirect of [repository] points at.
String? releaseTagOfRedirect(String repository, String? location) {
  if (location == null) return null;
  final uri = Uri.tryParse(location);
  if (uri == null || uri.host != 'github.com') return null;
  final prefix = '$repository/releases/tag'.split('/');
  final parts = uri.pathSegments;
  if (parts.length != prefix.length + 1) return null;
  for (var i = 0; i < prefix.length; i++) {
    if (parts[i].toLowerCase() != prefix[i].toLowerCase()) return null;
  }
  return parts.last.isEmpty ? null : Uri.decodeComponent(parts.last);
}

/// When the release [tag] was last updated, from a github.com releases
/// Atom feed: the `<updated>` of the entry that links to its page.
@visibleForTesting
String? publishedInFeed(String atom, String tag) {
  for (final entry in RegExp(r'<entry>([\s\S]*?)</entry>').allMatches(atom)) {
    final body = entry[1]!;
    final link = RegExp(r'<link[^>]*href="([^"]+)"').firstMatch(body)?[1];
    if (link == null || !link.endsWith('/releases/tag/$tag')) continue;
    return RegExp(r'<updated>([^<]+)</updated>').firstMatch(body)?[1]?.trim();
  }
  return null;
}

/// A release shaped like the API's for [tag], listing the package for
/// [package] and its `.sig` file by the names releases give them.
@visibleForTesting
Map<String, dynamic> releaseOfTag(String tag,
    {required String package, required bool portable, String? published}) {
  final version = tag.startsWith('v') ? tag.substring(1) : tag;
  final base =
      'https://github.com/0x696c757a696f/lumtub/releases/download/${Uri.encodeComponent(tag)}';
  final ending = package.startsWith('linux-')
      ? '.AppImage'
      : package.startsWith('macos-')
          ? '.dmg'
          : package.startsWith('android-')
              ? '.apk'
              : portable
                  ? '.zip'
                  : '-setup.exe';
  final file = 'Lumtub_${version}_$package$ending';
  return {
    'tag_name': tag,
    'html_url': 'https://github.com/0x696c757a696f/lumtub/releases/tag/${Uri.encodeComponent(tag)}',
    if (published != null) 'published_at': published,
    'assets': [
      if (package.isNotEmpty) ...[
        {'name': file, 'browser_download_url': '$base/${Uri.encodeComponent(file)}'},
        {'name': '$file.sig', 'browser_download_url': '$base/${Uri.encodeComponent('$file.sig')}'},
      ],
    ],
  };
}

/// The update [release] (GitHub's JSON) offers a build of [current] made at
/// [built]: newer, with the file for [package]. Null when it is not newer or
/// the native core is missing.
AppRelease? offerOf(Map<String, dynamic> release,
    {required String current, DateTime? built, String package = '', bool portable = false}) {
  final core = NativeCore.instance;
  if (core == null) return null;
  final ask = jsonEncode({
    'release': release,
    'current': current,
    'built': built == null ? null : built.millisecondsSinceEpoch ~/ 1000,
    'package': package,
    'portable': portable
  });
  final answer = jsonDecode(core.take(core.withText(ask, core.updateOffer)) ?? 'null');
  if (answer is! Map<String, dynamic>) return null;
  return AppRelease(
      version: answer['version'] as String,
      page: answer['page'] as String,
      asset: answer['asset'] as Map<String, dynamic>?,
      signature: answer['signature'] as Map<String, dynamic>?);
}

/// Why the package [file] (listed as [name]) fails its `.sig` file
/// [signature], or null when both signatures hold. It reads the whole
/// package, so run it on another isolate.
/// With [version] (the release offered) the package's name must carry that
/// version, newer than [current], so a signed older package can't be passed
/// off as an update.
String? verifyUpdate(
    {required String file,
    required String name,
    required String signature,
    String? version,
    String? current}) {
  final core = NativeCore.instance;
  if (core == null) return 'The native core is missing';
  final ask = {
    'file': file,
    'name': name,
    'signature': signature,
    if (version != null) 'version': version,
    if (version != null && current != null && RegExp(r'^v?\d+\.\d+\.\d+').hasMatch(current))
      'current': current
  };
  final answer = jsonDecode(core.take(core.withText(jsonEncode(ask), core.updateVerify)) ?? 'null');
  if (answer is Map && answer['ok'] == true) return null;
  return answer is Map ? '${answer['error']}' : 'Could not check the signature';
}

/// Starts the installer [package] into [folder]; see `lumtub_update_launch`.
/// With [name] and [signature] the core checks the package once more
/// through a handle that keeps it from changing until the installer has
/// started. Null without the native core.
Map<String, dynamic>? launchInstaller(
    {required String package,
    required String folder,
    required int processId,
    required bool relaunch,
    String? name,
    String? signature}) {
  final core = NativeCore.instance;
  if (core == null) return null;
  final ask = jsonEncode({
    'package': package,
    'folder': folder,
    'processId': processId,
    'relaunch': relaunch,
    if (name != null) 'name': name,
    if (signature != null) 'signature': signature
  });
  return jsonDecode(core.take(core.withText(ask, core.updateLaunch)) ?? 'null')
      as Map<String, dynamic>?;
}

/// A PowerShell script that waits for Lumtub ([processId]) to end, then runs
/// the installer silently or unpacks the portable ZIP over the folder of
/// [executable], removes [package] and starts Lumtub again if [relaunch].
@visibleForTesting
String? updateScript(
    {required String package,
    required int processId,
    required String executable,
    required bool portable,
    required bool relaunch}) {
  final core = NativeCore.instance;
  if (core == null) return null;
  final ask = jsonEncode({
    'package': package,
    'processId': processId,
    'executable': executable,
    'portable': portable,
    'relaunch': relaunch
  });
  return jsonDecode(core.take(core.withText(ask, core.updateScript)) ?? 'null') as String?;
}
